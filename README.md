# Simple Price List: home page

Static marketing site for [Simple Price List](https://app.simplepricelist.com), built with [Hugo](https://gohugo.io) and served by an unprivileged nginx container.

No themes, no Node, no JavaScript. The site is plain Hugo templates plus one CSS file, so a build takes well under a second.

## Layout

```text
.
├── hugo.toml                  # Site config: title, app URL, optional contact email / repo URL
├── content/
│   ├── _index.md              # Home page (the page body lives in layouts/index.html)
│   └── legal.md               # Legal notice and disclaimer
├── data/home.yaml             # Editable home page copy: steps, features, use cases, FAQ
├── layouts/                   # Hugo templates (base, home, single page, 404, partials)
├── assets/css/main.css        # All styles (minified and fingerprinted by Hugo)
├── static/favicon.svg         # Same logo as the app
├── deploy/nginx.conf          # nginx config: caching, gzip, security headers, /healthz
├── Dockerfile                 # Hugo build stage, then nginx-unprivileged runtime
├── docker-compose.yml         # Portainer stack definition
└── Jenkinsfile                # Build, smoke test, push, deploy
```

## Editing

- **Text on the home page:** edit `data/home.yaml`. The hero and disclaimer banner are in `layouts/index.html`.
- **Legal notice:** edit `content/legal.md` and update `lastmod`.
- **App link, contact email, source link:** edit `[params]` in `hugo.toml`.
- **Colors:** edit the CSS variables at the top of `assets/css/main.css`. They match the app's teal brand, and dark mode follows the visitor's system setting.

## Local preview

With Hugo installed (any recent version; the build is pinned to 0.140.2):

```bash
hugo server            # http://localhost:1313, live reload
```

Or preview with Docker only:

```bash
docker build -t simplepricelist-site .
docker run --rm -p 8081:8080 simplepricelist-site   # http://localhost:8081
```

## Deploying with Jenkins and Portainer

The `Jenkinsfile` does all of the work. The Jenkins agent only needs the Docker CLI with access to a Docker daemon, plus the `docker compose` plugin or `curl` depending on the deploy mode.

1. **Build image:** Hugo is downloaded inside the Docker build and its checksum is verified. It renders the site, which is then copied into `nginxinc/nginx-unprivileged`.
2. **Smoke test:** the image is started read-only, and the pipeline checks `/healthz`, the home page, the legal notice (including the disclaimer text) and the sitemap.
3. **Push image:** this stage runs only when `REGISTRY` is set.
4. **Deploy:** choose one mode with `DEPLOY_MODE`:

| Mode | When to use it | Setup |
|------|----------------|-------|
| `docker-compose` (default) | The Jenkins agent talks to the same Docker host that Portainer manages. | None. The stack `simplepricelist-site` is created or updated with `docker compose` and appears in Portainer's stack list. Portainer marks it as created outside Portainer, so you have limited control over it there. |
| `portainer-webhook` | Portainer should own the stack, and images go through a registry. | Push the image to a registry (set `REGISTRY`). In Portainer, create a stack from this repo's `docker-compose.yml` with the environment variable `SITE_IMAGE=<registry>/simplepricelist-site:latest`. Enable the webhook with **re-pull image**, and save the webhook URL in Jenkins as a *Secret text* credential named `portainer-simplepricelist-site-webhook`. |
| `none` | You only want CI. | None. |

### Jenkins job setup

1. Push this directory to its own Git repository.
2. In Jenkins, create a **Pipeline** job (or a Multibranch Pipeline) with *Pipeline script from SCM* pointing to that repository. The script path is `Jenkinsfile`.
3. Run it once so Jenkins picks up the build parameters, then set the defaults you want.

### Stack settings

| Variable | Default | Meaning |
|----------|---------|---------|
| `SITE_IMAGE` | `simplepricelist-site:latest` | Image to run |
| `SITE_PORT` | `8081` | Host port (the app already uses 8080) |

Put your reverse proxy (Nginx Proxy Manager, Traefik, Caddy, …) in front of `SITE_PORT` for `simplepricelist.com` with TLS. The container answers `GET /healthz` for health checks.
