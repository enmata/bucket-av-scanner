#!/bin/bash

RABBITMQ_RETRIES=15;
echo "[MQ Init] MQ is starting..."
until /usr/local/bin/rabbitmqadmin --host=$RABBITMQ_ENDPOINT --port=$RABBITMQ_PORT_MANAGEMENT --username=$RABBITMQ_DEFAULT_USER --password=$RABBITMQ_DEFAULT_PASS list vhosts > /dev/null 2>&1 || [ "$RABBITMQ_RETRIES" -eq 0 ];
do
  echo "[MQ Init] Waiting MQ to start...: $((RABBITMQ_RETRIES--))";
  sleep 1;
done;
echo "[MQ Init] MQ Started. Setting up users, queue, binding and routing_key...";
/usr/local/bin/rabbitmqadmin --host=$RABBITMQ_ENDPOINT --port=$RABBITMQ_PORT_MANAGEMENT --username=$RABBITMQ_DEFAULT_USER --password=$RABBITMQ_DEFAULT_PASS declare user name=$RABBITMQ_REGULAR_USER_NAME password=$RABBITMQ_REGULAR_USER_PASS tags=administrator
/usr/local/bin/rabbitmqadmin --host=$RABBITMQ_ENDPOINT --port=$RABBITMQ_PORT_MANAGEMENT --username=$RABBITMQ_DEFAULT_USER --password=$RABBITMQ_DEFAULT_PASS declare permission vhost=/ user=$RABBITMQ_REGULAR_USER_NAME configure=.* write=.* read=.*
/usr/local/bin/rabbitmqadmin --host=$RABBITMQ_ENDPOINT --port=$RABBITMQ_PORT_MANAGEMENT --username=$RABBITMQ_DEFAULT_USER --password=$RABBITMQ_DEFAULT_PASS declare queue name=$RABBITMQ_QUEUE_NAME durable=false;
/usr/local/bin/rabbitmqadmin --host=$RABBITMQ_ENDPOINT --port=$RABBITMQ_PORT_MANAGEMENT --username=$RABBITMQ_DEFAULT_USER --password=$RABBITMQ_DEFAULT_PASS declare binding source="amq.direct" destination_type="queue" destination=$RABBITMQ_QUEUE_NAME routing_key="bucket_notifications";
echo "[MQ Init] Complete"
