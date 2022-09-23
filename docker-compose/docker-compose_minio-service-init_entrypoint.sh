#!/bin/bash
MINIO_RETRIES=15;
echo "[MinIO Init] MinIO is starting..."
until curl --silent --insecure -f "$MINIO_SERVER_URL/minio/health/live" || [ "$MINIO_RETRIES" -eq 0 ];
do
  echo "[MinIO Init] Waiting MinIO initial start...: $((MINIO_RETRIES--))";
  sleep 5;
done;
echo "[MinIO Init] MinIO Started. Setting up users, events and notification queues...";
/usr/bin/mc alias set s3minio $MINIO_SERVER_URL $MINIO_ROOT_USER $MINIO_ROOT_PASSWORD --insecure;
/usr/bin/mc mb s3minio/$MINIO_BUCKET_NAME  --insecure;
/usr/bin/mc admin user add s3minio $MINIO_USER_NAME $MINIO_USER_PASSWORD --insecure;
/usr/bin/mc admin policy set s3minio consoleAdmin user=$MINIO_USER_NAME --insecure;

RABBITMQ_RETRIES=15;
until curl --silent --insecure "http://$RABBITMQ_endpoint:$RABBITMQ_PORT/api/users/rabbituser" || [ "$RABBITMQ_RETRIES" -eq 0 ];
do
  echo "[MinIO Init] Waiting MQ initialization...: $((RABBITMQ_RETRIES--))";
  sleep 5;
done;
/usr/bin/mc admin config set s3minio notify_amqp:1 enable="on" exchange="amq.direct" exchange_type="direct" mandatory="on" no_wait="off" url="amqp://$RABBITMQ_REGULAR_USER_NAME:$RABBITMQ_REGULAR_USER_PASS@mq-service:5672" auto_deleted="off" delivery_mode="2" durable="on" internal="off" routing_key="$RABBITMQ_QUEUE_ROUTING_KEY" --insecure;
echo "[MinIO Init] Restarting MinIO starting to apply settings.."
/usr/bin/mc admin service restart s3minio --insecure;

MINIO_RETRIES=15;
until curl --silent --insecure -f "$MINIO_SERVER_URL/minio/health/live" || [ "$MINIO_RETRIES" -eq 0 ];
do
  echo "[MinIO Init] Waiting MinIO to start after service restart...: $((MINIO_RETRIES--))";
  sleep 2;
done;
/usr/bin/mc event add s3minio/$MINIO_BUCKET_NAME arn:minio:sqs::1:amqp --event "put"  --insecure;
echo "[MinIO Init] Complete"
