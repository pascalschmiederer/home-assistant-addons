ARG BUILD_FROM
FROM $BUILD_FROM

RUN apk add --no-cache \
    arp-scan \
    bash \
    jq \
    iputils \
    bind-tools \
    mosquitto-clients \
    coreutils

COPY run.sh /run.sh
RUN chmod +x /run.sh

COPY rootfs/ /
