FROM docker.io/library/ubuntu:24.04

RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates libevent-2.1-7t64 libssl3t64 zlib1g \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /srv
COPY uim-dataflow-service /srv/uim-dataflow-service

EXPOSE 8080
ENV PORT=8080

CMD ["/srv/uim-dataflow-service"]
