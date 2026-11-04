#!/usr/bin/env bash
# Lance le serveur MCP Paperclip avec l'identité de l'Orchestrateur-CEO.
# Lit ~/.config/local-ai-orchestra/state.env (créé par 02-paperclip-agents.sh), pour ne pas
# avoir à saisir la clé API dans OpenBot / Claude Code / Codex.
set -euo pipefail
STATE="$HOME/.config/local-ai-orchestra/state.env"
[[ -f "$STATE" ]] || { echo "state.env introuvable : lance 02-paperclip-agents.sh" >&2; exit 1; }
[[ -f "$HOME/.config/local-ai-orchestra/path.env" ]] && source "$HOME/.config/local-ai-orchestra/path.env" && export PATH="$AGENT_PATH:$PATH"
set -a; source "$STATE"; set +a
exec npx -y @paperclipai/mcp-server
