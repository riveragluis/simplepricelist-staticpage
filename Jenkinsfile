// Builds the Simple Price List home page (Hugo -> nginx image), smoke-tests it,
// optionally pushes it to a registry, and deploys it to the homelab Portainer host.
//
// Agent requirements: Docker CLI with access to a Docker daemon (plus the
// "docker compose" plugin for DEPLOY_MODE=docker-compose, curl for portainer-webhook).
// Hugo itself runs inside the Docker build, so it doesn't need to be installed.

pipeline {
    agent any

    options {
        timestamps()
        disableConcurrentBuilds()
        buildDiscarder(logRotator(numToKeepStr: '20'))
        timeout(time: 20, unit: 'MINUTES')
    }

    parameters {
        choice(
            name: 'DEPLOY_MODE',
            choices: ['docker-compose', 'portainer-webhook', 'none'],
            description: '''docker-compose: run the stack on the Docker host this agent talks to (it shows up in Portainer).
portainer-webhook: push to REGISTRY, then call a Portainer stack webhook to re-pull and redeploy.
none: build and test only.'''
        )
        string(
            name: 'REGISTRY',
            defaultValue: '',
            description: 'Optional registry prefix, e.g. registry.homelab.lan:5000. Leave empty to keep the image local. Required for portainer-webhook.'
        )
        string(
            name: 'REGISTRY_CREDENTIALS_ID',
            defaultValue: '',
            description: 'Optional Jenkins username/password credential for the registry. Leave empty for a registry without auth.'
        )
        string(
            name: 'PORTAINER_WEBHOOK_CREDENTIALS_ID',
            defaultValue: 'portainer-simplepricelist-site-webhook',
            description: 'Jenkins "secret text" credential holding the Portainer stack webhook URL (portainer-webhook mode only).'
        )
        string(
            name: 'SITE_BASE_URL',
            defaultValue: 'https://simplepricelist.com/',
            description: 'Public URL of the site. Hugo uses it for canonical links and the sitemap.'
        )
        string(
            name: 'SITE_PORT',
            defaultValue: '8081',
            description: 'Host port to publish the site on (docker-compose mode).'
        )
    }

    environment {
        IMAGE_NAME   = 'simplepricelist-site'
        STACK_NAME   = 'simplepricelist-site'
        HUGO_VERSION = '0.140.2'
    }

    stages {
        stage('Checkout') {
            steps {
                checkout scm
                script {
                    def shortSha = sh(returnStdout: true, script: 'git rev-parse --short HEAD').trim()
                    def registry = params.REGISTRY?.trim()
                    env.IMAGE_REPO = registry ? "${registry}/${env.IMAGE_NAME}" : env.IMAGE_NAME
                    env.IMAGE_TAG  = "${env.BUILD_NUMBER}-${shortSha}"
                    currentBuild.description = "${env.IMAGE_REPO}:${env.IMAGE_TAG}"
                }
                sh 'docker version'
            }
        }

        stage('Build image') {
            steps {
                sh '''
                    docker build --pull \
                        --build-arg HUGO_VERSION="$HUGO_VERSION" \
                        --build-arg SITE_BASE_URL="$SITE_BASE_URL" \
                        --label org.opencontainers.image.revision="$(git rev-parse HEAD)" \
                        --label org.opencontainers.image.title="$IMAGE_NAME" \
                        -t "$IMAGE_REPO:$IMAGE_TAG" \
                        -t "$IMAGE_REPO:latest" \
                        .
                '''
            }
        }

        stage('Smoke test') {
            steps {
                // Run the image with the same hardening as production and check the
                // key pages from inside the container (no host port needed).
                sh '''
                    cid=$(docker run -d --read-only --tmpfs /tmp "$IMAGE_REPO:$IMAGE_TAG")
                    trap 'docker rm -f "$cid" >/dev/null 2>&1 || true' EXIT

                    ok=""
                    for i in $(seq 1 30); do
                        if docker exec "$cid" wget -q -O /dev/null http://127.0.0.1:8080/healthz; then ok=1; break; fi
                        sleep 1
                    done
                    if [ -z "$ok" ]; then docker logs "$cid"; echo "Site did not become healthy"; exit 1; fi

                    docker exec "$cid" wget -q -O - http://127.0.0.1:8080/ | grep -q "Simple Price List"
                    docker exec "$cid" wget -q -O - http://127.0.0.1:8080/legal/ | grep -q "not guaranteed for business-critical operations"
                    docker exec "$cid" wget -q -O - http://127.0.0.1:8080/legal/ | grep -q "no privacy guarantee"
                    docker exec "$cid" wget -q -O /dev/null http://127.0.0.1:8080/sitemap.xml
                    echo "Smoke test passed"
                '''
            }
        }

        stage('Push image') {
            when { expression { params.REGISTRY?.trim() } }
            steps {
                script {
                    def push = {
                        sh '''
                            docker push "$IMAGE_REPO:$IMAGE_TAG"
                            docker push "$IMAGE_REPO:latest"
                        '''
                    }
                    if (params.REGISTRY_CREDENTIALS_ID?.trim()) {
                        withCredentials([usernamePassword(credentialsId: params.REGISTRY_CREDENTIALS_ID,
                                                          usernameVariable: 'REG_USER',
                                                          passwordVariable: 'REG_PASS')]) {
                            sh 'echo "$REG_PASS" | docker login "$REGISTRY" -u "$REG_USER" --password-stdin'
                            try { push() } finally { sh 'docker logout "$REGISTRY" || true' }
                        }
                    } else {
                        push()
                    }
                }
            }
        }

        stage('Deploy: docker compose') {
            when { expression { params.DEPLOY_MODE == 'docker-compose' } }
            steps {
                sh '''
                    export SITE_IMAGE="$IMAGE_REPO:$IMAGE_TAG"
                    # Use the image built and tested above instead of rebuilding it.
                    export SITE_PULL_POLICY=missing
                    docker compose -p "$STACK_NAME" -f docker-compose.yml up -d --remove-orphans

                    # Wait for Docker's health check to report the new container as healthy.
                    for i in $(seq 1 30); do
                        status=$(docker inspect -f '{{.State.Health.Status}}' simplepricelist-site 2>/dev/null || echo missing)
                        [ "$status" = "healthy" ] && break
                        sleep 2
                    done
                    echo "Container health: $status"
                    [ "$status" = "healthy" ] || { docker logs --tail 50 simplepricelist-site; exit 1; }
                '''
            }
        }

        stage('Deploy: Portainer webhook') {
            when { expression { params.DEPLOY_MODE == 'portainer-webhook' } }
            steps {
                script {
                    if (!params.REGISTRY?.trim()) {
                        error('portainer-webhook mode needs REGISTRY so Portainer can pull the new image.')
                    }
                }
                withCredentials([string(credentialsId: params.PORTAINER_WEBHOOK_CREDENTIALS_ID, variable: 'PORTAINER_WEBHOOK_URL')]) {
                    sh 'curl -fsS -X POST "$PORTAINER_WEBHOOK_URL"'
                }
            }
        }
    }

    post {
        success {
            echo "Built ${env.IMAGE_REPO}:${env.IMAGE_TAG} (deploy mode: ${params.DEPLOY_MODE})"
        }
        always {
            // Keep the Docker host tidy: drop dangling build layers, keep tagged images.
            sh 'docker image prune -f >/dev/null 2>&1 || true'
        }
    }
}
