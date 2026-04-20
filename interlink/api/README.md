# Building a Qubernetes-Supported Interlink API Image

This image provides the API container used in the Interlink setup. It builds the `interlink` binary from the upstream `interLink` repository and packages it together with the startup script used in the deployment.

## Contents

The image is built in two stages:

1. A **builder stage** that clones and builds the `interLink` repository and produces the `interlink` binary.
2. A **runtime stage** that installs the runtime tools needed by the API container and includes:
   - the built `interlink` binary
   - `start-api.sh`

The API container is responsible for:
- waiting for shared runtime files created by the init container
- preparing SSH access
- rendering the runtime InterLink config
- starting the InterLink API server
- monitoring remote plugin health
- deleting its own pod if repeated health checks fail

Default build parameters are defined in `interlink/api/Dockerfile` and in the GitHub Actions workflow.

## Release a new version

1. Update `interlink/api/Dockerfile` if needed.
2. Commit the changes.
3. Create a Git tag using one of these formats:
   - `interlink-api-vX.Y.Z` for a base version
   - `interlink-api-vX.Y.Z-rN` for a revision

Replace `X.Y.Z` with the image release version you want to use, and `N` with the revision number.

```sh
# For a base version
git tag interlink-api-vX.Y.Z
git push origin interlink-api-vX.Y.Z

# For a revision
git tag interlink-api-vX.Y.Z-rN
git push origin interlink-api-vX.Y.Z-rN