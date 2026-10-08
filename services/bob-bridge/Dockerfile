# bob-bridge — host-agent relay sidecar
#
# Receives generate requests from the browser and forwards them to
# bob-host-agent.sh running on the Ubuntu host via a Unix socket.
# Bob Shell runs on the host (not here) — this container is a lightweight relay.

FROM node:20-alpine

WORKDIR /app

COPY package.json ./
RUN npm install --omit=dev

COPY server.js ./

USER node

EXPOSE 4000

ENV BOB_BRIDGE_PORT=4000
ENV HOST_AGENT_SOCKET=/tmp/bob-host-agent.sock

CMD ["node", "server.js"]
