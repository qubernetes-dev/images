#!/bin/sh
set -eu

# Expected enviroment variables. Defaults are set so the port range will be [4000,4100] 
# with no preferred port set. This script is perfectly usable without separately setting the
# enviroment variables, as the port 4000 is the preferred port for using this script anyway.
START_PORT="${START_PORT:-4000}"
END_PORT="${END_PORT:-4100}"
PREFERRED_PORT="${PREFERRED_PORT:-}"

# Helper function for logging errors
log_err() {
  printf '%s\n' "$*" >&2
}

# Checks that a given argument is a valid number
is_integer() {
  case "$1" in
    ''|*[!0-9]*)
      return 1
      ;;
    *)
      return 0
      ;;
  esac
}

# Checks that a given port is within the closed interval of [START_PORT, END_PORT]
port_in_range() {
  port="$1"

  if [ "$port" -lt "$START_PORT" ] || [ "$port" -gt "$END_PORT" ]; then
    return 1
  fi

  return 0
}

# Function for detecting if a specific port is currently in use with the ss tool
is_port_in_use_ss() {
  port="$1"
  ss -ltn 2>/dev/null | awk -v p=":$port" '
    $4 ~ p"$" { found=1 }
    END { exit(found ? 0 : 1) }
  '
}

# Function for detecting if a specific port is currently in use with the netstat tool
is_port_in_use_netstat() {
  port="$1"
  netstat -ltn 2>/dev/null | awk -v p=":$port" '
    $4 ~ p"$" { found=1 }
    END { exit(found ? 0 : 1) }
  '
}

# Function for detecting if a specific port is currently in use with the lsof tool
is_port_in_use_lsof() {
  port="$1"
  lsof -iTCP:"$port" -sTCP:LISTEN >/dev/null 2>&1
}

# Function that checks if a given port is in use, using one of three tools (ss/netstat/lsof)
# depending on which is available in the system
is_port_in_use() {
  port="$1"

  if command -v ss >/dev/null 2>&1; then
    if is_port_in_use_ss "$port"; then
      return 0
    else
      return 1
    fi
  fi

  if command -v netstat >/dev/null 2>&1; then
    if is_port_in_use_netstat "$port"; then
      return 0
    else
      return 1
    fi
  fi

  if command -v lsof >/dev/null 2>&1; then
    if is_port_in_use_lsof "$port"; then
      return 0
    else
      return 1
    fi
  fi

  log_err "ERROR: No supported port inspection tool found (ss, netstat, or lsof)."
  exit 2
}

# Function that iterates through a given range of ports and selects the first one that is available
# for use (not used by any other process currently)
find_available_port() {
  current="$START_PORT"

  if [ -n "$PREFERRED_PORT" ]; then
    if ! is_integer "$PREFERRED_PORT"; then
      log_err "ERROR: PREFERRED_PORT is not an integer: $PREFERRED_PORT"
      exit 2
    fi

    if port_in_range "$PREFERRED_PORT" && ! is_port_in_use "$PREFERRED_PORT"; then
      printf '%s\n' "$PREFERRED_PORT"
      return 0
    fi
  fi

  while [ "$current" -le "$END_PORT" ]; do
    if ! is_port_in_use "$current"; then
      printf '%s\n' "$current"
      return 0
    fi
    current=$((current + 1))
  done

  return 1
}


# Main loop. Check that given enviroment variables are valid numbers (START_PORT and END_PORT)
# and then start the search loop.
main() {
  if ! is_integer "$START_PORT"; then
    log_err "ERROR: START_PORT is not an integer: $START_PORT"
    exit 2
  fi

  if ! is_integer "$END_PORT"; then
    log_err "ERROR: END_PORT is not an integer: $END_PORT"
    exit 2
  fi

  if [ "$START_PORT" -gt "$END_PORT" ]; then
    log_err "ERROR: START_PORT must be <= END_PORT"
    exit 2
  fi

  if ! find_available_port; then
    log_err "ERROR: No available port found in range ${START_PORT}-${END_PORT}"
    exit 1
  fi
}

main "$@"