# Allowlist-only HTTP(S) forward proxy: the only way out of the claude container's internal network.
FROM debian:bookworm-slim@sha256:734a72b3d6142a71993b4bc580ca01d8ca687f77a2c422d96a961d3376b179bc

RUN apt-get update \
    && apt-get install -y --no-install-recommends tinyproxy-bin \
    && rm -rf /var/lib/apt/lists/* \
    && (getent passwd tinyproxy >/dev/null \
        || useradd --system --no-create-home --shell /usr/sbin/nologin tinyproxy) \
    && command -v tinyproxy

COPY --chown=root:root --chmod=0444 tinyproxy.conf /etc/tinyproxy/tinyproxy.conf
COPY --chown=root:root --chmod=0444 allowlist.txt /etc/tinyproxy/allowlist.txt

# Unprivileged user created above (tinyproxy-bin does not create one).
USER tinyproxy
EXPOSE 3128
ENTRYPOINT ["tinyproxy", "-d", "-c", "/etc/tinyproxy/tinyproxy.conf"]
