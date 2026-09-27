# Builds the Hugo site and serves it with an unprivileged nginx.
# Everything happens inside Docker, so the build host only needs Docker.

ARG HUGO_VERSION=0.140.2

# Stage 1: build the static site with Hugo
FROM alpine:3.20 AS build
ARG HUGO_VERSION
ARG TARGETARCH
# Optional override, e.g. http://homelab.lan:8081/ for an internal preview.
ARG SITE_BASE_URL=

# The Alpine base image already has wget (with HTTPS) and CA certificates, so no
# packages are installed. Each step fails with its own message so a Portainer
# build error shows what went wrong.
RUN set -eu; \
    ARCH="${TARGETARCH:-amd64}"; \
    FILE="hugo_${HUGO_VERSION}_linux-${ARCH}.tar.gz"; \
    BASE="https://github.com/gohugoio/hugo/releases/download/v${HUGO_VERSION}"; \
    cd /tmp; \
    wget -O "${FILE}" "${BASE}/${FILE}" \
      || { echo "ERROR: could not download ${BASE}/${FILE} (no internet access from the build, or no Hugo release for architecture '${ARCH}')" >&2; exit 1; }; \
    wget -O checksums.txt "${BASE}/hugo_${HUGO_VERSION}_checksums.txt" \
      || { echo "ERROR: could not download the Hugo checksums file" >&2; exit 1; }; \
    grep " ${FILE}\$" checksums.txt > hugo.sha256 \
      || { echo "ERROR: ${FILE} is not listed in the Hugo checksums file" >&2; exit 1; }; \
    sha256sum -c hugo.sha256 \
      || { echo "ERROR: checksum mismatch for ${FILE}" >&2; exit 1; }; \
    tar -xzf "${FILE}" -C /usr/local/bin hugo; \
    rm -f /tmp/hugo_* /tmp/checksums.txt /tmp/hugo.sha256; \
    hugo version

WORKDIR /src
COPY . .
RUN hugo --minify --gc --environment production ${SITE_BASE_URL:+--baseURL "$SITE_BASE_URL"}

# Stage 2: serve it
FROM nginxinc/nginx-unprivileged:1.27-alpine
COPY deploy/nginx.conf /etc/nginx/conf.d/default.conf
COPY --from=build /src/public /usr/share/nginx/html

EXPOSE 8080
HEALTHCHECK --interval=30s --timeout=5s --start-period=5s --retries=3 \
    CMD wget -q --spider http://127.0.0.1:8080/healthz || exit 1
