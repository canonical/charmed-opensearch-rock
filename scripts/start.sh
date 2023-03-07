#!/usr/bin/env bash

set -eux


function set_yaml_prop() {
    local target_file="${1}"
    local full_key_path="${2}"
    local value="${3}"
    local append="${4:-"no"}"
    local split_array_content="${5:-"yes"}"

    operator="="

    # allow appending
    if [ "${append}" == "yes" ]; then
        operator="+="
    fi

    # traversal must be done through the "/" separator to allow for "." in key names
    IFS='/' read -r -a keys <<< "${full_key_path}"

    expression=""
    for key in "${keys[@]}"
    do
        prefix=""
        suffix=""
        if [[ "${key}" != [* ]]; then
            prefix=".\""
            suffix="\""
        fi
        expression="${expression}${prefix}${key}${suffix}"
    done

    # yq fails serializing values starting with or containing special characters so they must be wrapped in double quotes
    # so, wrap any non number
    if [[ "${value}" == [* ]]; then
        value=${value:1:-1}

        if [ "${split_array_content}" == "yes" ]; then
            IFS=',' read -r -a arr_elts <<< "${value}"

            value=""
            for key in "${arr_elts[@]}"
            do
                key=$(echo -e "${key}" | tr -d '[:space:]')
                if ! [[ ${key} =~ ^[0-9]+$ ]] && ! [[ ${key} =~ ^\".*\"$ ]]; then
                    key="\"${key}\""
                fi
                value="${value}${key},"
            done
            value="[${value:0:-1}]"
        else
            value="[${value}]"
        fi
    elif ! [[ "${value}" =~ ^[0-9]+$ ]]  && ! [[ ${value} =~ ^\".*\"$ ]]; then
       value="\"${value}\""
    fi

    /usr/bin/yq -i "${expression} ${operator} ${value}" "${target_file}"
}

function network_host() {
    echo "[ \"_site_\", \"$(hostname -i)\" ]"
}

function node_roles() {
    formatted_roles=""

    IFS=',' read -r -a roles <<< "${NODE_ROLES}"
    for role in "${roles[@]}"; do
        if [ -n "${formatted_roles}" ]; then
            formatted_roles="${formatted_roles}, "
        fi
        formatted_roles="${formatted_roles}\"$(echo -e "${role}" | tr -d '[:space:]')\""
    done

    echo "[ ${formatted_roles} ]"
}

function init_cm_nodes() {
    formatted_nodes=""

    IFS=',' read -r -a nodes <<< "${INITIAL_CM_NODES}"
    for node in "${nodes[@]}"; do
        if [ -n "${formatted_nodes}" ]; then
            formatted_nodes="${formatted_nodes}, "
        fi
        formatted_nodes="${formatted_nodes}\"$(echo -e "${node}" | tr -d '[:space:]')\""
    done

    echo "[ ${formatted_nodes} ]"
}

function seed_hosts() {
    formatted_hosts=""

    if [[ "${NODE_ROLES}" == *"cluster_manager"* ]]; then
        formatted_hosts="\"$(hostname -i)\""
    fi

    IFS=',' read -r -a hosts <<< "${SEED_HOSTS}"
    for host in "${hosts[@]}"; do
        if [ -n "${formatted_hosts}" ]; then
            formatted_hosts="${formatted_hosts}, "
        fi
        formatted_hosts="${formatted_hosts}\"$(echo -e "${host}" | tr -d '[:space:]')\""
    done

    echo "[ ${formatted_hosts} ]"
}


conf="${OPENSEARCH_PATH_CONF}/opensearch.yml"

set_yaml_prop "${conf}" "cluster.name" "${CLUSTER_NAME}"
set_yaml_prop "${conf}" "node.name" "${NODE_NAME}"
set_yaml_prop "${conf}" "node.roles" "$(node_roles)"

if [[ -n "${INITIAL_CM_NODES}" ]] && [[ "${NODE_ROLES}" == *"cluster_manager"* ]]; then
    set_yaml_prop "${conf}" "cluster.initial_cluster_manager_nodes" "$(init_cm_nodes)"
fi

set_yaml_prop "${conf}" "network.host" "$(network_host)"
set_yaml_prop "${conf}" "discovery.seed_hosts" "$(seed_hosts)"
set_yaml_prop "${conf}" "path.data" "/data"
set_yaml_prop "${conf}" "path.logs" "/logs"
set_yaml_prop "${conf}" "plugins.security.disabled" "true"

cat "${conf}"

/usr/bin/setpriv \
  --clear-groups \
  --reuid opensearch \
  --regid opensearch \
  -- /bin/opensearch
