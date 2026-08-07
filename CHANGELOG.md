## 0.54.0 (Unreleased)

### Unreleased

#### Breaking

- **The form's image and file drawers moved out of `BrandoAdmin.Components.Form`**
  into `BrandoAdmin.Components.Form.ImageDrawer` and
  `BrandoAdmin.Components.Form.FileDrawer`, markup only. The JS command helpers
  moved with them, since their only callers are the markup they target:
  `close_image/1`, `close_image_editor/1`, `open_image_editor/3`,
  `duplicate_image/3` and `reset_image_field/2` are now on `ImageDrawer`;
  `close_file/1` and `reset_file_field/2` on `FileDrawer`. The image editor
  drawer is `ImageDrawer.editor/1`.

  **What to change.** Alias the new modules and call `render/1` there. The
  drawers' `update/2` and `handle_event/3` clauses stay on `Form` — they write
  the parent's state — so nothing about event handling changes.

- **`Brando.Videos.Uploader.initiate_upload/3` never raises, and its error terms
  changed.** It was possible for a provider client's exception to escape this
  function; it now returns `{:error, reason}` for every failure. Two new reasons
  join the existing ones:

  | Reason | When |
  |---|---|
  | `{:error, :provider_not_configured}` | the strategy's credentials are missing or empty, checked before dispatch |
  | `{:error, :provider_error}` | an unexpected provider exception, rescued and logged with its stacktrace |

  **What to change.** If you call this function, a `rescue` around it is now dead
  code and can be removed. If you rendered the error, note that
  `:provider_error` replaces what used to be the raised exception's message —
  use `Brando.Uploads.video_upload_error_message/1`, which is now the single
  owner of the user-facing text for all of these.

  **Why the check moved rather than the raise being caught.** The three
  providers still raise on missing credentials, exactly as 0.54.0 decided —
  rescuing that at the facade would have converted the decision straight back
  into the error tuple 0.54.0 removed. Instead
  `Brando.Uploads.validate_provider_video_intake/2` checks credentials among the
  other pre-flight validators, so the raise stays a last-resort invariant guard
  that the admin path does not reach.

  This matters because `initiate_upload/3` is called from three LiveViews
  holding an editor's unsaved work, and only one of them had a `rescue`. A pick
  in the video picker or a transformer against a misconfigured provider took the
  form process down, and every unsaved change with it.

- **Mux and Bunny now reject empty-string credentials, as Cloudflare already
  did.** All three check for a non-empty binary. Previously a truthiness check
  let `access_token_id: ""` or `api_key: ""` through, and the request went out to
  the live API carrying an empty auth header instead of the site being told its
  configuration was wrong.

  **What to change.** Nothing, unless you were relying on an empty-string
  credential reaching the provider — which only ever produced a 401 from the
  other end. A config that sets a credential to `""` now fails at the same point
  an absent one does.


- **All three video providers now raise on missing credentials.**
  `Brando.Videos.Uploaders.Cloudflare` returned `{:error, :not_configured}` when
  `account_id` or `api_token` was absent, while `Mux` and `Bunny` raised. Cloudflare
  now raises too, with a message naming the config keys it wants.

  Missing credentials are a deploy-time configuration error, not a runtime
  condition — and the disagreement meant a caller could not handle the three
  providers with one branch:

      # before — this was necessary, and easy to get wrong
      case Uploader.delete_remote(video) do
        {:error, :not_configured} -> :cloudflare_only
        {:error, reason} -> handle(reason)
        :ok -> :ok
      end

      # after — one shape for all three
      Uploader.delete_remote(video)

  **What to change.** If you match on `{:error, :not_configured}` from a
  Cloudflare call, that clause is now dead and the raise will reach you instead.
  Two paths are worth knowing about:

  * **Uploads from the admin are unaffected**, and since 0.54.1 that is true of
    all three upload surfaces rather than only the entry form's drawer.
    `Brando.Videos.Uploader.initiate_upload/3` validates provider credentials
    before dispatch and never raises, so a misconfigured account surfaces as a
    message rather than taking a LiveView down. See the 0.54.1 entry below.
  * **`delete_remote/1` is where you may notice.** It is called from
    `Brando.Videos` and from soft-delete purging, and an unconfigured provider now
    raises there. This is not new behaviour for that path — `Bunny.delete_remote/1`
    has always raised on missing credentials — but it is new for Cloudflare.

  No shim is provided. A shim would have to rescue and re-wrap, which reinstates
  exactly the branch this removes.

  One difference was left in place by this change and closed by the next:
  Cloudflare rejected an empty-string credential (it checks for a non-empty
  binary) where Mux and Bunny accepted one and failed later at the API. That is
  about *detecting* the failure rather than reporting it, so it was out of scope
  here. **All three now agree** — see the 0.54.1 entry below.

- **`Brando.CDN.key_exists?/2` is removed, replaced by `Brando.CDN.key_available?/2`
  — and the sense is inverted.** `key_exists?/2` returned `true` when the key was
  **taken**; `key_available?/2` returns `true` when the key is **free**. A consumer
  that swaps the name without also inverting the branch turns "skip, something is
  there" into "go ahead, write" and overwrites live objects.

      # before
      if Brando.CDN.key_exists?(key, cfg), do: rename(key), else: key

      # after
      if Brando.CDN.key_available?(key, cfg), do: key, else: rename(key)

  The error semantics changed with it, deliberately. `key_exists?/2` was
  `match?({:ok, _}, head_object(…))`, so anything that was not a clean hit —
  a timeout, a signature failure, a 403 from a bucket that masks 404 without
  `s3:ListBucket` — read as "absent" and let the write proceed.
  `key_available?/2` frees the key only on a definitive `{:error, :not_found}`,
  so an unreadable answer now reads as **occupied**. The cost of guessing wrong
  in that direction is one unnecessary `unique_filename/1` suffix; the cost in
  the old direction was new bytes underneath an existing asset's row.

  **No `key_exists?/2` shim is provided, on purpose.** `not key_available?(k, cfg)`
  is *not* the old function: on an uninterpretable error it returns `true` where
  `key_exists?/2` returned `false`. A shim would look like a compatibility layer
  while silently changing behaviour on exactly the path this change was about, so
  the call sites are better updated by hand.

- **The video drawer's markup moved out of `BrandoAdmin.Components.Form` into
  `BrandoAdmin.Components.Form.VideoDrawer`.** Six public functions moved with it
  and are no longer defined on `Form`:

  | was | is now |
  |---|---|
  | `Form.video_drawer/1` | `Form.VideoDrawer.render/1` |
  | `Form.reset_video_field/1,2` | `Form.VideoDrawer.reset_video_field/1,2` |
  | `Form.reset_video_thumbnail/1,2` | `Form.VideoDrawer.reset_video_thumbnail/1,2` |
  | `Form.parse_video_url/1,2` | `Form.VideoDrawer.parse_video_url/1,2` |
  | `Form.extract_thumbnail/1,2` | `Form.VideoDrawer.extract_thumbnail/1,2` |
  | `Form.close_video/0,1` | `Form.VideoDrawer.close_video/0,1` |

  The function bodies are unchanged — this is a move, verified by diffing the
  extracted text against the original, and the only edits are the renames in the
  table plus three private helpers losing their now-redundant `video_` prefix.
  The rendered markup and every `phx-*` binding in it are identical, so a form
  that does not call these functions by name sees no difference.

  **The drawer's behaviour deliberately did not move.** All eight `update/2` and
  eleven `handle_event/3` clauses stay on `Form`, because they write *`Form`'s*
  state: `save_video_authorized` assigns `:form` and `:entry` and ships field
  changes, and drawer recovery is computed for image, video and file together in
  one place. `VideoDrawer` is a `:component`, like `MetaDrawer` and
  `ScheduledPublishingDrawer` — its events belong to the parent form, and its
  `myself` still arrives as an assign, so component targeting is unchanged.

#### Features

- **`Brando.Videos.ProviderConfigCheck` reports misconfigured video providers at
  boot.** Runs from `Brando.Supervisor.init/1`. The provider clients have always
  said missing credentials are "a deploy-time configuration error", but nothing
  checked at deploy time — a bad configuration was found by the first editor who
  picked a video file.

  It **logs** and never blocks startup. Refusing to boot would turn a
  misconfiguration into an outage and break every environment that legitimately
  has no provider credentials. Sites wanting the strict reading can opt in:

      config :brando, :strict_video_provider_config, true

  which raises at boot instead. Off by default, because it decides whether an
  application starts.

  Three cases are reported, chosen so a site not using a provider is never
  nagged: the default strategy is an unconfigured provider; a provider has
  *some* credential keys set and others missing; a provider has usable
  credentials but no webhook secret (uploads start, never complete, and the
  upload control silently does not render). A provider with no configuration at
  all is not reported.

- **`configured?/0` on all three video providers.** `Brando.Videos.Uploaders.Mux`,
  `.Bunny` and `.Cloudflare` each expose the credential predicate their
  `api_request` raises on, so that a pre-flight validator and the raise cannot
  answer differently.

  It is not the same question as `Brando.Videos.upload_available?/1`, which
  decides whether to *render* an upload control and additionally requires a
  `webhook_secret`. Use `configured?/0` to ask whether a call would work, and
  `upload_available?/1` to ask whether to offer the button.

- **`Brando.Uploads.video_upload_error_message/1`** — the single owner of the
  user-facing text for a failed provider video upload. The video picker, the
  form's video drawer and the transformer all report on the same browser channel
  and had drifted: the picker pushed `inspect/1` of the raw term, so a missing
  credential reached an editor as `:provider_not_configured`.

- **`one_of` / `exactly_one_of` constraints for "either of these fields"**: an entry that is valid
  with either of two fields filled in — a listing needing an image *or* a video —
  could not be expressed before, since `required: true` is per field and either
  one alone is enough.

      asset :listing_image, :image,
        constraints: [one_of: [:listing_image, :listing_video]],
        cfg: :default

  The error attaches to the field carrying the constraint. Assets count as
  present whether set as an association or as their `_id` column, so both the
  picker and the upload path satisfy it; `one_of_message` overrides the wording.
  Assets now run through `Brando.Blueprint.Constraints` at all — previously only
  attributes and relations did — so `constraints:` is accepted on any asset type.

  `exactly_one_of` is the exclusive form, for fields that are alternatives rather
  than a fallback chain (an image *or* a video, never both).

  A validation only covers writes that go through the changeset, so `check:` was
  added alongside it to declare the matching database constraint —
  `check: [must_have_one_media_type: "requires either an image or a video"]`.
  Nothing in Blueprint called `Ecto.Changeset.check_constraint/3` before, so a
  race or a direct `Repo.insert` raised `Ecto.ConstraintError` instead of
  returning an invalid changeset. `check:` also takes a bare atom or a list of
  them, falling back to `check_message`.

  All three are accepted on attributes, relations and assets, and are verified at
  compile time. Asset constraints were not verified at all before this — only
  attributes and relations were — so a typo in an asset's `constraints:` survived
  compilation and raised from the changeset instead.

#### Fixes

- **`Brando.Videos.upload_available?/1` now agrees with the providers about what
  a credential is.** It decided the credential half itself, accepting any
  non-nil non-empty term, while the providers require a non-empty binary. A
  non-binary credential — `account_id: 12345` rather than `"12345"` — therefore
  rendered the upload control over a provider that rejected the pick behind it.
  It now delegates to `configured?/0` and owns only the checks that function
  deliberately does not make: the webhook secret and routing values such as
  `library_id`, which keep the looser check because an id is not a secret.


- **S3 credentials no longer reach exception messages or `inspect/1` output.**
  `Brando.CDN.upload_image/4` raises when a config has no bucket, and that raise
  interpolated the full S3 config — including `access_key_id` and
  `secret_access_key` — into its message, which is then carried by the Logger,
  Oban's `errors` column and any attached error reporter. The credentials are
  now dropped from that message.

  `%Brando.CDN.S3Config{}` also derives `Inspect` with both fields redacted, so
  inspecting a media config no longer prints them either. Note that
  `Brando.CDN.get_s3_config/2` with `as: :keyword_list` returns a plain keyword
  list built via `Map.from_struct/1`, which the derivation does not cover — code
  that interpolates *that* value must still drop the credentials itself.

- **The Bunny video provider no longer forwards its API key across a redirect.**
  `Req` strips credentials when a redirect crosses to another host, but it does
  so by deleting exactly two things: the `authorization` header and the `:auth`
  option. Bunny authenticates with an `AccessKey` header, which is neither — so
  a `302` from `video.bunnycdn.com` to any other host sent the library API key
  along with the follow-up request. This needed no configuration to reach: it
  was the behaviour on **stock defaults**.

  All three Bunny API calls now build `redirect: false`, so a 3xx is returned as
  an ordinary non-2xx error rather than chased. None of them relied on following
  redirects — they are JSON REST calls against a fixed host.

  It is set in the *built* options rather than as a documented default on
  purpose: the provider merge is `Keyword.merge(configured, built)`, so built
  options outrank configured ones and this **cannot be switched back on** from
  `runtime.exs`.

  Mux and Cloudflare are unaffected and need no equivalent — both authenticate
  with `authorization`, which `Req` strips itself.

- **`overwrite: true` now actually overwrites on the CDN path.**
  `Brando.Utils.build_upload_key/2` tested the key for availability
  unconditionally and appended a `unique_filename/1` suffix whenever it was
  taken — so a config asking to overwrite got a renamed object instead, which is
  the one outcome the option exists to prevent. It now short-circuits on
  `overwrite`, and does not consult the bucket at all in that case (one fewer
  `HEAD` per upload). `force_filename` is affected the same way: it was honoured
  when the name was chosen, then defeated by the suffix.

  The two sibling paths already branched correctly — `Brando.Upload`'s
  filesystem writer and the client-direct filename builder — so this was the odd
  one of three against a documented option.

- **Admin login no longer flashes before animating**: the login screen appeared
  fully assembled, vanished, then faded in. Three causes. The initial hide was an
  inline `opacity: 0` set by JS on `#application-login` — but that element is a
  LiveView, and the connected mount patched it back to server truth, deleting the
  style and exposing the form (~287ms). The reveal was then gated on a blind
  `setTimeout(…, 500)`, which re-hid the box (~703ms) before finally animating at
  ~1.2s. Meanwhile the fader lifted at ~204ms, so all of it happened in the open.

  The hide is now a stylesheet rule in the critical inline CSS
  (`html.moonwalk:not(.login-revealed) #application-login`), which a patch cannot
  strip; `login-revealed` lands on `<html>`, which LiveView never touches, and is
  added as the reveal begins so a later patch can never strand the form invisible.
  The reveal is triggered by the element's own `phx-mounted` instead of a fixed
  delay (with a timer as a fallback for dead renders), and the fader holds until
  the reveal announces itself. Settles in ~1.3s with no flash, down from ~1.7s
  with one.

#### Features

- **Transformer: mixed drop, ordered queue, inline asset picking**: a transformer
  subform is now a drop zone for images *and* videos at once. Drop a mixed pile
  (or use either picker — both gestures take the same path) and each file is
  routed to its own transport: images through LiveView's upload, videos straight
  to Mux/Bunny/Cloudflare, or into the sticky UploadManager for `:local`/`:s3`.

  The batch is sorted by filename and registered up front, so every file gets a
  placeholder card immediately, in order, with its own progress and error state —
  the resulting entries no longer land in whatever order the uploads happened to
  finish. Placeholders are skipped when the form saves (with a warning if any are
  still running), removing one aborts its transfer, and files the browser rejects
  (wrong type, over the config's `size_limit`) are listed by name instead of
  vanishing. Provider video uploads accept multiple files and queue sequentially;
  they previously took `files[0]` and ignored the rest. `Brando.Uploads.AssetIntent`
  gained an optional opaque `ref` so UploadManager deliveries can be correlated
  back to the placeholder that is waiting for them.

  Expanding an entry now offers a picker row per asset field — select, swap for an
  already uploaded asset, or remove, without re-uploading. Uploaded and picked
  assets also render their thumbnail immediately; new entries previously showed a
  grey placeholder until the page was reloaded.

  Drag and drop now advertises itself: the transformer carries a permanent
  dashed drop target rather than a hint that only appeared once you were already
  dragging, and clicking it opens a combined picker. Mixed-media transformers
  gained an "Upload files" button alongside the per-type ones.

  New subform option `layout` arranges entries as rows (`:list`, the default) or
  cards (`:grid` — media on top, the `listing:` component beneath, tools on
  hover). `add_entry: false` hides the "Add entry" button, for schemas where a
  blank entry can never be valid (a `NOT NULL` asset column, or a check
  constraint like "exactly one of image_id/video_id").

  Mux, Bunny and Cloudflare hooks now share `providerVideoUploader`, which owns
  queueing, request correlation and teardown; each provider supplies only its
  transfer.

- **Block variable layout** (#2522): module variables now carry a `width`
  (`1/1`, `1/2`, `1/3`, `1/4`, `auto`, `fill`), a `new_row` break and a
  `placement` (in the block / configure modal / hidden from editors), replacing
  the old `important` boolean. The block editor packs them into rows of twelve
  units — several short fields now share a line instead of each claiming one.

  The module editor gained a tab bar (Template · Overview · Variables ·
  References · Datasource), and the Variables tab is a drag-and-drop layout
  canvas beside a live preview rendered with the block editor's own components,
  so the layout is composed against what editors will actually see. Chips are
  the variable list: drag to arrange, click to edit, duplicate, delete, move
  between surfaces. `placement: :hidden` is new — a template-only constant that
  never renders an input.

  Layout set on a module propagates to existing blocks through `reapply_vars/3`.

- **Multi-user block sync fixes**: edits now ship when a block's editing session
  settles — plain blur is enough (previously another block had to receive focus
  before anything shipped, so edits routinely never reached other editors). Late
  joiners receive other editors' unsaved changes on mount — blocks AND entry
  fields (title, slug, …). Child structural changes (insert/delete/reorder) sync
  immediately instead of waiting for a blur, and received edits are visible right
  away: header textareas refresh on remote apply, and rich-text (TipTap) blocks
  re-boot AFTER the content patch lands (they previously re-read the DOM before
  the patch and stayed visibly stale, even though the data synced). A snapshot
  arriving while you're editing the same block is deferred and applied when you
  leave the block instead of being dropped — and an untouched block never
  re-ships stale state over newer remote edits. Block presence locks no longer
  flap: lock decorations go through LiveView's sticky JS commands so patches
  can't wipe them (they used to vanish until the owner's next focus event),
  locks replay to late joiners, and clicking non-focusable UI (toggles,
  handles) inside a block no longer drops the lock. Entry FIELD locks got the
  same treatment — they were silently wiped by the form re-render on every
  keystroke, and now also replay to late joiners.

- **Block editor internals: render from the op store**: Block shells now render
  straight from the op store's order (roots) and each parent's `block_list`
  (children); seed forms became uid-keyed mount-only maps. This removes the parallel
  ordered form lists that every structural mutation had to keep in sync — a whole
  drift bug class — and makes the block outline drawer reflect live structure and
  content (it previously showed mount-time children).

- **Undo for block deletes (restorable bin)**: Deleting a block (root or nested child)
  now shows an undo toast at the bottom of the block field. Undo restores the whole
  subtree — content, structure and database identity — so a restored persisted block
  updates its existing rows at save instead of re-inserting them. Deletes stack (LIFO
  undo), the bin clears on save, and restores sync to other editors in real time.

- **Unified upload manager**: All uploads (block vars, block refs, entry fields —
  images, files, videos, galleries) now route through a single sticky
  `BrandoAdmin.UploadManager` LiveView with its own queue and drawer UI. Upload
  progress no longer re-renders the form/block tree, which fixes stalled uploads
  and render storms on large entries (a 4 MB upload on a 115-block entry went from
  ~106s to ~7s). Includes drag-and-drop `UploadTrigger` drop zones with
  folder-browser integration, configurable transfer concurrency
  (`config :brando, Brando.Uploads, max_concurrent_transfers: 3`), opt-in
  client-direct S3/Spaces file uploads via presigned PUT
  (`cdn: %Brando.CDN.Config{enabled: true, direct: true}` on `Brando.Files`), and
  Mux/Bunny video upload visibility in the manager drawer. Local video uploads now
  store correctly as `Video{type: :upload}` records wrapping a `File`. See
  `docs/UPLOADER.md` for the full design and migration notes.

- **Gallery video uploads**: Gallery entry fields accept direct video file uploads
  via an "Upload videos" button (shown when the default video upload strategy is
  `:local`; Mux/Bunny sites upload through the video picker's provider hooks
  instead). Uploaded videos are appended to the gallery as video gallery objects.
  The gallery input's action row was normalized (real uniform buttons instead of a
  styled div), and the entire input is now a drag-and-drop zone for image uploads,
  matching the block gallery.

- **Live preview refresh button**: Add a "Refresh" button to the top-right corner of the
  live preview drawer header that re-ships a fresh live preview on demand while the drawer
  stays open. The breakpoint debug indicator/logo overlay in the admin is now gated behind
  the `:show_breakpoint_debug` config (off by default).

- **Validation rules for block fields** (#2573): Add `require_blocks` constraint for block field
  relations. Validates that blocks using specific module classes are present when saving.
  Skips validation for drafts and when blocks are not being cast.

  ```elixir
  relations do
    relation :blocks, :has_many,
      module: :blocks,
      constraints: [require_blocks: ["header"]]
  end
  ```

- **Block outline drawer** (#2667): Add a "Block outline" option to the block field dropdown
  that opens a side drawer with a condensed tree view of all blocks. Supports click-to-scroll
  navigation, drag-and-drop reordering at all levels, cross-container child moves, and
  cross-compatible-multi entry moves (same `module_id` only).

- **Real-time collaboration for block editor**: Multiple users can edit the same entry
  simultaneously with presence indicators on active fields and blocks.

- **Link to identifiers in TipTap editor** (#2527): TipTap text editor now supports
  linking to content identifiers directly.

- **Video upload providers (Mux and Bunny)**: Added support for Mux and Bunny as video
  upload and streaming providers.

- **Drag-and-drop media folders**: Media browser folders can now be reordered via
  drag and drop.

- **Spark DSL extensions**: Forward `extensions` option to Spark DSL for external
  blueprint extensions.

- **Blueprint migration hardening**: Blueprint migration generation now compares a normalized, versioned storage
  schema instead of name-only DSL entities. Generated migrations cover type/default/index/foreign-key and auxiliary
  table changes, use deterministic constraint names, allocate collision-free Ecto versions, and render dependency-safe
  `up/0` and `down/0` functions. Snapshot reads fail closed, writes are atomic, and divergent migration/snapshot
  histories stop generation. Use `mix brando.gen.blueprint_migration MyApp.Domain.Schema`; legacy snapshots upgrade on
  their next successful run. Table or primary-key changes require a hand-written migration followed by the explicit
  `--rebaseline` workflow. See [Blueprint migrations](guides/blueprint_migrations.md) before upgrading or generating.

- **JSON-LD `@graph` output**: All JSON-LD entities (identity, website, webpage, breadcrumbs,
  content) are now combined into a single connected `@graph` document instead of separate
  `<script>` tags. This follows Google's recommended approach and matches implementations
  like Yoast and SEOmatic.

- **Auto WebPage entity**: A `WebPage` entity is automatically added to the graph for every
  page render, with `@id` references linking it to the site identity and website.

- **WebPage type selection**: Pages now have a `json_ld_type` attribute (default: `"WebPage"`)
  configurable in the admin Advanced tab. Supports `WebPage`, `Article`, `AboutPage`,
  `ContactPage`, `CollectionPage`, `ItemPage`, and `ProfilePage`.

- **Identity type-specific fields** (#2734): The Identity form now includes type-specific fields
  via an embedded `type_config` schema:
  - Organization/Corporation: `foundingDate`, `numberOfEmployees`
  - Corporation: `tickerSymbol`
  - ProfessionalService: `areaServed`, `knowsAbout`
  - LocalBusiness/Restaurant: `openingHours`, `priceRange`, `geo`
  - Restaurant: `servesCuisine`, `hasMenu`

- **`{:list, SchemaModule}` field type**: New DSL field type for mapping over collections.
  Example: `field :performer, {:list, JSONLD.Schema.Person}, & &1.performers`

- **Multiple entities per page**: `put_json_ld/3` can be called multiple times to add
  multiple content entities to the graph.

- **`@id` on content entities**: Content entities extracted via the blueprint DSL now
  automatically get an `@id` based on the current URL and entity type.

#### Improvements

- **Validated Blueprint relation option contracts**: Relation declarations now
  reject unknown, misplaced, malformed, and silently ineffective options before
  Ecto schema generation. Has-one `through:` associations compile through the
  existing public `relation` DSL; Ecto's boolean many-to-many `unique:` option
  is preserved without creating a Blueprint database constraint; belongs-to
  delete rules are validated through generated migrations; and casting retains
  configured required/invalid messages for many-to-many and empty embeds-one
  values. Cardinality-one sort/drop options that Ecto cannot execute were
  removed from Brando's identity config. Public declarations remain unchanged.
  Most declaration corrections, many-to-many uniqueness, and has-one through
  associations need no database migration. Corrections to belongs-to storage or
  `on_delete:` require a reviewed generated migration with rollback/forward
  verification; rebaseline only when the live constraint was already corrected
  by hand. Igniter cannot infer deployed constraints or safe delete semantics.
  See
  [Relation option corrections](guides/blueprint_migrations.md#relation-option-corrections).

- **Database-aligned Blueprint field options and types**: Migration-only
  `null:`, `precision:`, and `scale:` options no longer leak into Ecto schema
  macros, while schema-only field options stay out of snapshots. Both
  `{:array, :enum}` and `{:array, Ecto.Enum}` compile consistently;
  string/integer enum mappings, enum arrays, custom `Ecto.Type` modules, and
  parameterized types now generate their primitive database types. Defaults are
  dumped through the Ecto type before rendering, so atom enum defaults become
  their string or integer database values and date/decimal/custom defaults are
  executable. Built-in attribute option typos, invalid enum mappings,
  malformed language choices, misplaced timestamp/virtual options, invalid
  decimal precision/scale, and conflicting `define_field: false` storage
  options now fail contextually at compile time. Public Blueprint declarations
  remain compatible. Existing enum/custom-type histories require inspection:
  run a reviewed generated default/null migration when it describes the live
  change, or use a hand-written type conversion plus `--rebaseline`; rebaseline
  directly only after verifying a database already maintained with the correct
  primitive types. Igniter cannot infer live types or data conversions. See
  [Field types, options, and defaults](guides/blueprint_migrations.md#field-types-options-and-defaults).

- **Physical-source-aligned Blueprint migrations**: Persisted attribute,
  belongs-to, embed, referenced-key, and primary-key `source:` values now flow
  through generated columns, composite indexes, constraint names, auxiliary
  relations, and format 3 snapshots. `define_field: false` attaches its foreign
  key to the separately declared physical column, `primary_key false` no longer
  creates an implicit `id`, and compile-time validation rejects invalid sources
  and physical collisions (including generated timestamps and PostgreSQL's
  63-byte identifier form). Existing public Blueprint APIs are unchanged. New
  tables need no special upgrade step. For existing source-mapped tables,
  inspect the live schema before generating: use `rename_from:` for an
  attribute whose old logical column still exists; use a reviewed hand-written
  migration plus `--rebaseline` for primary keys or relation/embed renames; or
  rebaseline directly only when the database is already verified to use the
  physical columns. Igniter cannot safely choose among those cases. See
  [Physical Ecto sources](guides/blueprint_migrations.md#physical-ecto-sources).

- **Fail-closed Blueprint database-name collisions**: Migration schemas no
  longer silently discard indexes when two generated names are equal, including
  equality caused by PostgreSQL's 63-byte identifier limit. Index names are
  checked across owner and auxiliary tables, foreign-key names are checked per
  table, and stored snapshots reject the same invalid states. A unique
  `:language` attribute now emits the intended unique index instead of first
  generating a non-unique language index with the same name. Applications that
  declare `attribute :language, :language, unique: true` should generate,
  review, and run a Blueprint migration; no Igniter step can safely enumerate
  application Blueprints and their migration histories.

- **Quiet E2E startup probes**: Playwright now checks the admin login route
  instead of making its readiness probe depend on the separately built
  frontend bundle. The runner also removes the inherited `NO_COLOR` variable
  before Playwright deliberately enables color and asks Phoenix to shut down
  gracefully, eliminating recurring runner noise without changing test
  behavior.

- **Reversible Blueprint E2E migration fixtures**: The checked-in Client,
  Category, and Project Blueprint migrations now drop dependent auxiliary
  tables before their owner tables, target the tables they actually created,
  and spell long PostgreSQL identifiers explicitly. A full E2E reset now rolls
  every post-baseline migration back and forward before seeding, so fixture
  reversibility and migration-name warnings are continuously covered.

- **PostgreSQL-safe Blueprint constraint names**: Generated index and foreign-key
  names now use PostgreSQL's stored 63-byte identifier form in migrations,
  snapshots, and runtime changeset constraints. Long unique and foreign-key
  violations are therefore returned as changeset errors instead of raising an
  unmatched constraint exception. Existing databases need no migration:
  PostgreSQL already truncated these names when it created them, and Brando
  canonicalizes older Blueprint snapshots in memory without generating index or
  constraint churn.

- **Database-aligned callback collision scopes**: Arity-one Blueprint
  `prevent_collision` callbacks may now be combined with `with:` and `message:`.
  Persisted `with:` fields constrain the callback query, Ecto unique constraint,
  and generated database index together. Callback-only declarations remain
  globally unique. Message-only uniqueness and `prevent_collision: true` now
  generate valid single-column indexes, and `nil` composite scopes no longer
  raise while building a changeset. Existing callbacks that narrow candidates
  by persisted columns should add those columns to `with:` and run
  `mix brando.gen.blueprint_migration MyApp.Schema`; Igniter cannot infer the
  intended database scope.

- **Reliable Blueprint nested deletion**: Generated Blueprint changesets now
  short-circuit irrelevant validation when an opted-in schema receives
  `marked_as_deleted: true`. Persisted nested entries are deleted even if other
  submitted fields are invalid, while unsaved entries are ignored instead of
  causing Ecto to raise. The `changeset/5` API and stored schemas are unchanged;
  no Igniter or database migration is required.

- **Valid Blueprint uniqueness scopes**: `unique: [with: ...]` and
  `unique: [prevent_collision: ...]` now reject repeated scope columns and a
  scope that repeats the attribute or relation foreign key being made unique.
  This prevents invalid duplicate-column Ecto constraints and generated
  indexes. Valid Blueprint declarations and runtime APIs are unchanged; no
  Igniter or database migration is required.

- **Consistent Blueprint collection relation casting**: Required `has_many`,
  `many_to_many`, and `entries` relations now reject every supported empty form
  or API representation instead of only the empty string. Optional collections
  still clear normally. Many-to-many helpers accept atom- or string-keyed
  params and turn malformed or unresolved IDs into changeset errors rather than
  crashes or silent data loss. Blueprint declarations and changeset APIs are
  unchanged; no Igniter or database migration is required.

- **Fail-closed Blueprint and revision snapshots**: Migration snapshots now
  reject unknown future formats, malformed normalized storage schemas, invalid
  metadata, and filename/embedded-version mismatches before diffing. Revision
  blobs must decode to the recorded Blueprint type and entry ID before preview
  or restore, preventing a swapped blob from applying another entry's data. Old
  source-controlled Blueprint snapshots remain readable when they contain
  retired declaration or field-name atoms, but executable terms are rejected.
  Public APIs are unchanged, and this integrity hardening requires no Igniter
  upgrade or database migration.

- **Reliable scoped Blueprint collision handling**: Arity-one
  `prevent_collision` callbacks now receive the changeset and supply the
  candidate query as documented instead of being silently bypassed. Scoped
  collision checks also rerun when only a scope field changes, while persisted
  entries are excluded from colliding with themselves. The Blueprint DSL and
  changeset helper APIs are unchanged, and this correction requires no Igniter
  upgrade or database migration.

- **Safe mixed-container Blueprint value paths**: `fallback/2` and
  `try_path/2` now traverse each map, struct, keyword list, and indexed list
  according to the container at that path step. Mixed paths no longer raise
  when they enter a keyword list or ordinary list, and incompatible scalar/key
  combinations return `nil` as documented. False, zero, and empty-string values
  remain valid results. The existing helper API is unchanged and this runtime
  correction requires no Igniter upgrade or database migration.

- **Reliable Blueprint form error labels**: Save-error summaries now translate
  configured string labels and safely humanize the actual form field when its
  label is hidden, blank, nil, or otherwise non-text. Foreign-key errors use the
  visible relation/asset field name (`Cover video`) instead of leaking generated
  storage names such as `Cover_video_id`; unknown keys also use normal humanized
  text. Existing form and translation APIs are unchanged, and no Igniter
  upgrade or database migration is required.

- **Complete Blueprint relation preloads**: `Brando.Blueprint.preloads_for/2`
  now includes direct `has_one` relations, so complete entry loads no longer
  leave those associations unloaded. Cast `has_many` preload queries also
  preserve an explicitly declared `preload_order`; sequenced child schemas only
  fall back to ascending `sequence` when no order is configured. The public
  preload APIs and declaration syntax are unchanged. This affects query loading
  only and requires no Igniter upgrade or database migration.

- **Validated Blueprint asset declaration options**: Top-level asset options
  are now checked instead of silently ignoring misspellings such as
  `requried: true`. The stable `cfg` and `required` options remain unchanged;
  galleries also retain their existing Ecto cast-message and
  `force_update_on_change` options. Clearing a required gallery now emits the
  standard required error and honors `required_message` instead of reporting a
  generic invalid association. This is a compile-time/runtime validation fix:
  correct any newly reported option typo, but no API rename, Igniter upgrade,
  or database migration is required.

- **Required Blueprint collection relations**: Cast `has_many`, `many_to_many`,
  and `entries` relations declared with `required: true` can no longer be
  cleared through an empty form value while leaving the changeset valid. They
  now emit the standard required error (including a configured
  `required_message`); optional collections retain their existing
  clear-to-empty behavior. This is a runtime validation correction only: no
  Blueprint API change, Igniter upgrade, or database migration is required.

- **Generated Blueprint schema types**: Blueprint schemas now export the
  conventional `t/0` struct type automatically, eliminating missing-type
  warnings for contexts and media APIs. An application-defined `t/0` remains
  authoritative and is never replaced. This is a compile-time typing
  improvement only: no application code change, Igniter upgrade, or database
  migration is required.

- **Unified Blueprint asset config-target resolution**: Static asset DSL
  declarations, deferred asset functions, and `config_target` functions now
  share one normalizer and validator. Function targets return typed configs
  with defaults merged, reject declaration-only sentinels and wrong config
  structs, and field targets can no longer resolve an asset of a different
  media type. The upload facade safely falls back to the typed default config
  and rewrites invalid targets to `"default"`. This is a runtime correctness
  change only: no Ecto migration or Igniter upgrade script is required.

- **Validated Blueprint asset configuration contracts**: Image, file, video,
  and per-media gallery configs now reject invalid runtime-critical fields with
  asset-specific errors, including malformed paths, limits, MIME lists,
  booleans, image formats, video strategies, and completion callbacks. Deferred
  config functions are validated when materialized. `completed_callback` now
  consistently accepts arity-2 functions or MFA tuples and runs when files are
  stored, images finish processing (including SVG), local videos are stored, or
  Mux/Bunny videos first become ready; metadata edits no longer re-fire file
  completion. Bunny is also accepted by the persisted video enum. Completion
  work may retry, so callbacks with external side effects should be idempotent.
  This changes no database storage: no Ecto migration or Igniter upgrade script
  is required. Compile after upgrading, correct reported configs, and see
  [Blueprints](guides/blueprints.md) and [Uploader](docs/UPLOADER.md).

- **Reliable Blueprint form runtime contracts**: Static form query maps now work
  as declared, retain the URL entry ID in `:matches`, and are checked for invalid
  match shapes; callback queries fail with a clear error when they do not return
  a map. Form alerts now execute the advertised function-component and MFA forms
  with documented form context assigns instead of passing callback tuples to the
  translation layer. This is a runtime and DSL correction only: no Ecto migration
  or Igniter upgrade script is required. Compile after upgrading, fix any static
  query whose `:matches` is not a map, and see [Blueprints](guides/blueprints.md).

- **Validated secondary Blueprint DSL contracts**: Datasources now require the
  callbacks their type consumes, execute the function-or-MFA forms advertised by
  Spark, and reject duplicate datasource or metadata keys. Form query/save/redirect
  MFA callbacks use the same reusable runtime boundary. Metadata and JSON-LD now
  reject multiple silently ignored schemas; JSON-LD also validates root structs,
  fields, callback requirements, and nested `build/1` modules while safely handling
  absent schemas and optional dates. Listings validate runtime-consumed keys,
  limits, filters, sorts, actions, exports, and child-listing links, and documented
  active filter defaults now reach the initial query. Translation declarations can no
  longer silently overwrite duplicate contexts or keys. These are DSL/runtime
  corrections only: no Ecto migration or Igniter upgrade script is required.
  Compile after upgrading, fix reported declarations, and review configured listing
  defaults because they now take effect. See [Blueprints](guides/blueprints.md).

- **Correct generated Blueprint join owners**: Generated `:blocks` and
  `:entries` join schemas now use the actual Blueprint owner module for their
  Ecto associations instead of the convention-derived schema target retained in
  `__modules__()` for resource generation. This fixes nested and legacy schema
  locations without changing module registry conventions or database storage,
  so no migration is required.

- **Validated Blueprint root configuration**: `use Brando.Blueprint` now rejects
  missing, duplicate, and unknown options plus malformed application/domain/schema
  and singular/plural names before macro setup. The semantic verifier also checks
  table names, data layers, factories, mark-as-deleted flags, naming overrides,
  and primary-key representations before Ecto schema generation. Blueprint
  primary keys are explicitly limited to the canonical integer `id`, UUID, or an
  intentional disabled key because generated relations and migration snapshots do
  not support arbitrary Ecto primary-key layouts. These checks need no database
  migration by themselves; fix declarations reported during compilation. If a
  correction changes an existing table or primary key, deploy a hand-written
  migration and use the documented rebaseline workflow in
  [Blueprint migrations](guides/blueprint_migrations.md).

- **Consistent Blueprint schema and relation validation**: Custom `belongs_to`
  foreign keys now use one canonical field across casting, required validation,
  unique constraints, foreign-key constraints, generated schemas, and migration
  metadata; custom constraint names are also preserved in changesets. Blueprint
  compilation now rejects non-boolean `required`/`virtual`/`define_field`
  options, invalid relation storage options, unsupported relation constraints,
  uniqueness scopes that reference non-persisted fields, unique virtual fields,
  collision callbacks with the wrong arity, and declarations that collide with
  the implicit primary key. Bare array attributes are rejected in favor of
  `{:array, type}`, and Blueprint `:uuid`/`:timestamp` attributes now map to valid
  Ecto runtime types. Form error lookup now handles all foreign-key-backed inputs
  while preferring exact `_id` field names. No database migration is required
  when the existing database already matches the declared custom key.
  If fixing a reported declaration changes a column, foreign key, or unique
  index, generate and review a Blueprint migration; see
  [Blueprint migrations](guides/blueprint_migrations.md) and the relation notes
  in [Blueprints](guides/blueprints.md).

- **Safer Blueprint identifier and URL templates**: Invalid Liquid syntax in
  `identifier` and `absolute_url` declarations now raises a contextual
  `BlueprintError` with the setting, parser reason, and line number instead of an
  opaque match error. Identifier titles now consistently trim outer whitespace,
  language values are checked against the schema's `Ecto.Enum`, content images
  reliably take precedence over the SEO `meta_image` fallback, and the legacy
  identifier field extractor no longer raises or creates atoms for unknown/deep
  paths. `persist_identifier` also rejects non-boolean values explicitly. No
  database migration is required. When upgrading, fix any malformed Liquid
  templates and invalid language values reported during compilation or identifier
  generation; run `mix brando.identifiers.sync` only if normalized title
  whitespace should be reflected in already persisted identifiers.

- **Blueprint form and transformer validation**: Blueprint compilation now reports
  unknown form fields, invalid `source`/`hidden` references, duplicate inputs,
  missing subform relations, relation/cardinality mismatches, invalid nested
  fields, misconfigured block inputs, and invalid transformer assets. The
  documented `{:transformer, field}` and mixed-media
  `{:transformer, [image_field, video_field]}` styles now compile correctly;
  transformer metadata is computed once by the DSL instead of rescanning the form
  tree during every admin save flow, missing defaults create the related struct,
  and uploads use canonical asset config targets. No database migration is
  required. When upgrading, compile with warnings as errors and fix reported form
  references; transformer defaults must be a map/struct or an arity-2 function,
  listings must be arity-1 function components, and transformer relations must be
  `:has_many`/`:embeds_many` with `cardinality: :many`.

- **Clearer Blueprint metadata extraction**: Meta schema evaluation now separates
  schema lookup, field evaluation, target expansion, and missing-value handling
  into focused functions with an explicit public contract. Single and multi-target
  fields retain their existing order; nil results and missing-key reads are omitted
  as before. No application or database migration is required.

- **Focused Blueprint DSL code generation**: Blueprint schema compilation now
  composes small, responsibility-specific AST fragments for state, traits, routes,
  module metadata, fields, schemas, forms, changesets, and trait implementations.
  This replaces the monolithic compiler quote without changing generated schema
  APIs, and removes dead generated alias/module setup. The change is internal and
  requires no application or database migration.

- **Reliable Blueprint migration relation introspection**: Migration generation
  now loads referenced schema modules before reading their table and primary-key
  metadata. Fresh Mix processes no longer reject valid unloaded Ecto schemas or
  silently fall back to integer keys for UUID references. Generated migration APIs
  are unchanged, and no application or database migration is required.

- **Safe Blueprint template preload extraction**: Identifier and absolute URL
  templates now detect arbitrarily deep declared relation paths without converting
  template text to atoms. Unknown nested paths are ignored instead of potentially
  failing schema compilation with `ArgumentError`. Existing preload metadata and
  template APIs are unchanged, and no application or database migration is required.

- **Isolated Blueprint changeset runtime**: Generated schema changesets now execute
  casting, trait mutation, uniqueness, constraint, relation, asset, and block processing
  through the focused `Brando.Blueprint.ChangesetRunner`. This keeps runtime pipeline
  changes out of the compile-connected `Brando.Blueprint` facade. Existing
  `Brando.Blueprint.run_changeset/1`, `maybe_sequence/3`, and
  `maybe_validate_required/2` calls remain compatible. No application code or database
  migration is required.

- **Blueprint runtime routing boundary**: Generated admin routes, absolute URLs,
  localized paths, form redirects, and language attribute defaults now resolve
  configuration through the lightweight `Brando.RuntimeConfig` module instead of
  depending on the top-level `Brando` application facade. Existing `Brando.endpoint/0`,
  `Brando.helpers/0`, `Brando.routes/0`, and `Brando.gettext/0` calls remain compatible.
  No application code or database migration is required.

- **Cycle-safe Blueprint configuration reads**: Brando's User Blueprint now resolves
  its compile-time administrator languages through `Brando.RuntimeConfig`, completing
  the lightweight configuration boundary without pulling the application supervisor
  into schema compilation. Custom Blueprints that evaluate `Brando.config/1` in DSL
  declarations may make the same optional replacement with
  `Brando.RuntimeConfig.get/1`; runtime calls remain compatible and no database
  migration is required.

- **Granular Blueprint listing components**: Custom rows can now import the
  lightweight `Brando.Blueprint.Listings.Components.Core` module and opt into
  `Cover` or `Children` only when needed. Brando's own schemas use these narrow
  imports, preventing simple grid/link rows from inheriting image and hierarchical
  admin component trees. The original `Brando.Blueprint.Listings.Components`
  import remains fully compatible; migration is optional and no database change
  is required.

- **Cycle-safe listing image rendering**: Blueprint covers now render through a
  focused admin image component backed by lightweight image metadata, config-target,
  and URL resolvers. `Brando.Images`, `Brando.Images.Utils`, `Brando.Utils`, and
  `BrandoAdmin.Components.Content` retain their existing public APIs as wrappers,
  while schema compilation no longer traverses the database Images context or the
  general admin content tree. No application code or database migration is required.

- **Cycle-safe child-listing actions**: Blueprint `<.children_button>` helpers now
  render a lightweight stateless control and target the owning listing row directly.
  The row validates submitted association names against the entry before toggling,
  and sticky LiveView JS preserves the button's visual and accessibility state across
  patches. Existing helper calls and the legacy internal LiveComponent remain
  compatible; no application code or database migration is required.

- **Isolated trait schema compilation**: Blueprint traits may now use the explicit
  `compile_with:` option to run `generate_code/2` through a focused compiler module,
  keeping schema expansion independent of runtime-heavy trait callbacks. The option is
  removed from the runtime trait configuration. `Brando.Trait.Sequenced` selects its
  built-in compiler automatically, and the equivalent `trait :sequenced` shorthand
  avoids a module-body dependency on the runtime trait. Brando's schemas use the new
  shorthand; the full module syntax, callbacks, and public sequencing functions remain
  supported. Custom traits are unchanged unless they opt in; no application code or
  database migration is required.

- **Isolated Status trait compilation**: `Brando.Trait.Status` now uses the focused
  trait compiler boundary, and Brando's schemas use the equivalent `trait :status`
  shorthand to avoid pulling identifier and content-cascade runtime dependencies into
  schema compilation. The full module syntax and public status API remain supported;
  applications may migrate incrementally, and no database migration is required.

- **Isolated Timestamped trait compilation**: `Brando.Trait.Timestamped` now expands
  schema attributes through a focused compiler module, and Brando's schemas use the
  equivalent `trait :timestamped` shorthand. Existing full module declarations remain
  supported, so applications may migrate incrementally. This is a compile-time-only
  change and requires no database migration.

- **Isolated Creator trait compilation**: `Brando.Trait.Creator` now expands its
  required creator relation through a focused compiler module, while runtime changeset
  mutation remains on the trait. Brando's schemas use the equivalent `trait :creator`
  shorthand. Existing full module declarations remain supported for incremental
  adoption; no database migration is required.

- **Isolated SoftDelete trait compilation**: `Brando.Trait.SoftDelete` now expands its
  `deleted_at` attribute through a focused compiler module, and Brando's schemas use the
  equivalent `trait :soft_delete` shorthand without changing trait options or runtime
  behavior. Existing full module declarations remain supported for incremental
  adoption; no database migration is required.

- **Isolated Translatable trait compilation**: `Brando.Trait.Translatable` now expands
  language metadata and optional alternate schemas through a focused compiler module,
  and Brando's schemas use the equivalent `trait :translatable` shorthand. Alternate
  configuration and the existing full module declarations remain supported for
  incremental adoption; no database migration is required.

- **Completed built-in trait compiler boundaries**: `Brando.Trait.Meta` and
  `Brando.Trait.ScheduledPublishing` now expand schema metadata through focused compiler
  modules, while AI configuration and publish-time callbacks remain on their runtime
  traits. Brando's schemas use `trait :meta` and `trait :scheduled_publishing`;
  existing full module declarations remain supported for incremental adoption. No
  database migration is required.

- **Runtime-only trait compiler boundary**: Traits that inject no Blueprint schema code
  may use the reusable `Brando.Trait.NoopCompiler` while retaining validation,
  changeset, and save callbacks. Brando's `EnsureUID` and `ValidateVarKeys` traits select
  it automatically, and the new `trait :ensure_uid` and `trait :validate_var_keys`
  shorthands avoid module-body runtime trait dependencies. Existing full module
  declarations remain compatible and no application or database migration is required.

- **Isolated admin form LiveView compilation**: `BrandoAdmin.LiveView.Form` now delegates
  setup to focused internal compiler and hook modules, keeping the large runtime hook
  implementation out of application compile graphs. The public
  `use BrandoAdmin.LiveView.Form, schema: ...` declaration is unchanged. Runtime
  behavior, routes, and database schemas are unchanged, so no code migration, Igniter
  upgrade, or database migration is required.

- **Isolated admin listing LiveView compilation**: `BrandoAdmin.LiveView.Listing` now
  delegates setup to focused internal compiler and hook modules, keeping runtime listing
  hooks out of application compile graphs. The public
  `use BrandoAdmin.LiveView.Listing, schema: ...` declaration is unchanged. Listing
  behavior, routes, and database schemas are unchanged, so no code migration, Igniter
  upgrade, or database migration is required.

- **Isolated context query compilation**: `Brando.Query` now delegates macro expansion
  and query execution to focused internal compiler and runtime modules, so Blueprint
  contexts do not compile against the runtime query engine. The public
  `use Brando.Query` declaration and runtime functions are unchanged. Query behavior and
  database schemas are unchanged, so no code migration, Igniter upgrade, or database
  migration is required.

- **Symbolic built-in subform components**: Blueprint `inputs_for` definitions can now
  use `:vars`, `:gallery_objects`, `:identity_type_config`, or `:page_vars` instead of
  concrete admin LiveComponent modules. Brando's schemas use these tokens, which are
  resolved only at the render boundary and keep admin editor trees out of schema
  compilation. Custom modules and existing full module values remain supported; no
  database migration is required.

- **Lighter Blueprint listing rendering dependencies**: Listing helpers now use
  focused `Brando.HTML.Icon` and `Brando.HTML.I18n` components instead of depending
  directly on the full `Brando.HTML` module. The existing `Brando.HTML.icon/1` and
  `Brando.HTML.i18n/1` APIs remain as compatibility wrappers, so applications need
  no code or database migration.

- **Explicit Blueprint listing component imports**: `use Brando.Blueprint` no longer
  imports `Brando.Blueprint.Listings.Components` into every schema. Blueprints with
  custom listing row functions should add
  `import Brando.Blueprint.Listings.Components.Core`; schemas without custom rows need
  no change. Add the opt-in `Cover` or `Children` import when the row uses `<.cover>`
  or `<.children_button>`. Search for `<.cover>`, `<.url>`, `<.update_link>`,
  `<.field>`, `<.children_button>`, or `<.i18n>` inside Blueprint modules to identify
  consumers, add the imports directly after `use Brando.Blueprint`, then compile. The
  compatibility facade remains available. No database migration is required.

- **Block editor single-owner state (the clobber class is gone)**: Each block
  live_component now owns its editing state exclusively. After first mount, parent
  re-renders can no longer overwrite a block's form (`update/2` drops incoming
  `form`/`children` assigns), forms never travel between components (the
  `send_form_to_parent`/`update_block` push-up/push-down protocol and the `propagate`
  flag are deleted), and the O(n) position-ack handshake is gone — sequence derives
  from list order at save materialization, blocks receive their current position as a
  `list_index` prop, and structural changes refresh the live preview directly. The
  historical "sibling edit/FK wiped by a stale cached form" bug class is now
  structurally unrepresentable.

- **Block editor docs truth pass**: New `guides/block_editor.md` (wiring blocks into a
  blueprint, frontend rendering, modules/refs/vars/containers, editor state model and
  debugging notes). CLAUDE.md's obsolete changeset-propagation section replaced with
  the single-owner/ops architecture rules; UPLOADER.md delivery targets updated to the
  op model; real `@moduledoc`s on `BlockField` and `Block` documenting state ownership;
  `Block.commit_ref_data/2` no longer sends the dead `propagate` flag.

- **Block editor multi-user sync ships op snapshots**: When an editor blurs a block,
  its subtree diff snapshot (param diffs + structure — never changesets) is broadcast
  straight from the op store and merged into other editors' stores, then handed to
  their mounted components via the `replace_form` cascade. Child-block edits now sync
  too (the old changeset-shipping path only ever covered root blocks), remotely
  inserted children attach on receive, and a received edit can no longer be lost by
  the receiver's next save. The dead prefab-template button in the empty-blocks state
  (its handler never existed) was removed.

- **Block editor op layer (strangler phase)**: Every structural/content mutation in
  the block editor (insert, duplicate, paste, delete, reorder, content commits, remote
  sync, reconnect recovery) is now mirrored through named operations applied by a pure
  reducer (`BlockField.Ops`) holding the full block tree: root order, parent/child
  structure, and a uid-keyed param-diff store. Blocks at any nesting level emit ops
  directly to their owning BlockField at every commit point (the `assign_block_form`
  chokepoint), so the store stays save-complete without form propagation.
  **Save, live preview and share all materialize from the op store**: one pass over
  the store builds every root changeset directly in BlockField — the recursive
  fetch/provide gather protocol across the component tree is deleted entirely (the
  shadow-compare phase validated the store against gathered changesets, 34/34
  identical, before the flip). After a save, a `replace_form` cascade re-seeds every
  mounted block with the freshly persisted data (new db ids) — the only sanctioned
  parent→child form handoff after mount, covered by a new save-and-continue e2e spec.
  Also fixes a bug where deleting a child block rebuilt the parent's form with the
  deleted child's uid in the form id.

- **Block editor keyed block list**: The root block list is now rendered with a keyed
  `:for` comprehension (`:key` on block uid), matching the already-keyed child lists.
  LiveView diffs blocks by identity instead of list index, so inserting, deleting or
  reordering blocks no longer forces a re-render of every index-shifted sibling.
  Root-block drag reordering switched to SortableJS fallback dragging
  (`forceFallback: true`, like every other sortable in the admin) and gained e2e
  regression specs — reorder + preview refresh + persistence were previously uncovered.

- **Block editor typing latency**: Validating a block no longer runs a full Villain
  render (plus an HTML-formatter pass) per debounced keystroke while live preview is
  closed — rendering is gated on the preview being open, and pretty-printing was
  dropped from the editor path entirely. Entry-field keystrokes likewise no longer
  re-render entry-consuming blocks with the preview closed.

- **Liquex parse cache**: Parsed Liquid documents for module/container templates are
  cached in ETS keyed by template hash (mirroring the HEEx renderer's compile cache),
  so constant templates parse once per code version instead of on every render.
  `Villain.render_block/3` also now copies only the cached lists the block type
  actually consumes out of Cachex (one list for module blocks instead of four).

- **Block tree loading**: The hand-unrolled per-level `children` preloads (~25 queries
  per nesting level, hard-capped at 4 levels) were replaced with a recursive-CTE
  function preload plus one batched preload pass — fewer queries on every form open
  and post-save reload, and no more nesting-depth cap.

- **Save write amplification**: Editor-stamped `rendered_html`/`rendered_at` changes
  are stripped from block changesets at save assembly. Opening live preview previously
  dirtied every block row, turning a one-block edit into an UPDATE per block.

- **Block editor shared helpers**: One-shot media commits (select / reset /
  upload-complete / image-editor) now route through `Block.commit_ref_data/2`, which
  hardwires the required cache propagation so it can no longer be forgotten by
  copy-paste. The duplicated block-data-map, media-resolution, crop-group, and
  image-editor-open logic across picture/video/gallery/map blocks was extracted into
  shared `Block`/`Form` helpers (net ~230 lines removed).

- **Villain render pipeline**: Use iodata lists instead of string concatenation for
  improved rendering performance.

- **Extract Content.Blocks from Villain**: Clean rendering boundary separating content
  block management from the Villain rendering pipeline.

- **Imagequant for dominant color**: Replaced previous dominant color extraction with
  imagequant for more accurate results.

- **Live preview optimizations**: Fixed cache bugs, added compile-time assets, and
  general cleanup for better live preview performance.

- **SameSite/Secure cookies**: Set `SameSite` and `Secure` attributes on cookies.

- **CI matrix**: Drop OTP 26, add Elixir 1.19/1.20 + OTP 28/29.

#### Dependencies

- Bumped `phoenix` to `1.8.8` and `phoenix_live_view` to `1.2.3`. Both are pinned exactly,
  so when upgrading also pin `phoenix_live_view` to `1.2.3` in your `assets/package.json`
  (and rebuild your backend assets) — LiveView warns when the JS client and server versions
  differ.
- Bumped `oban` to `~> 2.23`. The schema is upgraded to v14 via `brando_153` (see Migrations).
- Bumped `image` (0.69), `req` (0.6), `req_llm` (1.16), `sentry` (13.2), and `spark`, `tz`,
  `earmark`, `floki`, `html_sanitize_ex`, `credo`, `ex_doc`, `igniter`.
- Held `ecto`/`ecto_sql` at `3.13`: Ecto `3.14` requires `decimal ~> 3.0`, which `liquex 0.15`
  does not yet support.
- **`hackney` is no longer pulled in transitively.** `ex_aws` (now `~> 2.7`) only declares
  `hackney` as an *optional* dependency, and `fastimage` (which required `hackney`) has been
  dropped in favour of `image` + `vex`. If anything in your app relied on `hackney` being
  present, add it explicitly.

  In particular, **Swoosh** defaults to the Hackney API client and will now crash at boot
  with `(RuntimeError) missing hackney dependency`. Point Swoosh at Req instead (Req is
  already a dependency):

  ```elixir
  # config/config.exs
  config :swoosh, :api_client, Swoosh.ApiClient.Req
  ```

#### Security

- `config_target` strings are now resolved strictly (`Brando.Assets.ConfigTarget`):
  schema segments resolve through existing atoms only and must name a Brando
  blueprint module, and `<type>:<schema>:function:<fn>` targets only call
  functions the blueprint actually exports with arity 0. Previously a crafted
  target reaching `get_config_for/1` (e.g. via the upload manager's client
  `intake` event) could execute arbitrary zero-arity functions
  (`"file:System:function:halt"`) and mint unbounded atoms. **Breaking edge
  case:** config-function targets must now live on a blueprint schema module —
  plain helper modules are rejected.

#### Bug Fixes

- **E2E harness: two-user sessions + multi-user sync spec**: The Playwright auth
  fixture now exposes the per-test sandbox session as its own fixture plus a lazy
  `secondUserPage` (seeded second superuser) sharing the same sandbox — enabling
  true multi-user specs. New `block-multiuser-sync.spec.js` verifies the core sync
  guarantee end-to-end: user A's blurred block edit ships as an op snapshot, merges
  into user B's store, and B's untouched save persists A's edit — covered both from
  a fresh mount and directly after create + save-and-continue.

- **Collaboration arms on freshly created entries**: After create + save-and-continue
  (`push_patch` to the update route), the parent LiveView never assigned `entry_id`
  and the block field had no sync topic — presence, field sync and block sync stayed
  silently disarmed until a full reload. The entry scope now arms via a
  `handle_params` hook when the patched URL first carries an `entry_id`, and the
  block field subscribes its sync topic as soon as a persisted entry lands.

- **E2E harness: parallel preloads escaped the SQL sandbox**: In the sandboxed e2e
  server (`:auto` mode), Ecto's parallel preload Tasks are separate processes that
  silently get fresh connections outside the per-test transaction — preloads of
  just-written rows (e.g. a saved block's children) came back empty while the rows
  existed. `Brando.Repo` now forces `in_parallel: false` on reads when
  `config :brando, :sql_sandbox_serial_preloads` is set (e2e only; no-op in dev/prod).
  New `block-nested-child-persistence.spec.js` drives nested-child insert/edit/delete
  through the UI with save + reload (2 specs; blocks suite now 58).

- **Nested child blocks at save (three compounding bugs)**: A new DB-level regression
  suite for the materialized save path (insert/edit/delete/cross-parent-move of nested
  children through a real save) uncovered a chain of latent bugs: (1) the save cast ran
  the non-recursive block changeset, which silently drops all `children` params — edits
  to nested blocks did not persist; (2) `recursive_block_changeset` never forced
  `:insert` for new (nil-id) blocks, so fixing (1) made every new-block save crash with
  `NoPrimaryKeyValueError` (both changeset variants now share the new-block
  finalization); (3) children loaded through the recursive-CTE tree preload kept
  `__meta__.source: "block_descendants"`, so deleting one issued a DELETE against a
  nonexistent table; (4) materialization dropped the `"children"` key when a parent's
  child list became empty, so deleting a parent's last child (or moving its only child
  elsewhere) never persisted — the tree is authoritative and now always emits
  `children`. `strip_render_artifacts` also no longer feeds `:replace`/`:delete`
  children back into `put_assoc` (Ecto raises).

- **Video block reset button**: The `reset_video` handler (reset to the ref's template
  defaults) existed but no button invoked it — wired into the video block's action
  button group alongside the cover-image reset.

- **Video/map block media loss**: several video block commits (`select_video`,
  `video_created_from_url`, cover-image select/reset, override resets) and the map
  block's embed-URL commit did not propagate to the parent's cached form, so a
  subsequent block insert/delete silently wiped the just-set `video_id` / embed URL.
  All media commits now propagate (and route through `Block.commit_ref_data/2`).

- **Map block crashed the form**: inserting a map block crashed the entire form
  LiveView — `Villain.Parser.map/2` had no clause for an unconfigured map (no embed
  URL yet) and the editor's validate-time render hit it immediately. An empty
  fallback clause was added, matching the other media parsers.

- **Upload manager audit fixes**: consume-time storage errors (e.g. mimetype
  rejections) no longer crash the sticky manager and kill in-flight uploads;
  server-transport files on CDN-enabled sites are queued for CDN push at consume
  (parity with `save_file`); nested (subform) image fields receive their
  processed-image updates again; client-direct uploads honor the folder browser's
  `folder_id` and a replayed completion can't create duplicate `File` rows;
  local-video uploads no longer break when the configured video `default_config`
  is a plain map; rejected files show an error item in the drawer instead of
  disappearing silently; transfer slots can no longer leak (wedging the queue);
  failed image processing marks the drawer item as errored instead of pinning it
  at "Processing…"; the file drawer resolves the correct config for
  nested/subform file fields.
- **Known limitation (upload manager)**: dynamic `upload_path` (function form) in
  gallery asset opts is not honored by the manager upload path — the old
  per-field handler resolved it, the manager stores under the config's static
  `upload_path` (see docs/UPLOADER.md).
- Fixed `@context` inconsistency (`http` vs `https://schema.org`).
- Breadcrumb URLs are now absolute (via `hostname/1`).
- Fixed `PostalAddress.addressRegion` incorrectly mapping to `city` instead of `region`.
- Fixed `CreativeWork.build/1` stub that logged errors and returned empty struct.
- Added `image` field to Page's `json_ld_schema` using `meta_image`.
- Fixed block recovery triggering on fresh navigation.
- Transfer content when deleting user instead of leaving orphaned records.
- Form inputs now render their `placeholder` attribute. It was silently dropped because
  `placeholder` was missing from the `:global` include list on the shared input component.
- Oban workers `EntryRenderer` and `EntryCascade` now use the `:incomplete` unique state group.
  The previous `[:available, :scheduled]` list left lifecycle gaps that silently failed to
  deduplicate in-flight jobs (Oban 2.23 now warns about this at compile time).
- A freshly picked picture or video ref no longer disappears from the live preview when another
  part of the same block is edited. After a `validate_block` rebuild the ref's `image`/`video`
  association comes back as `%Ecto.Association.NotLoaded{}` (the `image_id`/`video_id` is
  preserved). The Villain parser only used the association when it was a loaded struct, so the
  `NotLoaded` case fell through to the "has media" branch and rendered nothing. Both the picture
  and video clauses now normalize `NotLoaded` to `nil` and refetch by id, mirroring
  `resolve_gallery_assoc/2`.
- Picture ref's empty-state "Pick an existing image" button now opens the image drawer directly
  instead of opening the config modal first.

#### Documentation

- Rewrote `guides/jsonld.md` with complete guide covering `@graph` output, DSL field types,
  list type, controller usage, WebPage types, identity type-specific fields, and custom schemas.

#### Migrations

- `brando_150`: Adds `type_config` (jsonb) to `sites_identities`.
- `brando_151`: Adds `json_ld_type` (string, default "WebPage") to `pages`.
- `brando_152`: Adds `breadcrumbs` (jsonb, default `[]`) to `pages`.
- `brando_153`: Upgrades the Oban schema to v14 (required by Oban 2.23). Run
  `mix brando.upgrade && mix ecto.migrate` to bring in the migration.

  **BREAKING (only if you deploy with the bundled `fabfile.py` / Fabric):** the v14
  Oban migration runs `ALTER TYPE oban_job_state ...`, which Postgres only permits the
  *owner* of the type to do. If your database objects were created by a different role
  than the one running migrations (the common case when deploying with the bundled
  `fabfile.py`, where `postgres` owns the objects and the app role runs migrations), the
  migration fails with `ERROR 42501 (insufficient_privilege) must be owner of type
  oban_job_state`. The `grant_db` task in `fabfile.py` has been updated to also reassign
  ownership of enum types (it previously only covered tables, sequences, functions, and
  views). If you use Fabric, update your project's `fabfile.py` to match and run
  `fab <env> grant_db` before migrating. Otherwise, run once as a superuser:
  `ALTER TYPE public.oban_job_state OWNER TO <your_app_db_user>;`

- `brando_156`: Adds `new_row` (boolean) and `placement` (string) to `content_vars`
  and drops `important`. Existing vars are migrated by value — `important: true`
  becomes `placement: "content"`, everything else `placement: "config"` — and every
  var gets `new_row: true`, which reproduces the old one-var-per-row rendering.
  No layout is lost; rows are opt-in from there.

- **HEEx support for `identifier` and `absolute_url`**: Both macros now accept `~H` templates
  as an alternative to Liquex templates.

  ```elixir
  identifier ~H"{@entry.title} [{@entry.category.name}]"
  absolute_url ~H"/projects/{@entry.category.slug}/{@entry.slug}"
  ```

  Association references are automatically extracted for preloads.

- **Identifier preloads**: Added `__identifier_preloads__/0` to blueprints, matching the
  existing `__absolute_url_preloads__/0`. Associations referenced in identifier templates
  are now automatically detected.

#### Features

- **Villain text styles API**: Added `styles` to `Brando.Villain.Blocks.TextBlock.Data` for configurable text style presets.
  - Supports styled node elements: `p`, `h1`-`h6`
  - Supports styled inline elements: `span`
  - Includes normalization, validation, and deduplication for style definitions
- **TipTap style integration**: Text block editor now reads `data-tiptap-styles` and renders style actions in the toolbar.
- **Module text ref defaults**: Creating a new text ref in Module Form now initializes default styles with a `p.lede` preset.
- **AI form input generation**: Added `ai: [...]` support for `:text`, `:textarea`, and `:rich_text` inputs with server-side generation via `ReqLLM`.
  - Shows an AI action button in inputs only when configured
  - Updates form fields server-side and keeps block/live-preview synchronization
  - Supports context fields including rendered `:blocks`
  - Supports Meta drawer fields (`meta_title`, `meta_description`) by reusing blueprint input opts
  - Adds trait-provided AI defaults (`Brando.Trait.ai_field_opts/3`) with Meta trait support
    for `trait Brando.Trait.Meta, ai: [...]`

#### Documentation

- Added guide: `guides/villain_text_styles.md`.
- Added AI input docs to `guides/blueprints.md` and `Brando.Blueprint.Forms` module docs.

#### Tests

- Added tests for `styles` normalization/validation/defaults in `test/brando/villain/blocks/text_block_test.exs`.
- Added Module Form test ensuring text refs initialize with default styles in `test/brando_admin/live/content/module_form_live_test.exs`.
- Extended existing parser/ref tests to cover styled text and style propagation.
- Added `Brando.AI` config-resolution tests in `test/brando/ai_test.exs`.
- Added AI input rendering tests for `meta_description` in `test/brando_admin/components/form/input_test.exs`.

### Features

- **Advanced Listing Filters**: Added support for boolean switches and select dropdowns in listing filters.
  - New filter types: `:boolean` (toggle switch) and `:select` (dropdown)
  - Boolean filters appear as toggle switches below the header
  - Select filters support both static options (nested DSL) and dynamic options (function)
  - All filter state is stored in URL params for shareability

  ```elixir
  listings do
    listing do
      # Text filter (keyword form)
      filter(label: "Title", key: "title")

      # Boolean switch (keyword form)
      filter(label: "Featured only", key: "featured", type: :boolean, default: false)

      # Select with static options (block form)
      # NOTE: When using block form, ALL properties must be inside the block
      filter do
        label "Category"
        key "category_slug"
        type :select
        default nil

        option "All", nil
        option "News", "news"
      end

      # Select with dynamic options (block form)
      filter do
        label "Author"
        key "author_id"
        type :select
        options &__MODULE__.list_authors/1
      end
    end
  end
  ```

- **Conditional form visibility**: Added `hidden` rules for form inputs.
  - Supports `hidden: true | false`
  - Supports `hidden: {:field_name, expected_value}`
  - Supports `hidden: fn form -> boolean end`
  - Tuple rules compare atom/string values as equivalent (`:full_case` and `"full_case"`)

- **Media and gallery workflow improvements**
  - Added video support in galleries
  - Added gallery listing and improved gallery admin UX
  - Added interactive image editor with live crop previews
  - Added image editor access from picture and gallery blocks
  - Added compact image input variant for subforms

- **Upload and preview improvements**
  - Added non-blocking live uploads with real-time progress for picture blocks
  - Moved gallery blocks and image/file vars to LiveView uploads
  - Added LivePreview recovery and improved shared preview metadata handling
  - Upgraded `livepreview.js` integration with newer `morphdom` capabilities

- **Block editor and module tooling**
  - Moved block toolbar actions into a dropdown menu
  - Refactored block duplication internals and shared helpers
  - Included table templates in module export/import flows
  - Added a listing action to trigger block re-rendering

- **Runtime/infrastructure improvements**
  - Moved cascade and revision processing to background Oban jobs
  - Added listeners to generated mix templates
  - Standardized frontend template tooling on `pnpm`

### Fixes

- Prevented duplicate upload submissions caused by multi-triggered events.
- Fixed video rendering edge cases for `:upload` and `:external_file` types.
- Added HLS manifest parsing support in the video pipeline.
- Cleaned out invalid refs handling paths.
- Fixed duplicate ID generation in table/template related workflows.
- Added missing guards for relation updates when entries are absent.
- Fixed listing filter shortcut handling.
- Improved resilience in E2E and flaky test scenarios.

### Documentation

- Added form API docs for `hidden` input rules in `Brando.Blueprint.Forms`.
- Updated deployment guide and install/developer workflow documentation.

### Breaking Changes

- **Filter DSL field renamed**: In listing filters, the `filter:` field has been renamed to `key:` for clarity.
  - Before: `filter label: "Title", filter: "title"`
  - After: `filter label: "Title", key: "title"`

- **Video Type Migration**: The deprecated `Brando.Type.Video` has been replaced with `Brando.Videos.Video`. The video schema has been updated:
  - `source` field renamed to `type` (enum: `:upload`, `:external_file`, `:vimeo`, `:youtube`)
  - `url` field renamed to `source_url`
  - Added new fields: `title`, `caption`, `aspect_ratio`
  - Videos are now stored as separate database entities instead of embedded JSON
  - Video rendering components and parsers updated to use new schema
  - If you were using `Brando.Type.Video` in your code, update to use `Brando.Videos.Video`
  - Test data using video factories should use new field names (`type` instead of `source`)

- **Image processing backend update**: Replaced `sharp-cli` usage with Image/Vix processors. If you had custom sharp-based processing setup, migrate to Image/Vix-based processing.

- **`hackney` removed (Swoosh api_client)**: `hackney`/`tzdata` were dropped in favour of `tz` and
  `req`. Swoosh defaults its API client to hackney, so apps will fail to boot with
  `Could not find hackney dependency` / `missing hackney dependency`. Point Swoosh at the
  Req-based client (`req` is already a dependency) in `config/config.exs`:

  ```elixir
  config :swoosh, :api_client, Swoosh.ApiClient.Req
  ```

  (Your `config/test.exs` likely already sets `config :swoosh, :api_client, false`.)

#### 0.54 upgrade checklist

Follow the complete [Migrating to Brando 0.54](guides/migrating_to_054.md)
guide. The required order is:

1. Commit the existing application and back up the database and Gettext catalogs.
2. Update Brando, then run `mix brando.migrate54`. The task rewrites legacy
   unnamed and named `form` options, listing `filter:` keys,
   `Brando.Villain.list_villains/0`, root Docker digest commands, and font cache
   suffixes. It also fills missing single-Repo Brando and Swoosh Req
   configuration and is safe to rerun. It warns about the video-data, template,
   related-entry, Vite, custom admin-view, head, navigation, dependency-client,
   secure config-target, and Fabric/Oban changes that require manual
   application-specific decisions. When both legacy `deployment.cfg` and
   `fabfile.py` exist, it also creates a non-secret `florist.config.exs` without
   overwriting any existing Florist or Fabric files. Review the generated
   single/nginx deployment, password environment variables, persistent media
   symlink cutover, service configuration, backups, and rclone caveats in the
   migration guide before using it.
3. Review, format, compile, and test the source diff.
4. Run `mix brando.upgrade`, then generate or deliberately rebaseline each
   application's Blueprint storage history as documented in
   [Blueprint migrations](guides/blueprint_migrations.md).
5. Review and exercise every migration backward and forward before running
   `mix ecto.migrate`.
6. After migration, run `mix brando.entries.resave` and
   `mix brando.identifiers.sync`, then reconcile backed-up Gettext catalogs.

Do not use `--rebaseline` to avoid a required database migration. Existing
tables without Blueprint snapshots must be verified against the live database
before establishing their first baseline.

* BREAKING: Refs have been split out to their own table. Run `mix brando.upgrade` to get migrations.
  The refs structure has changed significantly:
  - Refs are now stored in a separate table with foreign keys to media
  - Picture refs: `{{ refs.my_image.data.data.path }}` becomes `{{ refs.my_image.path }}`
  - Gallery refs: `{{ refs.my_gallery_ref.data.images }}` becomes `{{ refs.my_gallery_ref.gallery.gallery_objects }}`
  - Video refs work similarly with direct property access

* BREAKING: Galleries now have `gallery_objects` instead of `gallery_images`. 
  In your templates: `{{ entry.my_gallery.gallery_images }}` becomes `{{ entry.my_gallery.gallery_objects }}`

* BREAKING: Change from `mix phx.digest` to `mix brando.digest` in your Dockerfile,
  if you're using Vite. This ensures we can properly use chunks without double
  loading. Ensure you have the latest version of Vite installed.

* BREAKING: Remove `?vsn=d` from your `fonts.css` and your preloaded `fonts` in `.head`

* BREAKING: Add `config :brando, repo_module: MyApp.Repo` to your `config/brando.exs`

* BREAKING: If you upgrade to Vite 5+, they have moved the default manifest directory to `.vite`.
  To fix, edit your `assets/front/vite.config.js` and replace `manifest: true`
  with `manifest: 'manifest.json`.

* BREAKING: Changed Listings dsl (moved to Spark). See full example in listings.md in guides.

* BREAKING: Changed JSON-LD dsl (moved to Spark). See full example in jsonld.md in guides.
  `json_ld_field` has been renamed to `field`

* BREAKING: Changed Meta dsl (moved to Spark). See full example in meta.md in guides.
  `meta_field` has been renamed to `field`

* BREAKING: Run `mix brando.identifiers.sync` to create missing identifiers,
  delete orphaned identifiers and update URLs

* BREAKING: If you are updating to the new block system, resave your entries:
  `mix brando.entries.resave`

* BREAKING: The new `gettext` update requires some changes to your code.
  Replace all occurrences of
      `import MyAppAdmin.Gettext`
  with
      `use Gettext, backend: MyAppAdmin.Gettext`

  Also update your app's `gettext.ex` from
      `use Gettext, otp_app: :my_app, priv: "priv/gettext/backend"`
  to
      `use Gettext.Backend, otp_app: :my_app, priv: "priv/gettext/backend"`

* BREAKING: Consolidated admin `Create` and `Update` views to `Form`. If you have
  any custom logic in your `Create` view, move this to your `Update` view and add a
  conditional check in your mount:
  ```
  if socket.assigns.live_action == :create do
    # ...
  end
  ```
  Then add a conditional check for the heading in your `render`:
  ```
  <%= if @live_action == :create do %>
    <%= gettext("Create project") %>
  <% else %>
    <%= gettext("Update project") %>
  <% end %>
  ```
  Then rename your `Update` view to (i.e.) `ProjectFormLive` and delete your `Create` view,
  finally change your routes in your `router.ex`:
  ```
  scope "/projects", MyAppAdmin.Projects do
    live "/projects", ProjectListLive
    live "/projects/create", ProjectFormLive, :create
    live "/projects/update/:entry_id", ProjectFormLive, :update
  end
  ```

* BREAKING: Simplified `:entries` (for related entries) -- removed the indirection
  of adding `_identifiers` to the assoc's name, so if you have
  ```
  relation :related_entries, :entries, constraints: [max_length: 3]
  ```
  in your code, there will be no auto generated `:related_entries_identifiers`. This means
  the `:related_entries` will be the join table between your schema and the identifiers table.
  ```
  identifiers = Enum.map(case.related_entries, &1.identifier)
  case_ids = Enum.map(case.related_entries, &1.identifier.entry_id)
  related_cases = Cases.list_cases!(%{matches: %{ids: ids}})

  # or
  identifiers = Enum.map(case.related_entries, &1.identifier)
  Brando.Content.get_entries_from_identifiers(identifiers, %{preload: [:categories, :cover]})
  ```

* BREAKING: `Brando.Villain.list_villains/0` is now `Brando.Villain.list_blocks/0`
* BREAKING: change `trait Brando.Trait.Villain` to `trait Brando.Trait.Blocks`
* BREAKING: remove old `data` attributes with type `:villain` and add has_many relation `:blocks`:

    relations do
      relation :blocks, :has_many, module: :blocks
    end

* BREAKING: added `url` field to identifiers. Go through your blueprints and ensure
  that `persist_identifier false` is set for all schemas you don't want to create identifiers for.

  Run `mix brando.identifiers.sync` to create missing identifiers, delete orphaned identifiers and update URLs

* BREAKING: added `link` type vars to navigation items. You can iterate menu items with some new components:
  ```
  <section :if={assigns[:navigation]} class="main">
    <ul>
      <.menu :let={item} menu={@navigation}>
        <li>
          <.menu_item :let={text} conn={@conn} item={item}>
            <%= text %>
          </.menu_item>
        </li>
      </.menu>
    </ul>
  </section>
  ```

* BREAKING: added `<.head>` component. Switch out your regular `<head>` in your frontend app with this to take advantage of properly ordered head elements:
  ```
  <.head
    conn={@conn}
    fonts={[{:woff2, "/fonts/MyFont-Regular.woff2?vsn=d"}]}
  >
    <:prefetch>
      <link href="//player.vimeo.com" rel="dns-prefetch" />
    </:prefetch>

    <link rel="shortcut icon" href="/ico/favicon.ico" />
    <meta name="format-detection" content="telephone=no" />
  </.head>
  ```

* Added `wrapped_labels` option to multi select.


## 0.53.0

* BREAKING: Switch out `import Phoenix.LiveView.Helpers` with `import Phoenix.Component`

* Upgrade deps:
  ```
  {:phoenix_live_view, "~> 0.20"},
  {:phoenix_live_dashboard, "~> 0.8"},
  ```

* BREAKING: If you upgrade to Vite 3, they suddenly output `admin/main.css` instead of `admin/admin.css`.
  To fix, edit your `assets/backend/vite.config.js` and replace `manifest: false`
  with `manifest: 'admin_manifest.json`. You can also add in a hash since we now use a manifest:
  ```
  entryFileNames: `assets/admin/admin-[hash].js`,
  chunkFileNames: `assets/admin/__[name]-[hash].js`,
  assetFileNames: `assets/admin/admin-[hash].[ext]`
  ```

* BREAKING: Svelte's Vite plugin is requiring type = module now so there are some changes to do:
  - Upgrade Vite + plugins > 4
  - Set `assets/backend/package.json` type to `module` -> `"type": "module"`
  - Rename `assets/backend/postcss.config.js` to `assets/backend/postcss.config.cjs`
  - Rename `assets/backend/europa.config.js` to `assets/backend/europa.config.cjs`
  - Upgrade `assets/backend` europacss to `> 0.12`

* BREAKING: Updated Sentry to 10.x. Add to your `Dockerfile` before mix release:

    RUN mix sentry.package_source_code
    RUN mix release

  Then remove the `included_environments` key from the `:sentry` config in `config/prod.exs``
  and copy the sentry cfg to other env configs you might want to enable sentry on,
  for instance `config/staging.exs`.

* BREAKING: Change Presence module — in your `lib/my_app/presence.ex`:

    use BrandoAdmin.Presence,
      otp_app: :my_app,
      pubsub_server: MyApp.PubSub,
      presence: __MODULE__

* To enable presence in your update forms, add `presences={@presences}` to your
  `Form` live components in update views:

  ```
  <.live_component module={Form}
    id="page_form"
    entry_id={@entry_id}
    current_user={@current_user}
    presences={@presences}
    schema={@schema}>
    <:header>
      <%= gettext("Edit page") %>
    </:header>
  </.live_component>
  ```

* BREAKING: Replace `<%= csrf_meta_tag %>` with ´<.csrf_meta_tag />`

* BREAKING: Switch out `<%= google_analytics(...) %>` calls in your code with
  `<.google_analytics code="...." />

* BREAKING: Dropped `use Phoenix.HTML` so your `error_tag` in `error_helpers.ex` won't
  work anymore. Check out https://github.com/phoenixframework/phoenix/blob/main/installer/templates/phx_web/components/core_components.ex for how to implement errors in the frontend.

* BREAKING: If updating frontend to Vite 5, you need to explicitly set the manifest path.
  So change `manifest: true`, to `manifest: 'manifest.json'`

* BREAKING: Rewritten `:entries` (related entries). Now stores identifiers in a table and
  references this table for related entries.

  Blueprint setup is same as before:

      relation :related_entries, :entries, constraints: [max_length: 3]

  and form setup:

      input :related_entries, :entries,
        label: t("Related entries"),
        sources: [{__MODULE__, %{preload: [], order: "asc title", status: :published}}],
        filter_language: true


* BREAKING: Datasources — *selection* list callback should return identifiers
  instead of entries, and the select callback itself receives identifiers as the
  sole argument:

  ```elixir
  selection :featured,
    fn schema, language, _vars ->
      Brando.Content.list_identifiers(schema, %{language: language})
    end,
    fn identifiers ->
      entry_ids = Enum.map(identifiers, & &1.entry_id)

      results =
        from t in __MODULE__,
          where: t.id in ^entry_ids,
          order_by: fragment("array_position(?, ?)", ^entry_ids, t.id)

      {:ok, MyApp.Repo.all(results)}
    end
  ```

* BREAKING: Updated `mix brando.upgrade` script. Copy the new script into
  your application:

  ```zsh
  $ cp deps/brando/priv/templates/brando.install/lib/mix/brando.upgrade.ex lib/mix/brando.upgrade.ex
  ```

* BREAKING: Deprecated `:many_to_many` for now. This might return later if
  there's a usecase for it. Right now it is replaced by `:has_many` `through`
  associations instead.

  Before:

  ```elixir
  relation :contributors, :many_to_many,
    module: Articles.Contributor,
    join_through: Articles.ArticleContributor,
    on_replace: :delete,
    cast: true
  ```

  After:

  ```elixir
  relation :article_contributors, :has_many,
    module: Articles.ArticleContributor,
    preload_order: [asc: :sequence],
    on_replace: :delete_if_exists,
    cast: true

  relation :contributors, :has_many,
    module: Articles.Contributor,
    through: [:article_contributors, :contributor],
    preload_order: [asc: :sequence]
  ```

  If you use the `ArticleContributor` schema for a multi select, you must
  add `@allow_mark_as_deleted true` to this schema. Also you need to add a
  `relation_key` to the input declaration:

  ```elixir
  input :article_contributors, :multi_select,
    options: &__MODULE__.get_contributors/2,
    relation_key: :contributor_id,
    resetable: true,
    label: t("Contributors")
  ```
* BREAKING: `ErrorView` is now `ErrorHTML`. If you are using Brando's error
  templates, you must swap your endpoint's `render_errors` key with:
  ```elixir
  config :my_app, MyApp.Endpoint,
    render_errors: [
      formats: [html: Brando.ErrorHTML, json: Brando.ErrorJSON], layout: false
    ]
  ```
  Also switch out the view in your `fallback_controller.ex`:
  ```elixir
  |> put_view(html: <%= application_module %>Web.ErrorHTML)
  ```
* BREAKING: Add `delete_selected` as a built-in action for listing selections.
  This means you should remove your own `delete_selected` from your listing's
  `selection_actions`

* BREAKING: Added default actions for listings:
  - edit
  - delete
  - duplicate

  This means you should remove these from your listings (unless you want them doubled)

* BREAKING: `@identity` now refers to the current language identity, instead
  of a map of all languages
* BREAKING: Remove datasource block and introduce module blocks with
  datasource instead. Run `mix brando.upgrade && mix ecto.migrate`
  to convert your existing datasource blocks to module blocks.
* BREAKING: Admin now reads JS and CSS from `priv/static/admin_manifest.json`.
  Make sure to set this in `assets/backend/vite.config.js` to:
  `manifest: 'admin_manifest.json`
* BREAKING: CDN config is now per asset module, so instead of
  ```elixir
  config :brando, Brando.CDN, #...
  ```
  add
  ```elixir
  config :brando, Brando.Images, cdn: [enabled: false]
  config :brando, Brando.Files, cdn: [enabled: true, ...]
  ```
* BREAKING: Switch out your `<%= live_patch gettext("Create new") ...` calls
  in your list views. Replace with
  ```elixir
  <.link navigate={@admin_create_url} class="primary">
    <%= gettext("Create new") %>
  </.link>
  ```
* BREAKING: With moving to Phoenix 1.7+, we've tossed out Phoenix.View from
  Brando and use the new `embed_templates` setup instead. If your app depends
  on Phoenix.View, then you must add it as a dependency:
  ```
  {:phoenix_view, "~> 2.0"},
  ```

  You can use a prefab'ed MyAppWeb setup by replacing your `use MyAppWeb, :controller` (etc)
  with `use BrandoWeb, :controller` (etc). You can also use

  `use BrandoWeb, :legacy_controller`

  for utilizing the new layouts setup, but use regular template views.

  Convert your layout templates to heex, rename the layout view to
  `MyAppWeb.Layouts`, move it to `my_app_web/components/layouts.ex` and add

  ```elixir
  use BrandoWeb, :html

  embed_templates "components/layouts/*"
  embed_templates "components/partials/*"
  ```

  Move your partials from `templates/page` into `components/partials`,
  rename them to drop the leading `_` and reference them in your `app.html.heex`
  layout as `<.navigation {assigns} />`, `<.footer {assigns} />` etc.

* BREAKING: Update your `live_preview.ex` to the new format for setting layout
  and template:

  Old:
  ```elixir
  layout_module MyAppWeb.ProjectView
  layout_template "app.html"
  view_module MyAppWeb.ProjectView
  view_template "detail.html"
  ```

  New (for Phoenix.Template integrations):
  ```elixir
  layout {MyAppWeb.Layouts, :app}
  template {MyAppWeb.ProjectHTML, "detail"}
  # or
  template fn e -> {MyAppWeb.ProjectHTML, e.template} end
  ```

  New (for Phoenix.View integrations):
  ```elixir
  layout {MyAppWeb.LayoutView, "app.html"}
  template {MyAppWeb.ProjectView, "detail.html"}
  # or
  template fn e -> {MyAppWeb.ProjectView, e.template} end
  ```

* Use Finch for emails:
  - Add `finch` as a dep to your `mix.exs`:
  ```elixir
  {:finch, "~> 0.13"},
  ```
  - Add to your config:
  ```elixir
  config :swoosh, :api_client, MyApp.Finch
  ```
  - Add to your application supervisor in `lib/my_app/application.ex`
  ```diff
    children = [
      # Start the Ecto repository
      MyApp.Repo,
      # Start the Telemetry supervisor
      MyAppWeb.Telemetry,
      # Start the PubSub system
      {Phoenix.PubSub, name: MyApp.PubSub},
      # Start Finch
  +   {Finch, name: MyApp.Finch},
      # Start the Endpoint (http/https)
      MyAppWeb.Endpoint,
      # Start the Presence system
      MyApp.Presence,
      # Start the Brando supervisor
      Brando
      # Start a worker by calling: MyApp.Worker.start_link(arg)
      # {MyApp.Worker, arg},
    ]

* Add `:preview_expiry_days` config. Default is two days.
  I.e `config :brando, :preview_expiry_days, 31`
* Add alternate entries
* Add default actions to listing rows: `edit`, `delete`, `duplicate`
* Add `select` var type
* Add `video_file_options/1` callback to Villain parser. Return a kw list of
  options you want to use for video blocks.
* Add split dropdown button to form tabs for more advanced save options
* Update revisions when saving entry without redirecting
* Add scheduled publishing for revisions
* Fix max width for #content
* Presence in update forms. Add `presences={@presences}` to your
  `my_schema_update_live.ex` live view
* Automatically add uploaded gallery images to gallery
* Add `alert` and `after_save` to forms:

```elixir
forms do
  form :password,
    after_save: &__MODULE__.update_password_config/2,
    tab t("Content") do
      alert :info,
            t(
              "The administrator has set a mandatory password change on first login for this website."
            )

      fieldset do
        size :half
        input :password, :password, label: t("Password"), confirmation: true
      end
    end
  end
end

def update_password_config(entry, _current_user) do
  Brando.Users.update_user(
    entry.id,
    %{config: %{reset_password_on_first_login: false}},
    entry
  )
end
```
* Add `confirmation: <bool>` to password inputs
* Implement forced password change if user has `reset_password_on_first_login` as true in config.
  Run `mix brando.upgrade` to bring in a migration that sets this to false for existing users.
* Show media url in file assets listing
* Update villain module list when modules are added/deleted/updated
* Update relation(s) in multi select so they are available for live preview
* Allow uploading SVGs to image fields / picture blocks
* Set img `data-src` as transparent svg when we have `dominant_color`/`svg` placeholder
* Show live preview as shrinked webpage in iframe
* Reapply module ref on update
* Support showing entry URL for slug field with `show_url: true`.
* Improve pagination limits for listings


## 0.52.0

* First LV version
* Config: Add `admin_module: MyAppAdmin` to your `config/brando.exs`
* `Trait.changeset_mutator/4` is now `Trait.changeset_mutator/5`. It receives
  some additional opts from changeset, that normally would not be touched.
* Page properties are now page vars. `get_prop` -> `get_var`
* `render_sections_css` -> `render_palettes_css`
* Added input `:gallery`
* Added input `:color`
* Allow setting additional app specific cron jobs with
  ```
  config :my_app,
    cron_jobs: [
      {"0 0 * * *", MyApp.Worker.RefreshFrontpage}
    ]
  ```
* Added `Brando.Plug.Media`


## 0.51.0

* NOTE: This will be the final GraphQL/Vue version. Next version will be with LiveViews!
* Vite: Respect `hmr` config setting. Set it to `true` in your `dev.exs`, and `false` in `prod.exs`
* Query: Add `mutation :duplicate`
* Images: Add `dominant_color` to image struct.
* Revisions: Adds initial revision support.
* Publisher: Add Oban job support for scheduled publishing
* Pagination: Add `pagination: true` to generate pagination meta for `list` queries
* SSG: Add barebones start
* Villain: Replace $timestamp in Villain HTML
* Villain: Added localized date filter
* Router: Add `Brando.Plug.Fragment` to assign a map of fragments to you connection:
  ```
  plug Brando.Plug.Fragment, parent_key: "partials", as: :partials
  ```


## 0.50.0

* Query: Add `get_<schema>!` version that raises on no result
* Query: Add `insert/update/delete` mutations. See `UPGRADE.md`
* Query: Add `cache` to `get_*`
* Query: Add joined `order_by`:

    `{:ok, posts} = list_posts(%{order: [{:asc, {:comments, :title}]})`

* Soft Delete: Add cron job to check for expired soft deleted entries
* Villain: Removed markdown parsing from `Text` blocks.
* Villain: Refactored `templates` as `modules`, see `UPGRADE.md`
* Villain: Add `{% hide %}` tag for hiding content only in the Villain Editor.
* Router: Add `admin_routes/0` and `page_routes/0`
* Router: Add `:put_extra_secure_browser_headers`
* Frontend: Add Vite tooling, see `UPGRADE.md`
* Releases: Improved `ReleaseTasks` -- works better with Elixir releases


## 0.49.0

* BREAKING: Removed `mogrify`/`imagemagick` -- use `sharp-cli`/`sharp` instead.
* Move to mix releases from Distillery for new project template.
* Add `webp` processing to `png` and `jpeg` assets. Falls back to `png`/`jpeg`
  if browser does not support webp.
* Add `?vsn=d` to all `fonts.pcss` URLs to fix fonts not caching.
* Dynamic redirects.
* Live preview: Changed syntax - see UPGRADE.md
* Live preview: Now sends entry diffs on update to save some bandwidth
* Live preview: Send base64 of images on entry creation
* Villain: Added telemetry for `parse_and_render`
* Try to rotate images by EXIF info on upload
* Add system startup warnings to Brando JS
* Better Villain template authoring experience
* Add `Brando.HTML.preload_fonts/1`


## 0.48.0

* Switch to Liquex.
  `{% for item <- entry.items %}` -> `{% for item in entry.items %}`
  `${global:category_key.global_key}` -> `{{ globals.category_key.global_key }}`
  `${menu:main.en}` -> `{{ navigation.main.en }}`

  Brando checks for old syntax and warns on system startup.

* Villain: Allow undeleting refs in template blocks
* BrandoJS/config: allow `templates` config to be a function. Gets called with `page`
* Add `Brando.Type.Video` with corresponding `KInputVideo`
* Cache navigation menus
* Add Query cache. `Page.list_pages(%{status: :published, cache: true})`
* Add `sizes: "auto"` to `picture_tag`
* Removed `Brando.Registry` and old i18n logic
* English translations for BrandoJS
* Set image meta editing as default true on Image fields in BrandoJS
* Inject `--aspect-ratio` css var for `video_tag`
* Add `address2` and `address3` in `Identity` for extra address lines
* Add `navigation` to villain templates context
* Optimized sequencing query. Now only performs a single query
* Add cache option to `Brando.Query` list functions


## 0.47.0

* Add page properties.
* Fix ordering of translation fragments
* Fix lightbox src with lazyload in `picture_tag`
* Rerender matching templates in Villains when updating globals or identity
* Add `render_caption` callback to Villain parser. Picture blocks call this to render captions.
* Set fehn 3.0 as default Docker image (Ubuntu 20.04)
* Allow parsing RFC 3339z datetime strings in date filter
* Add sitemap logic, `Brando.Sitemap`.
* Add `oban` for cron jobs.
* Add `orientation` filter
* Dynamic navigation V1
* Cleaned up `Brando.Pages.get_page/*` functions
* Added `publish_at` logic to pages.
* Use `imageType` fragment in generator
* Add `select` logic to `Brando.Query`
* Fix nonstandard module naming bugs in generator (NNCA would become Nnca etc)


## 0.46.0

* New parser for template language!
* Added CDN image uploads.
* Deprecated `Pages.list_page_fragments_translations`. Use `Pages.list_fragments_translations` instead.
* Switch frontend bundler to Rollup
* Renamed `User.full_name` to `User.name`. Requires BrandoJS to be updated.


## 0.45.0

* Rewrote upload handling. **Requires** latest BrandoJS to work!
* Please ensure that `|> generate_html()` appears LAST in your schema's `changeset` functions.
  This is to ensure that any `${entry:field}` interpolation passes successfully!
* Mandatory /2 for all parser functions. Second argument is an options list.
  Mostly for futureproofing and caching templates
* Optimized Dockerfile templates.
* `picture_tag` moved `moonwalk` to `<picture>` tag instead of `<img>`
* Simplify needed `brando.exs` config
* Removed deprecated `Brando.Config` genserver.
* Started laying the foundation for authorization. See `UPGRADE.MD`
* Rename mix task `brando.gen.html` -> `brando.gen`
* Add `meta_image` field to `Brando.Page`
* Add `Brando.Datasource`
* Smarter Dockerfile layer caching
* Add globals to identity configuration
* Add variables to Villain templates
* Improve default backend eslint configuration
* Add creator switch to generator
* Copy static files in development
* New JS backend — BrandoJS
* Add `Brando.Datasource`. Allows you to access preset backend queries from Villain.
* Simplify Villain default parser. Now you can `use Brando.Villain.Parser`
for sensible defaults, and override when neccessary.
* KInputTable: Rename `newRows` -> `addRows`


### DEPRECATIONS

* Move `put_creator` to after `cast` but before `validate_required` in your
  changeset functions.


## 0.44.0

* Drag and drop sequence pages.
* Ensure all jpg files are written as `.jpg`
* Move to local backend JS for tighter integration.
* Generator now generates a more complete `staging` config
* Generator separates out the form for backend schemas
* GraphQL rewrite to use Dataloader internally, also when using `brando.gen.html`
* Rename `Brando.Field.ImageField` -> `Brando.Field.Image.Schema`
* Rename `Brando.Field.FileField` -> `Brando.Field.File.Schema`


## 0.43.0

* Add `Brando.HTML.init_js()`
* Change potentially long identity fields to `:text`.
* Adds custom meta from `identity` setup to page


## 0.42.0

* Moved js deps to `@univers-agency` package scope.
* `Brando.User` is now `Brando.Users.User` for consistency.
* In `session_controller.ex`, ensure user has not been soft deleted in `create/3`
* Soft deletion fields have been added.
* Switch out the `:hmr` logic for `css` and `js`
* Run startup checks
* More advanced META and JSONLD handling.
* Added SHARP image processing. Choose this for the fastest/highest quality
* Removed all `import Brando.Images.Optimize` and `optimize/2` in changeset functions.


## 0.41.0

* Tables have been renamed.
* Fragments now belong to pages.


## 0.40.0

* Copy the brando.upgrade mix task from brando src.
* Switch all your image fields to `:jsonb` types in migrations from `:text`.


## 0.39.0

* Clean up time! Lots of deprecations and changes. See UPGRADE.md


## 0.38.0

* Update for Ecto 3, Phoenix 1.4
* More configuration choices in backend/config
* Add opts to body_tag
* Add config genserver
* More flexible cookie_law
* Add rerendering of page fragments
* Larger default image sizes
* Rewritten backend JS
* Rewritten generators
* Rewritten image handling


## 0.37.0

- Guardian was updated. Router changes. See UPGRADE.md
- `render_fragment` has been renamed to `fetch_fragment`.
- `brando_pages` has been incorporated into `brando` core.

## pre 0.37.0
