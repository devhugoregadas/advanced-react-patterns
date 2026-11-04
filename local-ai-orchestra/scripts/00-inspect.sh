#!/usr/bin/env bash
# Inspection en lecture seule du Mac : Paperclip, Docker, CLIs claude/codex, OpenBot.
# Ne modifie rien. Usage : bash local-ai-orchestra/scripts/00-inspect.sh
set -uo pipefail

PAPERCLIP_URL="${PAPERCLIP_URL:-http://127.0.0.1:3100}"
PAPERCLIP_HOME="${PAPERCLIP_HOME:-$HOME/.paperclip}"
OPENBOT_DATA="$HOME/Library/Application Support/OpenBot"

ok()   { printf '  \033[32m✔\033[0m %s\n' "$*"; }
warn() { printf '  \033[33m!\033[0m %s\n' "$*"; }
ko()   { printf '  \033[31m✘\033[0m %s\n' "$*"; }
hdr()  { printf '\n\033[1m== %s ==\033[0m\n' "$*"; }

hdr "Système"
echo "  $(sw_vers -productName 2>/dev/null) $(sw_vers -productVersion 2>/dev/null) — $(uname -m)"
if pmset -g 2>/dev/null | grep -qE '^\s*sleep\s+0'; then ok "Veille système désactivée (sleep 0)"
else warn "La veille système est active → le Mac peut s'endormir (voir 01-install.sh --keep-awake)"; fi
command -v brew >/dev/null && ok "Homebrew : $(brew --version | head -1)" || warn "Homebrew absent"
command -v jq   >/dev/null && ok "jq : $(jq --version)" || ko "jq absent (requis par les scripts) → brew install jq"

hdr "Node.js (Paperclip exige Node >= 24.11)"
if command -v node >/dev/null; then
  v=$(node -v | tr -d v); major=${v%%.*}; minor=$(echo "$v" | cut -d. -f2)
  if (( major > 24 || (major == 24 && minor >= 11) )); then ok "node v$v"; else ko "node v$v trop ancien"; fi
else ko "node absent"; fi

hdr "CLIs IA (dans le PATH du shell)"
for c in claude codex; do
  if p=$(command -v "$c"); then ok "$c → $p ($("$c" --version 2>/dev/null | head -1))"
  else ko "$c introuvable dans le PATH"; fi
done
[[ -f "$HOME/.codex/auth.json" ]] && ok "Codex connecté (~/.codex/auth.json présent)" || warn "Codex : pas de ~/.codex/auth.json → lance 'codex login'"
if claude auth status >/dev/null 2>&1 || [[ -d "$HOME/.claude" ]]; then ok "Claude Code : profil ~/.claude présent"
else warn "Claude Code : pas de session → lance 'claude' puis /login"; fi

hdr "PATH vu par les apps graphiques / launchd"
lpath=$(launchctl getenv PATH 2>/dev/null || true)
echo "  launchctl PATH : ${lpath:-<non défini → /usr/bin:/bin:/usr/sbin:/sbin>}"
for c in claude codex node; do
  p=$(command -v "$c" 2>/dev/null) || continue
  d=$(dirname "$p")
  case ":${lpath:-/usr/bin:/bin:/usr/sbin:/sbin}:" in
    *":$d:"*) ok "$c visible par les apps graphiques" ;;
    *) warn "$c ($d) invisible pour les apps lancées hors terminal → corrigé par 01-install.sh" ;;
  esac
done

hdr "Docker"
if command -v docker >/dev/null; then
  ok "docker CLI : $(docker --version)"
  if docker info >/dev/null 2>&1; then ok "démon Docker actif"
    docker ps --format '  conteneur : {{.Names}} ({{.Image}}) {{.Status}}' | grep -iE 'paperclip|openbot' || echo "  aucun conteneur Paperclip/OpenBot"
  else warn "démon Docker arrêté"; fi
else warn "Docker absent (non requis : Paperclip tourne en natif via npx)"; fi

hdr "Paperclip"
[[ -f "$PAPERCLIP_HOME/instances/default/config.json" ]] && ok "instance trouvée : $PAPERCLIP_HOME/instances/default" || warn "aucune instance dans $PAPERCLIP_HOME"
if curl -fsS -m 3 "$PAPERCLIP_URL/api/health" >/dev/null 2>&1; then
  ok "serveur actif sur $PAPERCLIP_URL"
  companies=$(curl -fsS -m 5 "$PAPERCLIP_URL/api/companies" 2>/dev/null || true)
  if [[ -n "$companies" ]] && command -v jq >/dev/null; then
    echo "$companies" | jq -r '(if type=="array" then . else (.companies // .data // []) end)[] | "  société : \(.name) (\(.id))"' 2>/dev/null
  fi
else ko "aucun serveur Paperclip sur $PAPERCLIP_URL"; fi
svc=$(launchctl list 2>/dev/null | awk 'tolower($3) ~ /paperclip/ {print $3}' | head -1)
if [[ -z "$svc" ]]; then
  plist=$(grep -lis paperclip "$HOME"/Library/LaunchAgents/*.plist 2>/dev/null | head -1)
  [[ -n "$plist" ]] && svc=$(defaults read "${plist%.plist}" Label 2>/dev/null)
fi
[[ -n "$svc" ]] && ok "service launchd Paperclip : $svc" || warn "pas de service launchd → Paperclip ne redémarre pas tout seul"
if npm view @paperclipai/mcp-server version >/dev/null 2>&1; then ok "@paperclipai/mcp-server disponible sur npm ($(npm view @paperclipai/mcp-server version))"
else warn "impossible de vérifier @paperclipai/mcp-server sur npm"; fi
claude mcp list 2>/dev/null | grep -qi paperclip && ok "MCP paperclip déclaré dans Claude Code" || warn "MCP paperclip non déclaré dans Claude Code"
grep -qs 'mcp_servers.paperclip' "$HOME/.codex/config.toml" && ok "MCP paperclip déclaré dans Codex" || warn "MCP paperclip non déclaré dans Codex"

hdr "OpenBot"
[[ -d /Applications/OpenBot.app ]] && ok "OpenBot.app installé" || ko "OpenBot.app absent de /Applications"
pgrep -fl "OpenBot" >/dev/null 2>&1 && ok "OpenBot en cours d'exécution" || warn "OpenBot n'est pas lancé"
[[ -f "$OPENBOT_DATA/openbot.db" ]] && ok "base OpenBot : $OPENBOT_DATA/openbot.db" || warn "pas encore de base OpenBot (premier lancement à faire)"
[[ -f "$OPENBOT_DATA/automation/url" ]] && ok "API scripts locale : $(cat "$OPENBOT_DATA/automation/url")" || warn "API scripts OpenBot non initialisée"
[[ -d "$HOME/OpenBot/Agents" ]] && echo "  workspaces agents : $(ls "$HOME/OpenBot/Agents" 2>/dev/null | wc -l | tr -d ' ')"

hdr "Fichiers de ce kit"
[[ -f "$HOME/.config/local-ai-orchestra/state.env" ]] && { ok "agents Paperclip déjà créés :"; sed 's/^/    /' "$HOME/.config/local-ai-orchestra/state.env" | grep -v KEY; } || warn "02-paperclip-agents.sh pas encore lancé"
echo
