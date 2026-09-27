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
├── docker-compose.yml         # Portainer stack definition (builds from the Dockerfile)
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

## Deploying from GitHub with Portainer (recommended)

Portainer can clone this repository and build the image itself, so pushing to `master` is all it takes to deploy. You don't need Jenkins or a registry.

1. If a `simplepricelist-site` stack or container already exists (for example one started by Jenkins), remove it first. The new stack uses the same container name.
2. In Portainer, go to **Stacks → Add stack → Repository** and fill in:
   - **Name:** `simplepricelist-site`
   - **Repository URL:** `https://github.com/riveragluis/simplepricelist-staticpage`
   - **Authentication:** needed only if the repo is private. Use your GitHub username and a personal access token with read access to the repository contents.
   - **Repository reference:** `refs/heads/master`
   - **Compose path:** `docker-compose.yml`
3. Turn on **GitOps updates**. Choose **Polling** (for example every 5 minutes) to redeploy automatically after each push, or **Webhook** if you'd rather trigger deploys yourself, for example from GitHub Actions.
4. Set environment variables only if you need to. `SITE_PORT` defaults to `8081`; see [Stack settings](#stack-settings).
5. Deploy the stack.

On each deploy, `pull_policy: build` makes Portainer rebuild the image from the `Dockerfile`, so new commits show up. A build takes under a minute. The Docker host needs internet access to pull the Alpine and nginx base images and download Hugo.

## Deploying with Jenkins and Portainer

Use this instead of the GitHub setup above, or run Jenkins with `DEPLOY_MODE=none` just for its smoke tests. Don't let both deploy the same stack.

The `Jenkinsfile` does all of the work. The Jenkins agent only needs the Docker CLI with access to a Docker daemon, plus the `docker compose` plugin or `curl` depending on the deploy mode.

1. **Build image:** Hugo is downloaded inside the Docker build and its checksum is verified. It renders the site, which is then copied into `nginxinc/nginx-unprivileged`.
2. **Smoke test:** the image is started read-only, and the pipeline checks `/healthz`, the home page, the legal notice (including the disclaimer text) and the sitemap.
3. **Push image:** this stage runs only when `REGISTRY` is set.
4. **Deploy:** choose one mode with `DEPLOY_MODE`:

| Mode | When to use it | Setup |
|------|----------------|-------|
| `docker-compose` (default) | The Jenkins agent talks to the same Docker host that Portainer manages. | None. The stack `simplepricelist-site` is created or updated with `docker compose`, using the image Jenkins just built and tested (the pipeline sets `SITE_PULL_POLICY=missing`), and appears in Portainer's stack list. Portainer marks it as created outside Portainer, so you have limited control over it there. |
| `portainer-webhook` | Portainer should own the stack, and images go through a registry. | Push the image to a registry (set `REGISTRY`). In Portainer, create a stack from this repo's `docker-compose.yml` with the environment variables `SITE_IMAGE=<registry>/simplepricelist-site:latest` and `SITE_PULL_POLICY=always`. Enable the webhook with **re-pull image**, and save the webhook URL in Jenkins as a *Secret text* credential named `portainer-simplepricelist-site-webhook`. |
| `none` | You only want CI. | None. |

### Jenkins job setup

1. Push this directory to its own Git repository.
2. In Jenkins, create a **Pipeline** job (or a Multibranch Pipeline) with *Pipeline script from SCM* pointing to that repository. The script path is `Jenkinsfile`.
3. Run it once so Jenkins picks up the build parameters, then set the defaults you want.

### Stack settings

| Variable | Default | Meaning |
|----------|---------|---------|
| `SITE_IMAGE` | `simplepricelist-site:latest` | Name to tag the built image with, or a registry image to pull |
| `SITE_PULL_POLICY` | `build` | `build` rebuilds from the repo on every deploy. `missing` uses an image already on the host. `always` pulls `SITE_IMAGE` from a registry. |
| `SITE_PORT` | `8081` | Host port (the app already uses 8080) |

Put your reverse proxy (Nginx Proxy Manager, Traefik, Caddy, …) in front of `SITE_PORT` for `simplepricelist.com` with TLS. The container answers `GET /healthz` for health checks.
