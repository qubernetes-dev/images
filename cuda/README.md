# Introduction

This serve as a base image for containers that need GPU accelerated quantum simulators like Qiskit Aer or PennyLine Lightning.

## Release a new version

1. Update the `Dockerfile` to change the base image.
2. Update the `requirements.txt` to set the desired dependencies.
3. Commit the changes.
4. Create a Git tag using the format: `cuda-vX.Y.Z` for a base version, or `cuda-vX.Y.Z-rN` for a revision (replace X.Y.Z with the CUDA version used in `Dockerfile` and N with the revision number).

```sh
# For a base version
git tag cuda-vX.Y.Z
git push origin cuda-vX.Y.Z
# For a revision
git tag cuda-vX.Y.Z-rN
git push origin cuda-vX.Y.Z-rN
```

5. The Github workflow (pipeline) will automatically build and push the image to Github image registry.
6. The newly created Qubernetes compatible CUDA image can be found in:
   - `ghcr.io/qubernetes-dev/cuda:X.Y.Z` (for base tags like `cuda-vX.Y.Z`)
   - `ghcr.io/qubernetes-dev/cuda:X.Y.Z-rN` (for revision tags like `cuda-vX.Y.Z-rN`)
