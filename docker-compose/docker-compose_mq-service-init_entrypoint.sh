#!/bin/bash

# https://www.rabbitmq.com/access-control.html#default-state
# https://rawcdn.githack.com/rabbitmq/rabbitmq-server/v3.10.7/deps/rabbitmq_management/priv/www/api/index.html

MQ_RETRIES=15;
echo "[MQ Init] MQ is starting..."
until /usr/local/bin/rabbitmqadmin --host=mq-service --port=15672 --username=$RABBITMQ_DEFAULT_USER --password=$RABBITMQ_DEFAULT_PASS list vhosts > /dev/null 2>&1 || [ "$MQ_RETRIES" -eq 0 ];
do
  echo "[MQ Init] Waiting MQ to start...: $((MQ_RETRIES--))";
  sleep 1;
done;
echo "[MQ Init] MQ Started. Setting up users, queue, binding and routing_key...";
/usr/local/bin/rabbitmqadmin --host=mq-service --port=15672 --username=$RABBITMQ_DEFAULT_USER --password=$RABBITMQ_DEFAULT_PASS declare user name=$RABBITMQ_REGULAR_USER_NAME password=$RABBITMQ_REGULAR_USER_PASS tags=administrator
/usr/local/bin/rabbitmqadmin --host=mq-service --port=15672 --username=$RABBITMQ_DEFAULT_USER --password=$RABBITMQ_DEFAULT_PASS declare permission vhost=/ user=$RABBITMQ_REGULAR_USER_NAME configure=.* write=.* read=.*
/usr/local/bin/rabbitmqadmin --host=mq-service --port=15672 --username=$RABBITMQ_DEFAULT_USER --password=$RABBITMQ_DEFAULT_PASS declare queue name=s3minioqueue durable=false;
/usr/local/bin/rabbitmqadmin --host=mq-service --port=15672 --username=$RABBITMQ_DEFAULT_USER --password=$RABBITMQ_DEFAULT_PASS declare binding source="amq.direct" destination_type="queue" destination="s3minioqueue" routing_key="bucket_notifications";
echo "[MQ Init] Complete"
