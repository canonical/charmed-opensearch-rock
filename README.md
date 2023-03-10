# Charmed OpenSearch Rock

This repository contains the packaging metadata for creating a Charmed OpenSearch ROCK. This ROCK image is based on the [OpenSearch Snap](https://github.com/canonical/opensearch-snap)

For more information on ROCKs, visit the [rockcraft Github](https://github.com/canonical/rockcraft).

## Building the ROCK
The steps outlined below are based on the assumption that you are building the ROCK with the latest LTS of Ubuntu.  
If you are using another version of Ubuntu or another operating system, the process may be different.
To avoid any issue with other operating systems you can simply build the image with [multipass](https://multipass.run/):
```bash
sudo snap install multipass
multipass launch 22.04 -n rock-dev
multipass shell rock-dev
``` 

### Clone Repository
```bash
git clone https://github.com/canonical/charmed-opensearch-rock.git
cd charmed-opensearch-rock
```
### Installing Prerequisites
```bash
sudo snap install rockcraft --edge --classic
sudo snap install docker
sudo snap install lxd
sudo snap install skopeo --edge --devmode
```
### Configuring Prerequisites
```bash
sudo usermod -aG docker $USER 
sudo lxd init --auto
```
*_NOTE:_* You will need to open a new shell for the group change to take effect (i.e. `su - $USER`)
### Packing and Running the ROCK
```bash
rockcraft pack

sudo skopeo --insecure-policy copy oci-archive:charmed-opensearch_2.6.0_amd64.rock docker-daemon:opensearch:2.6.0

docker run \
  -d --rm -it \
  -e NODE_NAME=cm0 \
  -e INITIAL_CM_NODES=cm0 \
  -p 9200:9200 \
  --name cm0 \
  charmed-opensearch:2.6.0
```

### Testing a multi nodes deployment:
```
# create first cm_node container
container_0_id=$(docker run \
  -d --rm -it \
  -e NODE_NAME=cm0 \
  -e INITIAL_CM_NODES=cm0 \
  -p 9200:9200 \
  --name cm0 \
  charmed-opensearch:2.6.0)
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
    charmed-opensearch:2.6.0)
container_1_ip=$(docker inspect -f '{{ .NetworkSettings.IPAddress }}' "${container_1_id}")

# wait a bit for it to fully initialize
sleep 15s

# create 2nd cm_node container
container_2_id=$(docker run \
    -d --rm -it \
    -e NODE_NAME=cm1 \
    -e SEED_HOSTS="${container_0_ip},${container_1_ip}" \
    -e INITIAL_CM_NODES="cm0,cm1" \
    -p 9202:9200 \
    --name cm1 \
    charmed-opensearch:2.6.0)

# wait a bit for it to fully initialize
sleep 15s
```

You now can query the nodes:
```
curl -X GET http://127.0.1.1:9200/_nodes/
```
And expect to see 3 nodes.

**NOTE:** This deployment IS NOT suitable for production AS IS. As this deployment disables and does NOT configure the security of OpenSearch. Please use it as part of the Juju OpenSearch K8s charm once ready.

## License
The Charmed OpenSearch ROCK is free software, distributed under the Apache
Software License, version 2.0. See
[LICENSE](https://github.com/canonical/opensearch-rock/blob/main/LICENSE)
for more information.


