# Content status, deletion, and ordering

Publication, deletion, and sequence answer different questions: can this entry be
shown publicly, is it still in ordinary listings, and where does it appear? Keep
those decisions explicit in both a Blueprint and its public queries.

The examples use existing Pages, which already have the relevant traits. A custom
schema opts in with `trait :status`, `trait :soft_delete`, and `trait :sequenced`,
then applies the resulting [Blueprint migration](blueprint_migrations.md).

## Status and valid publication

Brando's status type stores these values:

| Status | Database value | Intended editorial use |
| --- | --- | --- |
| `:draft` | `0` | Work in progress, including incomplete entries |
| `:published` | `1` | Eligible for public queries |
| `:pending` | `2` | Awaiting scheduled publication |
| `:disabled` | `3` | Retained but intentionally not published |

A Blueprint draft skips its ordinary required-field validation. Other statuses
validate required fields. Drafts are not exempt from every constraint: type
casting, uniqueness, association rules, and database constraints can still fail.
Use named status atoms or accepted form values, not arbitrary integers from an
untrusted request.

Publish through the context:

```elixir
case Brando.Pages.update_page(page, %{status: :published}, current_user) do
  {:ok, published} ->
    {:ok, published}

  {:error, %Ecto.Changeset{} = changeset} ->
    # Return this changeset to the form so the editor can fix its errors.
    {:error, changeset}

  {:error, :forbidden} ->
    {:error, :forbidden}
end
```

The current fields must be valid for publication, including required asset
associations. A successful context mutation coordinates identifiers, query-cache
eviction, and content rendering/cascades. Avoid replacing it with a raw database
status update. `Brando.Trait.Status.update_status/4` is used by status controls;
its legacy fast path is narrower than a full context save. Application publication
workflows should use the context as above.

Public queries must explicitly select `status: :published`; the default context
query is useful for editing and does not imply publication filtering. Use
`:published_and_pending` only when deliberately displaying pending content.
`has_url: true` and the entry language can impose further requirements. A status
change does not rebuild an already deployed static site or invalidate an
application-owned external cache.

For schemas with scheduled publishing, a changed future `publish_at` can convert
published to pending and queue a future update. See [Scheduled publishing](scheduled_publishing.md)
before combining status and date changes. For an already published page whose
next version must remain private, store an inactive [revision](revisions.md)
rather than saving unfinished content over the live entry.

## Deletion and restoration

The soft-delete trait adds `deleted_at`. Ordinary context queries exclude deleted
entries. A context delete marks the entry instead of immediately removing its row:

```elixir
alias Brando.Pages
alias Brando.Pages.Page

{:ok, deleted} = Pages.delete_page(page.id, current_user)
{:error, {:page, :not_found}} = Pages.get_page(page.id)

# Trusted administrative code can inspect the deleted row explicitly.
{:ok, deleted} = Pages.get_page(%{matches: %{id: page.id}, with_deleted: true})

{:ok, restored} = Brando.Authorization.Boundary.restore(current_user, deleted)
```

The restore boundary checks permissions in group mode; low-level
`Brando.Repo.restore/1` is for trusted maintenance code. In a custom admin read,
use the current authorization scope even when including deleted rows. Selecting
`with_deleted` is a query option, not permission to inspect another user's content.

`trait :soft_delete, obfuscated_fields: [:slug]` frees a unique value on deletion
by appending a marker and random suffix. Pages use this for `uri`. Restoration
tries to normalize the original value and resolves a collision if another entry
has claimed it. Inspect the **returned** restored URI; do not assume a former
public URL is still available. A database conflict outside those configured
collision rules may still return an error or raise a constraint exception.

Restoration clears deletion, recreates the identifier where applicable, and
evicts query caches. It is not a replacement for all domain-specific update
callbacks. For imported/restored pages, recompute breadcrumbs when needed with
`Brando.Pages.update_breadcrumbs(restored)` and verify dependent block/static
output. Deleted rows should not leak into custom `Repo` queries: add an explicit
`is_nil(entry.deleted_at)` condition or use `Brando.SoftDelete.Query.exclude_deleted/1`.

## Retention and media

The default soft-delete purger runs at **03:00 UTC** and permanently removes rows
whose deletion timestamp is older than **30 days**, across active sites'
environments. Revisioned entries lose their revision history on permanent purge.
Restore before that window closes; soft deletion is not a substitute for backups.
Custom Oban configuration must preserve the purger if this policy is desired.

A bulk `soft_delete_all` sets deletion timestamps but does not run each entry's
obfuscation, identifier, or context callbacks. Use it only when your maintenance
workflow handles those consequences explicitly.

Asset-row retention and media-byte retention are separate. Files may still be
used by another environment, and remote video deletion follows the provider's
configured delete timing. Local orphan cleanup checks references across the
site's environments before pruning bytes. See [Sites and environments](tenancy_and_environments.md)
and [Videos](videos.md); never delete a media directory merely because one
content row was soft-deleted.

## Choose sequence behavior

The sequence trait adds an integer `sequence`, defaulting to zero:

| Declaration | Insertion behavior |
| --- | --- |
| `trait :sequenced` | New entries can share sequence zero |
| `trait :sequenced, append: true` | Insert after the current highest sequence |
| `trait :sequenced, strict: true` | Insert at zero and increment existing sequences |

Append/strict insertion scopes by language when the schema has one, otherwise by
the whole schema in the current tenant. They do not infer a category, parent, or
other application grouping. Choose one mode; strict takes precedence if both
options are supplied. Neither mode is a uniqueness constraint on the sequence
column or a guarantee of gap-free values after every later operation.

Always query with an explicit stable order. A useful default is
`order: [{:asc, :sequence}, {:desc, :inserted_at}, {:asc, :id}]`.
If several entries share sequence zero, relying only on `sequence` leaves ties
undefined. Strict insertion is useful for next/previous navigation that depends
on distinct positions; verify the query semantics in [Querying](querying.md).

## Reorder a collection

After loading the authorized entries in the collection, send their IDs in the
new order:

```elixir
Brando.Trait.Sequenced.sequence(
  Brando.Pages.Page,
  %{"ids" => [third.id, first.id, second.id]},
  current_user
)
```

The IDs are database IDs in the intended tenant, not form indices. The helper
sets sequences from zero, evicts schema queries, and invalidates datasources.
`"sortable_offset"` supports a list beginning at a later offset; reorder within a
known collection/page rather than mixing arbitrary filtered subsets. In group
mode, the operation checks reorder permission for every submitted entry and
rejects unknown/unauthorized IDs; it also caps the request at 1,000 keys.

Nested form rows use their relation's `sort_param` and `drop_param` instead. Let
the form submit those positions and save the parent, especially for unsaved rows
without IDs. See [Blueprint subforms](blueprints.md) for relation declarations.
Do not use the persisted-entry sequence helper to reorder a browser-only row.

Reload the listing and parent form after a drag. Check the public list and any
datasource consumer after the render queue drains, then repeat in another
language/environment to verify ordering remains in the intended scope.
