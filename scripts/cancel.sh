#!/usr/bin/env bash
#
# Cancel a scheduled email: POST /v1/emails/:id/cancel
#
#   MAILTEA_API_KEY=mt_pat_... ./scripts/cancel.sh txemail_abc123
#
# Only works while the send is still queued. Once scheduled_at has passed the
# message is gone and the API says so instead of pretending to cancel it.

set -euo pipefail

: "${MAILTEA_API_KEY:?Set MAILTEA_API_KEY — see .env.example}"

EMAIL_ID="${1:-}"
if [ -z "$EMAIL_ID" ]; then
  echo "Usage: $0 <email-id>    (e.g. txemail_abc123)" >&2
  exit 1
fi

BASE_URL="${MAILTEA_API_BASE_URL:-https://api.mailtea.app}"

response=$(curl --silent --show-error \
  --request POST "$BASE_URL/v1/emails/$EMAIL_ID/cancel" \
  --header "Authorization: Bearer $MAILTEA_API_KEY" \
  --write-out $'\n%{http_code}')

status="${response##*$'\n'}"
body="${response%$'\n'*}"

if [ "$status" -ge 400 ]; then
  echo "Cancel failed (HTTP $status): $body" >&2
  exit 1
fi

echo "Cancelled $EMAIL_ID" >&2
printf '%s\n' "$body"
