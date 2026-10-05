#!/usr/bin/env bash
#
# Send one email: POST /v1/emails
#
#   MAILTEA_API_KEY=mt_pat_... ./scripts/send.sh
#
# The JSON response goes to stdout so you can pipe it (`| jq .`); progress and
# errors go to stderr, so `id=$(./scripts/send.sh)` captures only the payload.

set -euo pipefail

: "${MAILTEA_API_KEY:?Set MAILTEA_API_KEY — see .env.example}"
: "${MAILTEA_FROM:?Set MAILTEA_FROM to a verified sending identity}"
: "${MAILTEA_TO:?Set MAILTEA_TO to a recipient address}"

# MAILTEA_API_BASE_URL is an optional override of the API host.
BASE_URL="${MAILTEA_API_BASE_URL:-https://api.mailtea.app}"
SUBJECT="${MAILTEA_SUBJECT:-Hello from curl}"

# Values land inside JSON string literals, so a subject like: Your "receipt"
# would close the string early and the API would reject the whole body as
# malformed. Backslash goes first — escaping the quote first would then double
# the backslash it just added.
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
  "subject": "$(json_escape "$SUBJECT")",
  "html": "<p>Sent with <strong>curl</strong> and the Mailtea API.</p>",
  "text": "Sent with curl and the Mailtea API.",
  "tags": [{ "name": "example", "value": "curl" }]
}
JSON
)

# -w appends the status code on its own line so the body stays intact; without
# it curl exits 0 on a 4xx and a failed send looks like a successful one.
response=$(curl --silent --show-error \
  --request POST "$BASE_URL/v1/emails" \
  --header "Authorization: Bearer $MAILTEA_API_KEY" \
  --header "Content-Type: application/json" \
  --data "$payload" \
  --write-out $'\n%{http_code}')

status="${response##*$'\n'}"
body="${response%$'\n'*}"

if [ "$status" -ge 400 ]; then
  echo "Send failed (HTTP $status): $body" >&2
  exit 1
fi

# Pulling the id out without jq keeps this script dependency-free. With jq:
#   ./scripts/send.sh | jq -r .id
id=$(printf '%s' "$body" | sed -n 's/.*"id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')

echo "Sent \"$SUBJECT\" to $MAILTEA_TO — id $id" >&2
printf '%s\n' "$body"
