#!/bin/bash
# Start one eve-online-haulerbot run on Windows, refusing if a host is already
# alive.
#
#   EVE_HAUL_SOURCE="Station A" EVE_HAUL_DEST="Station B" ./run_haulerbot.sh <run number> [minutes]
#
# Modelled on run_saxrat.sh in this same directory -- read that file's own
# header first if this is unfamiliar territory, since every trap it documents
# (the one-bot guard, why the settings block is a here-doc, why the tree is
# checked before the run starts) applies here unchanged. What is different is
# only the settings this bot takes.
#
# `EVE_HAUL_SOURCE` / `EVE_HAUL_DEST` are required and unset by default,
# deliberately -- a script that silently defaulted them to some previous
# operator's stations would send the ship to the wrong place with every log
# line reading like success, which is exactly the failure class this repo's
# own conventions exist to refuse. Missing either one is a hard stop, not a
# guess.
set -e

REPO="${EVE_BOT_REPO:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
LOGDIR="${EVE_BOT_LOGS:-$HOME/eve-bot-logs}"
N="$1"
MINUTES="${2:-360}"

[ -z "$N" ] && { echo "usage: EVE_HAUL_SOURCE=... EVE_HAUL_DEST=... run_haulerbot.sh <run number> [minutes]"; exit 1; }
[ -z "$EVE_HAUL_SOURCE" ] && { echo "EVE_HAUL_SOURCE is not set -- refusing to start rather than guess a source station."; exit 1; }
[ -z "$EVE_HAUL_DEST" ] && { echo "EVE_HAUL_DEST is not set -- refusing to start rather than guess a destination station."; exit 1; }
mkdir -p "$LOGDIR"

powershell -NoProfile -ExecutionPolicy Bypass \
    -File "$(cygpath -w "$REPO/tools/windows-host/stop_bots.ps1")" | tr -d '\r'

echo "--- working tree ---"
cd "$REPO"
git log --oneline -1
BOT="implement/applications/eve-online/eve-online-haulerbot/Bot.elm"
[ -f "$BOT" ] || { echo "  $BOT not found -- wrong tree, refusing to start"; exit 1; }
for f in hostDirectivePrefix holdTreeEntry dropRefusedDialogText; do
    c=$(grep -c "$f" "$BOT")
    printf "  %-24s %s\n" "$f" "$c"
    [ "$c" = "0" ] && { echo "  MISSING -- wrong tree, refusing to start"; exit 1; }
done

SETTINGS="source-station=$EVE_HAUL_SOURCE
destination-station=$EVE_HAUL_DEST"

# Optional extra, only added if the operator set it -- an unset env var
# here means "use the bot's own default", not "empty setting".
[ -n "$EVE_HAUL_INCLUDE_PATTERN" ] && SETTINGS="$SETTINGS
include-item-pattern=$EVE_HAUL_INCLUDE_PATTERN"

LOG="$LOGDIR/haulerbot_run${N}.log"
cd "$REPO/tools/macos-host/botlab_host"
nohup python -u botlab_host.py \
    "$(cygpath -w "$REPO/implement/applications/eve-online/eve-online-haulerbot")" \
    --settings "$SETTINGS" --execute-input \
    --session-duration-minutes "$MINUTES" --web-console \
    > "$LOG" 2>&1 &
echo "started run $N ($MINUTES min), '$EVE_HAUL_SOURCE' -> '$EVE_HAUL_DEST' -> $LOG"
