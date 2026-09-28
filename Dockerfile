# Builds the Hugo site and serves it with an unprivileged nginx.
# Everything happens inside Docker, so the build host only needs Docker.

ARG HUGO_VERSION=0.140.2

# Stage 1: build the static site with Hugo
# Uses the official Hugo image so the build never downloads anything itself:
# Docker pulls the image, the same way it pulls the nginx image below.
FROM ghcr.io/gohugoio/hugo:v${HUGO_VERSION} AS build
# Optional override, e.g. http://homelab.lan:8081/ for an internal preview.
ARG SITE_BASE_URL=
# The image runs as an unprivileged "hugo" user; this is a throwaway build
# stage, so run as root to write the output next to the copied sources.
USER root

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
