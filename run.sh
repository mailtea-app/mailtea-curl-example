#!/usr/bin/env bash
#
# The happy path, end to end: send, look the send up, schedule one, cancel it,
# send a batch, then list what is on the account.
#
#   cp .env.example .env && $EDITOR .env
#   ./run.sh

set -euo pipefail

cd "$(dirname "$0")"

# .env is plain shell, so sourcing it is enough — no dotenv library needed.
if [ -f .env ]; then
  set -a
  # shellcheck disable=SC1091
  . ./.env
  set +a
fi

: "${MAILTEA_API_KEY:?Set MAILTEA_API_KEY — copy .env.example to .env first}"

# Each script prints its JSON response on stdout, so the next step can read it.
email_id() {
  sed -n 's/.*"id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p'
}

echo "== Send =="
sent_id=$(./scripts/send.sh | email_id)

echo
echo "== Look it up =="
./scripts/get.sh "$sent_id"

echo
echo "== Schedule one for later =="
scheduled_id=$(./scripts/send-scheduled.sh | email_id)

echo
echo "== Cancel the scheduled one =="
./scripts/cancel.sh "$scheduled_id" > /dev/null

echo
echo "== Send a batch =="
./scripts/batch.sh

echo
echo "== List recent emails =="
./scripts/list.sh 5

echo
echo "Done."
