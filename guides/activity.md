# Activity log

The activity log records who created, changed, published, trashed, restored and
deleted content, and when. Administrators read it under
**Configuration → Activity**; an entry's own history is in the editor under
**History → Activity**.

An event names the entry as it was (title, language), the person, the fields that
changed and the [revision](revisions.md) the change saved. It doesn't keep the
values; the revisions hold the content, and **Compare** shows the difference
between a change's revision and the one before it.

## What is recorded

Every Blueprint entry that changes through Brando records an event:

| Action | Recorded when |
| --- | --- |
| Created | An entry is created, by hand, by the assistant or by duplicating one. |
| Updated | A save changes at least one field. Saves that only touch bookkeeping (`updated_at`, rendered HTML, sequence) record nothing. |
| Published / Unpublished | A save, a listing's status menu or a scheduled job moves the status into or out of published. |
| Moved to trash / Restored from trash | An entry with `trait :soft_delete` is deleted, or brought back. |
| Deleted permanently | An entry without soft delete is deleted, or the trash removes an entry after 30 days. |
| Restored revision | An editor activates an older revision. |
| Duplicated | A copy is made; the event names the original. |
| Imported | A [content transfer](content_transfer.md) creates or updates entries. One import shows as one row. Undoing it is recorded too. |
| Reordered | A listing is sorted by hand. One event for the whole list. |

Media (images, files, videos, galleries) and Brando's internal records (blocks,
variables, revisions, identifiers, previews) are not logged.

## Who did it

The person is the user the change was made as. When the change wasn't made by
hand in the admin, the source says how, and the person behind it is shown
underneath:

- **Scheduled publishing**: the job that published the entry, set by the user who
  scheduled it.
- **Assistant**: an applied [proposal](content_assistant.md), approved by the user
  who applied it.
- **A tool via MCP**: an applied proposal that a [connected
  tool](content_assistant.md#proposals-from-connected-tools) prepared, named
  when known ("Claude Code via MCP"), approved by the user who applied it.
- **Content transfer**: an import, run by the user who imported it.
- **System**: no user, such as `mix brando.entries.resave` or the trash purge.

In code, wrap work that runs on someone's behalf so its events say so:

```elixir
Brando.Activity.with_source(:import, fn ->
  MyApp.Importer.run(rows, current_user)
end)
```

## Access

Without group authorization, administrators and superusers see
**Configuration → Activity**. With [group authorization](authorization.md), the
**Activity** permission (`brando.activity.read`) decides, and the log only lists
content types the reader may read. New administrator groups get the permission;
existing groups need it granted. Anyone who can edit an entry can read its own
history in the editor.

The trash listing uses the log to show who moved each entry there.

## Configuration

```elixir
config :brando, Brando.Activity,
  retention_days: 365,
  ignore: [MyApp.Stats.Counter]
```

`retention_days` (default 365) is how long events are kept; a nightly job removes
older ones. Schemas in `ignore` are not logged.

Recording never fails a save. An event that can't be written, for example before
the `brando_193` migration has run, is logged as a warning and dropped.

## Reading the log in code

```elixir
Brando.Activity.list(%{schema: MyApp.Projects.Project, action: :published}, limit: 20)
Brando.Activity.for_entry(MyApp.Projects.Project, project.id)
Brando.Activity.count(%{user_id: user.id, since: ~U[2026-10-01 00:00:00Z]})
```

Events are `Brando.Activity.Event` structs, newest first, with `user` preloaded.
