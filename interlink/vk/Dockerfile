FROM golang:1.26-alpine AS builder

ARG INTERLINK_REPO=https://github.com/interlink-hq/interLink.git
ARG INTERLINK_REF=main

RUN apk add --no-cache git make bash

WORKDIR /src
RUN git clone --depth 1 --branch "${INTERLINK_REF}" "${INTERLINK_REPO}" interLink

WORKDIR /src/interLink
RUN make all && test -f bin/vk

FROM alpine:3.19

RUN apk add --no-cache \
    ca-certificates \
    curl \
    bash

RUN mkdir -p \
    /app/bin \
    /app/config

COPY --from=builder /src/interLink/bin/vk /app/bin/vk
COPY start-vk.sh /start-vk.sh

RUN chmod +x /app/bin/vk /start-vk.sh

ENTRYPOINT ["/start-vk.sh"]