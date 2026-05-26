FROM node:lts-bookworm-slim

RUN apt-get update && apt-get install -y curl jq

RUN curl -fsSL https://claude.ai/install.sh | bash

RUN curl -LsSf https://astral.sh/uv/install.sh | sh

WORKDIR /app

ENTRYPOINT [ "/root/.local/bin/claude" ]
