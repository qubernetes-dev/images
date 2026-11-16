FROM golang:1.24-alpine AS build

ARG MINIO_VERSION
ARG MINIO_RELEASE_TAG
ARG MINIO_COMMIT_ID
ARG MINIO_SHORT_COMMIT_ID
ARG MINIO_COPYRIGHT_YEAR

ENV CGO_ENABLED=0
WORKDIR /build

COPY src/ ./

RUN go build -tags kqueue -trimpath \
      --ldflags "-s -w \
        -X github.com/minio/minio/cmd.Version=${MINIO_VERSION} \
        -X github.com/minio/minio/cmd.CopyrightYear=${MINIO_COPYRIGHT_YEAR} \
        -X github.com/minio/minio/cmd.ReleaseTag=${MINIO_RELEASE_TAG} \
        -X github.com/minio/minio/cmd.CommitID=${MINIO_COMMIT_ID} \
        -X github.com/minio/minio/cmd.ShortCommitID=${MINIO_SHORT_COMMIT_ID}" \
      -o /go/bin/minio .

FROM golang:1.24-alpine AS build-mc

ARG MC_VERSION
ARG MC_RELEASE_TAG
ARG MC_COMMIT_ID
ARG MC_SHORT_COMMIT_ID
ARG MC_COPYRIGHT_YEAR

ENV CGO_ENABLED=0
WORKDIR /build

COPY mc-src/ ./

RUN go build -tags kqueue -trimpath \
      --ldflags "-s -w \
        -X github.com/minio/mc/cmd.Version=${MC_VERSION} \
        -X github.com/minio/mc/cmd.CopyrightYear=${MC_COPYRIGHT_YEAR} \
        -X github.com/minio/mc/cmd.ReleaseTag=${MC_RELEASE_TAG} \
        -X github.com/minio/mc/cmd.CommitID=${MC_COMMIT_ID} \
        -X github.com/minio/mc/cmd.ShortCommitID=${MC_SHORT_COMMIT_ID}" \
      -o /go/bin/mc .

FROM alpine:3 AS certs
RUN apk add -U --no-cache ca-certificates

FROM registry.access.redhat.com/ubi9/ubi-micro:latest

ARG RELEASE

LABEL name="MinIO" \
      vendor="MinIO Inc <dev@min.io>" \
      maintainer="Qubernetes" \
      version="${RELEASE}" \
      release="${RELEASE}" \
      summary="MinIO is a High Performance Object Storage, API compatible with Amazon S3 cloud storage service." \
      description="Built from the official minio/minio source."

ENV MINIO_ACCESS_KEY_FILE=access_key \
    MINIO_SECRET_KEY_FILE=secret_key \
    MINIO_ROOT_USER_FILE=access_key \
    MINIO_ROOT_PASSWORD_FILE=secret_key \
    MINIO_KMS_SECRET_KEY_FILE=kms_master_key \
    MINIO_CONFIG_ENV_FILE=config.env \
    MC_CONFIG_DIR=/tmp/.mc

RUN chmod -R 777 /usr/bin

COPY --from=certs /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/
COPY --from=build /go/bin/minio /usr/bin/minio
COPY --from=build-mc /go/bin/mc /usr/bin/mc
RUN chmod +x /usr/bin/minio /usr/bin/mc

COPY src/CREDITS /licenses/CREDITS
COPY src/LICENSE /licenses/LICENSE

COPY mc-src/CREDITS /licenses/CREDITS.mc
COPY src/dockerscripts/docker-entrypoint.sh /usr/bin/docker-entrypoint.sh
RUN chmod +x /usr/bin/docker-entrypoint.sh

EXPOSE 9000
VOLUME ["/data"]

ENTRYPOINT ["/usr/bin/docker-entrypoint.sh"]
CMD ["minio"]
