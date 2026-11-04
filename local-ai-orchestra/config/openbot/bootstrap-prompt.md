# Prompt d'amorçage OpenBot

OpenBot n'a **pas de fichier de configuration** : agents, routines et serveurs MCP sont stockés
dans sa base SQLite et se créent depuis l'interface ou via ses outils d'agent. Ce prompt demande à
l'agent par défaut d'OpenBot de tout créer lui-même.

1. Lance `scripts/02-paperclip-agents.sh` d'abord (il crée la clé API utilisée par le MCP).
2. Ouvre OpenBot → l'agent par défaut → colle le bloc ci-dessous en remplaçant `<KIT_DIR>` par
   le chemin absolu du dossier `local-ai-orchestra` (ex. `/Users/hugo/dev/advanced-react-patterns/local-ai-orchestra`).
3. Vérifie le résultat dans l'UI (fiche agent, Routines, MCP), puis discute uniquement avec
   **Orchestrateur-CEO**.

---

```text
Configure OpenBot pour mon équipe IA locale. Utilise tes outils OpenBot et confirme chaque étape.

1. Serveur MCP (save_mcp_server) :
   name: "paperclip", transport: "stdio",
   command: "<KIT_DIR>/scripts/paperclip-mcp.sh", args: [], enabled: true
   (le script lit lui-même la clé API ; aucune variable d'environnement à saisir.)

2. Agent (create_agent) :
   name: "Orchestrateur-CEO"
   title: "Directeur technique proactif — mon interlocuteur unique"
   provider: Claude Code (mon abonnement Claude), reasoningEffort: high
   instructions: "Lis et applique en permanence <KIT_DIR>/agents/orchestrateur-ceo/AGENTS.md.
     Tu pilotes l'équipe via le serveur MCP paperclip. Pour toute validation humaine :
     paperclipCreateApproval (type request_board_approval) + ticket en blocked, puis
     await_event et notifie-moi."
   Accès : serveur MCP "paperclip" activé ; dossier de travail partagé : mon dossier Projets.
   Notifications : activées (desktop + iPhone).

3. Failover (update_profile sur Orchestrateur-CEO) :
   backupModels: mode automatic, order: [le modèle Codex par défaut de mon abonnement ChatGPT]
   → si le quota Claude est atteint, l'agent bascule sur Codex et revient sur Claude à la fin
     de la limite.

4. Fichier d'instructions : copie <KIT_DIR>/agents/orchestrateur-ceo/AGENTS.md dans le
   AGENTS.md à la racine du workspace de l'agent Orchestrateur-CEO (~/OpenBot/Agents/<id>/AGENTS.md).

5. Heartbeat (create_routine pour Orchestrateur-CEO) :
   name: "Heartbeat Kanban"
   schedule: { kind: "interval", amount: 10, unit: "minutes" }
   timezone: "Europe/Paris", active: true
   instruction: "Heartbeat : via MCP paperclip, appelle paperclipInboxLite puis
     paperclipListIssues (in_progress, in_review, blocked) et paperclipListApprovals.
     Applique les règles a) à f) de ton AGENTS.md (tests obligatoires, relances, failover
     Claude→Codex des tickets d'Architecte-Claude en cas de rate limit). Si une approval a été
     décidée, reprends l'attente correspondante. S'il n'y a rien de nouveau, termine avec
     routine_no_update sans me notifier. Sinon envoie-moi un point au format défini."
   limitPolicy / missedPolicy : ne pas rattraper les exécutions manquées, une seule à la fois.

6. Routine quotidienne (create_routine) : "Point du matin", daily 08:45 Europe/Paris,
   instruction : "Fais-moi le point d'avancement complet du Kanban Paperclip."

Ensuite, présente-toi en tant qu'Orchestrateur-CEO et attends ma première idée.
```

---

### Pourquoi le CEO vit dans OpenBot (mode par défaut)

- c'est ta fenêtre unique de discussion (desktop + iPhone, comme Grok Bot) ;
- `await_event` et les notifications push y sont natifs ;
- le failover Claude → Codex du CEO est natif (`backupModels`) ;
- Paperclip garde le Kanban, les statuts, les approvals et réveille Architecte-Claude / Dev-Codex
  dès qu'on leur assigne un ticket (`wakeOnAssignment`).

Si tu préfères que le CEO tourne dans Paperclip (heartbeat Paperclip toutes les 10 min + réveil
sur événement de ticket), relance `02-paperclip-agents.sh --ceo-brain paperclip` et **n'active
pas** la routine « Heartbeat Kanban » ci-dessus, pour éviter deux cerveaux en parallèle.
