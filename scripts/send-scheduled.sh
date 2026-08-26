#!/usr/bin/env bash
#
# Schedule an email for later: POST /v1/emails with scheduled_at.
#
#   MAILTEA_API_KEY=mt_pat_... ./scripts/send-scheduled.sh [rfc3339-timestamp]
#
# Mailtea holds the message until scheduled_at, so the id it returns can still
# be rescheduled (PATCH /v1/emails/:id) or cancelled (POST /v1/emails/:id/cancel
# — see cancel.sh) until then. There is no DELETE on this resource.

set -euo pipefail

: "${MAILTEA_API_KEY:?Set MAILTEA_API_KEY — see .env.example}"
: "${MAILTEA_FROM:?Set MAILTEA_FROM to a verified sending identity}"
: "${MAILTEA_TO:?Set MAILTEA_TO to a recipient address}"

BASE_URL="${MAILTEA_API_BASE_URL:-https://api.mailtea.app}"
SUBJECT="${MAILTEA_SUBJECT:-Hello from curl}"

# Default to an hour out. BSD date (macOS) and GNU date (Linux) disagree on the
# flag, so try both rather than depend on which one is installed.
default_at=$(date -u -v+1H '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null \
  || date -u -d '+1 hour' '+%Y-%m-%dT%H:%M:%SZ')
SCHEDULED_AT="${1:-${MAILTEA_SCHEDULED_AT:-$default_at}}"

# See send.sh — values land inside JSON string literals and have to be escaped.
json_escape() {
  local value="$1"
  value="${value//\\/\\\\}"
  value="${value//\"/\\\"}"
  printf '%s' "$value"
}

payload=$(cat <<JSON
{
  "from": "$(json_escape "$MAILTEA_FROM")",
  "to": "$(json_escape "$MAILTEA_TO")",
  "subject": "$(json_escape "$SUBJECT") (scheduled)",
  "html": "<p>This one was queued ahead of time.</p>",
  "scheduled_at": "$(json_escape "$SCHEDULED_AT")"
}
JSON
)

response=$(curl --silent --show-error \
  --request POST "$BASE_URL/v1/emails" \
  --header "Authorization: Bearer $MAILTEA_API_KEY" \
  --header "Content-Type: application/json" \
  --data "$payload" \
  --write-out $'\n%{http_code}')

status="${response##*$'\n'}"
body="${response%$'\n'*}"

if [ "$status" -ge 400 ]; then
  echo "Schedule failed (HTTP $status): $body" >&2
  exit 1
fi

id=$(printf '%s' "$body" | sed -n 's/.*"id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')

echo "Scheduled for $SCHEDULED_AT — id $id" >&2
printf '%s\n' "$body"
