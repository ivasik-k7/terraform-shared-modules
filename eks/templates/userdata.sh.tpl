#!/bin/bash
set -o xtrace

# Bootstrap the node
/etc/eks/bootstrap.sh ${cluster_name} \
  --b64-cluster-ca ${cluster_ca} \
  --apiserver-endpoint ${cluster_endpoint} \
  ${bootstrap_extra_args}