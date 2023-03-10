#!/usr/bin/env bash

version="$(cat rockcraft.yaml | yq .version)"

# create first cm_node container
container_0_id=$(docker run \
    -d --rm -it \
    -e NODE_NAME=cm0 \
    -e INITIAL_CM_NODES=cm0 \
    -p 9200:9200 \
    --name cm0 \
    charmed-opensearch:"${version}")
container_0_ip=$(docker inspect -f '{{ .NetworkSettings.IPAddress }}' "${container_0_id}")

# wait a bit for it to fully initialize
sleep 15s

# create data/voting_only node container
container_1_id=$(docker run \
    -d --rm -it \
    -e NODE_NAME=data1 \
    -e SEED_HOSTS="${container_0_ip}" \
    -e NODE_ROLES=data,voting_only \
    -p 9201:9200 \
    --name data1 \
    charmed-opensearch:"${version}")
container_1_ip=$(docker inspect -f '{{ .NetworkSettings.IPAddress }}' "${container_1_id}")

# wait a bit for it to fully initialize
sleep 15s

# create 2nd cm_node container
docker run \
    -d --rm -it \
    -e NODE_NAME=cm1 \
    -e SEED_HOSTS="${container_0_ip},${container_1_ip}" \
    -e INITIAL_CM_NODES="cm0,cm1" \
    -p 9202:9200 \
    --name cm1 \
    charmed-opensearch:"${version}"

# wait a bit for it to fully initialize
sleep 15s

# test

# test node
cluster_resp=$(curl -k -XGET http://localhost:9200)
echo -e "Cluster Response: \n ${cluster_resp}"
node_name=$(echo "${cluster_resp}" | jq -r .name)
if [ "${node_name}" != "cm0" ]; then
    echo "Error: Wrong node name."
    exit 1
fi

# query all nodes of cluster
successful_nodes="$(curl -k -XGET http://localhost:9200/_nodes | jq ._nodes.successful)"
echo "Successful nodes: ${successful_nodes}"
if [ "${successful_nodes}" != 3 ]; then
    echo "Error: Wrong number of nodes."
    exit 1
fi

all_nodes="$(curl -X GET http://127.0.1.1:9200/_nodes/ | \
  jq '.nodes | values[] | .name' | \
  jq -s '. |= if . then sort else empty end' | \
  jq -r '. | values[]' | \
  paste -sd "," - \
)"
echo "All nodes: ${all_nodes}"
if [ "${all_nodes}" != "cm0,cm1,data1" ]; then
    exit 1
fi
