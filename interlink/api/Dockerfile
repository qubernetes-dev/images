FROM golang:1.26-alpine AS builder

ARG INTERLINK_REPO=https://github.com/interlink-hq/interLink.git
ARG INTERLINK_REF=main

RUN apk add --no-cache git make bash

WORKDIR /src
RUN git clone --depth 1 --branch "${INTERLINK_REF}" "${INTERLINK_REPO}" interLink

WORKDIR /src/interLink
RUN make all && test -f bin/interlink

FROM alpine:3.19

RUN apk add --no-cache \
    ca-certificates \
    curl \
    bash \
    openssh-client

RUN mkdir -p \
    /app/bin \
    /app/config \
    /runtime \
    /root/.ssh \
 && chmod 700 /root/.ssh

COPY --from=builder /src/interLink/bin/interlink /app/bin/interlink
COPY start-api.sh /start-api.sh

RUN chmod +x /app/bin/interlink /start-api.sh

ENTRYPOINT ["/start-api.sh"]