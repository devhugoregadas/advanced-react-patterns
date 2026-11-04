# local-ai-orchestra — remplacer Grok Bot Ultra par OpenBot + Paperclip

Une équipe IA 100 % locale sur ton MacBook Pro, propulsée uniquement par tes abonnements
**Claude Code** et **OpenAI Codex**. Aucune clé API n'est nécessaire.

```
   Toi (desktop / iPhone)
          │  chat, notifications, validations
          ▼
 ┌──────────────────────── OpenBot ────────────────────────┐
 │  Orchestrateur-CEO  (Claude, failover auto → Codex)     │
 │  routine "Heartbeat Kanban" toutes les 10 min           │
 └──────────────┬──────────────────────────────────────────┘
                │ MCP @paperclipai/mcp-server
                ▼
 ┌──────────────────────── Paperclip (localhost:3100) ─────┐
 │  Kanban : todo → in_progress → in_review → done         │
 │  Approvals (validations humaines)                       │
 │  ├─ Architecte-Claude        claude_local (Opus 5.5)    │
 │  ├─ Architecte-Fable         claude_local (Fable 5.1)   │
 │  ├─ Dev-Codex                codex_local (tests)        │
 │  └─ Architecte-Codex-Backup  codex_local (failover)     │
 └─────────────────────────────────────────────────────────┘
```

## Installation (sur le Mac)

```bash
git clone -b claude/local-grok-openbot-setup-3woop0 https://github.com/devhugoregadas/advanced-react-patterns.git
cd advanced-react-patterns/local-ai-orchestra

bash scripts/00-inspect.sh                     # 1. diagnostic, ne modifie rien
bash scripts/01-install.sh --keep-awake        # 2. installe ce qui manque (demande confirmation)
claude    # puis /login   ← compte Claude
codex login               ← compte ChatGPT
bash scripts/02-paperclip-agents.sh --workspace "$HOME/Projets"   # 3. organigramme
```

4. Installe OpenBot (`.dmg` depuis https://github.com/nightly-labs/openbot/releases), puis colle
   le prompt de `config/openbot/bootstrap-prompt.md`.
5. Kanban : http://localhost:3100

## Contenu

| Fichier | Rôle |
|---|---|
| `scripts/00-inspect.sh` | Diagnostic : Node ≥ 24.11, claude/codex dans le PATH (shell **et** apps graphiques), Docker, Paperclip, MCP, OpenBot, veille |
| `scripts/01-install.sh` | Installe jq/Node/CLIs, corrige le PATH des apps graphiques, `paperclipai onboard`, service launchd, veille désactivée |
| `scripts/02-paperclip-agents.sh` | Crée la société et les 5 agents via l'API Paperclip (idempotent), la clé API du CEO ; `--register-mcp` (optionnel) ajoute le MCP à Claude Code et Codex |
| `scripts/paperclip-mcp.sh` | Lance `@paperclipai/mcp-server` avec l'identité du CEO |
| `agents/*/AGENTS.md` | Prompts système des agents (modifiables à chaud : Paperclip les relit à chaque exécution) |
| `config/openbot/bootstrap-prompt.md` | Prompt qui fait d'OpenBot ta fenêtre unique (chat, iPhone, validations, points) branchée sur le CEO Paperclip |
| `config/launchd/…plist` | Modèle de service macOS pour garder Paperclip actif 24h/24 |

## Correspondance avec ta demande

| Demande | Mise en œuvre |
|---|---|
| Kanban [To Do]/[In Progress]/[Review]/[Done] | Statuts Paperclip `todo` / `in_progress` / `in_review` / `done` (+ `blocked`) |
| Heartbeat 5–15 min | Routine OpenBot toutes les 10 min (ou `--ceo-brain paperclip` : `runtimeConfig.heartbeat.intervalSec = 600` + réveil sur événement de ticket) |
| Délégation Architecte / Dev | Assignation de tickets ; les exécutants se réveillent à l'assignation (`wakeOnAssignment`) |
| Communication entre agents | Commentaires avec @mention sur les tickets Paperclip |
| Tests obligatoires avant Review | Règle d) du CEO + règle absolue de Dev-Codex (commande + sortie + exit code collés) |
| Approval Gates | `paperclipCreateApproval` (`request_board_approval`) + `await_event` + notification OpenBot |
| Escalade Opus → Fable | Règle des deux essais d'Architecte-Claude (commentaire `ESCALADE`) + règle g) du CEO — voir `agents/PROTOCOLE-modeles-claude.md` |
| Failover rate limit | CEO : `backupModels` OpenBot (Claude → Codex, retour auto). Tickets : le CEO réassigne à Architecte-Codex-Backup / Dev-Codex |

## Limites connues

- **OpenBot n'a pas de config déclarative** : la partie OpenBot passe par le prompt d'amorçage
  (ou l'UI). Rien n'est écrit directement dans sa base SQLite.
- **Sécurité** : comme Paperclip et OpenBot par défaut, les agents tournent sans demande de
  permission (`dangerouslySkipPermissions`, `dangerouslyBypassApprovalsAndSandbox`). Limite-les à
  `--workspace`. Les validations humaines passent par les règles du CEO, pas par un bac à sable.
- **Failover des exécutants** : Paperclip met Architecte-Claude en pause jusqu'à la fin du quota.
  La bascule vers Codex est faite par le CEO à son réveil suivant (≤ 10 min), pas instantanément.
- **Validation d'une approval** : réponds dans OpenBot ; le CEO consigne ta réponse. Pour clore
  formellement l'approval, clique Approuver/Rejeter dans l'UI Paperclip (action du « board »).
- Ces scripts ont été écrits à partir de la doc et du code source de Paperclip et d'OpenBot,
  mais pas exécutés sur ton Mac. Si une réponse d'API ne correspond pas, `02-paperclip-agents.sh`
  s'arrête avec l'erreur `curl` : envoie-la-moi.
