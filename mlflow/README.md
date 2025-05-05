# Building a Qubernetes-Supported MLflow Image

Follow these steps to create Qubernetes-compatible MLflow Docker image.

### 1. Update `Dockerfile` & `requirements.txt` (if needed)
- Edit `mlflow/Dockerfile` to change docker image building process
- Edit `mlflow/requirements.txt` to set the desired MLflow version and compatible dependencies.

### 2. Commit the changes

### 3. Create a Git tag
- Use the format: `mlflow-vX.Y.Z` (replace X.Y.Z with the MLflow version used in `requirements.txt` file).
```sh
git tag mlflow-vX.Y.Z
git push origin mlflow-vX.Y.Z
```

### Github workflow (pipeline) will automatically build and push the image to Github image registry
- The newly created Qubernetes compatible MLflow image can found in `ghcr.io/qubernetes-dev/mlflow:X.Y.Z` when the tag is pushed.

## Example

To build and push MLflow 2.21.1:
```sh
# Update Dockerfile & requirements.txt according to the requirement
# Commit changes
git add requirements.txt Dockerfile
git commit -m "Update MLflow to 2.21.1"

# Tag and push
git tag mlflow-v2.21.1
git push origin mlflow-v2.21.1

# The pipeline will handle building and pushing the image.
```
