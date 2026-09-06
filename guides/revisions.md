# Revisions

A revision is a numbered snapshot of an entry, including its block associations.
It lets an editor keep a working version, inspect an older version, or restore a
specific saved state. It is different from an [unsaved live preview](live_preview.md)
and from a [scheduled publication](scheduled_publishing.md).

Pages and fragments already use `trait :revisioned`. For a custom Blueprint,
add that trait and apply the current Brando migrations before using this guide.
Revision operations run in the entry's environment and obey the entry's
[authorization policy](authorization.md).

## Store, preview, and activate

1. Create a page with a heading block and save it. Revisions require a persisted
   entry ID; a brand-new unsaved page has no history yet.
2. Change its title and heading without saving the entry. Open **Revisions** and
   choose **Store current editor state**. Brando collects the editor's current
   fields and blocks, validates them, and stores an **inactive** revision.
   The public entry is unchanged.
3. Give the revision a useful description, such as **Autumn launch**. Make another
   temporary edit, then select the stored revision to preview it. Confirm the
   replacement of unsaved editor changes. The revision loads as an **unsaved
   working copy**; selecting it has not changed the database entry.
4. Inspect that working copy with live preview. Choose **Activate revision** when
   you want to restore it to the entry. Reload the editor and check both its
   scalar fields and block content.

Activation restores the revision's status as well as its content. Activating an
old draft can therefore make a currently published entry a draft. Use scheduled
revision publication when the intended operation is explicitly “restore this
snapshot and publish it.”

Ordinary successful context saves capture revisions synchronously. Snapshot
capture uses the entry state supplied by that save, so a later save cannot race
with a background snapshot job. There is one active revision per entry; storing
an inactive working copy leaves the active marker where it was.

## Work with a numbered snapshot

Use metadata listing for history screens rather than loading every snapshot blob:

```elixir
alias Brando.Pages.Page
alias Brando.Revisions

{:ok, history} = Revisions.list_revision_metadata(Page, page.id, limit: 20, offset: 0)

# `revision` is the entry-local revision number, not a revision row's database ID.
selected = Enum.find(history, &(not &1.active))

if selected do
  {:ok, {_metadata, {_number, snapshot}}} =
    Revisions.get_revision(Page, page.id, selected.revision)

  {:ok, restored} =
    Revisions.set_entry_to_revision(Page, page.id, selected.revision, current_user)

  restored.title == snapshot.title
end
```

The metadata page is newest first, defaults to 50 rows, and caps its limit at
200. An entry with no inactive history makes `selected` nil; show an empty state
instead of assuming that a previous version exists.

To deliberately store a validated working copy in application code, use:

```elixir
with {:ok, working_copy} <-
       page
       |> Page.changeset(%{title: "Autumn launch"}, current_user)
       |> Ecto.Changeset.apply_action(:update) do
  Revisions.create_revision(working_copy, current_user, false)
end
```

Pass `false` to keep it inactive. `create_revision/3` preserves supplied loaded
associations and loads missing ones; it does not validate arbitrary structs for
you. The form path performs authorization and validation before calling it.
Do not build a custom public endpoint around raw snapshot functions without the
same entry access checks.

## Restore failures and schema changes

Restoration is transactional. It rebuilds missing historical block links,
applies the current schema changeset, refreshes the identifier, and moves the
active marker together. Afterwards it invalidates query caches, schedules
content rendering/cascades, and notifies open editors. It is not a raw overwrite
of the serialized struct.

The drawer labels snapshots from a different schema version and asks the editor
to review compatibility. A version mismatch is not a promise that restoration
will succeed: removed fields, changed validation, missing assets, or corrupt
snapshot data may prevent it. Handle `{:error, reason}` and retain the current
entry on failure. A snapshot belonging to another entry is rejected. Inspect
older snapshots in a non-live environment after a schema migration before
relying on them for a release.

Invalid editor changes do not create a revision: field errors remain in the
form. If loading history fails, the drawer offers **Try again**. Avoid refreshing
the whole page until any unsaved working copy has been stored or discarded.

## Retention

Protection, activity, and scheduling are separate flags. Automatic cleanup keeps
active, protected, and scheduled revisions and purges other revisions older than
**30 days**. The default revision-purger cron runs at 04:00 UTC across active
sites' environments. Application Oban overrides must preserve that job if wanted.

**Purge inactive versions** is broader than nightly cleanup: it removes every
inactive, unprotected, unscheduled revision for that entry, without an age gate.
Individual deletion has the same flag protections. Protect a milestone you need
to retain, and keep database backups for recovery beyond the revision lifecycle.

Manual activation cancels the selected revision's pending publication job.
Cancelling a schedule clears its scheduled retention flag; it does not delete
the revision. See [Scheduled publishing](scheduled_publishing.md) for the full
schedule/cancel/execute workflow.
