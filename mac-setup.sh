#!/usr/bin/env bash

docker-machine start slt-b2d

sleep 30

export DOCKER_MACHINE_NAME=slt-b2d
export DOCKER_CERT_PATH=/Users/sterry1/.docker/machine/machines/slt-b2d
export DOCKER_TLS_VERIFY=1
export DOCKER_HOST=tcp://192.168.99.100:2376

eval $(docker-machine env slt-b2d)

