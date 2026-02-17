# OpenClaw Docker

Deploiement d'OpenClaw dans Docker avec persistance complete et backup S3.

## Prerequis

- Docker + Docker Compose v2
- [Task](https://taskfile.dev) (`go-task`)
- AWS CLI (pour les backups S3)

## Installation

```bash
git clone git@github.com:stanig2106/openclaw-backup.git
cd openclaw-backup
task setup
```

Le setup fait tout : clone OpenClaw, build l'image Docker (avec brew, go, bun, uv, ffmpeg), lance l'onboarding, demarre le gateway et connecte le dashboard.

## Restauration sur un nouveau serveur

```bash
git clone git@github.com:stanig2106/openclaw-backup.git
cd openclaw-backup
cp .env.backup .env  # ou recree le .env avec les credentials S3
task restore
```

## Commandes

### Service

| Commande | Description |
|----------|-------------|
| `task start` | Demarrer le gateway |
| `task stop` | Arreter le gateway |
| `task restart` | Redemarrer le gateway |
| `task logs` | Voir les logs en temps reel |
| `task status` | Verifier le statut |
| `task shell` | Ouvrir un shell dans le conteneur |
| `task dashboard` | Afficher l'URL du dashboard |

### Backup & Restore

| Commande | Description |
|----------|-------------|
| `task backup` | Backup complet sur S3 (donnees + image Docker) |
| `task backup:local` | Backup complet en local |
| `task backup:list` | Lister les backups S3 |
| `task backup:cron` | Activer le backup automatique (3h30, 3 backups max) |
| `task backup:cron:remove` | Supprimer le cron |
| `task backup:prune` | Nettoyer les anciens backups S3 |
| `task restore` | Restaurer depuis S3 (choix interactif) |
| `task restore:local` | Restaurer depuis un fichier local |

### Systeme

| Commande | Description |
|----------|-------------|
| `task commit` | Sauvegarder l'etat systeme du conteneur dans l'image |
| `task recreate` | Recreer le conteneur depuis l'image |
| `task update` | Mettre a jour OpenClaw (backup auto, pull, rebuild) |
| `task build` | Reconstruire l'image Docker |

### Channels

| Commande | Description |
|----------|-------------|
| `task channel:whatsapp` | Connecter WhatsApp (QR code) |
| `task channel:telegram -- <token>` | Ajouter un bot Telegram |
| `task channel:discord -- <token>` | Ajouter un bot Discord |

### Autres

| Commande | Description |
|----------|-------------|
| `task auth:codex` | Connecter OpenAI Codex via OAuth |
| `task devices` | Lister les devices |
| `task devices:approve -- <id>` | Approuver un device |
| `task clean` | Supprimer conteneurs et image |
| `task clean:all` | Tout supprimer (IRREVERSIBLE) |

## Persistance

- **Donnees** (config, workspace, .env) : bind mounts dans `./data/`
- **Systeme** (apt install, /opt, /usr) : preserve par `docker stop/start`, sauvegarde via `task commit`
- **Backups** : archive complete (donnees + image Docker) sur S3

## Acces distant (VPS)

```bash
ssh -N -L 18789:127.0.0.1:18789 user@TON_VPS_IP
```

Puis ouvre `http://127.0.0.1:18789/` sur ton PC.

## Structure

```
.
├── Taskfile.yml          # Toutes les commandes
├── Dockerfile            # Image avec brew, go, bun, uv, ffmpeg
├── docker-compose.yml    # Services gateway + cli
├── .env                  # Configuration (non versionne)
├── scripts/
│   ├── common.sh         # Fonctions partagees
│   ├── s3-helper.sh      # Fonctions S3
│   ├── setup.sh          # Installation complete
│   ├── update.sh         # Mise a jour
│   ├── backup.sh         # Backup local
│   ├── backup-s3.sh      # Backup S3
│   ├── backup-cron.sh    # Cron backup
│   ├── backup-prune.sh   # Nettoyage backups
│   ├── restore.sh        # Restore local
│   └── restore-s3.sh     # Restore S3
└── data/                 # Donnees persistantes (non versionne)
    ├── config/
    └── workspace/
```
