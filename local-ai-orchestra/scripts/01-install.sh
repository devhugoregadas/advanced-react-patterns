#!/usr/bin/env bash
# Installe / répare ce qui manque sur le Mac. Chaque étape demande confirmation (sauf --yes).
# Usage : bash local-ai-orchestra/scripts/01-install.sh [--yes] [--keep-awake]
set -euo pipefail

YES=0; KEEP_AWAKE=0
for a in "$@"; do case "$a" in --yes) YES=1;; --keep-awake) KEEP_AWAKE=1;; esac; done

KIT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PAPERCLIP_URL="${PAPERCLIP_URL:-http://127.0.0.1:3100}"
STATE_DIR="$HOME/.config/local-ai-orchestra"
LOG_DIR="$STATE_DIR/logs"
mkdir -p "$STATE_DIR" "$LOG_DIR"

ask() { [[ $YES == 1 ]] && return 0; read -r -p "→ $1 [o/N] " r; [[ "$r" =~ ^[oOyY]$ ]]; }
step() { printf '\n\033[1m▶ %s\033[0m\n' "$*"; }

[[ "$(uname)" == "Darwin" ]] || { echo "Ce script est prévu pour macOS."; exit 1; }

step "Outils de base (Homebrew, jq, Node >= 24.11)"
command -v brew >/dev/null || { echo "Installe Homebrew d'abord : https://brew.sh"; exit 1; }
command -v jq >/dev/null || { ask "Installer jq ?" && brew install jq; }
need_node=1
if command -v node >/dev/null; then
  v=$(node -v | tr -d v); M=${v%%.*}; m=$(echo "$v" | cut -d. -f2)
  (( M > 24 || (M == 24 && m >= 11) )) && need_node=0
fi
if [[ $need_node == 1 ]]; then ask "Installer/mettre à jour Node (brew install node) ?" && brew install node; fi

step "CLIs claude et codex"
if ! command -v claude >/dev/null; then
  ask "Installer Claude Code (installeur officiel) ?" && curl -fsSL https://claude.ai/install.sh | bash
fi
if ! command -v codex >/dev/null; then
  ask "Installer OpenAI Codex CLI (npm i -g @openai/codex) ?" && npm install -g @openai/codex
fi
echo "  Connexion avec tes abonnements (pas de clé API) :"
echo "   - claude  → lance 'claude' puis /login (compte Claude Pro/Max)"
echo "   - codex   → lance 'codex login' (compte ChatGPT)"
[[ -f "$HOME/.codex/auth.json" ]] || echo "  ⚠ Codex n'est pas encore connecté."

step "PATH pour les apps graphiques et launchd (OpenBot, Paperclip)"
AGENT_PATH="$HOME/.local/bin"
for c in claude codex node npx; do
  p=$(command -v "$c" 2>/dev/null) && AGENT_PATH="$AGENT_PATH:$(dirname "$p")"
done
AGENT_PATH="$(echo "$AGENT_PATH:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin" | tr ':' '\n' | awk '!s[$0]++' | paste -sd: -)"
echo "AGENT_PATH=\"$AGENT_PATH\"" > "$STATE_DIR/path.env"
echo "  PATH retenu : $AGENT_PATH"
if ask "Appliquer ce PATH aux apps graphiques (launchctl config user path — demande sudo, puis redémarrage de session) ?"; then
  sudo launchctl config user path "$AGENT_PATH"
  launchctl setenv PATH "$AGENT_PATH"
  echo "  OK. Redémarre OpenBot (ou ta session) pour qu'il voie claude/codex."
fi
cat <<EOF
  Alternative sans sudo : dans OpenBot, les variables OPENBOT_<PROVIDER>_PATH permettent de
  pointer un binaire précis ; et Paperclip reçoit déjà ce PATH via son service launchd ci-dessous.
EOF

step "Paperclip (serveur local, mode local_trusted, port 3100)"
# Pas de `paperclipai onboard` ici : il démarre le serveur et ne rend jamais la main.
# `paperclipai run` (lancé par le service) fait lui-même l'onboarding si la config manque.
if curl -fsS -m 3 "$PAPERCLIP_URL/api/health" >/dev/null 2>&1; then
  echo "  Paperclip tourne déjà sur $PAPERCLIP_URL."
fi

PLIST="$HOME/Library/LaunchAgents/com.local-ai-orchestra.paperclip.plist"
if [[ -f "$PLIST" ]] && curl -fsS -m 3 "$PAPERCLIP_URL/api/health" >/dev/null 2>&1; then
  echo "  Service launchd déjà en place."
elif ask "Installer Paperclip comme service launchd (onboarding auto, démarre au login, redémarre s'il plante) ?"; then
  NPX_BIN="$(command -v npx)"
  sed -e "s#__NPX__#$NPX_BIN#g" -e "s#__PATH__#$AGENT_PATH#g" -e "s#__HOME__#$HOME#g" -e "s#__LOGS__#$LOG_DIR#g" \
    "$KIT_DIR/config/launchd/com.local-ai-orchestra.paperclip.plist" > "$PLIST"
  launchctl bootout "gui/$(id -u)" "$PLIST" 2>/dev/null || true
  launchctl bootstrap "gui/$(id -u)" "$PLIST"
  echo "  Service chargé. Logs : $LOG_DIR/paperclip.*.log"
  for i in {1..90}; do curl -fsS -m 2 "$PAPERCLIP_URL/api/health" >/dev/null 2>&1 && break; sleep 2; done
  curl -fsS -m 2 "$PAPERCLIP_URL/api/health" >/dev/null 2>&1 && echo "  ✔ Paperclip répond." || echo "  ⚠ Paperclip ne répond pas encore — voir les logs."
fi

if [[ $KEEP_AWAKE == 1 ]]; then
  step "Mac allumé 24h/24"
  ask "Désactiver la veille système sur secteur (sudo pmset -c sleep 0 ; l'écran peut toujours s'éteindre) ?" && \
    sudo pmset -c sleep 0 && sudo pmset -c disksleep 0 && sudo pmset -c womp 1
fi

cat <<EOF

Étape suivante :
  bash $KIT_DIR/scripts/02-paperclip-agents.sh --workspace "\$HOME/Projets"
EOF
