#!/usr/bin/env bash
# Crée (ou met à jour) la société et l'organigramme dans Paperclip via son API REST.
# Idempotent : relançable sans créer de doublons.
#
# Usage :
#   bash local-ai-orchestra/scripts/02-paperclip-agents.sh --workspace "$HOME/Projets" \
#        [--company "Studio IA"] [--ceo-brain openbot|paperclip] [--register-mcp|--unregister-mcp]
#
#   --register-mcp    ajoute le MCP Paperclip (identité du CEO) à TOUS les Claude Code / Codex
#                     du Mac. Désactivé par défaut : OpenBot et les agents Paperclip n'en ont pas besoin.
#   --unregister-mcp  retire cet ajout global (Claude Code + ~/.codex/config.toml, avec sauvegarde).
#   --no-claude-executable  n'ajoute pas CLAUDE_CODE_EXECUTABLE (utile quand Paperclip embarquera
#                     claude-agent-acp >= 0.100, dont le binaire supporte claude-opus-5-5).
#   --codex-engine cli|acp|auto  moteur Codex (défaut cli). En cli, Paperclip lance le `codex` du Mac
#                     avec un bac à sable workspace-write AVEC réseau (accès à l'API Paperclip).
#                     Le moteur ACP par défaut utilise une copie de codex-acp (1.13.1) qui ignore
#                     l'accès réseau : Dev-Codex ne joint plus 127.0.0.1:3100.
#
# Les réglages existants des agents (ex. adapterConfig.env) sont conservés : le script fusionne.
#
#   --ceo-brain openbot    (défaut) le CEO "pense" dans OpenBot (chat, notifications iPhone,
#                          await_event, failover natif Claude→Codex). Dans Paperclip, sa fiche sert
#                          d'identité (clé API, organigramme) et son heartbeat Paperclip est coupé
#                          pour ne pas faire tourner deux cerveaux.
#   --ceo-brain paperclip  le CEO tourne dans Paperclip : réveil sur événement (assignation,
#                          sollicitation, approval) + filet de sécurité toutes les 60 min
#                          (--ceo-heartbeat-min N pour changer). OpenBot sert de fenêtre de chat.
set -euo pipefail

KIT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PAPERCLIP_URL="${PAPERCLIP_URL:-http://127.0.0.1:3100}"
STATE_DIR="$HOME/.config/local-ai-orchestra"
STATE="$STATE_DIR/state.env"
WORKSPACE="$HOME/Projets"; COMPANY="Studio IA"; CEO_BRAIN="openbot"
CEO_HEARTBEAT_SEC=3600   # filet de sécurité ; le CEO est surtout réveillé par les événements
MCP_MODE="keep"   # keep | register | unregister
CLAUDE_EXEC=1     # force le CLI claude local (contourne le binaire trop ancien embarqué par Paperclip)
CODEX_ENGINE="cli" # cli : codex du Mac, bac à sable workspace-write avec accès réseau à Paperclip

while [[ $# -gt 0 ]]; do case "$1" in
  --workspace) WORKSPACE="$2"; shift 2;;
  --company) COMPANY="$2"; shift 2;;
  --ceo-brain) CEO_BRAIN="$2"; shift 2;;
  --register-mcp) MCP_MODE="register"; shift;;
  --ceo-heartbeat-min) CEO_HEARTBEAT_SEC=$(( $2 * 60 )); shift 2;;
  --no-claude-executable) CLAUDE_EXEC=0; shift;;
  --codex-engine) CODEX_ENGINE="$2"; shift 2;;
  --unregister-mcp) MCP_MODE="unregister"; shift;;
  *) echo "Option inconnue : $1"; exit 1;;
esac; done
[[ "$CEO_BRAIN" =~ ^(openbot|paperclip)$ ]] || { echo "--ceo-brain doit valoir openbot ou paperclip"; exit 1; }

command -v jq >/dev/null || { echo "jq requis (brew install jq)"; exit 1; }
mkdir -p "$STATE_DIR" "$WORKSPACE"; chmod 700 "$STATE_DIR"
WORKSPACE="$(cd "$WORKSPACE" && pwd)"

AUTH=()
[[ -n "${PAPERCLIP_BOARD_TOKEN:-}" ]] && AUTH=(-H "Authorization: Bearer $PAPERCLIP_BOARD_TOKEN")
api() { # api METHOD PATH [JSON]
  local m="$1" p="$2" d="${3:-}"
  if [[ -n "$d" ]]; then curl -fsS -X "$m" ${AUTH[@]+"${AUTH[@]}"} -H 'Content-Type: application/json' -d "$d" "$PAPERCLIP_URL$p"
  else curl -fsS -X "$m" ${AUTH[@]+"${AUTH[@]}"} "$PAPERCLIP_URL$p"; fi
}
as_list() { jq 'if type=="array" then . else (.companies // .agents // .data // .items // []) end'; }
id_of()   { jq -r '.id // .agent.id // .company.id // .data.id // empty'; }

curl -fsS -m 3 "$PAPERCLIP_URL/api/health" >/dev/null 2>&1 || { echo "Paperclip ne répond pas sur $PAPERCLIP_URL (lance 01-install.sh)"; exit 1; }

# --- Société -------------------------------------------------------------------------------
CID=$(api GET /api/companies | as_list | jq -r --arg n "$COMPANY" '.[] | select(.name==$n) | .id' | head -1)
if [[ -z "$CID" ]]; then
  CID=$(api POST /api/companies "$(jq -n --arg n "$COMPANY" \
    '{name:$n, description:"Équipe IA locale : Orchestrateur-CEO (Claude), Architecte-Claude, Dev-Codex"}')" | id_of)
  echo "✔ Société créée : $COMPANY ($CID)"
else echo "• Société existante : $COMPANY ($CID)"; fi

CLAUDE_BIN="$(command -v claude || echo claude)"

# --- Agents --------------------------------------------------------------------------------
# upsert NAME ROLE TITLE ADAPTER INSTR_DIR REPORTS_TO HEARTBEAT_JSON CAPABILITIES [MODEL] [EFFORT]
upsert() {
  local name="$1" role="$2" title="$3" adapter="$4" instr="$KIT_DIR/agents/$5/AGENTS.md" reports="$6" hb="$7" caps="$8"
  local model="${9:-}" effort="${10:-}"
  local id cfg
  id=$(api GET "/api/companies/$CID/agents" | as_list | jq -r --arg n "$name" '.[] | select(.name==$n) | .id' | head -1)
  if [[ "$adapter" == claude_local ]]; then
    local exe=""; [[ $CLAUDE_EXEC == 1 && "$CLAUDE_BIN" == /* ]] && exe="$CLAUDE_BIN"
    cfg=$(jq -n --arg cwd "$WORKSPACE" --arg i "$instr" --arg c "$CLAUDE_BIN" \
      --arg m "$model" --arg e "$effort" --arg x "$exe" \
      '{cwd:$cwd, instructionsFilePath:$i, command:$c, dangerouslySkipPermissions:true}
       + (if $m=="" then {} else {model:$m} end) + (if $e=="" then {} else {effort:$e} end)
       + (if $x=="" then {} else {env:{CLAUDE_CODE_EXECUTABLE:$x}} end)')
  else
    cfg=$(jq -n --arg cwd "$WORKSPACE" --arg i "$instr" --arg eng "$CODEX_ENGINE" \
      '{cwd:$cwd, instructionsFilePath:$i, dangerouslyBypassApprovalsAndSandbox:false, engine:$eng}')
  fi
  # Fusion avec la config existante : un PATCH remplace adapterConfig (et sa clé env) en entier.
  if [[ -n "$id" ]]; then
    local existing
    existing=$(api GET "/api/agents/$id" | jq '(.agent // .data // .) | .adapterConfig // {}')
    cfg=$(jq -n --argjson old "$existing" --argjson new "$cfg" '$old * $new')
    if [[ $CLAUDE_EXEC == 0 && "$adapter" == claude_local ]]; then
      cfg=$(jq 'del(.env.CLAUDE_CODE_EXECUTABLE)' <<<"$cfg")
    fi
  fi
  local body
  body=$(jq -n --arg n "$name" --arg r "$role" --arg t "$title" --arg a "$adapter" --arg cap "$caps" \
    --arg rep "$reports" --argjson cfg "$cfg" --argjson hb "$hb" \
    '{name:$n, role:$r, title:$t, capabilities:$cap, adapterType:$a, adapterConfig:$cfg,
      runtimeConfig:{heartbeat:$hb}} + (if $rep=="" then {} else {reportsTo:$rep} end)')
  if [[ -z "$id" ]]; then
    id=$(api POST "/api/companies/$CID/agents" "$body" | id_of)
    echo "✔ Agent créé : $name ($id)" >&2
  else
    api PATCH "/api/agents/$id" "$body" >/dev/null
    echo "• Agent mis à jour : $name ($id)" >&2
  fi
  echo "$id"
}

if [[ "$CEO_BRAIN" == paperclip ]]; then
  CEO_HB=$(jq -n --argjson s $CEO_HEARTBEAT_SEC '{enabled:true, intervalSec:$s, wakeOnDemand:true, wakeOnAssignment:true, wakeOnAutomation:true}')
else
  CEO_HB='{"enabled":false,"intervalSec":0,"wakeOnDemand":false,"wakeOnAssignment":false,"wakeOnAutomation":false}'
fi
# Les exécutants ne tournent que lorsqu'on leur assigne un ticket ou qu'on les mentionne (économise les quotas).
WORKER_HB='{"enabled":false,"intervalSec":0,"wakeOnDemand":true,"wakeOnAssignment":true,"wakeOnAutomation":true}'

CEO_ID=$(upsert "Orchestrateur-CEO" ceo "Directeur technique / chef d'orchestre" claude_local orchestrateur-ceo "" \
  "$CEO_HB" "Découpe les demandes en tickets, délègue, suit le Kanban, impose les tests, gère approvals, escalade et failover" \
  claude-opus-5-5 medium)
ARCH_ID=$(upsert "Architecte-Claude" cto "Architecte logiciel" claude_local architecte-claude "$CEO_ID" \
  "$WORKER_HB" "Architecture, code complexe multi-fichiers, revues de code" \
  claude-opus-5-5 high)
FABLE_ID=$(upsert "Architecte-Fable" engineer "Spécialiste escalade / raisonnement profond" claude_local architecte-fable "$CEO_ID" \
  "$WORKER_HB" "Audits de sécurité, workflows très longs, bugs qui ont résisté à Opus (escalade uniquement)" \
  claude-fable-5-1 high)
DEV_ID=$(upsert "Dev-Codex" engineer "Développeur / testeur" codex_local dev-codex "$CEO_ID" \
  "$WORKER_HB" "Implémentation rapide, scripts, tests unitaires et e2e dans le terminal, debugging")
BACKUP_ID=$(upsert "Architecte-Codex-Backup" engineer "Architecte de secours (failover quota Claude)" codex_local architecte-codex-backup "$CEO_ID" \
  "$WORKER_HB" "Remplace Architecte-Claude quand le quota Claude est atteint")

# --- Clé API du CEO (pour le serveur MCP utilisé par OpenBot) ------------------------------
CEO_KEY=""
[[ -f "$STATE" ]] && CEO_KEY=$(grep '^PAPERCLIP_API_KEY=' "$STATE" | cut -d= -f2- | tr -d '"' || true)
if [[ -z "$CEO_KEY" ]]; then
  CEO_KEY=$(api POST "/api/agents/$CEO_ID/keys" '{"name":"openbot-mcp"}' | jq -r '.key // .token // .apiKey // .secret // empty')
  [[ -n "$CEO_KEY" ]] && echo "✔ Clé API créée pour Orchestrateur-CEO" || echo "⚠ Clé API non récupérée — crée-la dans l'UI Paperclip et ajoute-la à $STATE"
fi

umask 077
cat > "$STATE" <<EOF
PAPERCLIP_API_URL="$PAPERCLIP_URL"
PAPERCLIP_COMPANY_ID="$CID"
PAPERCLIP_AGENT_ID="$CEO_ID"
PAPERCLIP_API_KEY="$CEO_KEY"
ARCHITECTE_CLAUDE_ID="$ARCH_ID"
ARCHITECTE_FABLE_ID="$FABLE_ID"
DEV_CODEX_ID="$DEV_ID"
ARCHITECTE_CODEX_BACKUP_ID="$BACKUP_ID"
CEO_BRAIN="$CEO_BRAIN"
WORKSPACE="$WORKSPACE"
EOF
echo "✔ État enregistré dans $STATE (chmod 600)"

# --- Serveur MCP Paperclip pour Claude Code / Codex (usage manuel, optionnel) ---------------
MCP_WRAPPER="$KIT_DIR/scripts/paperclip-mcp.sh"
chmod +x "$MCP_WRAPPER"
if [[ "$MCP_MODE" == register ]]; then
  if command -v claude >/dev/null && ! claude mcp list 2>/dev/null | grep -qi '^paperclip'; then
    claude mcp add --scope user paperclip -- "$MCP_WRAPPER" && echo "✔ MCP paperclip ajouté à Claude Code"
  fi
  if command -v codex >/dev/null && ! grep -qs 'mcp_servers.paperclip' "$HOME/.codex/config.toml"; then
    mkdir -p "$HOME/.codex"
    printf '\n[mcp_servers.paperclip]\ncommand = "%s"\nargs = []\n' "$MCP_WRAPPER" >> "$HOME/.codex/config.toml"
    echo "✔ MCP paperclip ajouté à Codex (~/.codex/config.toml)"
  fi
elif [[ "$MCP_MODE" == unregister ]]; then
  command -v claude >/dev/null && claude mcp remove --scope user paperclip >/dev/null 2>&1 \
    && echo "✔ MCP paperclip retiré de Claude Code"
  CODEX_CFG="$HOME/.codex/config.toml"
  if grep -qs '^\[mcp_servers\.paperclip\]' "$CODEX_CFG"; then
    cp "$CODEX_CFG" "$CODEX_CFG.bak.$(date +%Y%m%d%H%M%S)"
    awk '/^\[/{skip=($0=="[mcp_servers.paperclip]")} !skip' "$CODEX_CFG" > "$CODEX_CFG.tmp" && mv "$CODEX_CFG.tmp" "$CODEX_CFG"
    echo "✔ MCP paperclip retiré de Codex (sauvegarde : $CODEX_CFG.bak.*)"
  fi
fi

cat <<EOF

Organigramme prêt :
  Orchestrateur-CEO ($CEO_BRAIN)
   ├─ Architecte-Claude        (claude_local, Opus 5.5, effort high)
   ├─ Architecte-Fable         (claude_local, Fable 5.1, escalade)
   ├─ Dev-Codex                (codex_local)
   └─ Architecte-Codex-Backup  (codex_local, failover)

Étape suivante : ouvre OpenBot et colle le contenu de
  $KIT_DIR/config/openbot/bootstrap-prompt.md
(chemin du serveur MCP à indiquer : $MCP_WRAPPER)
EOF
