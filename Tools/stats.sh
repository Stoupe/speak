#!/bin/zsh
# Prints a summary of Speak's anonymous usage stats (README → Usage stats) from the D1 database behind
# speak-telemetry.stoupe.dev. Read-only. Needs the cf CLI signed in to the Cloudflare account (cf auth login).
#
#   Tools/stats.sh          # last 30 days
#   Tools/stats.sh 90       # last 90 days
set -euo pipefail
cd "$(dirname "$0")/../server/telemetry"

DATABASE="8113e4ab-d7f9-4164-b537-239207213d89"  # speak-telemetry, also in cloudflare.config.ts
DAYS=${1:-30}
[[ "$DAYS" == <-> ]] || { echo "usage: Tools/stats.sh [days]" >&2; exit 2; }
SINCE="day >= date('now', '-$DAYS days')"

# Runs one query and prints its rows as an aligned table.
table() {
    print -P "\n%B$1%b"
    cf d1 query "$DATABASE" --sql "$2" 2>/dev/null \
        | jq -r '.[0].results | if length == 0 then "  (no reports)" else
            ((.[0] | keys_unsorted) as $k | ($k | join("\t")), (.[] | [.[$k[]]] | map(tostring) | join("\t"))) end' \
        | column -t -s $'\t' | sed 's/^/  /'
}

table "Per day: Macs reporting (each Mac sends at most one report a day), dictations, words" \
    "SELECT day, count(*) AS macs, sum(dictations) AS dictations, sum(words) AS words,
            sum(hands_free) AS hands_free, sum(empty) AS empty, sum(cancelled) AS cancelled
     FROM reports WHERE $SINCE GROUP BY day ORDER BY day DESC"

table "Totals over the last $DAYS days" \
    "SELECT count(*) AS reports, sum(dictations) AS dictations, sum(words) AS words,
            round(1.0 * sum(words) / max(sum(dictations), 1), 1) AS words_per_dictation,
            round(100.0 * sum(hands_free) / max(sum(dictations), 1), 1) AS hands_free_pct,
            round(100.0 * sum(empty) / max(sum(dictations) + sum(empty) + sum(cancelled), 1), 1) AS empty_pct,
            round(100.0 * sum(cancelled) / max(sum(dictations) + sum(empty) + sum(cancelled), 1), 1) AS cancelled_pct
     FROM reports WHERE $SINCE"

table "Versions" \
    "SELECT app, build, count(*) AS reports FROM reports WHERE $SINCE GROUP BY app, build ORDER BY build DESC"

table "Setup (share of reports)" \
    "SELECT round(100.0 * avg(polish), 1) AS polish_on_pct, round(100.0 * avg(intelligence), 1) AS intelligence_pct,
            round(100.0 * avg(trigger = 'fn'), 1) AS fn_pct, round(100.0 * avg(trigger = 'rightOption'), 1) AS right_option_pct,
            round(100.0 * avg(trigger = 'rightCommand'), 1) AS right_command_pct
     FROM reports WHERE $SINCE"

table "Macs" \
    "SELECT os, chip, count(*) AS reports FROM reports WHERE $SINCE GROUP BY os, chip ORDER BY reports DESC LIMIT 15"

table "Languages" \
    "SELECT locale, count(*) AS reports FROM reports WHERE $SINCE GROUP BY locale ORDER BY reports DESC LIMIT 15"
