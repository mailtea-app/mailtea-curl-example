#!/usr/bin/env bash
#
# Look up one email: GET /v1/emails/:id
#
#   MAILTEA_API_KEY=mt_pat_... ./scripts/get.sh txemail_abc123
#
# The response carries last_event ("delivered", "bounced", "complained", ...),
# which is how you check what happened to a send without waiting on a webhook.

set -euo pipefail

: "${MAILTEA_API_KEY:?Set MAILTEA_API_KEY — see .env.example}"

EMAIL_ID="${1:-}"
if [ -z "$EMAIL_ID" ]; then
  echo "Usage: $0 <email-id>    (e.g. txemail_abc123)" >&2
  exit 1
fi

BASE_URL="${MAILTEA_API_BASE_URL:-https://api.mailtea.app}"

response=$(curl --silent --show-error \
  --request GET "$BASE_URL/v1/emails/$EMAIL_ID" \
  --header "Authorization: Bearer $MAILTEA_API_KEY" \
  --write-out $'\n%{http_code}')

status="${response##*$'\n'}"
body="${response%$'\n'*}"

if [ "$status" -ge 400 ]; then
  echo "Lookup failed (HTTP $status): $body" >&2
  exit 1
fi

printf '%s\n' "$body"
