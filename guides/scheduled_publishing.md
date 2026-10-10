# Scheduled publishing

<!-- llms-description: Publish an entry or an approved revision at a set time, let an entry expire, see and move what is planned in the calendar, cancel a schedule, and follow the jobs that run it. -->

Choose what should be published before choosing a time:

| Operation | What runs at the scheduled time | Use it for |
| --- | --- | --- |
| Entry `publish_at` | Publish the entry's then-current saved content | An article that editors can keep refining until release |
| Scheduled revision | Restore a specific inactive snapshot and force published status | An approved campaign version that must not drift with later edits |
| Entry `unpublish_at` | Deactivate the entry | A campaign, job post or event that has to end on time |

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
The worker runs a context update as the user who scheduled it, so publication
validation and permission checks still apply at execution time.

With group authorization, when that user may no longer make the change (their
groups lost the right to update, publish or schedule the entry, or a record
policy denies it), or their account has been deactivated or deleted, the
publication is not retried. The
job is cancelled, and the date is cleared as **Delete job** clears it:
`publish_at` is removed and the pending entry goes back to draft, saved by the
system. The entry's Activity says that it was not published as scheduled, and
why. Someone who may publish it can schedule it again. An expiry refused the
same way is still carried out on time, by the system, so that a refusal never
leaves an entry live for longer than planned; Activity says so, and why. While
the site is suspended the job waits, checking every ten minutes without
spending its attempts, for as long as the sweep would still take the date
(`sweep_days`); after that, or when the site is archived, the job ends and
leaves the entry as it is. A refusal for any other reason is retried, and on the
last attempt taken back as above, so the sweep never publishes it as the
system. A save that fails for another reason, such as validation, is retried
as before. Without group authorization nothing is refused: schedules run as
the user who made them, deactivated or not, and as the system when the account
no longer exists.

The job publishes only an entry that is still pending when it runs: a future
date on a draft or a deactivated entry queues a job that does nothing, and the
Scheduled publishing drawer says so. Use the published-to-pending flow above.

## See it in the calendar

**Calendar** in the sidebar, after Dashboard and Search, shows what is planned
by day, a month or a week at a time: entries to be published (`publish_at` on a
pending entry), scheduled revisions and expiries (`unpublish_at`), in the site's
time zone (`config :brando, timezone:`). It covers every content type with
`trait :scheduled_publishing` and an admin, with a filter for one type, and only
the entries the user may read; the title links to the entry when they may edit
it. The view, the date and the type are in the URL.

An item can be moved to another day, at the same time of day, by dragging it
or with its **Move to…** button, which opens a dialog with the day and is the
way to do it from the keyboard or a phone. Both ask before moving. An item that
changed since the calendar was loaded (published by hand, its expiry cleared,
its revision cancelled or moved) is not moved: the calendar says so and shows
what is planned now. A move
saves the date through the entry's context, as saving it in the form does, or
reschedules the revision through `Brando.Publisher.schedule_revision/5`, so the
same validation, permissions and jobs apply: moving publishing takes the
**schedule** permission, moving an expiry or a revision also **publish**. On a
phone the calendar is a list of the days that have something planned.
`BrandoAdmin.Schedule` reads and moves the items.

## Cancel an entry schedule

Use **Delete job** on the Scheduled Publishing screen, or cancel the matching
job in the current authorization and tenant context:

```elixir
{1, _} = Brando.Publisher.delete_job(job.id, user)
```

Deleting a job clears the date it was for, so that nothing publishes the entry
later: a publishing job clears `publish_at` and sets a pending entry back to
draft, and an expiry job clears `unpublish_at`. The entry is saved through its
context as `user` (`:system` when left out), so Activity records it. A date
that has moved since the job was made is left alone. The Scheduled Publishing
screen asks before it deletes.

Or save the entry with its intended status and date: any change to
`publish_at`, clearing it or moving it into the past included, removes the
entry's waiting publication job, whoever scheduled it, and only a future date
queues a new one. For example, set `status: :draft, publish_at: nil` to keep it
private. Clearing the date on a pending entry changes its status to published
unless you explicitly choose another status.

A job that was already running when the date changed checks the entry when it
runs and does nothing unless the entry is still pending and its `publish_at`
has come. Cancelling a job that has already executed cannot undo its
publication.

## Let an entry expire

**Expires** in the same drawer sets `unpublish_at`. When it comes, the entry is
deactivated (status `:disabled`) through the context's update, the same change
as choosing Deactivated by hand: Activity records it as unpublished, and the
`entry.unpublished` content event goes to webhooks, IndexNow and the search
index, with the actor `"scheduler"`. The listing shows "Expires 12 Oct" under
the entry's status, and the dashboard lists what expires in the next 14 days.

```elixir
{:ok, page} = Brando.Pages.update_page(page, %{
  unpublish_at: DateTime.add(DateTime.utc_now(), 14, :day)
}, current_user)
```

- It has to come after `publish_at`; the save is refused otherwise.
- Changing it replaces the job, and clearing it (`unpublish_at: nil`) cancels it.
- A time that has already passed deactivates a published or pending entry at
  once.
- At its time the job deactivates the entry only if it is still published or
  pending and its `unpublish_at` has come; an entry unpublished by hand, or
  given a later date, is left alone. A publication job finds an entry whose
  expiry has passed and does not publish it.
- Setting or clearing an expiry takes both the **schedule** and the **publish**
  permission.
- Restoring a revision, scheduled or not, keeps the expiry the entry has: it
  is not part of the revision's content.

The expired entry keeps its `unpublish_at`, so it shows when it ended.
Publishing it again clears an expiry that has passed, unless the same change
sets a new one. A duplicate or a new translation starts without an expiry, and
a content transfer treats `unpublish_at` like `publish_at`: a draft has none,
preserve keeps the target's own and source takes the archive's.

## Dates without jobs

Cloning an environment or restoring an archive carries the dates but not the
jobs, which live with the queue. `Brando.Worker.ScheduledPublishingSweep`, in
Brando's default Oban crontab every ten minutes, catches up in every active
environment (`Brando.Publisher.sweep/1`): it publishes pending entries whose
`publish_at` passed more than five minutes ago and deactivates published or
pending entries whose `unpublish_at` did, through the context as the jobs do.
Running it again changes nothing. With group authorization, a publication whose
job is still waiting, running or retrying is left to that job, so the sweep
never publishes what the job's user is refused; a job waiting for another,
later date (one the entry had before an archive was restored) does not hold it
up. Expiries do not wait.

It only takes dates from the last seven days, so dates left from before the
sweep existed are not acted on when it first runs; change the window with
`config :brando, Brando.Publisher, sweep_days: 7`. A content type whose table
cannot be read in an environment (its migrations lag) is logged and skipped,
and an entry that fails to save is logged and left alone for a day, or until
it is saved again. To see what it would do, in every environment:

```sh
mix brando.scheduled_publishing.sweep          # list, change nothing
mix brando.scheduled_publishing.sweep --apply  # do it now
```
 An application that sets
`config :brando, Oban` itself must add
`{"*/10 * * * *", Brando.Worker.ScheduledPublishingSweep}` to its crontab;
`mix brando.doctor` warns when it is missing.

## Schedule an approved revision

In **History → Revisions**, store the editor state as an inactive revision, describe it,
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

Scheduling a revision again, from the revisions drawer or the calendar,
cancels its job and queues another. A job that is no longer the revision's one
waiting job, or whose time has not come, does nothing when it runs, so a stale
job cannot publish the revision early.

At execution, Brando restores the snapshot transactionally, forces published
status and the current publication timestamp, makes the revision active, and
updates identifiers, caches, and rendered content. Later edits to the live entry
do not change the scheduled snapshot. A revision that comes due while its entry
is in the trash is not published: the job is cancelled, the revision is no
longer scheduled, and the entry's Activity says why. Restoring the entry
publishes nothing; schedule the revision again if it should still go out.

To cancel before execution, use **Cancel schedule** in the revision row:

```elixir
:ok = Brando.Publisher.cancel_scheduled_revision(Page, page.id, revision.revision)
```

This API uses the current authorization scope. In application code, establish it
with `Brando.Authorization.Boundary.with_scope/2`, as in the authorization guide;
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
