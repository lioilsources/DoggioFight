#!/usr/bin/env bash
# Spustí Luanti přímo do světa s aktuálně odbočenou verzí hry.
#   ./play.sh                     -> aktuální větev
#   ./play.sh main                -> přepne na main a spustí
#   ./play.sh claude/submarine-mode
# Hra je do Luanti připojena symlinkem v games/, takže stačí přepnout
# větev a spustit.
set -euo pipefail

LUANTI="${LUANTI:-$HOME/Downloads/luanti.app/Contents/MacOS/luanti}"
WORLD="${WORLD:-Paja}"
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

[ -x "$LUANTI" ] || { echo "Luanti nenalezen: $LUANTI (nastav LUANTI=...)" >&2; exit 1; }

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
