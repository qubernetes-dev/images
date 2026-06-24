FROM golang:1.26-alpine AS builder

ARG INTERLINK_SLURM_PLUGIN_REPO=https://github.com/interlink-hq/interlink-slurm-plugin.git
ARG INTERLINK_SLURM_PLUGIN_REF=main

RUN apk add --no-cache git make bash

WORKDIR /src

RUN git clone --depth 1 --branch "${INTERLINK_SLURM_PLUGIN_REF}" "${INTERLINK_SLURM_PLUGIN_REPO}" interlink-slurm-plugin

WORKDIR /src/interlink-slurm-plugin

RUN make all && test -f bin/slurm-sd

FROM alpine:3.19

RUN apk add --no-cache \
    python3 \
    openssh-client \
    curl \
    ca-certificates

RUN mkdir -p \
    /opt/interlink/binaries/x86_64 \
    /opt/interlink/scripts \
    /opt/interlink/config \
    /runtime

COPY --from=builder /src/interlink-slurm-plugin/bin/slurm-sd /opt/interlink/binaries/x86_64/slurm-sd

COPY init.py /init.py
COPY port.sh /opt/interlink/scripts/port.sh

RUN chmod +x \
    /init.py \
    /opt/interlink/scripts/port.sh \
    /opt/interlink/binaries/x86_64/slurm-sd

ENTRYPOINT ["python3", "/init.py"]