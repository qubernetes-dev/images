#!/bin/sh
set -eu

VIRTUAL_NODE_NAME="${VIRTUAL_NODE_NAME:-}"

KUBERNETES_SERVICE_IP="${KUBERNETES_SERVICE_IP:-}"
KUBERNETES_API_SERVER_IP="${KUBERNETES_API_SERVER_IP:-}"
KUBERNETES_API_SERVER_PORT="${KUBERNETES_API_SERVER_PORT:-}"

VK_BIN="/app/bin/vk"
CONFIG_RENDERED="/app/config/VirtualKubeletConfig.yaml"
GENERATED_KUBECONFIG="/tmp/kubeconfig"

K8S_TOKEN_FILE="/var/run/secrets/kubernetes.io/serviceaccount/token"
K8S_CA_FILE="/var/run/secrets/kubernetes.io/serviceaccount/ca.crt"
K8S_NS_FILE="/var/run/secrets/kubernetes.io/serviceaccount/namespace"

log() {
  printf '%s %s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" "$*"
}

require_value() {
  key="$1"
  value="$2"
  if [ -z "$value" ]; then
    log "ERROR: required value missing: $key"
    exit 1
  fi
}

k8s_token() {
  cat "$K8S_TOKEN_FILE"
}

delete_existing_node_if_present() {
  if curl -fsS \
    --cacert "$K8S_CA_FILE" \
    -H "Authorization: Bearer $(k8s_token)" \
    "$(k8s_api_base)/api/v1/nodes/$VIRTUAL_NODE_NAME" >/dev/null 2>&1; then

    log "Existing virtual node '$VIRTUAL_NODE_NAME' found, deleting it before start"

    curl -fsS -X DELETE \
      --cacert "$K8S_CA_FILE" \
      -H "Authorization: Bearer $(k8s_token)" \
      "$(k8s_api_base)/api/v1/nodes/$VIRTUAL_NODE_NAME" >/dev/null

    sleep 3
  else
    log "No existing virtual node '$VIRTUAL_NODE_NAME' found"
  fi
}

validate_config_file() {
  if [ ! -f "$CONFIG_RENDERED" ]; then
    log "ERROR: mounted virtual kubelet config not found: $CONFIG_RENDERED"
    exit 1
  fi
}

validate_incluster_auth_inputs() {
  if [ ! -f "$K8S_TOKEN_FILE" ]; then
    log "ERROR: service account token not found: $K8S_TOKEN_FILE"
    exit 1
  fi

  if [ ! -f "$K8S_CA_FILE" ]; then
    log "ERROR: service account CA file not found: $K8S_CA_FILE"
    exit 1
  fi

  if [ ! -f "$K8S_NS_FILE" ]; then
    log "ERROR: service account namespace file not found: $K8S_NS_FILE"
    exit 1
  fi

  if [ -n "$KUBERNETES_API_SERVER_IP" ]; then
    require_value "KUBERNETES_API_SERVER_PORT" "$KUBERNETES_API_SERVER_PORT"
  else
    require_value "KUBERNETES_SERVICE_HOST" "${KUBERNETES_SERVICE_HOST:-}"
    require_value "KUBERNETES_SERVICE_PORT" "${KUBERNETES_SERVICE_PORT:-}"
  fi
}

k8s_api_base() {
  if [ -n "$KUBERNETES_API_SERVER_IP" ]; then
    printf 'https://%s:%s' "$KUBERNETES_API_SERVER_IP" "$KUBERNETES_API_SERVER_PORT"
  else
    printf 'https://%s:%s' "$KUBERNETES_SERVICE_HOST" "$KUBERNETES_SERVICE_PORT"
  fi
}

generate_kubeconfig() {
  token="$(cat "$K8S_TOKEN_FILE")"
  namespace="$(cat "$K8S_NS_FILE")"
  server="$(k8s_api_base)"

  cat > "$GENERATED_KUBECONFIG" <<EOF
apiVersion: v1
kind: Config
clusters:
- name: in-cluster
  cluster:
    server: ${server}
    certificate-authority: ${K8S_CA_FILE}
users:
- name: service-account
  user:
    token: ${token}
contexts:
- name: default
  context:
    cluster: in-cluster
    user: service-account
    namespace: ${namespace}
current-context: default
EOF

  chmod 600 "$GENERATED_KUBECONFIG"
  export KUBECONFIG="$GENERATED_KUBECONFIG"
  log "Generated kubeconfig at $GENERATED_KUBECONFIG for API server $server"
}

main() {
  require_value "VIRTUAL_NODE_NAME" "$VIRTUAL_NODE_NAME"
  validate_config_file
  validate_incluster_auth_inputs
  generate_kubeconfig

  # TODO: Test if deleting an existing node is even necessary
  # delete_existing_node_if_present

  log "Starting virtual-kubelet for node '$VIRTUAL_NODE_NAME'"
  exec "$VK_BIN" \
    --configpath="$CONFIG_RENDERED" \
    --nodename="$VIRTUAL_NODE_NAME"
}

main "$@"