[![Build Status](https://travis-ci.org/fizquierdo/graphan-docker.svg?branch=master)](https://travis-ci.org/fizquierdo/graphan-docker)

### Create and start TEST and DEV neo4j db containers:

	docker-compose build
	docker-compose --verbose up

### Run tests with Rspec from the localhost

	cd app && rspec spec

### Start/stop app in production:

	docker-compose -f docker-compose-prod.yml up -d 
	docker-compose -f docker-compose-prod.yml stop

### Pre-processing made to HSK lists

	cd app && sh scripts/preprocessing/preprocess_hsk.sh

