FROM debian:12-slim

ENV DEBIAN_FRONTEND=noninteractive \
    PUID=1000 \
    PGID=1000 \
    VS_ROOT=/var/vintagestory \
    VS_INSTALL_PATH=/var/vintagestory/server \
    VS_DATA_PATH=/var/vintagestory/data

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        bash \
        ca-certificates \
        curl \
        gosu \
        jq \
        procps \
        tar \
        tini \
    && curl -fsSL https://packages.microsoft.com/config/debian/12/packages-microsoft-prod.deb -o /tmp/packages-microsoft-prod.deb \
    && dpkg -i /tmp/packages-microsoft-prod.deb \
    && rm -f /tmp/packages-microsoft-prod.deb \
    && apt-get update \
    && apt-get install -y --no-install-recommends \
        dotnet-runtime-8.0 \
        dotnet-runtime-10.0 \
    && rm -rf /var/lib/apt/lists/* \
    && groupadd --gid 1000 vintagestory \
    && useradd --uid 1000 --gid 1000 --create-home --home-dir /home/vintagestory --shell /usr/sbin/nologin vintagestory \
    && mkdir -p /opt/bootstrap /var/vintagestory \
    && chown -R vintagestory:vintagestory /opt/bootstrap /var/vintagestory

COPY .vintagestory-version /opt/bootstrap/default-vs-version
COPY docker/entrypoint.sh /usr/local/bin/docker-entrypoint.sh

RUN chmod 755 /usr/local/bin/docker-entrypoint.sh

WORKDIR /var/vintagestory/server

VOLUME ["/var/vintagestory"]

EXPOSE 42420/tcp
EXPOSE 42420/udp

STOPSIGNAL SIGINT

HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=5 \
    CMD pgrep -f '[V]intagestoryServer' >/dev/null || exit 1

ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/docker-entrypoint.sh"]
CMD ["run"]
