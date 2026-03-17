#!/usr/bin/env bash

set -eux

CLUSTER_NAME="${CLUSTER_NAME:-opensearch-dev}"
NODE_NAME="${NODE_NAME:-node-0}"
NODE_ROLES="${NODE_ROLES:-cluster_manager,data}"
INITIAL_CM_NODES="${INITIAL_CM_NODES:-}"
NETWORK_HOST="${NETWORK_HOST:-_local_,_site_}"
SEED_HOSTS="${SEED_HOSTS:-}"


function set_yaml_prop() {
    local target_file="${1}"
    local key="${2}"
    local value="${3}"

    /usr/bin/python3 /usr/bin/set_conf.py --file "${target_file}" --key "${key}" --value "${value}"
}

function ensure_editable_cacerts_trust_store() {
    # Create a writable PKCS12 truststore derived from the JDK's read-only cacerts.
    # this comes from https://github.com/canonical/opensearch-snap/blob/2/edge/snap/hooks/install#L55
    local dest="${OPENSEARCH_PATH_CERTS}/cacert.p12"
    local jvm_opts="${OPENSEARCH_PATH_CONF}/jvm.options"

    if [ ! -f "${dest}" ]; then
        local src=""
        if [ -f "/etc/ssl/certs/java/cacerts" ]; then
            src="/etc/ssl/certs/java/cacerts"
        elif [ -n "${JAVA_HOME:-}" ] && [ -f "${JAVA_HOME}/lib/security/cacerts" ]; then
            src="${JAVA_HOME}/lib/security/cacerts"
        fi

        local keytool=""
        if [ -n "${JAVA_HOME:-}" ] && [ -x "${JAVA_HOME}/bin/keytool" ]; then
            keytool="${JAVA_HOME}/bin/keytool"
        elif command -v keytool >/dev/null 2>&1; then
            keytool="$(command -v keytool)"
        fi

        if [ -n "${src}" ] && [ -n "${keytool}" ]; then
            "${keytool}" \
                -importkeystore \
                -srckeystore "${src}" \
                -destkeystore "${dest}" \
                -srcstoretype JKS \
                -deststoretype PKCS12 \
                -srcstorepass changeit \
                -deststorepass changeit \
                -noprompt
            # keep this truststore editable by both daemon and root (group).
            chmod 660 "${dest}" || true
        else
            echo "Skipping cacert.p12 generation: missing source cacerts or keytool" >&2
        fi
    fi

    if [ -f "${jvm_opts}" ]; then
        grep -q "javax.net.ssl.trustStore=.*cacert.p12" "${jvm_opts}" \
            || echo "-Djavax.net.ssl.trustStore=${dest}" >> "${jvm_opts}"
        grep -q "javax.net.ssl.trustStorePassword=changeit" "${jvm_opts}" \
            || echo "-Djavax.net.ssl.trustStorePassword=changeit" >> "${jvm_opts}"
    fi
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

ensure_editable_cacerts_trust_store

set_yaml_prop "${conf}" "cluster.name" "${CLUSTER_NAME}"
set_yaml_prop "${conf}" "node.name" "${NODE_NAME}"
set_yaml_prop "${conf}" "node.roles" "$(node_roles)"

if [[ -n "${INITIAL_CM_NODES}" ]] && [[ "${NODE_ROLES}" == *"cluster_manager"* ]]; then
    set_yaml_prop "${conf}" "cluster.initial_cluster_manager_nodes" "$(init_cm_nodes)"
fi

set_yaml_prop "${conf}" "network.host" "$(network_host)"
set_yaml_prop "${conf}" "discovery.seed_hosts" "$(seed_hosts)"
set_yaml_prop "${conf}" "path.data" "${OPENSEARCH_VARLIB}/data"
set_yaml_prop "${conf}" "path.logs" "${OPENSEARCH_VARLOG}/logs"
set_yaml_prop "${conf}" "plugins.security.disabled" "true"
sed -i "s@=logs/@=${OPENSEARCH_VARLOG}/@" "${OPENSEARCH_PATH_CONF}/jvm.options"

cat "${conf}"

exec "${OPENSEARCH_BIN}"/opensearch
