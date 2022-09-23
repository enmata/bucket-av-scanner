#!/bin/bash
MINIO_RETRIES=15;
echo "[MinIO Service] MinIO is starting..."
until ls /root/.minio/certs/public.crt >> /dev/null 2>&1
do
  echo "[MinIO Service] Waiting SSL certificate creation...";
  sleep 1;
done;
minio server /data --quiet --console-address ":9001";
echo "[MinIO Service] Complete"
