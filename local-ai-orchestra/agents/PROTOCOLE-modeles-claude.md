# Protocole multi-modèles Claude (Opus 5.5 / Fable 5.1)

Où chaque point du protocole est appliqué dans le kit :

| Point du protocole | Mise en œuvre |
|---|---|
| Opus 5.5 = architecte principal | `Architecte-Claude` : `model: claude-opus-5-5`, `effort: high` (`02-paperclip-agents.sh`) |
| Discipline d'effort medium / high | Règle 6 de `architecte-claude/AGENTS.md`. Le CEO tourne en Opus 5.5 `medium` |
| Escalade après deux échecs | Règle 7 de `architecte-claude/AGENTS.md` (commentaire `ESCALADE`, ticket `blocked`) + règle g) de `orchestrateur-ceo/AGENTS.md` |
| Fable 5.1 = spécialiste d'escalade | `Architecte-Fable` : `model: claude-fable-5-1`, `effort: high`, réveillé uniquement à l'assignation |
| Rendre la main à Opus / Codex | Étape 5 de `architecte-fable/AGENTS.md` |
| Jamais de build cassé en [Review] | Règle d) du CEO, règle absolue de Dev-Codex, règles d'Architecte-Fable |
| Historique en ajout seul, `tool_choice: auto` | Rien à configurer : Claude Code gère lui-même l'historique et les appels d'outils. Ces réglages concernent l'API, pas les agents |

Pour passer Fable en effort `max` (audits de sécurité), modifie `effort` de l'agent dans l'UI Paperclip
ou dans `02-paperclip-agents.sh`, puis relance le script. Fable et Opus partagent le même quota Claude.
