# Builds the Hugo site and serves it with an unprivileged nginx.
# Everything happens inside Docker, so the build host only needs Docker.

ARG HUGO_VERSION=0.140.2

# Stage 1: build the static site with Hugo
FROM alpine:3.20 AS build
ARG HUGO_VERSION
ARG TARGETARCH
# Optional override, e.g. http://homelab.lan:8081/ for an internal preview.
ARG SITE_BASE_URL=

RUN apk add --no-cache ca-certificates wget \
 && ARCH="${TARGETARCH:-amd64}" \
 && FILE="hugo_${HUGO_VERSION}_linux-${ARCH}.tar.gz" \
 && cd /tmp \
 && wget -q "https://github.com/gohugoio/hugo/releases/download/v${HUGO_VERSION}/${FILE}" \
 && wget -q "https://github.com/gohugoio/hugo/releases/download/v${HUGO_VERSION}/hugo_${HUGO_VERSION}_checksums.txt" \
 && grep " ${FILE}\$" "hugo_${HUGO_VERSION}_checksums.txt" | sha256sum -c - \
 && tar -xzf "${FILE}" -C /usr/local/bin hugo \
 && rm -f /tmp/hugo_* \
 && hugo version

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
