# Content import and export

**Configuration → Import / export** moves complete saved entries between Brando
installations, sites and environments. Entries include authored fields, metadata,
assets, owned records and every block field. Review the bundle before creating
new entries or updating existing ones on the destination.

**Advanced export options → Block fields only** retains the original workflow:
replace or append selected fields on an existing entry. Version-1 bundles remain
supported.

Repository screenshots: [Export](../docs/admin-ui/content-transfer-export.png),
[upload](../docs/admin-ui/content-transfer-import.png),
[uploaded bundle](../docs/admin-ui/content-transfer-import-ready.png),
[mobile selection](../docs/admin-ui/content-transfer-export-mobile.png),
[desktop review](../docs/admin-ui/content-transfer-review-desktop.png), and
[mobile review](../docs/admin-ui/content-transfer-review-mobile.png).

## Prepare the destination

Run framework migration **174**, which creates recovery receipts and fills only
missing module and table-template UIDs before making those columns non-null.
Existing UIDs and module versions stay intact. Provisioned environments inherit
the constraints; receipts remain in `public` and are scoped to the current
database, site/environment and actor.

Deploy the application's Blueprint schemas, block fields, templates, datasource
implementations, media configurations, globals, routes and assets first. A
content bundle carries stored content and optional module definitions. It does
not deploy application code or service credentials.

## Editor workflow

1. **Export content.** Search saved entries across registered Blueprints and
   select the entries to move. Fragments are searchable entries with their own
   language, parent key and key.
2. **Prepare the bundle.** Review entry, block and dependency counts. Include
   originals to transfer images and uploaded files; include definitions to make
   missing module lineages available on the destination. Unsaved editor changes
   are excluded: save the entry before exporting. Saved draft entries can be exported.
   **Related entries** offers an explicit **Include entry** action. References
   left outside the bundle require a destination mapping during import.
3. **Review your entries.** Choose **Create a new entry** or **Update an existing
   entry**. Review titles, URI/slug/key, language and publication. Key collisions
   block import instead of silently renaming content. Expand **Review fields &
   content** to inspect changes, block text, assets and owned records.
   New entries default to Draft without a publication schedule; updates keep the
   destination's status and publication date. Choosing the source publication
   settings applies its status and date through the normal publisher scheduler.
   Saving as draft clears the entry's scheduled status job. Block-field bundles
   retain their **Replace** / **Append** controls.
4. **Resolve dependencies.** Confirm mappings for referenced content and media.
   Module and table-template UIDs match automatically. Historical independent
   copies appear as suggestions and require an explicit choice. Definition
   differences are shown; incompatible references, variables, tables, module
   settings and child relationships block apply.
5. **Install missing definitions when needed.** Review the included definitions
   in the same screen. Only new definitions and identical existing definitions
   can be installed here. Map existing assets used by module defaults in the
   expandable definition-assets section. Use the dependency search to find them.
   Upload missing default assets through Assets first. Changes to an existing
   definition use the [module migration workflow](module_definitions.md).
6. **Apply content import.** The server checks the reviewed state and permissions
   again, saves a recovery snapshot, and imports all reviewed content in one
   database transaction. The result separates saved content from rendering and
   media processing. Static sites still use their normal build/deploy workflow.

Uploading, previewing and cancelling are read-only. **Install missing
definitions** is a separate, explicitly labelled write: those definitions remain
installed if the later content import is cancelled. **Apply content import**
writes the reviewed entries (or selected block fields), owned records and media.

### Module identity

`Module.uid` identifies a definition's lineage across installations. Its numeric
database ID is local. Content import resolves a UID to the local module ID and
stamps newly inserted blocks with that module's current version.

The older module-list import creates independent copies with fresh UIDs and
version 1. It remains available. A copied module can be explicitly mapped during
content review when its contract is compatible; matching names or coincident
database IDs never make that choice automatically. Reviewed mappings are reused
for unchanged dependency requirements from the same source and workspace.

### What is preserved

| Content | Transfer behavior |
| --- | --- |
| Authored entry fields | Blueprint attributes, SEO metadata, rich text and reviewed publication settings |
| Owned entry records | Cast-enabled child relations, embeds and ordered entry-selection joins; new destination identities |
| Root and nested blocks | Complete ordered trees; active/collapsed state, anchors and descriptions |
| Multi-module entries and tables | Child relationships, ordered rows and cells, compatible destination templates |
| Regions and footnotes | Owned slots, unused retained slots, module-set restrictions and remapped footnote markers |
| References and variables | Values and configuration; fresh owned database IDs and instance UIDs |
| Selected entries and link variables | Explicit identifier mapping, selection order, metadata and destination URLs |
| Rich-text identifier links | Destination identifiers and recomputed link targets |
| Galleries | New gallery and object ownership for every placement; remapped object overrides |
| Images and uploaded files | Checked originals, destination upload configuration and metadata; generated sizes are rebuilt |
| Uploaded/external/provider videos | File/thumbnail dependencies or configured remote source metadata |
| Containers, palettes and module sets | Explicit mappings to destination records |
| Referenced entries and fragments | Include the complete entry explicitly or map an existing destination |
| Markdown sources and pinned versions | Map existing destination sources and versions; normal publication permissions apply |

Shared entries are not followed recursively without selection. Include them from
export review or select them directly. Page fragments, child pages, translations
and other inverse collections remain independent entries; selecting a page does
not implicitly select that entire graph. Owned records are defined by Blueprint
embeds, cast-enabled child relations and `:entries` relations. Other belongs-to
and cast-enabled many-to-many relationships use reviewed dependency mappings.

New entries are inserted in dependency order. Self-links and mutual identifier
links retain their new destination identities. Cycles of direct foreign keys
between new entries block import with instructions to map a reference to an existing entry. Deploy matching
Blueprints first: missing or unknown authored fields are rejected. Database IDs,
block instance UIDs, creator identity, timestamps, deletion flags and passwords
are not portable authored values. The current actor owns the destination changes.

Shared-library definitions and overrides must be made local before transfer.
Unsupported reference types and missing application dependencies are actionable
errors; import does not silently discard their content.

## Media and retries

Originals are stored as `media/<sha256>` entries, with declared checksums and
sizes. Import verifies the ZIP, upload policy, configuration access and image
data before writing destination-owned files. Missing local originals (for
example, a CDN-only asset) require restoring the original locally or exporting
without originals and mapping an existing asset.

An unchanged mapping can reuse a prior destination asset. Recently transferred
originals with matching checksums are also offered for explicit reuse. Choose
**Create from bundle** to request a new asset instead. Gallery ownership is
always independent even when its media is shared.

Each reviewed plan has a unique operation ID. Retrying that plan returns its
receipt and cannot append duplicate content. Generating a new preview creates a
new intentional operation. If a connection drops during apply, check **Recent
imports** before starting another import. After a successful commit, retrying
rendering/media does not reimport content.

On ordinary validation, storage or database failure, the transaction rolls back
and cleanup removes the attempt's staged and newly written originals. A hard
process or host failure can leave orphan files: stage directories start with
`brando-content-<operation UUID>-` in the system temporary directory, and final
original filenames contain the operation UUID. Maintenance must check receipts
and asset references before removing final files. A valid committed asset must
never be deleted merely because an attempt timed out.

## Recovery

**Recent imports** shows the current actor's last ten imports in this workspace.
Each receipt records updated entries' authored state, created-entry identities,
dependency mappings and post-import fingerprints. **Recover previous content**
refuses to overwrite entries or owned content edited since import. It restores
updated entries, permanently removes newly created entries and their owned
records in reverse dependency order, and refreshes rendering. New relationships
and rich-text links to created entries block removal; remove those references
first. Recovery rechecks permissions and module contracts. A database rejection
rolls back the entire recovery operation.

Version-1 recovery remains limited to its selected block fields. Installed
definitions and transferred library media remain available. Include receipts in the application's
normal database backup and retention policy. Receipts are not copied between
tenant environments.

## Application integration

Stored Blueprints with persisted identifiers appear in the whole-entry catalog.
Fragments are supported without identifiers. Block-field mode lists registered
block providers, including a direct provider for types without identifiers.
Other referenced registered entries can be included from export review.

Pages match by URI and language; fragments match by parent key, key and language.
Custom Blueprints can define `content_transfer_key/1` and, for efficient lookup,
`content_transfer_query/1`. See [Blueprint transfer matching](blueprints.md#content-transfer-matching).
Hints suggest destinations; users still choose whether to create or update.

The server API uses an authenticated, active `Brando.Users.User` and the current
tenant context. It never accepts `:system` for content transfers:

```elixir
alias Brando.Content.Transfer

{:ok, exported} = Transfer.export([
  %{schema: MyApp.Projects.Project, id: project.id}
], user, media: true, definitions: true, source_label: "Studio / staging")

File.write!("content.zip", exported.binary)
{:ok, archive} = Transfer.read(exported.binary)

targets = Map.new(archive.bundle["entries"], fn entry ->
  {entry["key"], %{
    "mode" => "create",
    "publication" => "draft",
    "attributes" => %{"slug" => "reviewed-destination-slug"}
  }}
end)

# Updates use "mode" => "update", "id" => destination.id and
# "publication" => "preserve" (or an explicit "draft" / "source" choice).

mappings = %{} # Add reviewed destination IDs for unresolved dependency tokens.
{:ok, plan} = Transfer.preview(archive, targets, user, dependencies: mappings)
if Transfer.applicable?(plan) do
  {:ok, receipt} = Transfer.apply(plan, user)
  # Keep plan.id/receipt.id. Later, as needed:
  # Transfer.retry_refresh(receipt.id, user)
  # Transfer.restore(receipt.id, user)
end

Transfer.history(user)
```

`mappings` maps portable dependency tokens to reviewed destination IDs, or
`"create"` for supported bundled media. References to included entries default to
`"bundle"`; an explicit existing ID overrides that choice. Tokens are opaque manifest keys.
Their source numbers are diagnostics, never destination bindings. Plans are
server-side values and must stay scoped to their actor and environment.

Explicit `fields: ["blocks", "sidebar"]` selectors export version-1 block-field
bundles. Omit `fields` for complete entries, or pass `scope: :entries` to force
whole-entry export. Version 2 adds a schema-validated `entries` manifest; its
block-field index must agree with the entry payload. Both versions use
`content.json` in a ZIP and the existing optional definition format.

Limits are 128 MB compressed, 256 MB expanded, 8 MB of manifest JSON, 2,000 ZIP
entries/dependencies, 100 entries/fields, 5,000 blocks per entry/field, 40 block
nesting levels and 20 owned-record nesting levels. ZIP traversal, symlinks, duplicate names,
unsupported versions and missing or corrupt originals fail before apply.

### UID migration audit

Runtime module changesets, table-template changesets, factories, copy helpers
and definition imports provide UIDs. Historical migration 107 performs direct
definition inserts before UID columns were introduced. Migration 174 backfills
only `NULL` values in existing public/tenant definition tables and then adds the
constraint; it does not regenerate existing lineage or rewrite version history.
