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

# Spouštíme binárku napřímo, ne přes `open`. Kromě rychlosti to obchází
# App Translocation: appka stažená prohlížečem má na sobě karanténu a macOS
# ji přes LaunchServices spouští z náhodné read-only kopie. Přímý start
# LaunchServices míjí, takže hra běží ze své skutečné cesty.
LUANTI="${LUANTI:-}"
if [ -z "$LUANTI" ]; then
  for c in /Applications/luanti.app/Contents/MacOS/luanti \
           "$HOME/Applications/luanti.app/Contents/MacOS/luanti" \
           "$HOME/Downloads/luanti.app/Contents/MacOS/luanti"; do
    [ -x "$c" ] && LUANTI="$c" && break
  done
fi
WORLD="${WORLD:-Doggio}"
SEED="${SEED:-}"                 # prázdné = Luanti si vylosuje vlastní
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORLDS="${WORLDS:-$HOME/Library/Application Support/minetest/worlds}"

[ -x "$LUANTI" ] || { echo "Luanti nenalezen: $LUANTI (nastav LUANTI=...)" >&2; exit 1; }

# DualShock 4 přes Bluetooth se na macOS odpojoval přesně ve chvíli, kdy
# Luanti startovalo (v systémovém logu "disconnection indication" ve stejné
# vteřině jako start SDL). SDL si totiž PS4 pad otevírá vlastním HIDAPI
# driverem, jenže macOS ho už drží přes Game Controller framework. Tímhle
# hintem SDL svůj driver vynechá a použije systémový.
#   SDL_JOYSTICK_HIDAPI_PS4=1  ./play.sh   -> vrátí původní chování
export SDL_JOYSTICK_HIDAPI_PS4="${SDL_JOYSTICK_HIDAPI_PS4:-0}"

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
