# Scheduled publishing

Choose what should be published before choosing a time:

| Operation | What runs at the scheduled time | Use it for |
| --- | --- | --- |
| Entry `publish_at` | Publish the entry's then-current saved content | An article that editors can keep refining until release |
| Scheduled revision | Restore a specific inactive snapshot and force published status | An approved campaign version that must not drift with later edits |

The schema needs `trait :scheduled_publishing` and `trait :status`; revision
scheduling also needs `trait :revisioned`. Pages and fragments already have them.
Public migrations must include Oban and revision storage, and the `default`
Oban queue must be running. A stored date by itself does not execute work.

## Schedule the current entry

Open a saved page, choose **Scheduled publishing**, and select a future date and
time. Set the intended status to published and save. Brando converts a future
published/pending entry to **pending**, then queues its publication. Visit
**Configuration → Scheduled Publishing** to check the actual job and its time.

The context equivalent uses a timezone-aware timestamp:

```elixir
publish_at = DateTime.add(DateTime.utc_now(), 3_600, :second)

{:ok, page} = Brando.Pages.update_page(page, %{
  status: :published,
  publish_at: publish_at
}, current_user)

:pending = page.status
{:ok, jobs} = Brando.Publisher.list_jobs()
```

The job stores the schema and entry ID, not a snapshot. Later saved edits to that
entry are what it will publish. An ordinary unsaved browser edit is not included.
The worker runs a context update, so publication validation and permission checks
still apply at execution time.

Setting a future date while leaving status as draft or disabled does **not** make
that date inert: the scheduling callback is driven by a changed future
`publish_at`. Use the explicit published-to-pending flow above, and inspect the
queue whenever an entry has a publication date.

## Cancel an entry schedule

Use **Delete job** on the Scheduled Publishing screen, or cancel the matching
job in the current authorization and tenant context:

```elixir
{1, _} = Brando.Publisher.delete_job(job.id)
```

Then save the entry with its intended remaining status and date. For example,
set `status: :draft, publish_at: nil` to keep it private. Clearing `publish_at`
alone does not remove an already queued job. Also, clearing the date on a pending
entry changes its status to published unless you explicitly choose another
status. Cancellation and the content edit are separate operations.

Changing a future date replaces jobs matching that entry, actor, and target
status. Do not assume it removes schedules created by a different actor; verify
the queue and cancel superseded jobs. Cancelling a job that has already executed
cannot undo its publication.

## Schedule an approved revision

In **Revisions**, store the editor state as an inactive revision, describe it,
and use its schedule action. Only inactive revisions can be scheduled.
For application tooling:

```elixir
alias Brando.Pages.Page
alias Brando.Revisions

{:ok, revision} = Revisions.create_revision(page, current_user, false)
release_at = DateTime.add(DateTime.utc_now(), 7_200, :second)

{:ok, job} = Brando.Publisher.schedule_revision(
  Page, page.id, revision.revision, release_at, current_user
)
```

The revision number is local to the entry; `revision.id` is not the argument to
use. The API accepts a `DateTime` or an ISO-8601 string with an offset. It rejects
past dates, invalid timestamps, missing revisions, and an already active revision.
The caller needs both **schedule** and **publish** permission for the record.

At execution, Brando restores the snapshot transactionally, forces published
status and the current publication timestamp, makes the revision active, and
updates identifiers, caches, and rendered content. Later edits to the live entry
do not change the scheduled snapshot.

To cancel before execution, use **Cancel schedule** in the revision row:

```elixir
:ok = Brando.Publisher.cancel_scheduled_revision(Page, page.id, revision.revision)
```

This API uses the current authorization scope. In application code, establish it
through the `Boundary.run` wrapper, as in the authorization guide;
the authenticated admin already has it. Cancellation keeps the snapshot and
clears its scheduled flag, making normal retention rules apply again. Activating
that revision manually also cancels its pending job.

## Time zones and environments

Use `config :brando, timezone: "Europe/Oslo"` for the site's display convention.
Browser date inputs are converted to timestamp values; verify the displayed
zone and resulting instant before scheduling. API timestamps should include an
offset, for example `2026-10-15T09:00:00+02:00`. For local wall-clock times in
application code, explicitly resolve daylight-saving ambiguous or nonexistent
times before converting to UTC.

A named content environment is independent of `MIX_ENV`. A job queued while
editing Staging must continue to affect Staging even if Production later becomes
live. Brando captures `tenant_prefix` in the job arguments and restores it in
the worker. An enabled-tenancy job without a valid prefix is cancelled, rather
than falling back to `public`. For tooling, select a real registered environment
and run scheduling inside `Brando.Tenant.with_prefix/2`; do not invent a prefix
from untrusted request input. See [Sites and environments](tenancy_and_environments.md).

## Observe execution and failure

The publisher worker allows 10 attempts and a 60-second timeout per attempt.
Oban retries failures; an accepted schedule is not a guarantee that the content
will publish successfully. A failed revision restore preserves the current
entry, and a final failed attempt releases its scheduled retention flag.
Check the job's error and the content's current validation/authorization before
retrying. The actor is loaded again at execution, so changed access can matter.

In a development environment, schedule a minute ahead, save another edit, and
verify which version appears after execution. Repeat with a frozen revision,
then cancel a third schedule and wait past its former time. Check the actual
public route, entry status, revision active marker, and rendered blocks. Also
try publishing an incomplete draft: errors should remain visible and the entry
must stay out of public `status: :published` queries.

If jobs never run, first check that the worker process and `default` queue are
running in the intended application/database. An application-level
`config :brando, Oban` replaces Brando's defaults, including its queues and cron
jobs; it does not merge individual options.
