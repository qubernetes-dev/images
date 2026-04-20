#!/bin/sh
set -eu

REMOTE_USER="${REMOTE_USER:-}"
REMOTE_HOST="${REMOTE_HOST:-}"
JUMP_HOSTS="${JUMP_HOSTS:-}"

SHARED_PORT_FILE="${SHARED_PORT_FILE:-/runtime/remote-port}"
SHARED_KNOWN_HOSTS_FILE="${SHARED_KNOWN_HOSTS_FILE:-/runtime/known_hosts}"

API_HEALTHCHECK_INTERVAL="${API_HEALTHCHECK_INTERVAL:-15}"
API_FAILURE_THRESHOLD="${API_FAILURE_THRESHOLD:-5}"
CONNECT_TIMEOUT="${CONNECT_TIMEOUT:-10}"

CONFIG_RENDERED="/app/config/InterlinkConfig.yaml"
CONFIG_RUNTIME="/tmp/InterlinkConfig.runtime.yaml"
API_BIN="/app/bin/interlink"

SSH_DIR="/root/.ssh"
SSH_KEY_SRC="/keys/id_ed25519"
SSH_KEY="$SSH_DIR/id_ed25519"
SSH_KNOWN_HOSTS="$SSH_DIR/known_hosts"

K8S_TOKEN_FILE="/var/run/secrets/kubernetes.io/serviceaccount/token"
K8S_CA_FILE="/var/run/secrets/kubernetes.io/serviceaccount/ca.crt"
K8S_NS_FILE="/var/run/secrets/kubernetes.io/serviceaccount/namespace"

API_PID=""

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

k8s_namespace() {
  cat "$K8S_NS_FILE"
}

k8s_api_base() {
  printf 'https://%s:%s' "$KUBERNETES_SERVICE_HOST" "$KUBERNETES_SERVICE_PORT"
}

k8s_token() {
  cat "$K8S_TOKEN_FILE"
}

delete_own_pod() {
  pod_name="${HOSTNAME:-}"
  namespace="$(k8s_namespace)"

  if [ -z "$pod_name" ]; then
    log "ERROR: HOSTNAME is empty, cannot self-delete pod"
    exit 1
  fi

  log "Deleting pod '$pod_name' in namespace '$namespace' to trigger recreation"

  curl -fsS -X DELETE \
    --cacert "$K8S_CA_FILE" \
    -H "Authorization: Bearer $(k8s_token)" \
    "$(k8s_api_base)/api/v1/namespaces/$namespace/pods/$pod_name" >/dev/null
}

prepare_ssh() {
  mkdir -p "$SSH_DIR"

  if [ ! -f "$SSH_KEY_SRC" ]; then
    log "ERROR: SSH key not found: $SSH_KEY_SRC"
    exit 1
  fi

  if [ ! -f "$SHARED_KNOWN_HOSTS_FILE" ]; then
    log "ERROR: shared known_hosts not found yet: $SHARED_KNOWN_HOSTS_FILE"
    exit 1
  fi

  cp "$SSH_KEY_SRC" "$SSH_KEY"
  cp "$SHARED_KNOWN_HOSTS_FILE" "$SSH_KNOWN_HOSTS"

  chmod 700 "$SSH_DIR"
  chmod 600 "$SSH_KEY"
  chmod 600 "$SSH_KNOWN_HOSTS"
}

wait_for_shared_files() {
  while [ ! -f "$SHARED_KNOWN_HOSTS_FILE" ]; do
    log "INFO: waiting for shared known_hosts file"
    sleep 2
  done

  while [ ! -f "$SHARED_PORT_FILE" ]; do
    log "INFO: waiting for shared remote port file"
    sleep 2
  done
}

read_remote_port() {
  if [ ! -f "$SHARED_PORT_FILE" ]; then
    return 1
  fi
  tr -d '\r\n' < "$SHARED_PORT_FILE"
}

run_ssh() {
  if [ -n "$JUMP_HOSTS" ]; then
    ssh \
      -i "$SSH_KEY" \
      -o StrictHostKeyChecking=yes \
      -o UserKnownHostsFile="$SSH_KNOWN_HOSTS" \
      -o ConnectTimeout="$CONNECT_TIMEOUT" \
      -J "$JUMP_HOSTS" \
      "$REMOTE_USER@$REMOTE_HOST" \
      "$@"
  else
    ssh \
      -i "$SSH_KEY" \
      -o StrictHostKeyChecking=yes \
      -o UserKnownHostsFile="$SSH_KNOWN_HOSTS" \
      -o ConnectTimeout="$CONNECT_TIMEOUT" \
      "$REMOTE_USER@$REMOTE_HOST" \
      "$@"
  fi
}

validate_config_file() {
  if [ ! -f "$CONFIG_RENDERED" ]; then
    log "ERROR: mounted interLink config not found: $CONFIG_RENDERED"
    exit 1
  fi
}

render_runtime_config() {
  require_value "HOSTNAME" "${HOSTNAME:-}"

  log "Rendering runtime interLink config using pod hostname '${HOSTNAME}'"

  cp "$CONFIG_RENDERED" "$CONFIG_RUNTIME"

  sed -i "s|SidecarURL: \"<SIDECAR_URL>\"|SidecarURL: \"http://${HOSTNAME}\"|g" "$CONFIG_RUNTIME"

  if grep -q 'SidecarURL: "<SIDECAR_URL>"' "$CONFIG_RUNTIME"; then
    log "ERROR: failed to replace <SIDECAR_URL> placeholder in runtime config"
    log "INFO: rendered config follows:"
    cat "$CONFIG_RUNTIME" || true
    exit 1
  fi

  if ! grep -q "SidecarURL: \"http://${HOSTNAME}\"" "$CONFIG_RUNTIME"; then
    log "ERROR: runtime config does not contain expected SidecarURL"
    log "INFO: rendered config follows:"
    cat "$CONFIG_RUNTIME" || true
    exit 1
  fi

  log "Runtime config rendered successfully at $CONFIG_RUNTIME"
}

start_api() {
  log "Starting interLink API server"
  INTERLINKCONFIGPATH="$CONFIG_RUNTIME" "$API_BIN" &
  API_PID=$!
  echo "$API_PID" > /tmp/interlink-api.pid
}

check_remote_plugin_health() {
  remote_port="$1"

  if [ -z "$remote_port" ]; then
    return 1
  fi

  run_ssh \
    "curl -sf -X GET http://127.0.0.1:${remote_port}/status \
     -H 'Content-Type: application/json' \
     -d '[]' > /dev/null" >/dev/null 2>&1
}

monitor_remote_plugin() {
  failures=0

  while true; do
    if ! kill -0 "$API_PID" 2>/dev/null; then
      log "ERROR: interLink API server process exited"
      delete_own_pod
      sleep 3600
    fi

    remote_port="$(read_remote_port || true)"
    if [ -z "$remote_port" ]; then
      failures=$((failures + 1))
      log "WARN: shared remote port is missing or empty ($failures/$API_FAILURE_THRESHOLD)"
    elif check_remote_plugin_health "$remote_port"; then
      failures=0
    else
      failures=$((failures + 1))
      log "WARN: remote plugin health check failed on remote port ${remote_port} ($failures/$API_FAILURE_THRESHOLD)"
    fi

    if [ "$failures" -ge "$API_FAILURE_THRESHOLD" ]; then
      log "ERROR: remote plugin unhealthy after repeated checks, forcing pod recreation"
      delete_own_pod
      sleep 3600
    fi

    sleep "$API_HEALTHCHECK_INTERVAL"
  done
}

main() {
  require_value "REMOTE_USER" "$REMOTE_USER"
  require_value "REMOTE_HOST" "$REMOTE_HOST"

  validate_config_file
  wait_for_shared_files
  prepare_ssh
  render_runtime_config
  start_api
  monitor_remote_plugin
}

main "$@"