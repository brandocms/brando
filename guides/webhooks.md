# Webhooks and content events

Brando tells other systems when content changes: a static site build, a CDN,
a search index, a chat channel. Two layers do this.

- **Content events** (`Brando.ContentEvents`) turn every change that
  `Brando.Activity` records for an entry into one normalised event, and hand it
  to subscribers inside an Oban job, after the save has committed.
- **Webhooks** (`Brando.Webhooks`) are one such subscriber: signed HTTP POSTs
  to URLs an administrator sets up under Configuration → Integrations →
  Webhooks.

<!-- usage-rules:start topic="content-events" -->

## Events

| Event | When |
| --- | --- |
| `entry.created` | An entry was created, duplicated or imported as new. |
| `entry.updated` | An entry was saved with changes, a revision was restored, or an import changed it. |
| `entry.published` | An entry became published: from its form, a listing, scheduled publishing, or created as published (after `entry.created`). |
| `entry.unpublished` | A published entry got another status. |
| `entry.deleted` | An entry was moved to the trash or deleted. Emptying the trash later sends nothing more. |
| `entry.restored` | An entry came back from the trash. |

<!-- usage-rules:end -->

Several saves of the same entry within five seconds become one
`entry.updated` with every changed field. A publish in that window takes the
pending update's fields, so a save followed by a publish is one
`entry.published`.

```elixir
config :brando, Brando.ContentEvents, debounce_seconds: 5
```

<!-- usage-rules:start topic="content-events" -->

Schemas that Activity does not log (its `ignore` list, media, Brando's
internal records) send no events, and neither do changes to users.

## Subscribing in code

Brando's webhooks, [IndexNow](identity_and_seo.md#indexnow)
(`Brando.IndexNow`) and the admin search index (`Brando.Search`) are
subscribers. A search index of your own or another integration
subscribes with a module:

```elixir
config :brando, Brando.ContentEvents, subscribers: [MyApp.CdnPurge]

defmodule MyApp.CdnPurge do
  @behaviour Brando.ContentEvents.Subscriber

  @impl true
  def handle_event(%{type: "entry.published", url: url} = event) when is_binary(url) do
    %{url: url, event_id: event.id}
    |> Brando.Tenant.Job.attach()
    # One job per event: a retried dispatch finds it and adds none
    |> MyApp.Workers.PurgeUrl.new(unique: [keys: [:event_id], period: :infinity])
    |> Oban.insert()
  end

  def handle_event(_event), do: :ok
end
```

`handle_event/1` runs in the event's site and environment. Keep it short and
queue a job of your own for anything slow. Return `{:error, reason}` (or
raise) when the event could not be handled: the dispatcher job then runs
again, up to three times, and every subscriber gets the event again.
Subscribers must therefore be idempotent. Each event has an `id` that stays
the same across these retries; ignore an `id` you have already handled.
Brando's webhooks do this with a unique index, so a retry never queues a
delivery twice.

The dispatcher runs on the `:content_events` queue, deliveries on
`:webhooks`, and updates to the admin search index on `:search_index`.
Brando's default Oban configuration has all three. **An application that
sets `config :brando, Oban` itself must declare them, or no events, webhook
deliveries or search updates ever run**: the jobs are queued and wait
forever. `mix brando.doctor` (and the system check under Configuration →
Utilities) warns when they are missing.

<!-- usage-rules:no-compile -->
```elixir
config :brando, Oban,
  queues: [default: [limit: 1], content_events: [limit: 1], webhooks: [limit: 5], search_index: [limit: 2], ...],
  # also schedule the delivery log's cleanup
  cron: [crontab: [{"35 5 * * *", Brando.Worker.WebhookDeliveryPurger}, ...]]
```

### The admin search index

- `Brando.Search` indexes every Blueprint with a persisted `identifier` (one
  that declares an `identifier` and not `persist_identifier false`). There is
  nothing to configure per Blueprint.
- A document holds the entry's title, its slug or URI, its meta description,
  and the plain text of its text fields and of every block.
- `config :brando, Brando.Search, enabled: false` stops updates; the index is
  left as it is.
- Rebuild the index (Configuration → Utilities, or
  `Brando.Search.queue_rebuild/1`) once after upgrading, and after changing
  what an identifier or text field holds.

<!-- usage-rules:end -->

## Setting up a webhook

Configuration → Integrations → Webhooks lists the current environment's
webhooks. A webhook has a name, an `https` URL, the events it gets (all, or
some), and optionally the content types and languages it is limited to. When
it is created, its signing secret is shown once. Only people with the
Webhooks permission (`brando.webhooks.manage`) can see these screens; without
group authorization, admins and superusers.

Give that permission with care. A webhook is sent the type, id, URL, status
and changed field names of every entry, drafts included, of every content
type, whatever the manager may read, and it sends them to a URL the manager
chooses. The screens themselves show entry titles and links only for content
types the manager may read, and others by type and id.

A saved webhook's URL is shown as its scheme and host only, since a build
hook's URL often carries a key in its path. "Replace URL" sets a new one. Saving, deleting, pausing,
rotating the secret, redelivering and sending a test event ask for the
password again when the session has not confirmed it in the last ten minutes.

### Webhooks and environments

Webhooks belong to one environment, and they follow it through the release
flow:

- When you copy an environment (Production → Staging, say), the copy gets the
  source's webhooks, paused, and an empty delivery log. Staging therefore
  never calls the endpoints production calls.
- When an archive is restored as a new environment (a rollback), its
  webhooks are paused the same way.
- When an environment goes live, by hand or as scheduled, the webhooks that
  were paused because it was a copy start sending again. Webhooks paused by
  hand, or after their deliveries kept failing, stay paused.
- The environment that was live before keeps its webhooks as they were.
- Each pause and resume is recorded in Activity.

You can resume a copy's webhook before it goes live, if that environment
should call the URL. Every request carries the `environment` it came from,
so a receiver can also filter by it.

## The request

```http
POST /brando-webhook HTTP/1.1
Content-Type: application/json
User-Agent: Brando-Webhooks
Brando-Event: entry.published
Brando-Delivery: 2b0e8d4c-6a1f-4f5e-9d61-0c3f6f0f1b7a
Brando-Signature: t=1791456000,v1=5257a869e7ecebeda32affa62cdca3fa51cad7e77a0e56ff536d0ce8e108d8bd

{
  "delivery_id": "2b0e8d4c-6a1f-4f5e-9d61-0c3f6f0f1b7a",
  "event": "entry.published",
  "event_id": "c0a4c3f2-1d8e-4a3b-a2d6-7a9a0e7c5b11",
  "occurred_at": "2026-10-08T10:58:12.401Z",
  "site": "shop",
  "environment": "production",
  "entry": {
    "type": "projects.project",
    "id": 42,
    "language": "en",
    "url": "https://example.com/projects/the-house",
    "status": "published",
    "changed_fields": ["status", "title"]
  },
  "actor": {"kind": "person"}
}
```

- `delivery_id` is new for every delivery, including a redelivery;
  `event_id` stays the same, so a receiver can ignore repeats.
- `actor.kind` is `person`, `assistant`, `mcp`, `scheduler` or `system`.
  Who the person was is not sent.
- No entry content is sent. Fetch it through the site's API if you need it.
- `environment` is `null` on an installation without tenancy.
- "Send test event" posts `"event": "webhook.test"` with `"entry": null`.

## Verifying the signature

`v1` is the lowercase hex HMAC-SHA256, keyed with the secret (the whole
`whsec_…` string), of the timestamp `t`, a full stop and the raw request
body. Check it over the exact bytes you received, before parsing the JSON,
compare in constant time, and refuse a timestamp more than five minutes from
your clock so that a captured request cannot be replayed.

Node.js (Express):

```js
import crypto from 'node:crypto'
import express from 'express'

const app = express()

app.post('/brando-webhook', express.raw({ type: 'application/json' }), (req, res) => {
  const header = req.get('Brando-Signature') || ''
  const parts = Object.fromEntries(header.split(',').map((part) => part.split('=')))
  const timestamp = Number(parts.t)
  const expected = crypto
    .createHmac('sha256', process.env.BRANDO_WEBHOOK_SECRET)
    .update(`${parts.t}.${req.body}`)
    .digest('hex')

  const fresh = Math.abs(Date.now() / 1000 - timestamp) <= 300
  const valid =
    parts.v1 && parts.v1.length === expected.length &&
    crypto.timingSafeEqual(Buffer.from(parts.v1), Buffer.from(expected))

  if (!fresh || !valid) return res.sendStatus(400)

  const event = JSON.parse(req.body)
  // ...
  res.sendStatus(204)
})
```

Elixir (Plug), with the raw body kept by a `Plug.Parsers` `:body_reader`:

```elixir
:ok = Brando.Webhooks.Signature.verify(signature_header, raw_body, secret, tolerance: 300)
```

`Brando.Webhooks.Signature.verify/4` returns `{:error, :signature_mismatch}`,
`{:error, :timestamp_out_of_tolerance}` or `{:error, :invalid_header}`
otherwise. Without Brando, recompute
`Base.encode16(:crypto.mac(:hmac, :sha256, secret, "#{t}.#{body}"), case: :lower)`
and compare it with `Plug.Crypto.secure_compare/2`.

Answer with a 2xx status within ten seconds. Do the slow work after
answering.

### Rotating the secret

Rotating gives the webhook a new secret and invalidates the old one at once;
there is no overlap. Pause the webhook, rotate, put the new secret in the
receiver, and resume it. Events while it is paused are not sent later;
redeliver them from the log if you need them.

## Delivery

- Every delivery is an Oban job. A response other than 2xx, a timeout or a
  refused connection is retried with exponential backoff: 30 seconds,
  doubling to four hours between attempts, 15 attempts over about 24 hours.
- Redirects are not followed; a 3xx counts as a failure.
- When the last attempt fails, the webhook is paused and the dashboard warns
  the people who manage webhooks. Resume it once the receiver works again.
- At most two deliveries to one webhook run at a time (`concurrency`), and at
  most three to all the webhooks of one site environment
  (`site_concurrency`), so a slow receiver cannot hold the queue that every
  site shares. A delivery waiting for a slot does not use up an attempt.
- A delivery that arrived is never sent again by its job, even if writing
  its result to the log fails: the log then says the answer could not be
  saved.
- The first 4 KB of each response are kept in the delivery log, with the
  status code and how long it took. The log keeps 30 days (`retention_days`).

## Which URLs can be called

Only `https`, without a user name or password in the URL, on a host whose
every address is public. Private, loopback, link-local, CGNAT, multicast and
reserved IPv4 ranges, `0.0.0.0`, IPv6 loopback, link-local, unique local and
multicast, Teredo and local-use NAT64, and IPv4 addresses inside IPv6 that
fall in those ranges are refused (see `Brando.Webhooks.URLGuard`). The check runs
when the webhook is saved and again before every delivery, and the delivery
connects to the address that was checked, with the host name kept for TLS,
so a host that later resolves to an internal address is not called.

<!-- usage-rules:start topic="content-events" -->

For a receiver on your own machine in development:

```elixir
# config/dev.exs only
config :brando, Brando.Webhooks, allow_localhost: true
```

This allows loopback addresses, and `http` to them only; other hosts still
need `https`. Never set it in production.

<!-- usage-rules:end -->

## Configuration

```elixir
config :brando, Brando.ContentEvents,
  enabled: true,
  debounce_seconds: 5,
  subscribers: []

config :brando, Brando.Webhooks,
  enabled: true,
  retention_days: 30,
  concurrency: 2,
  site_concurrency: 3,
  allow_localhost: false
```

The upgrade migration `brando_209` creates the `webhooks` and
`webhook_deliveries` tables in every environment.
