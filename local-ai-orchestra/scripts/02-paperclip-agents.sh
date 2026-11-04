#!/usr/bin/env bash
# Crée (ou met à jour) la société et l'organigramme dans Paperclip via son API REST.
# Idempotent : relançable sans créer de doublons.
#
# Usage :
#   bash local-ai-orchestra/scripts/02-paperclip-agents.sh --workspace "$HOME/Projets" \
#        [--company "Studio IA"] [--ceo-brain openbot|paperclip]
#
#   --ceo-brain openbot    (défaut) le CEO "pense" dans OpenBot (chat, notifications iPhone,
#                          await_event, failover natif Claude→Codex). Dans Paperclip, sa fiche sert
#                          d'identité (clé API, organigramme) et son heartbeat Paperclip est coupé
#                          pour ne pas faire tourner deux cerveaux.
#   --ceo-brain paperclip  le CEO tourne dans Paperclip : heartbeat toutes les 10 min + réveil
#                          sur événement de ticket. OpenBot ne sert alors que de fenêtre de chat.
set -euo pipefail

KIT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PAPERCLIP_URL="${PAPERCLIP_URL:-http://127.0.0.1:3100}"
STATE_DIR="$HOME/.config/local-ai-orchestra"
STATE="$STATE_DIR/state.env"
WORKSPACE="$HOME/Projets"; COMPANY="Studio IA"; CEO_BRAIN="openbot"
CEO_HEARTBEAT_SEC=600

while [[ $# -gt 0 ]]; do case "$1" in
  --workspace) WORKSPACE="$2"; shift 2;;
  --company) COMPANY="$2"; shift 2;;
  --ceo-brain) CEO_BRAIN="$2"; shift 2;;
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
# upsert NAME ROLE TITLE ADAPTER INSTR_DIR REPORTS_TO HEARTBEAT_JSON CAPABILITIES
upsert() {
  local name="$1" role="$2" title="$3" adapter="$4" instr="$KIT_DIR/agents/$5/AGENTS.md" reports="$6" hb="$7" caps="$8"
  local cfg
  if [[ "$adapter" == claude_local ]]; then
    cfg=$(jq -n --arg cwd "$WORKSPACE" --arg i "$instr" --arg c "$CLAUDE_BIN" \
      '{cwd:$cwd, instructionsFilePath:$i, command:$c, dangerouslySkipPermissions:true}')
  else
    cfg=$(jq -n --arg cwd "$WORKSPACE" --arg i "$instr" \
      '{cwd:$cwd, instructionsFilePath:$i, dangerouslyBypassApprovalsAndSandbox:true}')
  fi
  local body
  body=$(jq -n --arg n "$name" --arg r "$role" --arg t "$title" --arg a "$adapter" --arg cap "$caps" \
    --arg rep "$reports" --argjson cfg "$cfg" --argjson hb "$hb" \
    '{name:$n, role:$r, title:$t, capabilities:$cap, adapterType:$a, adapterConfig:$cfg,
      runtimeConfig:{heartbeat:$hb}} + (if $rep=="" then {} else {reportsTo:$rep} end)')
  local id
  id=$(api GET "/api/companies/$CID/agents" | as_list | jq -r --arg n "$name" '.[] | select(.name==$n) | .id' | head -1)
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
  "$CEO_HB" "Découpe les demandes en tickets, délègue, suit le Kanban, impose les tests, gère approvals et failover")
ARCH_ID=$(upsert "Architecte-Claude" cto "Architecte logiciel" claude_local architecte-claude "$CEO_ID" \
  "$WORKER_HB" "Architecture, code complexe, revues de code")
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
DEV_CODEX_ID="$DEV_ID"
ARCHITECTE_CODEX_BACKUP_ID="$BACKUP_ID"
CEO_BRAIN="$CEO_BRAIN"
WORKSPACE="$WORKSPACE"
EOF
echo "✔ État enregistré dans $STATE (chmod 600)"

# --- Serveur MCP Paperclip pour Claude Code / Codex (usage manuel, optionnel) ---------------
MCP_WRAPPER="$KIT_DIR/scripts/paperclip-mcp.sh"
chmod +x "$MCP_WRAPPER"
if command -v claude >/dev/null && ! claude mcp list 2>/dev/null | grep -qi '^paperclip'; then
  claude mcp add --scope user paperclip -- "$MCP_WRAPPER" && echo "✔ MCP paperclip ajouté à Claude Code"
fi
if command -v codex >/dev/null && ! grep -qs 'mcp_servers.paperclip' "$HOME/.codex/config.toml"; then
  mkdir -p "$HOME/.codex"
  printf '\n[mcp_servers.paperclip]\ncommand = "%s"\nargs = []\n' "$MCP_WRAPPER" >> "$HOME/.codex/config.toml"
  echo "✔ MCP paperclip ajouté à Codex (~/.codex/config.toml)"
fi

cat <<EOF

Organigramme prêt :
  Orchestrateur-CEO ($CEO_BRAIN)
   ├─ Architecte-Claude        (claude_local)
   ├─ Dev-Codex                (codex_local)
   └─ Architecte-Codex-Backup  (codex_local, failover)

Étape suivante : ouvre OpenBot et colle le contenu de
  $KIT_DIR/config/openbot/bootstrap-prompt.md
(chemin du serveur MCP à indiquer : $MCP_WRAPPER)
EOF
