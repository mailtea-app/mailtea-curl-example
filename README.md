# Mailtea + curl Example

This example shows how to use [Mailtea](https://mailtea.app) with curl to send,
schedule, cancel, batch, and look up transactional email straight from the
shell — no SDK, no runtime, just HTTP.

## Prerequisites

To get the most out of this guide, you'll need to:

- [Create an API key](https://studio.mailtea.app/api-keys)
- [Verify your domain](https://docs.mailtea.app/docs/documentation/domains)

You also need `curl` and `bash`. Both ship with macOS and every mainstream Linux.

## Instructions

1. Install dependencies — there are none, but make the scripts executable if
   your checkout lost the bit:
   ```bash
   chmod +x run.sh test.sh scripts/*.sh
   ```
2. Copy `.env.example` to `.env` and add your API key:
   ```bash
   cp .env.example .env
   ```
3. Run it:
   ```bash
   ./run.sh
   ```

`run.sh` walks the whole happy path: send an email, look it up, schedule one,
cancel it, send a batch, then list what is on the account.

## The curl commands

Every script in `scripts/` is one of these with error handling and JSON escaping
wrapped around it. Set `MAILTEA_API_KEY` first; these are otherwise
copy-pasteable as-is.

### Send an email

```bash
curl -X POST https://api.mailtea.app/v1/emails \
  -H "Authorization: Bearer $MAILTEA_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "from": "Acme <hello@acme.com>",
    "to": "reader@yourdomain.com",
    "subject": "Hello from curl",
    "html": "<p>Sent with <strong>curl</strong> and the Mailtea API.</p>",
    "text": "Sent with curl and the Mailtea API.",
    "tags": [{ "name": "example", "value": "curl" }]
  }'
```

```json
{ "id": "txemail_ad6623a5f30e4639b95f7c1eb82a14e1" }
```

`to` takes a string or an array. `cc`, `bcc`, `reply_to`, `headers`, and
`attachments` are all optional — but SES caps a single message at **50
recipients combined** across `to` + `cc` + `bcc`.

### Schedule an email

Add `scheduled_at` as an RFC 3339 timestamp. Everything else is the same.

```bash
curl -X POST https://api.mailtea.app/v1/emails \
  -H "Authorization: Bearer $MAILTEA_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "from": "Acme <hello@acme.com>",
    "to": "reader@yourdomain.com",
    "subject": "Hello from curl (scheduled)",
    "html": "<p>This one was queued ahead of time.</p>",
    "scheduled_at": "2026-09-01T09:00:00Z"
  }'
```

### Look up an email

```bash
curl https://api.mailtea.app/v1/emails/txemail_ad6623a5f30e4639b95f7c1eb82a14e1 \
  -H "Authorization: Bearer $MAILTEA_API_KEY"
```

The response carries `last_event` — `queued`, `sent`, `delivered`, `bounced`,
`complained`, `canceled` — which is how you check on a send without waiting for
a webhook.

### Cancel a scheduled email

```bash
curl -X POST https://api.mailtea.app/v1/emails/txemail_f387756a748249c08e88a781e30de159/cancel \
  -H "Authorization: Bearer $MAILTEA_API_KEY"
```

Only works while the send is still queued.

### Send a batch

Up to 100 messages in one call. The body is a bare JSON array and every item
needs its own `from`. Batch takes no attachments and no `scheduled_at`.

```bash
curl -X POST https://api.mailtea.app/v1/emails/batch \
  -H "Authorization: Bearer $MAILTEA_API_KEY" \
  -H "Content-Type: application/json" \
  -d '[
    {
      "from": "Acme <hello@acme.com>",
      "to": "first@yourdomain.com",
      "subject": "Hello from curl (batch 1 of 2)",
      "html": "<p>First of the batch.</p>"
    },
    {
      "from": "Acme <hello@acme.com>",
      "to": "second@yourdomain.com",
      "subject": "Hello from curl (batch 2 of 2)",
      "html": "<p>Second of the batch.</p>"
    }
  ]'
```

Ids come back in the order you sent them:

```json
{ "data": [{ "id": "txemail_03d7276..." }, { "id": "txemail_91167b3..." }] }
```

### List recent emails

```bash
curl -G https://api.mailtea.app/v1/emails \
  -d limit=10 -d offset=0 \
  -H "Authorization: Bearer $MAILTEA_API_KEY"
```

Paginate with `offset`; `has_more` in the response tells you when to stop.

### Checking for errors

curl exits 0 on a 4xx, so a failed send looks like a successful one unless you
ask for the status code. The scripts here append it on its own line and check
it before trusting the body:

```bash
response=$(curl -sS -X POST "$BASE_URL/v1/emails" \
  -H "Authorization: Bearer $MAILTEA_API_KEY" \
  -H "Content-Type: application/json" \
  -d "$payload" \
  -w $'\n%{http_code}')

status="${response##*$'\n'}"
body="${response%$'\n'*}"

if [ "$status" -ge 400 ]; then
  echo "Send failed (HTTP $status): $body" >&2
  exit 1
fi
```

## Scripts

| Script | Endpoint |
|---|---|
| `scripts/send.sh` | `POST /v1/emails` |
| `scripts/send-scheduled.sh` | `POST /v1/emails` with `scheduled_at` |
| `scripts/get.sh <id>` | `GET /v1/emails/:id` |
| `scripts/cancel.sh <id>` | `POST /v1/emails/:id/cancel` |
| `scripts/batch.sh` | `POST /v1/emails/batch` |
| `scripts/list.sh [limit] [offset]` | `GET /v1/emails` |

Each prints the JSON response on stdout and progress on stderr, so you can pipe
one into the next:

```bash
id=$(./scripts/send.sh | jq -r .id)
./scripts/get.sh "$id" | jq .last_event
```

Set `MAILTEA_API_BASE_URL` to point them at a self-hosted Mailtea or a local
dev API; unset, they use `https://api.mailtea.app`.

## What this example covers

- Sending an email with `html`, `text`, and `tags`
- Scheduling a send with `scheduled_at`, then cancelling it
- Sending up to 100 messages in one batch call
- Looking up a send's `last_event` and listing recent emails
- Reading the HTTP status so a 4xx fails loudly instead of passing silently
- Escaping shell values into the JSON body, so a subject like `Your "receipt"`
  doesn't produce a request the API rejects as malformed
- Keeping the API key in the environment, never on the command line or in git

## Tests

```bash
./test.sh
```

The tests run against a bundled mock Mailtea server, so they need no API key
and make no network calls. `test.sh` runs every script in `scripts/` for real —
and then `run.sh`, which chains them — asserting each hit the right endpoint,
sent the bearer token, and carried the right body. Node is only used to run the
mock; the scripts under test are pure curl.

`run.sh` is tested from a copy with no `.env`, so a real key sitting in your
`.env` can never turn a test run into a real send.

## Learn more

- [Documentation](https://docs.mailtea.app)
- [API reference](https://docs.mailtea.app/docs/api-reference)
- [Node.js SDK](https://github.com/mailtea-app/mailtea-node) ·
  [Python SDK](https://github.com/mailtea-app/mailtea-python) ·
  [MCP server](https://github.com/mailtea-app/mailtea-mcp)
