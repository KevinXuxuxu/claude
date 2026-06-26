#!/usr/bin/env bash
set -euo pipefail

CONFIG_FILE="$HOME/.claude/providers.json"

# ── Prerequisites ──────────────────────────────────────────────────────────────

if ! command -v jq &>/dev/null; then
    echo "Error: jq is required to parse provider config."
    echo "Install with:  apt install jq  (Linux)  or  brew install jq  (macOS)"
    exit 1
fi

if [ ! -f "$CONFIG_FILE" ]; then
    echo "Error: config file not found at $CONFIG_FILE"
    echo "Copy the example from providers.example.json and customize it:"
    echo "  cp $(dirname "$0")/providers.example.json $CONFIG_FILE"
    exit 1
fi

# ── Parse flags ────────────────────────────────────────────────────────────────

use_proxy=0
verbose=0
while [[ $# -gt 0 ]]; do
    case "$1" in
        -p) use_proxy=1; shift ;;
        -v) verbose=1; shift ;;
        *) break ;;
    esac
done

# ── Resolve provider ──────────────────────────────────────────────────────────

provider_name="${1:-}"
if [ -z "$provider_name" ]; then
    provider_name="$(jq -r '.default_provider // "deepseek"' "$CONFIG_FILE")"
else
    shift
fi

if ! jq -e --arg name "$provider_name" '.providers[] | select(.name == $name)' "$CONFIG_FILE" &>/dev/null; then
    echo "Error: provider '$provider_name' not found in $CONFIG_FILE"
    echo "Available providers: $(jq -r '[.providers[].name] | join(", ")' "$CONFIG_FILE")"
    exit 1
fi

echo "Provider: $provider_name"

# ── Read provider config ──────────────────────────────────────────────────────

base_url="$(jq -r --arg name "$provider_name" '.providers[] | select(.name == $name) | .base_url' "$CONFIG_FILE")"
api_key="$(jq -r --arg name "$provider_name" '.providers[] | select(.name == $name) | .api_key // ""' "$CONFIG_FILE")"

# ── Build Docker args ─────────────────────────────────────────────────────────

mount_target="/$(basename "$PWD")"

docker_args=(
    --rm
    -v "$HOME/.claude:/root/.claude"
    -v "$HOME/.claude.json:/root/.claude.json"
    -v "$HOME/.cache/uv:/root/.cache/uv"
    -v "$HOME/.cache/huggingface:/root/.cache/huggingface"
    -v "$HOME/.cargo/registry:/usr/local/cargo/registry"
    -v "$PWD:$mount_target"
    -w "$mount_target"
    -it
)

# Base URL: proxy vs direct
if [ "$use_proxy" -eq 1 ]; then
    proxy_base_url="$(jq -r '.proxy.base_url // ""' "$CONFIG_FILE")"
    proxy_host_entry="$(jq -r '.proxy.host_entry // ""' "$CONFIG_FILE")"

    if [ -z "$proxy_base_url" ]; then
        echo "Error: proxy.base_url not set in $CONFIG_FILE"
        exit 1
    fi
    if [ -z "$proxy_host_entry" ]; then
        echo "Error: proxy.host_entry not set in $CONFIG_FILE"
        exit 1
    fi

    echo "  Route: $proxy_base_url/$provider_name"
    docker_args+=(-e "ANTHROPIC_BASE_URL=$proxy_base_url/$provider_name")
    docker_args+=(--add-host "$proxy_host_entry")
else
    echo "  Route: $base_url"
    docker_args+=(-e "ANTHROPIC_BASE_URL=$base_url")
fi

# API key (if the provider has one)
if [ -n "$api_key" ] && [ "$api_key" != "null" ]; then
    docker_args+=(-e "ANTHROPIC_API_KEY=$api_key")
fi

# Provider-specific env vars (e.g. ANTHROPIC_MODEL)
while IFS="=" read -r key value; do
    if [ -n "$key" ] && [ "$value" != "null" ]; then
        docker_args+=(-e "$key=$value")
    fi
done < <(jq -r --arg name "$provider_name" '.providers[] | select(.name == $name) | .env // {} | to_entries[] | "\(.key)=\(.value)"' "$CONFIG_FILE")

# ── Go ────────────────────────────────────────────────────────────────────────

cmd=(docker run "${docker_args[@]}" claude "$@")
if [ "$verbose" -eq 1 ]; then
    echo "── Full command ──"
    printf '%q ' "${cmd[@]}"
    echo ""
    echo "──────────────────"
fi

exec "${cmd[@]}"
