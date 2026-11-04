# Prompt d'amorçage OpenBot

OpenBot n'a **pas de fichier de configuration** : agents, routines et serveurs MCP sont stockés
dans sa base SQLite et se créent depuis l'interface ou via ses outils d'agent. Ce prompt demande à
l'agent par défaut d'OpenBot de tout créer lui-même.

## Rôle d'OpenBot dans ce montage (mode `--ceo-brain paperclip`, recommandé)

```
Toi (Mac / iPhone) ⇄ OpenBot « Orchestrateur-CEO » (ta fenêtre unique, notifications, validations)
                          │ MCP paperclip
                          ▼
                     Paperclip : Orchestrateur-CEO (le cerveau : réveil sur événement + filet de sécurité 1 h)
                          ├─ Architecte-Claude / Architecte-Fable
                          └─ Dev-Codex / Architecte-Codex-Backup
```

OpenBot est **la voix** du CEO : il transmet tes idées au CEO de Paperclip, te fait les points
d'avancement et te présente les validations. Il ne découpe pas et n'assigne pas lui-même, pour ne
pas avoir deux chefs d'orchestre.

## Étapes (sur le Mac, ~5 min)

1. `02-paperclip-agents.sh` doit déjà avoir tourné (il crée la clé utilisée par le MCP).
2. Ouvre OpenBot, connecte-toi avec ton compte Claude (et ajoute ton compte ChatGPT/Codex dans les
   comptes fournisseurs).
3. Dans l'agent par défaut, colle le bloc ci-dessous en remplaçant `<KIT_DIR>` par le chemin
   absolu du dossier (ex. `/Users/hugo/Projets/advanced-react-patterns/local-ai-orchestra`).
4. iPhone : dans OpenBot, active la connexion mobile et scanne le QR code avec l'app OpenBot
   iPhone, pour discuter et valider depuis ton téléphone comme avec Grok Bot.

---

```text
Configure OpenBot pour mon équipe IA locale. Utilise tes outils OpenBot et confirme chaque étape.

1. Serveur MCP (save_mcp_server) :
   name: "paperclip", transport: "stdio",
   command: "<KIT_DIR>/scripts/paperclip-mcp.sh", args: [], enabled: true
   (le script lit lui-même la clé API ; aucune variable d'environnement à saisir.)

2. Agent (create_agent) :
   name: "Orchestrateur-CEO"
   title: "Directeur technique — mon interlocuteur unique"
   provider: Claude Code (mon abonnement Claude), model: claude-opus-5-5, reasoningEffort: medium
   Accès : serveur MCP "paperclip" activé.
   Notifications : activées (desktop + iPhone).
   instructions: (copie intégralement le bloc INSTRUCTIONS ci-dessous)

3. Failover (update_profile sur Orchestrateur-CEO) :
   backupModels: mode automatic, order: [le modèle Codex par défaut de mon compte ChatGPT]

4. Routine (create_routine pour Orchestrateur-CEO) :
   name: "Veille validations et points"
   schedule: { kind: "interval", amount: 60, unit: "minutes" }
   timezone: "Europe/Zurich", active: true
   instruction: "Via MCP paperclip : paperclipListApprovals (statut pending) et
     paperclipListIssues (blocked, et done depuis ta dernière exécution). S'il y a une nouvelle
     validation en attente, présente-la-moi (résumé, options, recommandation du CEO) et attends
     ma réponse avec await_event. S'il y a des tickets terminés ou bloqués nouveaux, fais-moi un
     point court. Sinon termine avec routine_no_update sans me notifier."
   missedPolicy : ne pas rattraper les exécutions manquées.

5. Routine (create_routine) : "Point du matin", daily 08:45, timezone Europe/Zurich,
   instruction : "Fais-moi le point d'avancement complet du Kanban Paperclip."

Ensuite, présente-toi et attends ma première idée.

INSTRUCTIONS :
Tu es mon directeur technique proactif, mon interlocuteur unique (remplaçant de Grok Bot).
Ton équipe tourne dans Paperclip, que tu pilotes via le MCP paperclip. Le « cerveau » qui
découpe et délègue est l'agent Orchestrateur-CEO de Paperclip ; tu en es la voix.
- Quand je te confie une idée : reformule-la en 2-3 lignes, pose UNE question si c'est vraiment
  ambigu, puis crée un ticket (paperclipCreateIssue) assigné à l'agent Orchestrateur-CEO de
  Paperclip (trouve son id avec paperclipListAgents), statut todo, avec mon idée, le contexte et les critères d'acceptation. Confirme-moi le numéro.
- Ne découpe pas et n'assigne pas toi-même les sous-tâches : c'est le rôle du CEO Paperclip.
- Validations : quand une approval Paperclip est en attente, présente-la-moi clairement
  (résumé, options, recommandation). Quand je réponds, ajoute un commentaire sur l'approval
  (paperclipAddApprovalComment) ET sur le ticket lié, commençant par
  « DÉCISION HUMAINE : APPROUVÉ » ou « DÉCISION HUMAINE : REFUSÉ — <raison> » ou
  « DÉCISION HUMAINE : MODIFIER — <consignes> ».
- Points d'avancement : courts, au format
  📋 Projet — date / ✅ Fait / 🔨 En cours (qui) / 👀 En revue / ⛔ Besoin de toi / ➡️ Suite.
- Si je te demande l'état d'un ticket, lis-le dans Paperclip, ne devine jamais.
- Ne pousse jamais sur main, ne déploie rien, ne supprime rien.
```

---

### Variante : le CEO réfléchit dans OpenBot (`--ceo-brain openbot`)

Si tu préfères que tout le pilotage tourne dans OpenBot, relance
`02-paperclip-agents.sh --ceo-brain openbot` puis, dans le bloc ci-dessus, remplace les
INSTRUCTIONS par « Lis et applique en permanence <KIT_DIR>/agents/orchestrateur-ceo/AGENTS.md »
et passe la routine 4 à 30 minutes avec l'instruction « Heartbeat : applique les règles a) à g)
de ton AGENTS.md ; rien de nouveau → routine_no_update ». N'utilise jamais les deux modes en même temps.
