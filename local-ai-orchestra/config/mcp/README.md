# Serveur MCP Paperclip

Paquet officiel : `@paperclipai/mcp-server` (couche fine au-dessus de l'API REST Paperclip).

Le wrapper `../../scripts/paperclip-mcp.sh` charge `~/.config/local-ai-orchestra/state.env`
(URL, société, identité et clé du CEO) puis lance `npx -y @paperclipai/mcp-server`.
`02-paperclip-agents.sh --register-mcp` l'enregistre (optionnel, retrait avec `--unregister-mcp`) dans :

- **Claude Code** : `claude mcp add --scope user paperclip -- <KIT_DIR>/scripts/paperclip-mcp.sh`
- **Codex** : `~/.codex/config.toml`
  ```toml
  [mcp_servers.paperclip]
  command = "<KIT_DIR>/scripts/paperclip-mcp.sh"
  args = []
  ```
- **OpenBot** : via `save_mcp_server` (voir `../openbot/bootstrap-prompt.md`).

Les agents lancés **par Paperclip** (Architecte-Claude, Dev-Codex…) n'en ont pas besoin :
Paperclip leur injecte ses propres identifiants et outils pendant chaque heartbeat.

Outils principaux : `paperclipListIssues`, `paperclipCreateIssue`, `paperclipUpdateIssue`,
`paperclipCheckoutIssue`, `paperclipAddComment`, `paperclipListComments`,
`paperclipCreateApproval`, `paperclipListApprovals`, `paperclipInboxLite`,
`paperclipGetHeartbeatContext`, `paperclipApiRequest`.
