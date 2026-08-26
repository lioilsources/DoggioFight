#!/usr/bin/env bash
# Spustí DoggioWars s napojeným Twitch chatem.
#
#   ./play-twitch.sh <tvuj-twitch-kanal>
#
# Bridge čte chat anonymně (justinfan IRC) — žádný token, žádné OAuth,
# jen jméno kanálu. Ukončením hry se bridge zastaví taky.
set -euo pipefail

CHANNEL="${1:-}"
if [ -z "$CHANNEL" ]; then
  echo "použití: $0 <twitch-kanal>    (např. $0 lioilsources)" >&2
  exit 1
fi

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BRIDGE_REPO="${BRIDGE_REPO:-$(dirname "$REPO")/chatbridge}"
[ -d "$BRIDGE_REPO" ] || { echo "chybí repo chatbridge: $BRIDGE_REPO" >&2; exit 1; }

# Config si postavíme na míru do temp souboru — katalog z repa, kanál z CLI,
# ať se nemusí commitovat cizí přezdívka.
CFG="$(mktemp -t chatbridge-XXXX).yaml"
sed "s/^  channel:.*/  channel: \"$CHANNEL\"/" \
  "$BRIDGE_REPO/config.doggiowars.yaml" > "$CFG"

echo "== stavím bridge =="
(cd "$BRIDGE_REPO" && go build -o "$CFG.bin" ./cmd/chatbridge)

echo "== bridge poslouchá kanál: $CHANNEL =="
"$CFG.bin" -config "$CFG" &
BRIDGE_PID=$!
# hra i bridge padnou společně, ať po Ctrl+C nezůstane viset proces
trap 'kill $BRIDGE_PID 2>/dev/null || true; rm -f "$CFG" "$CFG.bin"' EXIT

sleep 2
if ! kill -0 $BRIDGE_PID 2>/dev/null; then
  echo "bridge se nerozběhl — viz výpis výše" >&2
  exit 1
fi

echo "== spouštím hru (příkazy do chatu: !drak !velryba !meduzy !cerv) =="
"$REPO/play.sh"
