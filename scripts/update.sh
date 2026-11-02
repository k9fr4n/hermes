#!/usr/bin/env bash
# Met a jour Hermes : recupere la derniere image upstream et recree le
# conteneur uniquement si l'image a change.
set -euo pipefail
cd "$(dirname "$0")/.."

docker compose pull hermes

# ID de l'image utilisee par le conteneur (vide s'il n'existe pas encore).
CURRENT_ID=$(docker inspect --format '{{.Image}}' hermes 2>/dev/null || true)

# Reference d'image resolue par Compose (tient compte de .env).
TARGET_REF=$(docker compose config --images | head -n1)
TARGET_ID=$(docker image inspect "$TARGET_REF" --format '{{.Id}}')

if [ -n "$CURRENT_ID" ] && [ "$CURRENT_ID" = "$TARGET_ID" ]; then
  echo "Deja a jour ($TARGET_REF)."
  docker compose up -d
else
  echo "Nouvelle image detectee, recreation du conteneur..."
  docker compose up -d --force-recreate
  # Nettoie l'ancienne image devenue orpheline.
  docker image prune -f >/dev/null
fi

docker compose ps
