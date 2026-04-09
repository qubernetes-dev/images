# Building a Qubernetes-Supported ROCm Image

This image provides a ROCm-based environment for running Qiskit with a ROCm-built `qiskit-aer` wheel. It is intended as the ROCm counterpart to the CUDA image in this repository.

## Contents

The image is built in two stages:

1. A **builder stage** that compiles a ROCm-enabled `qiskit-aer` wheel from source.
2. A **runtime stage** that installs:
   - `qiskit`
   - the built `qiskit-aer-gpu-rocm` wheel
   - a set of Qiskit-related Python dependencies

This image is meant to provide the ROCm and Qiskit components as a base image. Additional python libraries can be installed on top of this image in Q8Sproject files.

Default build parameters are defined in `rocm/Dockerfile` and in the GitHub Actions workflow.

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