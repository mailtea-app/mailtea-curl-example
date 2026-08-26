#!/usr/bin/env bash
#
# Runs every script in scripts/ — and then run.sh, which chains them — against
# the bundled mock Mailtea API, and checks that each one hit the right endpoint
# with the right body. No API key, no network, no test framework.
#
#   ./test.sh
#
# Needs node only for the mock server; the scripts under test are pure curl.

set -euo pipefail

cd "$(dirname "$0")"

tmp=$(mktemp -d)
mock_pid=""
cleanup() {
  if [ -n "$mock_pid" ]; then kill "$mock_pid" 2>/dev/null || true; fi
  rm -rf "$tmp"
}
trap cleanup EXIT

requests="$tmp/requests.tsv"

# ---------------------------------------------------------------- assertions

passed=0
failed=0

pass() { printf 'PASS  %s\n' "$1"; passed=$((passed + 1)); }
fail() { printf 'FAIL  %s\n' "$1"; printf '      %s\n' "$2"; failed=$((failed + 1)); }

eq() { # eq <label> <actual> <expected>
  if [ "$2" = "$3" ]; then pass "$1"; else fail "$1" "expected [$3], got [$2]"; fi
}

# `[` has no substring operator, so body checks go through `case`.
has() { # has <label> <haystack> <needle>
  case "$2" in
    *"$3"*) pass "$1" ;;
    *) fail "$1" "expected to find [$3] in [$2]" ;;
  esac
}

# --------------------------------------------------------------- mock server

# Sets MOCK_URL and mock_pid. A function rather than a one-off because the
# run.sh check below needs a second mock with its own recording.
start_mock() { # start_mock <requests-file> <url-file>
  node test/mock-server.mjs "$1" > "$2" &
  mock_pid=$!

  MOCK_URL=""
  for _ in $(seq 1 100); do
    if [ -s "$2" ]; then MOCK_URL=$(cat "$2"); break; fi
    sleep 0.05
  done
  [ -n "$MOCK_URL" ] || { echo "mock server never printed a URL" >&2; exit 1; }
}

# The mock only writes its recording on SIGTERM, so read nothing before this.
stop_mock() {
  kill -TERM "$mock_pid"
  wait "$mock_pid" 2>/dev/null || true
  mock_pid=""
}

start_mock "$requests" "$tmp/url"

MOCK_EMAIL_ID="txemail_00000000000000000000000000000000"

export MAILTEA_API_KEY="mt_pat_test_key_not_a_real_credential"
export MAILTEA_API_BASE_URL="$MOCK_URL"
export MAILTEA_FROM="Acme <hello@acme.com>"
export MAILTEA_TO="reader@mailtea.test"
export MAILTEA_SUBJECT="Hello from curl"

# ------------------------------------------------------- run the real scripts

send_out=$(./scripts/send.sh 2>&1) && send_rc=0 || send_rc=$?
scheduled_out=$(./scripts/send-scheduled.sh 2>&1) && scheduled_rc=0 || scheduled_rc=$?
get_out=$(./scripts/get.sh "$MOCK_EMAIL_ID" 2>&1) && get_rc=0 || get_rc=$?
cancel_out=$(./scripts/cancel.sh "$MOCK_EMAIL_ID" 2>&1) && cancel_rc=0 || cancel_rc=$?
batch_out=$(./scripts/batch.sh 2>&1) && batch_rc=0 || batch_rc=$?
list_out=$(./scripts/list.sh 5 2>&1) && list_rc=0 || list_rc=$?

# Values are pasted into JSON string literals, so anything quotable has to come
# out the far end as a body the API can actually parse.
awkward_out=$(MAILTEA_SUBJECT='Say "hi" \ bye' ./scripts/send.sh 2>&1) \
  && awkward_rc=0 || awkward_rc=$?

# A 404 from a wrong base URL must be a failure, not a silent success.
notfound_out=$(MAILTEA_API_BASE_URL="$MOCK_URL/nope" ./scripts/send.sh 2>&1) \
  && notfound_rc=0 || notfound_rc=$?

# Missing credentials must fail before any request goes out.
nokey_out=$(env -u MAILTEA_API_KEY ./scripts/send.sh 2>&1) && nokey_rc=0 || nokey_rc=$?

stop_mock

methods=(); paths=(); auths=(); bodies=()
while IFS=$'\t' read -r method path auth body; do
  methods+=("$method"); paths+=("$path"); auths+=("$auth"); bodies+=("$body")
done < "$requests"

expected_auth="Bearer $MAILTEA_API_KEY"

# -------------------------------------------------------------------- checks

echo "scripts/send.sh"
eq  "  exits 0" "$send_rc" "0"
eq  "  POSTs" "${methods[0]}" "POST"
eq  "  to /v1/emails" "${paths[0]}" "/v1/emails"
eq  "  with a bearer token" "${auths[0]}" "$expected_auth"
has "  body carries from" "${bodies[0]}" '"from":"Acme <hello@acme.com>"'
has "  body carries to" "${bodies[0]}" '"to":"reader@mailtea.test"'
has "  body carries subject" "${bodies[0]}" '"subject":"Hello from curl"'
has "  body carries html" "${bodies[0]}" '"html":"<p>Sent with <strong>curl</strong>'
has "  body carries tags" "${bodies[0]}" '"tags":[{"name":"example","value":"curl"}]'
has "  surfaces the returned id" "$send_out" "$MOCK_EMAIL_ID"

echo
echo "scripts/send-scheduled.sh"
eq  "  exits 0" "$scheduled_rc" "0"
eq  "  POSTs" "${methods[1]}" "POST"
eq  "  to /v1/emails" "${paths[1]}" "/v1/emails"
has "  body carries scheduled_at" "${bodies[1]}" '"scheduled_at":"20'
has "  subject marks it scheduled" "${bodies[1]}" '"subject":"Hello from curl (scheduled)"'
has "  surfaces the returned id" "$scheduled_out" "$MOCK_EMAIL_ID"

echo
echo "scripts/get.sh"
eq  "  exits 0" "$get_rc" "0"
eq  "  GETs" "${methods[2]}" "GET"
eq  "  to /v1/emails/:id" "${paths[2]}" "/v1/emails/$MOCK_EMAIL_ID"
eq  "  with a bearer token" "${auths[2]}" "$expected_auth"
has "  prints the delivery status" "$get_out" '"last_event":"delivered"'

echo
echo "scripts/cancel.sh"
eq  "  exits 0" "$cancel_rc" "0"
eq  "  POSTs" "${methods[3]}" "POST"
eq  "  to /v1/emails/:id/cancel" "${paths[3]}" "/v1/emails/$MOCK_EMAIL_ID/cancel"
eq  "  with a bearer token" "${auths[3]}" "$expected_auth"
has "  reports the cancelled id" "$cancel_out" "$MOCK_EMAIL_ID"

echo
echo "scripts/batch.sh"
eq  "  exits 0" "$batch_rc" "0"
eq  "  POSTs" "${methods[4]}" "POST"
eq  "  to /v1/emails/batch" "${paths[4]}" "/v1/emails/batch"
has "  body is a JSON array" "${bodies[4]}" '[{"from":"Acme <hello@acme.com>"'
has "  first item has its own from" "${bodies[4]}" '[{"from":"Acme <hello@acme.com>","to":"reader@mailtea.test","subject":"Hello from curl (batch 1 of 2)"'
has "  second item has its own from" "${bodies[4]}" '"from":"Acme <hello@acme.com>","to":"reader@mailtea.test","subject":"Hello from curl (batch 2 of 2)"'
has "  prints the returned ids" "$batch_out" '"id":"txemail_'

echo
echo "scripts/list.sh"
eq  "  exits 0" "$list_rc" "0"
eq  "  GETs" "${methods[5]}" "GET"
eq  "  to /v1/emails" "${paths[5]}" "/v1/emails"
has "  prints a list response" "$list_out" '"object":"list"'

echo
echo "JSON escaping"
# The mock parses each body and re-serializes it. A body it could not parse is
# recorded as a JSON *string*, so a leading brace is the proof it was valid.
eq  "  a quotable subject still exits 0" "$awkward_rc" "0"
has "  and produces a parseable body" "${bodies[6]}" '{"from":"Acme <hello@acme.com>"'
has "  with the quotes escaped, not dropped" "${bodies[6]}" '"subject":"Say \"hi\" \\ bye"'
has "  and still surfaces the returned id" "$awkward_out" "$MOCK_EMAIL_ID"

echo
echo "error handling"
eq  "  a 404 exits non-zero" "$notfound_rc" "1"
has "  and says so" "$notfound_out" "Send failed (HTTP 404)"
eq  "  a missing API key exits non-zero" "$nokey_rc" "1"
has "  and names the variable" "$nokey_out" "MAILTEA_API_KEY"
eq  "  and sends nothing" "${#methods[@]}" "8"

# ------------------------------------------------------------------- run.sh
# The README's headline command, and the only thing that exercises the scripts
# chained together. It runs from a copy with no .env, so a developer who keeps
# real credentials in examples/curl/.env cannot have this test send real mail.

run_dir="$tmp/run"
mkdir -p "$run_dir"
cp run.sh "$run_dir/"
cp -R scripts "$run_dir/scripts"

run_requests="$tmp/run-requests.tsv"
start_mock "$run_requests" "$tmp/run-url"
run_out=$(MAILTEA_API_BASE_URL="$MOCK_URL" "$run_dir/run.sh" 2>&1) && run_rc=0 || run_rc=$?
stop_mock

run_route=""
while IFS=$'\t' read -r method path _rest; do
  run_route="$run_route$method $path
"
done < "$run_requests"

echo
echo "run.sh"
eq  "  exits 0" "$run_rc" "0"
has "  sends" "$run_route" "POST /v1/emails
"
has "  looks the send up by the id it returned" "$run_route" "GET /v1/emails/$MOCK_EMAIL_ID
"
has "  cancels by the scheduled id" "$run_route" "POST /v1/emails/$MOCK_EMAIL_ID/cancel
"
has "  batches" "$run_route" "POST /v1/emails/batch
"
has "  lists" "$run_route" "GET /v1/emails
"
eq  "  and makes exactly six calls" "$(grep -c . "$run_requests")" "6"
has "  and finishes" "$run_out" "Done."

echo
echo "$passed passed, $failed failed"
[ "$failed" -eq 0 ]
