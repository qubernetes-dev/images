FROM alpine:3.19

RUN apk add --no-cache \
    openssh-client \
    curl \
    ca-certificates \
 && mkdir -p /root/.ssh \
 && chmod 700 /root/.ssh

COPY tunnel.sh /tunnel.sh
RUN chmod +x /tunnel.sh

CMD ["/tunnel.sh"]