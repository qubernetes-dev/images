# Building a Qubernetes-Supported ROCm Image

This image provides a minimal ROCm-based Python environment for running workloads on ROCm-enabled systems.

It is intended as the ROCm counterpart to the CUDA base image in this repository.

## Contents

The image contains:

- ROCm runtime/development environment from the upstream ROCm base image
- Python 3
- A Python virtual environment at `/opt/venv`
- Upgraded `pip`, `setuptools`, and `wheel`

For Qiskit support, use the separate ROCm Qiskit image.

## Release a new version

1. Update `rocm/Dockerfile` if needed.
2. Commit the changes.
3. Create a Git tag using one of these formats:
   - `rocm-vX.Y.Z` for a base version
   - `rocm-vX.Y.Z-rN` for a revision

Replace `X.Y.Z` with the image release version you want to use, and `N` with the revision number.

```sh
# For a base version
git tag rocm-vX.Y.Z
git push origin rocm-vX.Y.Z

# For a revision
git tag rocm-vX.Y.Z-rN
git push origin rocm-vX.Y.Z-rN