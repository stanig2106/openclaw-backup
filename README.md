# OpenClaw Docker Deploy

Déploiement simple d'OpenClaw dans Docker avec persistance et backup.

## Prérequis

- Docker + Docker Compose v2
- [Task](https://taskfile.dev) (`go-task`)
- Git

### Installer Task

```bash
# Linux
sh -c "$(curl --location https://taskfile.dev/install.sh)" -- -d -b /usr/local/bin

# macOS
brew install go-task
```

## Installation rapide

```bash
git clone <ce-repo> openclaw-docker
cd openclaw-docker
cp .env.example .env
# Édite .env avec tes clés API
task setup
```

## Commandes

| Commande | Description |
|---|---|
| `task setup` | Installation complète |
| `task start` | Démarrer le gateway |
| `task stop` | Arrêter le gateway |
| `task restart` | Redémarrer |
| `task logs` | Logs en temps réel |
| `task status` | Statut du gateway |
| `task backup` | Créer un backup |
| `task restore -- ./backups/fichier.tar.gz` | Restaurer un backup |
| `task update` | Mettre à jour OpenClaw |
| `task shell` | Shell dans le conteneur |
| `task cli -- <commande>` | Commande CLI OpenClaw |
| `task dashboard` | Afficher URL + token |
| `task tunnel` | Commande SSH tunnel |

### Channels

```bash
task channel:whatsapp          # Connecter WhatsApp (QR)
task channel:telegram -- <TOKEN>  # Ajouter bot Telegram
task channel:discord -- <TOKEN>   # Ajouter bot Discord
```

## Structure

```
openclaw-docker/
├── docker-compose.yml     # Config Docker
├── Taskfile.yml           # Commandes task
├── .env.example           # Template de config
├── .env                   # Ta config (non versionné)
├── scripts/
│   ├── setup.sh           # Installation
│   ├── backup.sh          # Backup
│   ├── restore.sh         # Restore
│   └── update.sh          # Mise à jour
├── data/                  # Données persistantes (non versionné)
│   ├── config/            # ~/.openclaw du conteneur
│   └── workspace/         # Workspace de l'agent
├── backups/               # Fichiers de backup (non versionné)
└── openclaw/              # Code source (cloné par setup, non versionné)
```

## Persistance

Toutes les données sont montées depuis `./data/` vers le conteneur :

| Donnée | Host | Conteneur |
|---|---|---|
| Config (openclaw.json, tokens, sessions) | `./data/config/` | `/home/node/.openclaw/` |
| Workspace (code, artefacts) | `./data/workspace/` | `/home/node/.openclaw/workspace/` |

Le conteneur peut être détruit et recréé sans perte de données.
`restart: unless-stopped` assure le redémarrage automatique après reboot du VPS.

## Backup & Migration

### Créer un backup

```bash
task backup
```

Crée une archive `./backups/openclaw-backup-YYYYMMDD_HHMMSS.tar.gz` contenant :
- Config complète (tokens, sessions, auth)
- Workspace
- Fichier .env

### Migrer vers un autre serveur

```bash
# Sur l'ancien serveur
task backup

# Transférer
scp ./backups/openclaw-backup-*.tar.gz user@nouveau-serveur:~/

# Sur le nouveau serveur
git clone <ce-repo> openclaw-docker
cd openclaw-docker
task restore -- ~/openclaw-backup-*.tar.gz
task setup  # Rebuild l'image
task start
```

## Accès distant (VPS)

Le gateway écoute par défaut sur `127.0.0.1` (non exposé). Utilise un tunnel SSH :

```bash
ssh -N -L 18789:127.0.0.1:18789 user@TON_VPS_IP
```

Puis ouvre `http://127.0.0.1:18789/` sur ton PC.

## Sécurité

- Le conteneur tourne en tant que user `node` (uid 1000), pas root
- Le port n'est pas exposé publiquement par défaut
- Le token gateway est généré aléatoirement
- Les données sensibles restent sur le host dans `./data/`
- `.env` n'est pas versionné dans git
