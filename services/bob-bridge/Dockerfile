# bob-bridge — host-agent relay sidecar
#
# Receives generate requests from the browser and forwards them to the
# bob-host-agent running on the Ubuntu host via a Unix socket.
# Does NOT need Bob Shell installed — all AI + WiFi work happens on the host.

FROM registry.redhat.io/ubi9/nodejs-20-minimal:latest

USER root

WORKDIR /app

COPY package.json ./
RUN npm install --omit=dev

COPY server.js ./

USER 1001

EXPOSE 4000

ENV BOB_BRIDGE_PORT=4000
ENV HOST_AGENT_SOCKET=/tmp/bob-host-agent.sock

CMD ["node", "server.js"]
