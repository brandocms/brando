---
name: brando-workers
description: Work on Brando Oban jobs, scheduled publishing, image processing, rendering cascades, cleanup, sitemap generation, or tenant-aware background execution.
user-invocable: true
---

# Background jobs

Paths are repository-relative. Workers live in `lib/brando/workers/` but their
module namespace is `Brando.Worker`. Find both the enqueue site and `perform/1`;
changing only one side can leave already queued serialized arguments incompatible.

## Tenant context and job lifetime

- `lib/brando/tenant/job.ex` carries tenant context across the Oban process
  boundary. Tenant-owned enqueue paths use `Tenant.Job.attach/1`; workers use
  `Tenant.Job.run/2` before touching content or media.
- Oban rows are shared in public. Tenant jobs need their prefix in arguments,
  including cancellation/deduplication queries. A matching entry ID alone can
  refer to content in multiple environments.
- Missing/invalid prefixes cancel tenant jobs. Do not fall back to a public
  content query when tenant context is absent.
- Installation-wide periodic workers use `each_active_environment/2` with the
  appropriate `:all` or `:live` scope. Check the worker's intended audience before
  changing which environments it traverses.
- Preserve idempotency, retries, return values, and terminal error reporting.
  Avoid introducing duplicate external side effects when a job retries.

## Important families

- `lib/brando/workers/entry_publisher.ex` supports status changes and publishing
  a selected revision. Trace scheduling through `lib/brando/publisher.ex` and
  revision restore through `lib/brando/revisions/revisions.ex`.
  Failed revision publication releases its schedule;
  success must use the intended user and current authorization semantics.
- `image_processor.ex` under the worker directory updates asset state and queues
  CDN work; read [media](../brando-media/SKILL.md) for the full sequence. Progress
  and terminal failure broadcasts have different consumer behavior.
- Entry rendering/cascade jobs refresh dependent content. Read
  [Villain](../brando-villain/SKILL.md) before changing dependency traversal.
- Upload-intent, video-upload, draft, revision, preview, media-orphan, and soft-
  delete cleanup have different retention and ownership rules. Inspect each
  worker's candidate query and reference checks before changing deletion.
- SSG/deployment and environment-copy jobs have broader side effects. Use the
  relevant deployment/environment documentation when the task involves them.

## Verification

Use `test/brando/tenant_job_test.exs` for process-context restoration and prefix
isolation. Search for the specific worker module in `test/` to select its focused
cases. Oban testing mode is configured in `config/test.exs`; a test using inline
jobs must still assert the persisted effect and retry/error contract. Do not
trigger production jobs as a substitute for a local worker test.
