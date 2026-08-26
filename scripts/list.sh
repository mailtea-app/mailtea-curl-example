#!/usr/bin/env bash
#
# List recent emails: GET /v1/emails
#
#   MAILTEA_API_KEY=mt_pat_... ./scripts/list.sh [limit] [offset]
#
# Paginate with offset; the response's has_more tells you when to stop.

set -euo pipefail

: "${MAILTEA_API_KEY:?Set MAILTEA_API_KEY — see .env.example}"

BASE_URL="${MAILTEA_API_BASE_URL:-https://api.mailtea.app}"
LIMIT="${1:-10}"
OFFSET="${2:-0}"

response=$(curl --silent --show-error --get \
  "$BASE_URL/v1/emails" \
  --data-urlencode "limit=$LIMIT" \
  --data-urlencode "offset=$OFFSET" \
  --header "Authorization: Bearer $MAILTEA_API_KEY" \
  --write-out $'\n%{http_code}')

status="${response##*$'\n'}"
body="${response%$'\n'*}"

if [ "$status" -ge 400 ]; then
  echo "List failed (HTTP $status): $body" >&2
  exit 1
fi

printf '%s\n' "$body"
