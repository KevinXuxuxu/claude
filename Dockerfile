FROM node:lts-bookworm-slim

RUN apt-get update && apt-get install -y curl jq build-essential

RUN curl -fsSL https://claude.ai/install.sh | bash

RUN curl -LsSf https://astral.sh/uv/install.sh | sh

RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --no-modify-path
ENV PATH="/root/.cargo/bin:${PATH}"
RUN rustup component add rustfmt

WORKDIR /app

ENTRYPOINT [ "/root/.local/bin/claude" ]
