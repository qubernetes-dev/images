#!/bin/sh
set -eu

REMOTE_USER="${REMOTE_USER:-}"
REMOTE_HOST="${REMOTE_HOST:-}"
JUMP_HOSTS="${JUMP_HOSTS:-}"

LOCAL_TUNNEL_PORT="${LOCAL_TUNNEL_PORT:-4000}"
SERVER_ALIVE_INTERVAL="${SERVER_ALIVE_INTERVAL:-30}"

SHARED_PORT_FILE="${SHARED_PORT_FILE:-/runtime/remote-port}"
SHARED_KNOWN_HOSTS_FILE="${SHARED_KNOWN_HOSTS_FILE:-/runtime/known_hosts}"

TUNNEL_MAX_RETRIES="${TUNNEL_MAX_RETRIES:-5}"
TUNNEL_RETRY_DELAY_SECONDS="${TUNNEL_RETRY_DELAY_SECONDS:-10}"

SSH_DIR="/root/.ssh"
SSH_KEY_SRC="/keys/id_ed25519"
SSH_KEY="$SSH_DIR/id_ed25519"
SSH_KNOWN_HOSTS="$SSH_DIR/known_hosts"

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

main() {
  require_value "REMOTE_USER" "$REMOTE_USER"
  require_value "REMOTE_HOST" "$REMOTE_HOST"

  wait_for_shared_files
  prepare_ssh

  retries=0

  while true; do
    remote_port="$(read_remote_port || true)"
    if [ -z "$remote_port" ]; then
      log "WARN: remote port file is empty, retrying"
      sleep "$TUNNEL_RETRY_DELAY_SECONDS"
      continue
    fi

    log "SSH tunnel starting: local ${LOCAL_TUNNEL_PORT} -> remote ${remote_port}"

    if [ -n "$JUMP_HOSTS" ]; then
      ssh -N \
        -i "$SSH_KEY" \
        -o StrictHostKeyChecking=yes \
        -o UserKnownHostsFile="$SSH_KNOWN_HOSTS" \
        -o ServerAliveInterval="$SERVER_ALIVE_INTERVAL" \
        -o ServerAliveCountMax=3 \
        -J "$JUMP_HOSTS" \
        -L 0.0.0.0:"$LOCAL_TUNNEL_PORT":127.0.0.1:"$remote_port" \
        "$REMOTE_USER@$REMOTE_HOST" || true
    else
      ssh -N \
        -i "$SSH_KEY" \
        -o StrictHostKeyChecking=yes \
        -o UserKnownHostsFile="$SSH_KNOWN_HOSTS" \
        -o ServerAliveInterval="$SERVER_ALIVE_INTERVAL" \
        -o ServerAliveCountMax=3 \
        -L 0.0.0.0:"$LOCAL_TUNNEL_PORT":127.0.0.1:"$remote_port" \
        "$REMOTE_USER@$REMOTE_HOST" || true
    fi

    retries=$((retries + 1))
    log "WARN: SSH tunnel dropped, retry $retries/$TUNNEL_MAX_RETRIES"

    if [ "$retries" -ge "$TUNNEL_MAX_RETRIES" ]; then
      log "ERROR: tunnel exceeded retry limit, forcing pod recreation"
      delete_own_pod
      sleep 3600
    fi

    sleep "$TUNNEL_RETRY_DELAY_SECONDS"
  done
}

main "$@"