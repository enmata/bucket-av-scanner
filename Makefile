all: deploy-docker wait-deploy-docker test clean-docker
	# runs sequentially all the workflow: "make deploy-docker", "make test" and "make deploy-docker"

deploy-docker:
	# creation of all the needed resources on local docker daemon
	docker-compose -f docker-compose/docker-compose.yml up --force-recreate -V -d

test:
	# runs sequentially tests by uploading a clean and infected files
	sh testing/bucket-av-scanner_tests.sh

clean-docker:
	# deletes the docker-compose resources created during the deploy
	docker-compose -f docker-compose/docker-compose.yml down
	docker-compose -f docker-compose/docker-compose.yml rm -v
	docker volume rm -f docker-compose_avscan_script_log docker-compose_clamd_service_log docker-compose_clamd_virus_definitions docker-compose_minio_service_data docker-compose_openssl_certs docker-compose_rabbitmq_service_log docker-compose_rabbitmq_service_queue

wait-deploy-docker:
	#Dirty workaround (sleep) waiting deploy-docker, as "ready heathcheck" has not been implemented yet for avscan-script, docker-deploy is done as "detached" mode, and gem installation takes time (around 11 minutes)
	sleep 660