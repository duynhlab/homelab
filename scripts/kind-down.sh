#!/usr/bin/env bash

set -o errexit

cluster_name="${CLUSTER_NAME:=homelab}"
reg_name="${cluster_name}-registry"

kind delete cluster --name ${cluster_name}

docker rm -f ${reg_name}
