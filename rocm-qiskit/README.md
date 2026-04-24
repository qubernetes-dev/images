# Building a Qubernetes-Supported ROCm Qiskit Image

This image provides a ROCm-based environment for running Qiskit with a ROCm-built `qiskit-aer` wheel.

It is intended as the ROCm Qiskit counterpart to the CUDA Qiskit image in this repository.

## Contents

The image is built in two stages:

1. A **builder stage** that compiles a ROCm-enabled `qiskit-aer` wheel from source.
2. A **runtime stage** that installs:
   - `qiskit`
   - the built `qiskit-aer-gpu-rocm` wheel
   - only the runtime system libraries required for Qiskit Aer execution

This image is meant to provide the ROCm and Qiskit components as a base image. Additional Python libraries can be installed on top of this image in Q8S project files.

Default build parameters are defined in `rocm-qiskit/Dockerfile` and in the GitHub Actions workflow.

## Release a new version

1. Update `rocm-qiskit/Dockerfile` if needed.
2. Commit the changes.
3. Create a Git tag using one of these formats:
   - `rocm-qiskit-vX.Y.Z` for a base version
   - `rocm-qiskit-vX.Y.Z-rN` for a revision

Replace `X.Y.Z` with the image release version you want to use, and `N` with the revision number.

```sh
# For a base version
git tag rocm-qiskit-vX.Y.Z
git push origin rocm-qiskit-vX.Y.Z

# For a revision
git tag rocm-qiskit-vX.Y.Z-rN
git push origin rocm-qiskit-vX.Y.Z-rN