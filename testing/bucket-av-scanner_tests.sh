#!/bin/bash

# Setting up parameters
export MINIO_SERVER_URL=https://localhost:9000
export MINIO_BUCKET_NAME=storagebucket
export AWS_ACCESS_KEY_ID=miniouser
export AWS_SECRET_ACCESS_KEY=LIia7mr7e1WD4R4Q
export AWS_DEFAULT_OUTPUT="text"

echo "[test] Testing is starting..."
until nc -vz localhost 8080 >> /dev/null 2>&1
do
  echo "[test] Waiting av-scan script to start...";
  sleep 5;
done;

echo "[test] CLEAN CASE: Uploading a clean file..."
echo "This is a new clean file" > clean_file.txt
aws s3 --endpoint-url $MINIO_SERVER_URL --no-verify-ssl cp clean_file.txt "s3://$MINIO_BUCKET_NAME" 2> /dev/null
echo "[test] CLEAN CASE: Listing clean file and tags..."
aws s3 --endpoint-url $MINIO_SERVER_URL --no-verify-ssl ls "s3://$MINIO_BUCKET_NAME/clean_file.txt" 2> /dev/null
aws s3api --endpoint-url $MINIO_SERVER_URL --no-verify-ssl get-object-tagging --bucket "$MINIO_BUCKET_NAME" --key clean_file.txt 2> /dev/null
aws s3 --endpoint-url $MINIO_SERVER_URL --no-verify-ssl rm "s3://$MINIO_BUCKET_NAME/clean_file.txt" 2> /dev/null

echo "[test] INFECTED CASE: Uploading a infected file..."
wget -q https://secure.eicar.org/eicar.com.txt
aws s3 --endpoint-url $MINIO_SERVER_URL --no-verify-ssl cp eicar.com.txt "s3://$MINIO_BUCKET_NAME" 2> /dev/null
echo "[test] INFECTED CASE: Listing infected file and tags..."
aws s3 --endpoint-url $MINIO_SERVER_URL --no-verify-ssl ls "s3://$MINIO_BUCKET_NAME/eicar.com.txt" 2> /dev/null

echo "[test] Wrapping up..."
rm clean_file.txt
rm eicar.com.txt
