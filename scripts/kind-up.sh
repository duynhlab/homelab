#!/usr/bin/env bash

set -o errexit

cluster_name="${CLUSTER_NAME:=homelab}"
# Kubernetes node image, pinned by tag AND digest (RFC-0032). Kind's release
# notes publish the digest per Kind version; a tag alone can be re-pushed.
# 1.35, not 1.36: the 1.36 kubelet crash-loops when /var/lib/docker is on ZFS
# ("failed to get rootfs info", kind#4229, fixed in cadvisor master but in no
# release yet). Move to 1.36 once a 1.36 patch ships that cadvisor fix.
# flux-validate.sh reads the version from this line for kubeconform, so keep
# it the only place the version is written. KIND_NODE_IMAGE overrides it; the
# rollback is a recreate on the previous baseline:
#   KIND_NODE_IMAGE=kindest/node:v1.34.3@sha256:08497ee19eace7b4b5348db5c6a1591d7752b164530a36f855cb0f2bdcbadd48
# renovate: datasource=docker depName=kindest/node
node_image="${KIND_NODE_IMAGE:=kindest/node:v1.35.8@sha256:07b2536e30b803ed61d1677a79df6115f798ce64c80f9e22f6ed45afd09323c0}"
reg_name="${cluster_name}-registry"
reg_localhost_port="5050"
reg_cluster_port="5000"

install_cluster() {
cat <<EOF | kind create cluster --name ${cluster_name} --wait 5m --config=-
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
  - role: control-plane
    image: ${node_image}
    kubeadmConfigPatches:
      - |
        kind: InitConfiguration
        nodeRegistration:
          kubeletExtraArgs:
            node-labels: "ingress-ready=true"
    extraPortMappings:
      - containerPort: 30080
        hostPort: 80
        protocol: TCP
      - containerPort: 30443
        hostPort: 443
        protocol: TCP
  - role: worker
    image: ${node_image}
  - role: worker
    image: ${node_image}
  - role: worker
    image: ${node_image}
EOF
}

register_registry() {
cat <<EOF | kubectl apply --server-side -f-
apiVersion: v1
kind: ConfigMap
metadata:
  name: local-registry-hosting
  namespace: kube-public
data:
  localRegistryHosting.v1: |
    host: "localhost:${reg_localhost_port}"
    hostFromContainerRuntime: "${reg_name}:${reg_cluster_port}"
    hostFromClusterNetwork: "${reg_name}:${reg_cluster_port}"
    help: "https://kind.sigs.k8s.io/docs/user/local-registry/"
EOF
}

# Create a registry container
if [ "$(docker inspect -f '{{.State.Running}}' "${reg_name}" 2>/dev/null || true)" != 'true' ]; then
  echo "starting Docker registry on localhost:${reg_localhost_port}"
  docker run -d --restart=always -p "127.0.0.1:${reg_localhost_port}:${reg_cluster_port}" \
    --name "${reg_name}" registry:3
fi

# Create a cluster with the local registry enabled
if [ "$(kind get clusters | grep ${cluster_name})" != "${cluster_name}" ]; then
  install_cluster
  register_registry
else
  echo "cluster ${cluster_name} exists"
fi

# Connect the registry to the cluster network
if [ "$(docker inspect -f='{{json .NetworkSettings.Networks.kind}}' "${reg_name}")" = 'null' ]; then
  echo "connecting the Docker registry to the cluster network"
  docker network connect "kind" "${reg_name}"
fi
