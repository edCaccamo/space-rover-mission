# bob-bridge — Bob Shell sidecar
#
# Installs Bob Shell (the official IBM Bob CLI), Node deps, then runs the
# bridge server. The workspace repo root is mounted at /workspace at runtime.
#
# Authentication:
#   Bob Shell in a non-interactive container uses an API key instead of
#   browser-based SSO. Set BOB_API_KEY in docker-compose.yml or a .env file.
#   Generate your key at https://bob.ibm.com (API Keys section).

FROM registry.redhat.io/ubi9/nodejs-20-minimal:latest

USER root

# Install Bob Shell using the official install script
# curl is available in ubi9-minimal; the script installs the `bob` binary to
# /usr/local/bin so it is on PATH for all users.
RUN curl -fsSL https://bob.ibm.com/download/bobshell.sh | bash

WORKDIR /app

# Copy package files and install Express + cors
COPY package.json ./
RUN npm install --omit=dev

# Copy server
COPY server.js ./

# Non-root user (uid 1001 is default in UBI minimal images)
USER 1001

EXPOSE 4000

ENV BOB_BRIDGE_PORT=4000
ENV BOB_WORKSPACE=/workspace
# BOB_API_KEY must be injected at runtime via docker-compose.yml or .env —
# never hardcode it here.

CMD ["node", "server.js"]
