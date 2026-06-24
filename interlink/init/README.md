# Building a Qubernetes-Supported Interlink Init Image

This image provides the init container used in the Interlink setup for preparing and starting the remote `slurm-sd` plugin over SSH.

## Contents

The image is built in two stages:

1. A **builder stage** that clones and builds the `interlink-slurm-plugin` repository and produces the `slurm-sd` binary.
2. A **runtime stage** that installs the runtime tools needed by the init container and includes:
   - the built `slurm-sd` binary
   - `init.py`
   - `port.sh`

The init container is responsible for:
- preparing SSH access
- validating host fingerprints
- selecting a remote port
- copying artifacts to the remote host
- rendering and copying the final Slurm config
- starting the remote plugin
- checking plugin health

Default build parameters are defined in `interlink/init/Dockerfile` and in the GitHub Actions workflow.

## Release a new version

1. Update `interlink/init/Dockerfile` if needed.
2. Commit the changes.
3. Create a Git tag using one of these formats:
   - `interlink-init-vX.Y.Z` for a base version
   - `interlink-init-vX.Y.Z-rN` for a revision

Replace `X.Y.Z` with the image release version you want to use, and `N` with the revision number.

```sh
# For a base version
git tag interlink-init-vX.Y.Z
git push origin interlink-init-vX.Y.Z

# For a revision
git tag interlink-init-vX.Y.Z-rN
git push origin interlink-init-vX.Y.Z-rN