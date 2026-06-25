#!/bin/sh
# filepath: entrypoint.sh
# Exit immediately if a command exits with a non-zero status.
set -e

# Default values (can be overridden by environment variables)
MLFLOW_HOST="${MLFLOW_HOST:-0.0.0.0}"
MLFLOW_DEFAULT_ARTIFACTS_DESTINATION="${MLFLOW_DEFAULT_ARTIFACTS_DESTINATION:-s3://mlflow}"

# Build the argument list dynamically so new optional flags can be added without branching.
# MLflow 3.x requires --allowed-hosts to be passed as a CLI flag (env var alone is insufficient).
set -- --host "$MLFLOW_HOST" --artifacts-destination "$MLFLOW_DEFAULT_ARTIFACTS_DESTINATION"
[ -n "$MLFLOW_ALLOWED_HOSTS" ] && set -- "$@" --allowed-hosts "$MLFLOW_ALLOWED_HOSTS"

exec mlflow server "$@"