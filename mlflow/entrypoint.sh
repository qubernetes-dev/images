# filepath: entrypoint.sh
#!/bin/sh
# Exit immediately if a command exits with a non-zero status.
set -e

# Default values (can be overridden by environment variables if needed)
MLFLOW_HOST="${MLFLOW_HOST:-0.0.0.0}"
MLFLOW_DEFAULT_ARTIFACT_ROOT="${MLFLOW_DEFAULT_ARTIFACT_ROOT:-s3://mlflow}"

# Start the MLflow server using exec to replace the shell process
# "$@" allows passing additional arguments from Kubernetes 'args' if needed in the future
exec mlflow server \
    --host "$MLFLOW_HOST" \
    --default-artifact-root "$MLFLOW_DEFAULT_ARTIFACT_ROOT" \
    "$@"