FROM docker.io/library/ubuntu:24.04

RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates libevent-2.1-7 libssl3 zlib1g \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /srv
COPY uim-appengine-service /srv/uim-appengine-service

EXPOSE 8080
ENV PORT=8080

CMD ["/srv/uim-appengine-service"]
