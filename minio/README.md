# Building a Qubernetes-Supported MinIO Image

Unlike the other images in this repo, this image is built **from source** rather than from a
pre-built upstream binary, so it reproduces the official MinIO release without depending on
`dl.min.io`'s binary downloads.

## Contents

The final (runtime) image contains:

- The `minio` binary, compiled from the pinned `src/` submodule commit
- CA certificates
- The entrypoint script and license/credits files, copied individually from `src/`

assembled the same way as upstream's `Dockerfile.release`. The source tree itself (`src/`) is
only present in the discarded builder stage, not in the final image.

## Release a new version

1. Bump the pinned commit in `minio/src` to the desired `minio/minio` release tag.
2. Commit the change.
3. Create a Git tag using the exact upstream release tag as the version (MinIO's releases are
   date-stamped, not semver, so the tag is reused verbatim instead of translated to `vX.Y.Z`):
   - `minio-RELEASE.<timestamp>Z` for a base version
   - `minio-RELEASE.<timestamp>Z-rN` for a revision (e.g. a `Dockerfile`-only change, same
     pinned commit)

```sh
# For a base version
git tag minio-RELEASE.2025-09-10T19-02-30Z
git push origin minio-RELEASE.2025-09-10T19-02-30Z

# For a revision
git tag minio-RELEASE.2025-09-10T19-02-30Z-r1
git push origin minio-RELEASE.2025-09-10T19-02-30Z-r1
```

## Building locally

If `minio/src` hasn't been initialized, `git submodule update --init minio/src` first — otherwise
the build fails at `COPY src/ ./` with an empty directory.
