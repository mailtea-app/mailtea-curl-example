#!/usr/bin/env bash
#
# Send up to 100 different emails in one call: POST /v1/emails/batch
#
#   MAILTEA_API_KEY=mt_pat_... ./scripts/batch.sh
#
# The body is a bare JSON array — one object per message, each with its own
# "from". Batch does not accept attachments or scheduled_at; use /v1/emails for
# those. Ids come back in the same order you sent them.

set -euo pipefail

: "${MAILTEA_API_KEY:?Set MAILTEA_API_KEY — see .env.example}"
: "${MAILTEA_FROM:?Set MAILTEA_FROM to a verified sending identity}"
: "${MAILTEA_TO:?Set MAILTEA_TO to a recipient address}"

BASE_URL="${MAILTEA_API_BASE_URL:-https://api.mailtea.app}"
SUBJECT="${MAILTEA_SUBJECT:-Hello from curl}"

# See send.sh — values land inside JSON string literals and have to be escaped.
json_escape() {
  local value="$1"
  value="${value//\\/\\\\}"
  value="${value//\"/\\\"}"
  printf '%s' "$value"
}

FROM_JSON=$(json_escape "$MAILTEA_FROM")
TO_JSON=$(json_escape "$MAILTEA_TO")
SUBJECT_JSON=$(json_escape "$SUBJECT")

payload=$(cat <<JSON
[
  {
    "from": "$FROM_JSON",
    "to": "$TO_JSON",
    "subject": "$SUBJECT_JSON (batch 1 of 2)",
    "html": "<p>First of the batch.</p>"
  },
  {
    "from": "$FROM_JSON",
    "to": "$TO_JSON",
    "subject": "$SUBJECT_JSON (batch 2 of 2)",
    "html": "<p>Second of the batch.</p>"
  }
]
JSON
)

response=$(curl --silent --show-error \
  --request POST "$BASE_URL/v1/emails/batch" \
  --header "Authorization: Bearer $MAILTEA_API_KEY" \
  --header "Content-Type: application/json" \
  --data "$payload" \
  --write-out $'\n%{http_code}')

status="${response##*$'\n'}"
body="${response%$'\n'*}"

if [ "$status" -ge 400 ]; then
  echo "Batch failed (HTTP $status): $body" >&2
  exit 1
fi

printf '%s\n' "$body"
