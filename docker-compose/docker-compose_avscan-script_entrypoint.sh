#!/bin/bash

echo "[av-scan script] Installing netcat for heathlcheck..."
apt-get update >> /dev/null 2>&1
apt-get install -y netcat >> /dev/null 2>&1

echo "[av-scan script] Installing gem dependencies..."
gem update
gem install -q aws-sdk-s3 json uri yaml logger securerandom bunny net rest-client

# Creating config files and scripts
echo "[av-scan script] Creating config files and scripts..."
mkdir -p /opt/av-scan
cat>/opt/av-scan/av-scan.conf<<EOF
delete: ${DELETE_FILE}
report_clean: ${REPORT_CLEAN}
tag_files: ${TAG_FILES}
tag_key: ${TAG_KEY}
minio_region: ${MINIO_REGION}
mq_queue_name: ${RABBITMQ_QUEUE_NAME}
mq_topic: ${RABBITMQ_TOPIC}
volume_size: ${VOLUME_SIZE}
minio_endpoint: ${MINIO_SERVER_URL}
minio_access_key_id: ${MINIO_ACCESS_KEY_ID}
minio_secret_access_key: ${MINIO_SECRET_ACCESS_KEY}
mq_endpoint: ${RABBITMQ_ENDPOINT}
mq_port: ${RABBITMQ_PORT}
mq_user_name: ${RABBITMQ_REGULAR_USER_NAME}
mq_user_password: ${RABBITMQ_REGULAR_USER_PASS}
clamd_endpoint: ${CLAMD_ENDPOINT}
clamd_port: ${CLAMD_PORT}
publish_endpoint: ${PUBLISH_ENDPOINT}
EOF
chown root /opt/av-scan/av-scan.conf
chmod 644 /opt/av-scan/av-scan.conf

cat>/opt/av-scan/worker.rb<<EOF
#!/usr/bin/env ruby
require 'aws-sdk-s3'
require 'json'
require 'uri'
require 'yaml'
require 'logger'
require 'securerandom'
require 'bunny'
require 'net/http'
require 'rest-client'


\$log = Logger.new File.open(__dir__ + '/av-scan.log', 'w')

class Worker

  attr_reader :conf, :s3, :tag_key

  NO_STATUS = 'no'
  CLEAN_STATUS = 'clean'
  INFECTED_STATUS = 'infected'

  NO_ACTION = 'no'
  TAG_ACTION = 'tag'
  DELETE_ACTION = 'delete'

  def initialize
    @conf = YAML::load_file(__dir__ + '/av-scan.conf')
    Aws.config.update(
            endpoint: conf['minio_endpoint'],
            access_key_id: conf['minio_access_key_id'],
            secret_access_key: conf['minio_secret_access_key'],
            force_path_style: true,
            region: conf['minio_region'],
            ssl_verify_peer: false
    )
    @tag_key = conf['tag_key']
    @mq_connection = Bunny.new(:host => conf['mq_endpoint'], :port => conf['mq_port'], :user => conf['mq_user_name'], :password => conf['mq_user_password'])
    @mq_connection.start()
    @mq_channel = @mq_connection.create_channel
    @s3 = Aws::S3::Client.new()
  end

  def run
    \$log.info "av-scan started"
    puts("av-scan started")
    @mq_queue = @mq_channel.queue(conf['mq_queue_name'])
    max_size = conf['volume_size'] * 1073741824 / 2 # in bytes
    clamd_endpoint = conf['clamd_endpoint']
    clamd_port = conf['clamd_port']

    @mq_queue.subscribe(block: true) do |_delivery_info, _properties, body|
      begin
        puts("-----MQ MESSAGE BODY-----")
        puts("#{body}")
        puts("-------------------------")
        body = JSON.parse(body)
        \$log.debug "body #{body}"
        if body.key?('Records')
          body['Records'].each do |record|
            bucket = record['s3']['bucket']['name']
            key = URI.decode_www_form_component(record['s3']['object']['key'])
            version = record['s3']['object']['versionId']
            fileName = "/tmp/#{SecureRandom.uuid}"

            puts("-----PARAMS FROM MQ NOTIFICATION-----")
            puts("--#{bucket}---")
            puts("--#{key}---")
            puts("--#{fileName}---")
            puts("-------------------------------------")

            if record['eventName'] == 's3:ObjectCreated:PutTagging'
              \$log.info "s3://#{bucket}/#{key} #{version} Just a key tagging event, discarting notification... "
              puts("Just a key tagging event, discarting notification... (console)")
              next
            end
            if record['s3']['object']['size'] > max_size
              \$log.info "s3://#{bucket}/#{key} #{version} bigger than half of the EBS volume, skip"
              if conf['tag_files']
                tag(bucket, key, version, NO_STATUS);
              end
              publish_notification(bucket, key, version, NO_STATUS, NO_ACTION);
              next
            end
            \$log.debug "downloading s3://#{bucket}/#{key} #{version}..."
            puts("downloading s3://#{bucket}/#{key} #{version}...")
            begin
              if version
                s3.get_object(
                  response_target: fileName,
                  bucket: bucket,
                  key: key,
                  version_id: version
                )
              else
                s3.get_object(
                  response_target: fileName,
                  bucket: bucket,
                  key: key
                )
              end
            rescue Aws::S3::Errors::NoSuchKey
              \$log.info "s3://#{bucket}/#{key} #{version} does no longer exist, skip"
              puts("s3://#{bucket}/#{key} #{version} does no longer exist, skip")
            end
            begin
                \$log.info "scanning s3://#{bucket}/#{key} #{version}..."
                puts("scanning s3://#{bucket}/#{key} #{version}...")
                response = RestClient::Request.new({
                                      :method => :post,
                                      :url => "https://#{clamd_endpoint}:#{clamd_port}/scan",
                                      :payload => {
                                        :multipart => true,
                                        :file => File.new("#{fileName}", 'rb')
                                      },
                                      :verify_ssl => false
                }).execute
                puts("---clamd_notification: clamd response---")
                puts response.body
                puts("----------------------------------------")
                if response.code == 200
                  puts("s3://#{bucket}/#{key} is clean, NO virus found (console)")
                  if conf['tag_files']
                    \$log.debug "s3://#{bucket}/#{key} #{version} is clean (tagging)"
                    tag(bucket, key, version, CLEAN_STATUS);
                  else
                    \$log.debug "s3://#{bucket}/#{key} #{version} is clean"
                  end
                  if conf['report_clean']
                    publish_notification(body)
                  end
                else
                  puts "s3://#{bucket}/#{key} #{version} could not be scanned, clamd notification response code was #{response.code}, retry"
                  \$log.debug "s3://#{bucket}/#{key} #{version} could not be scanned, clamd notification response code was #{response.code}, retry"
                end
            rescue Exception => ex
                puts("s3://#{bucket}/#{key} #{version} INFECTED, YES virus found (console)")
                puts("#{ex}")
                if conf['delete']
                  \$log.debug "s3://#{bucket}/#{key} #{version} is infected (deleting)"
                  s3.delete_object(
                    bucket: bucket,
                    key: key
                  )
                elsif conf['tag_files']
                  \$log.debug "s3://#{bucket}/#{key} #{version} is infected (tagging)"
                  tag(bucket, key, version, INFECTED_STATUS);
                else
                  \$log.debug "s3://#{bucket}/#{key} #{version} is infected"
                end
            ensure
              system("rm #{fileName}")
            end
          end
        end
      rescue Exception => e
        \$log.error "message failed: #{e.inspect} #{_delivery_info} #{_properties}"
        raise e
      end
    end
  end

  private

  def tag(bucket, key, version, status)
    if version
      s3.put_object_tagging(
        bucket: bucket,
        key: key,
        version_id: version,
        tagging: {tag_set: [{key: tag_key, value: status}]}
      )
    else
      s3.put_object_tagging(
        bucket: bucket,
        key: key,
        tagging: {tag_set: [{key: tag_key, value: status}]}
      )
    end
  end

  def publish_notification(body)

    uri = URI(conf['publish_endpoint'])
    header = {'Content-Type': 'application/json'}
    http = Net::HTTP.new(uri.host)
    request = Net::HTTP::Post.new(uri.request_uri, header)
    body_json = JSON["Message": JSON.generate(body) ]

    puts("---publish_notification: body_json sending---")
    puts("---#{body_json}---")
    request.body = body_json

    response = http.request(request)
    puts("---publish_notification: contentsharing response---")
    puts response.body
    puts("---------------------------------------------------")

  end

end

begin
  Worker.new.run
rescue Exception => e
  \$log.error "worker failed: #{e.inspect}"
  raise e
end
EOF
chown root /opt/av-scan/worker.rb
chmod 744 /opt/av-scan/worker.rb

# Running services
echo "[av-scan script] Running services"
netcat -l -p 8080 &
cd /opt/av-scan/
/usr/local/bin/ruby /opt/av-scan/worker.rb
