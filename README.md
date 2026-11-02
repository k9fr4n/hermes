# Hermes — deploiement Raspberry Pi

Repo de deploiement personnel pour [Hermes Agent](https://github.com/NousResearch/hermes-agent),
l'agent auto-ameliorant de Nous Research (MIT).

L'image Docker officielle **multi-arch (dont arm64)** est utilisee telle quelle
(`nousresearch/hermes-agent`). Le Raspberry Pi ne construit rien : il telecharge
l'image et la lance avec Docker Compose. Le dashboard (port 9119) et la webapp
(port 9120, Hermes Desktop dans le navigateur) sont publies via Traefik,
comme pour le deploiement OpenChamber.

```
nousresearch/hermes-agent (upstream, image officielle)
        │
        ▼  docker compose pull
Raspberry Pi ── conteneur hermes (gateway 8642 + dashboard 9119 + webapp 9120)
        │
        ▼  labels Traefik, reseau externe "proxy"
https://hermes-dashboard.ecritel.net (dashboard)
https://hermes-webapp.ecritel.net    (webapp)
```

## Prerequis (Pi)

- Raspberry Pi **64 bits** (Pi 4 ou Pi 5 recommande) sous Raspberry Pi OS 64 bits,
  Debian ou Ubuntu arm64.
- Docker Engine avec le plugin Compose (`docker compose version` doit repondre).
- ~2 Go de RAM libres et ~3 Go d'espace disque pour l'image
  (l'image embarque Chromium ; prevoir 2 Go de RAM mini, 4 Go avec les outils navigateur).
- Reseau Docker externe `proxy` et Traefik frontal (meme setup que OpenChamber).
- Acces sortant a `docker.io` pour telecharger l'image.

## Mise en route

### 1. Cloner le repo sur le Pi

```
git clone git@github.com:k9fr4n/hermes.git ~/hermes
cd ~/hermes
```

### 2. Configurer l'authentification du dashboard

Le dashboard ecoute en `0.0.0.0` dans le conteneur (port publie + Traefik) :
depuis le durcissement de juin 2026, un bind non-loopback **exige toujours**
un fournisseur d'auth — sans lui, le dashboard refuse de demarrer (fail-closed).
Ici on utilise le fournisseur user/password, reserve au LAN/VPN de confiance.

```
cp .env.example .env
openssl rand -hex 16    # copier le resultat dans HERMES_DASHBOARD_PASSWORD
openssl rand -base64 32 # copier le resultat dans HERMES_DASHBOARD_SECRET
nano .env
```

`.env` n'est jamais commite.

### 3. Lancer

```
docker compose up -d
docker compose ps
docker compose logs -f hermes   # le gateway + le dashboard y ecrivent au demarrage
```

Ouvrir `http://<ip-du-pi>:9119`, se connecter avec le user/password de l'etape 2.

### 4. Assistant de configuration (premier lancement)

Au premier demarrage, le conteneur initialise `data/` (config.yaml, .env, SOUL.md…).
Lancer l'assistant pour choisir le provider de modele :

```
docker compose exec hermes hermes setup
# ou, pour Nous Portal (OAuth, un abonnement couvre 300+ modeles) :
docker compose exec hermes hermes setup --portal
```

Verifier ensuite qu'une conversation simple fonctionne avant d'ajouter le reste :

```
docker compose exec hermes hermes model
docker compose exec hermes hermes doctor
```

### 5. Activer la webapp (port 9120)

La webapp (Hermes Desktop dans le navigateur) est prebuildee dans l'image mais
**desactivee par defaut** : c'est le gateway qui la sert quand `config.yaml` l'active.

```
docker compose exec hermes hermes config set webapp.enabled true
docker compose exec hermes hermes config set webapp.host 0.0.0.0
docker compose exec hermes hermes config set webapp.port 9120
docker compose exec hermes hermes config set webapp.public_url https://hermes-webapp.ecritel.net
docker compose restart hermes
```

L'authentification est la meme que celle du dashboard (user/password) :
un bind non-loopback refuse de demarrer sans fournisseur d'auth.

Ouvrir `http://<ip-du-pi>:9120` ou `https://hermes-webapp.ecritel.net`.

## Donnees et volumes

Tout l'etat vit dans `./data` sur le Pi, monte en `/opt/data` (l'image est sans etat) :

| Chemin sur le Pi | Contenu |
| --- | --- |
| `./data/.env` | Cles API et secrets (gerables depuis la page API Keys du dashboard) |
| `./data/config.yaml` | Toute la configuration non-secrete (modele, webapp, dashboard…) |
| `./data/sessions/` | Historique des conversations |
| `./data/skills/` | Skills installes |
| `./data/memories/` | Memoire persistante |
| `./data/logs/` | Logs (agent, gateway, `gateways/<profil>/current`, `container-boot.log`) |
| `./data/cron/` | Taches planifiees |

Le contenu de `data/` est ignore par git : il contient des secrets. Le dossier est
versionne vide (`.gitkeep`) pour qu'un clone soit directement utilisable.

Sauvegarde : un seul dossier a copier (`data/`). Ne jamais monter deux conteneurs
gateway sur le meme `data/` en ecriture simultanee (corruption des sessions).

## Cles API et provider de modele

De preference via le dashboard (pages **API Keys** / **Config**) ou en CLI :

```
docker compose exec hermes hermes model      # choix interactif du provider
docker compose exec hermes hermes config set OPENROUTER_API_KEY sk-or-...
docker compose exec hermes hermes gateway status
```

Les secrets vont dans `data/.env`, la config dans `data/config.yaml`
(voir `hermes config set` — la bonne valeur va automatiquement au bon fichier).

## Reverse proxy (Traefik)

Les labels Traefik sont dans `docker-compose.yml`, sur le modele OpenChamber :
deux routeurs avec **liaisons routeur→service explicites** — des qu'un conteneur
expose deux services, Traefik refuse les routeurs sans liaison explicite
(`cannot be linked automatically with multiple Services`).

| Domaine | Service | Port |
| --- | --- | --- |
| `hermes-dashboard.ecritel.net` | `hermes-dashboard` | 9119 |
| `hermes-webapp.ecritel.net` | `hermes-webapp` | 9120 |

Les noms sont reglables via `HERMES_DASHBOARD_HOSTNAME` / `HERMES_WEBAPP_HOSTNAME`
dans `.env`. Le dashboard est derriere HTTPS : declarer l'URL publique et ne faire
confiance qu'au reseau du proxy (sous-reseau actuel : `172.17.5.0/24`) dans
`data/config.yaml` pour que les cookies OAuth restent `Secure` :

```yaml
dashboard:
  public_url: "https://hermes-dashboard.ecritel.net"
  trusted_proxies:
    - "172.17.5.0/24"
```

Ne jamais mettre `*` ou `0.0.0.0/0` dans `trusted_proxies` (refuse par Hermes).
Apres modification : `docker compose restart hermes`.

> Securite : le user/password convient au LAN/VPN de confiance uniquement.
> Pour une exposition Internet directe, passer au provider OAuth (Nous Portal)
> ou OIDC — voir la doc [Web Dashboard → Authentication](https://hermes-agent.nousresearch.com/docs/user-guide/features/web-dashboard#authentication-gated-mode).

## Mise a jour

L'image suit la branche stable upstream (`latest`). Sur le Pi :

```
cd ~/hermes
git pull
./scripts/update.sh
```

Le script ne recree le conteneur que si l'image a change (`data/` est preserve,
et le conteneur rejoue les migrations de config non-interactives au demarrage).
Pour epingler une version : `HERMES_IMAGE=nousresearch/hermes-agent:v2026.8.31`
dans `.env`, puis `./scripts/update.sh`.

## Depannage

- **`HERMES_DASHBOARD_*` manquant au `docker compose up`** : le fichier `.env`
  manque ou une variable est vide (etape 2).
- **`Refusing to bind to 0.0.0.0` / dashboard qui ne demarre pas** : aucun
  fournisseur d'auth enregistre et bind non-loopback → fail-closed volontaire.
  Verifier les 3 variables `HERMES_DASHBOARD_BASIC_AUTH_*` (injectees depuis
  `.env`) puis `docker compose restart hermes`.
- **Webapp injoignable (connexion refusee sur 9120)** : `webapp.enabled` n'est
  pas a `true` dans `data/config.yaml` (etape 5), ou le conteneur n'a pas ete
  redemarre apres activation.
- **Page blanche / 404 via Traefik sur un seul des deux domaines** : verifier les
  liaisons `traefik.http.routers.<nom>.service` dans `docker-compose.yml`
  (obligatoires avec deux services sur le meme conteneur).
- **Le conteneur redemarre en boucle** : `docker compose logs hermes` (cause :
  RAM insuffisante — Chromium demande ~2 Go — volume mal monte, etc.).
- **`EACCES: permission denied`, fichiers `root:root` dans `data/`** : l'entrypoint
  corrige la propriete au demarrage via `HERMES_UID`/`HERMES_GID` (defaut 1000:1000).
  Verifier ces valeurs dans `.env`, puis `docker compose up -d --force-recreate`.
- **Deux gateways sur le meme `data/`** : a ne jamais faire (corruption sessions/memoires).
  Un seul conteneur heberge tous les profils (`hermes profile create …`).

## Contenu du repo

```
.
├── docker-compose.yml  # deploiement sur le Pi (gateway + dashboard + webapp, Traefik)
├── .env.example        # modele de configuration
├── scripts/update.sh   # pull + recreation si l'image a change
└── data/               # cree au premier lancement (ignore par git)
```

Hermes Agent est un projet MIT independant de ce repo de deploiement.
Doc officielle : https://hermes-agent.nousresearch.com/docs/
