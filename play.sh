#!/usr/bin/env bash
# Spustí Luanti přímo do světa s aktuálně odbočenou verzí hry.
#   ./play.sh                     -> aktuální větev
#   ./play.sh main                -> přepne na main a spustí
#   ./play.sh claude/submarine-mode
# Hra je do Luanti připojena symlinkem v games/, takže stačí přepnout
# větev a spustit. Svět se založí, pokud ještě není.
#
# Proměnné: WORLD (jméno světa), SEED (seed nového světa),
#           LUANTI (cesta k binárce), WORLDS (složka se světy)
set -euo pipefail

LUANTI="${LUANTI:-$HOME/Downloads/luanti.app/Contents/MacOS/luanti}"
WORLD="${WORLD:-Doggio}"
SEED="${SEED:-}"                 # prázdné = Luanti si vylosuje vlastní
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORLDS="${WORLDS:-$HOME/Library/Application Support/minetest/worlds}"

[ -x "$LUANTI" ] || { echo "Luanti nenalezen: $LUANTI (nastav LUANTI=...)" >&2; exit 1; }

# Svět si založíme sami, ať "rozjet novou hru" je jeden příkaz. Luanti
# umí --go jen do existujícího světa; bez tohohle by spadl na neznámý svět.
if [ ! -d "$WORLDS/$WORLD" ]; then
  echo "zakládám nový svět: $WORLD"
  mkdir -p "$WORLDS/$WORLD"
  cat > "$WORLDS/$WORLD/world.mt" <<EOF
gameid = doggiowars
world_name = $WORLD
backend = sqlite3
player_backend = sqlite3
auth_backend = sqlite3
mod_storage_backend = sqlite3
server_announce = false
EOF
  [ -n "$SEED" ] && printf 'seed = %s\n[end_of_params]\n' "$SEED" \
    > "$WORLDS/$WORLD/map_meta.txt"
fi

if [ $# -ge 1 ]; then
  branch="$1"
  git -C "$REPO" diff --quiet && git -C "$REPO" diff --cached --quiet ||
    { echo "Pracovní strom má neuložené změny — commitni nebo stashni." >&2; exit 1; }
  if ! git -C "$REPO" rev-parse --verify --quiet "$branch" >/dev/null; then
    git -C "$REPO" fetch origin "$branch"
    git -C "$REPO" checkout -b "$branch" --track "origin/$branch"
  else
    git -C "$REPO" checkout "$branch"
  fi
fi

echo "větev: $(git -C "$REPO" rev-parse --abbrev-ref HEAD)  svět: $WORLD"
exec "$LUANTI" --go --worldname "$WORLD" --gameid doggiowars
