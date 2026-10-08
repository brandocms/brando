# Notifications to Slack, Teams and email

Notifications are short messages to where people are when something happens in
a site environment: someone was mentioned in a note, scheduled publishing
published or unpublished an entry, or a background job failed. They go to a
Slack or Microsoft Teams channel, or by email to chosen users. People who are
rarely in the admin can get one email a day or a week instead.

They build on [content events](webhooks.md) (scheduled publishing), notes
(mentions), the mailer ([Email](email.md)) and Oban. The context is
`Brando.Notifications.Routing`.

## Set up

Run `mix brando.gen.migrations` and `mix brando.migrate` for `brando_217`,
which creates `notification_routes` and `notification_deliveries` in every
environment. Notifications use the `:notifications` queue (Slack, Teams and
email deliveries) and `:default` (emails, summaries, failed-job dispatch),
which Brando's default Oban configuration has. An application that sets
`config :brando, Oban` itself adds `notifications: [limit: 2]`. Email needs a mailer
(`mix brando.gen.mail`).

## Routes

An administrator adds routes under Configuration → Integrations →
Notifications, per site and environment. Each route has a name, a
destination, the events it sends and, optionally, content types.

| Destination | What to enter |
| --- | --- |
| Slack | An [incoming webhook](https://api.slack.com/messaging/webhooks) URL, `https://hooks.slack.com/services/…`. |
| Microsoft Teams | The URL of a Workflows flow, "Post to a channel when a webhook request is received", on `logic.azure.com` or `api.powerplatform.com`. |
| Email | The users to send to: members of the site. |

Slack and Teams URLs must be on those hosts (the `hosts` setting below), so
managing routes does not let anyone post to any address.

| Event | When |
| --- | --- |
| Mentions | Someone is mentioned in a note. The message names the author, the people mentioned and the entry, never the note's text nor the text it is anchored to. An email route leaves out the people mentioned: they get their own email. |
| Published on schedule | Scheduled publishing published an entry (`entry.published` from the scheduler). |
| Unpublished on schedule | Scheduled publishing unpublished an entry (`entry.unpublished` from the scheduler). |
| Failed jobs | Oban gave a job of this environment up, or a webhook was paused after its deliveries failed for a day. |

Content types limit the events about entries; failed jobs are always sent.
"Send test" posts a test message.

## Messages

Slack gets a `text` fallback and blocks; Teams a message with one Adaptive
Card (version 1.4). Both carry a title, a line of detail, the site and
environment, and a link to the entry in the admin, in the site's default admin
language. Slack's markup is escaped and Teams gets plain text runs
(`RichTextBlock`), so a title cannot make a link.
`Brando.Notifications.Message` builds them. A Slack or Teams message waits ten
seconds (`burst_seconds`) and takes along the others of the same
event on the route, so twelve entries published at nine make one message.

Email goes to each recipient in their own language, at most one every ten
minutes with everything since the last (sharing the mention emails' limit),
and only while the route is active and still names them, their account is
active, they may enter the site and, with group authorization, may read the
entry.

Each message is a delivery, sent by `Brando.Worker.NotificationDelivery` and
listed in the route's delivery log, as webhook deliveries are. A failed
attempt is retried with backoff, 10 attempts over about three hours. A Slack
or Teams route whose delivery failed every attempt is paused; resume it once
the URL works. The log keeps the webhook retention period
(`Brando.Webhooks.retention_days/0`, 30 days), removed by
`Brando.Worker.WebhookDeliveryPurger`.

## Email summaries

In their profile, under Config, a user chooses how notification and mention
email reaches them: as they come (at most one email every ten minutes), a
daily summary, or a weekly summary on Mondays. Summaries go out at 08:00 in `Brando.timezone/0`. An item waits
for the first summary after it arrived. Without a summary, mention emails keep
their batching (at most one every ten minutes). See
`Brando.Notifications.Digest`.

## Failed jobs

`Brando.Notifications.JobFailures` listens to Oban's telemetry. When a job is
discarded (it used every attempt, or returned `{:discard, reason}`), the
failed-job routes of the job's environment get its worker, queue, attempts and
the first line of its error, at most once per worker every ten minutes
(`failed_job_interval`, counted from the delivery log). A job
the worker cancelled is not a failure. Without tenancy every job counts; with
it, only jobs that belong to a site environment. Notification deliveries are
never notified themselves.

## Security

- A Slack or Teams webhook URL lets anyone post to the channel, so it is a
  secret. It is stored encrypted with `Brando.Crypto`, bound to the route, and
  never logged, written to Activity or sent back to the browser. The admin
  shows its host and last four characters; "Replace URL" starts from an empty
  field.
- Only `https` URLs on public addresses are called, checked when saved and
  before every delivery (`Brando.Webhooks.URLGuard`), with a 10-second timeout
  and no redirects.
- Managing routes needs the Notifications permission
  (`brando.notifications.manage`) with group authorization, or the admin or
  superuser role without it. Saving, pausing, deleting and sending a test ask
  for the password again when the session has not confirmed lately.
- Copying an environment, or restoring an archive as a new one, pauses the
  copy's routes, so staging does not post to production channels. They resume
  when that environment goes live.

## Configuration

```elixir
config :brando, Brando.Notifications,
  enabled: true,
  # notify failed-job routes when Oban discards a job
  failed_jobs: true,
  # at most one failed-job notification per worker in this many seconds
  failed_job_interval: 600,
  # how long a Slack or Teams message waits for others like it
  burst_seconds: 10,
  # the hosts (and subdomains) Slack and Teams routes may post to
  hosts: [slack: ["hooks.slack.com"], teams: ["logic.azure.com", "api.powerplatform.com", "webhook.office.com"]],
  # when summaries go out, in Brando.timezone()
  digest_hour: 8
```
