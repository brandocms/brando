## 0.55.0 (Unreleased)

### Upgrading

Follow [Migrating from 0.53 or 0.54](guides/migrating_from_053.md). Its "The short version"
lists the commands in order and where to stop and review; a site already on a 0.55 development
build starts where its first table says. Sites on 0.51 (the `legacy` branch, with the Vue admin)
follow [Migrating from 0.51](guides/migrating_from_051.md).

#### Breaking

- `ai:` on a form input is deprecated for `ai_actions:`, and AI results for text, textarea and rich
  text fields, block text included, are suggestions the editor accepts or discards
  ([#3096](https://github.com/brandocms/brando/pull/3096)).
  Before building with `--warnings-as-errors`, replace each `ai:` with the `ai_actions:` its compile
  warning prints:

  ```elixir
  # Before
  input :summary, :textarea, ai: [prompt: "Summarize.", context: [:title, :blocks]]

  # After
  input :summary, :textarea,
    ai_actions: [generate: [label: t("Generate"), prompt: "Summarize.", from: [:title, :blocks]]]
  ```

  `context:` becomes `from:`, which is required: name the fields the prompt reads. `model:` carries
  over. On a `:rich_text` input write `write_with_ai: [prompt: …, from: […], model: …]`.
  In `config :brando, Brando.AI`, move `api_key:` to `providers:` and request options such as
  `temperature:` to `default_opts:`.

- Write with AI is opt-in (`brando_218`, every environment), and the site prompt options are
  renamed ([#3103](https://github.com/brandocms/brando/pull/3103)).
  Add `write_with_ai: true` (or `write_with_ai: [prompt:, from:, model:]`) to the `:rich_text`
  inputs that should keep it, and turn it on for modules: **Write with AI** under Overview in the
  module editor, or `write_with_ai` in module definition files.
  `prompts: [block_text: [write_with_ai: false]]` turns it off in every module.
  Rename `fields:` to `prompts:` in `config :brando, Brando.AI`, and `ai:` to `ai_prompts:` in
  `trait :meta`. The old names warn and are removed in a later release.

- `trait :scheduled_publishing` adds `unpublish_at`, also on pages and fragments (`brando_214`,
  every environment); existing entries have no expiry. A scheduled publishing job publishes only an
  entry that is still pending, and **Delete job** clears the entry's publish date too
  ([#3092](https://github.com/brandocms/brando/pull/3092)).
  With your own `config :brando, Oban`, add
  `{"*/10 * * * *", Brando.Worker.ScheduledPublishingSweep}` to the crontab. Preview the sweep with
  `mix brando.scheduled_publishing.sweep`, or `Brando.Publisher.sweep(dry_run: true)` in a release.
  `Brando.Publisher.delete_job/2` takes the user to save as.

- Markdown alternates and IndexNow need two endpoint plugs
  ([#3026](https://github.com/brandocms/brando/pull/3026)).
  Add `plug Brando.Plug.Markdown` and `plug Brando.Plug.IndexNow` after `Brando.Plug.LivePreview`
  and before the router. See [Markdown alternates](guides/markdown_alternates.md) and
  [IndexNow](guides/identity_and_seo.md#indexnow).

- The admin search needs the `search_documents` table (`brando_212`, every environment) and a
  `search_index` Oban queue ([#3028](https://github.com/brandocms/brando/pull/3028)).
  Rebuild the index once in each environment: Configuration → Utilities → Search index → "Rebuild
  search index". With your own `config :brando, Oban`, add `search_index: [limit: 2]`, or the index
  never updates. See `Brando.Search`.

- Connected AI tools (MCP) mount only with `mcp_routes()` (`brando_213`), and each environment stays
  off until an administrator turns it on ([#3029](https://github.com/brandocms/brando/pull/3029)).
  Remove a `plug BrandoMCP` route. Optional: `Brando.MCP.BodyLimit` refuses oversized MCP requests
  before `Plug.Parsers`.

- Notifications need a `notifications` Oban queue (`brando_217`, every environment)
  ([#3091](https://github.com/brandocms/brando/pull/3091)).
  With your own `config :brando, Oban`, add `notifications: [limit: 2]`, or no notification is sent.
  Grant the Notifications permission (`brando.notifications.manage`) to the groups that should
  manage routes; no existing group has it. See [Notifications](guides/notifications.md).

- Webhooks need two Oban queues (`brando_209`, every environment)
  ([#3024](https://github.com/brandocms/brando/pull/3024)).
  With your own `config :brando, Oban`, add `content_events: [limit: 1], webhooks: [limit: 5]`, or
  no content events or deliveries run, and `{"35 5 * * *", Brando.Worker.WebhookDeliveryPurger}` to
  the crontab. See [Webhooks and content events](guides/webhooks.md).

- `GET /admin/logout` asks "Sign out?" and signs out with `DELETE` (or `POST`); ending a session
  disconnects its admin socket and LiveViews
  ([#3025](https://github.com/brandocms/brando/pull/3025)).
  `Brando.Users.build_token/1` and `verify_token/1` are deprecated and their tokens no longer
  connect to `BrandoAdmin.AdminSocket`: use `build_socket_token/2` and `verify_socket_token/1`.
  Reload open live previews after the deploy
  ([sessions](guides/users.md#understand-sign-in-and-session-lifetime)).

- Two-factor authentication (`brando_204`) and passkeys (`brando_205`) arrive; a session from before
  them asks for the password on its first sensitive action
  ([#3018](https://github.com/brandocms/brando/pull/3018), [#3019](https://github.com/brandocms/brando/pull/3019)).
  Add `"code"`, `"proof"` and `"secret"` to `config :phoenix, :filter_parameters`.
  Behind a reverse proxy on another server, list it in `config :brando, :trusted_proxies` and add
  `:peer_data` and `:x_headers` to the `/live` socket's `connect_info`. See
  [Behind a proxy](guides/users.md#behind-a-proxy).

- Admin icons are Lucide; Heroicons and `assets/css/heroicons.css` are removed
  ([#2960](https://github.com/brandocms/brando/pull/2960)).
  `<.icon>` renders `<span data-icon class="lucide-name">`. Old `hero-*` names still map; use Lucide
  names in new code. App CSS targeting `[class^="hero-"]` or `.hero-*` targets `[data-icon]` or
  `.lucide-name`; colour icons with `color`.

- An image config with an unknown size key (`"crp" => true`), a `srcset` naming a missing size, or
  an ImageMagick flag other than `>` fails to compile
  ([#2929](https://github.com/brandocms/brando/pull/2929), [#3060](https://github.com/brandocms/brando/pull/3060)).
  Fix the config it names. A config that replaces `sizes` needs its own `srcset`; the default one
  is dropped. Replace `^` with `"crop" => true`, `!` with `"crop" => true` and a `"ratio"`, and `%`
  with a width in pixels; remove `<`. A trailing `>` stays valid.

- Video uploads are opt-in: `default_video_upload_strategy` defaults to `:none`, so a site that
  never set it loses its video "Upload" buttons. To keep them, set
  `config :brando, :default_video_upload_strategy, :local`, or `upload_strategy: :local` per field.

- Brando requires Elixir 1.18 or later.

- A `:boolean` listing filter switched off shows all entries, and `default: true` toggles can be
  switched off. Set `off: false` on a filter that should keep filtering on false.

- `accept:` in a video or file asset `cfg` fails to compile with "unknown config fields": remove it.

- `mix brando.digest` deletes `*.map` files under `priv/static`
  ([#2905](https://github.com/brandocms/brando/pull/2905)).
  `mix brando.migrate55` sets `sourcemap: 'hidden'` in the Vite configs under `assets/`. A site
  whose Sentry fetched public maps uploads them during the build (see "Source maps" in the
  [deployment guide](guides/deployment.md)); `--keep-source-maps` on the digest publishes them.

- Module definition baselines leave out empty values, so a block type gaining a field no longer
  makes its modules conflict on import.
  If a lockfile reports conflicts after the upgrade, export a fresh baseline first.

- Var labels and select var option labels are translated, a map of admin language → text
  (`brando_190`, `brando_191`).
  Re-export module definitions. Code reading `var.label` as a string uses
  `Brando.Type.I18nString.localized(var.label)`.
  Definitions accept `label "Size"` or `label %{"en" => "Size", "no" => "Størrelse"}`, and options
  `{"Light", "light"}` or `%{"label" => %{"en" => "Light", "no" => "Lys"}, "value" => "light"}`.

- Image alt text, title and credits are translated, a map of content language → text
  (`brando_180`, `brando_181`) ([#2860](https://github.com/brandocms/brando/pull/2860)).
  Code reading `image.alt`, `image.title` or `image.credits` as a string uses
  `Brando.Images.text(image, :alt, language)` or `Brando.Images.resolve_texts(image, language)`.
  `<.picture>` takes `language:` (default: the request's locale); `Brando.Villain.map_images/2`
  takes the language. Templates print them with `i18n`: `{{ entry.cover.alt | i18n }}`. JSON built
  from an image now carries the maps.
  `mix brando.migrate55` lists application code to change, and `mix brando.check.image_texts` lists
  module, container and menu templates missing the filter.

- A page with `has_url: false` has no URL: `Page.__absolute_url__/1` returns `nil`. Code that builds
  a link for such a page handles `nil`.

- Videos are database records, `Brando.Videos.Video`, replacing the deprecated `Brando.Type.Video`:
  `source` is now `type` (`:upload`, `:external_file`, `:vimeo`, `:youtube`), `url` is `source_url`,
  and `title`, `caption` and `aspect_ratio` are new. Update video test factories.

- Image processing uses Image/Vix in place of `sharp-cli`. Move custom sharp-based processing to
  Image/Vix.

- `hackney`, `tzdata` and `fastimage` are no longer dependencies (`tz` and `req` replace them;
  `ex_aws` `~> 2.7` makes `hackney` optional), so Swoosh fails to boot with "Could not find hackney
  dependency". Add `hackney` to your deps if your app uses it, and set
  `config :swoosh, :api_client, Swoosh.ApiClient.Req` in `config/config.exs` (`config/test.exs`
  usually sets `false` already).

- Refs live in their own table, with foreign keys to media. In templates,
  `{{ refs.my_image.data.data.path }}` becomes `{{ refs.my_image.path }}`, and
  `{{ refs.my_gallery_ref.data.images }}` becomes
  `{{ refs.my_gallery_ref.gallery.gallery_objects }}`; video refs read their properties directly.

- Form components moved, unchanged. In custom inputs and field components:
  - Call `BrandoAdmin.Components.Form.Primitives` in place of `Form` for `field_base/1`, `input/1`,
    `label/1`, `error_tag/1`, `submit_button/1`, `translate_error/1`, `inputs_for_block/1`,
    `inputs_for_poly/1`, `array_inputs/1`, `array_inputs_from_data/1`, `map_inputs/1` and
    `map_value_inputs/1`.
  - The image drawer is `Form.ImageDrawer.render/1` and its editor `ImageDrawer.editor/1`;
    `close_image/1`, `close_image_editor/1`, `open_image_editor/3`, `duplicate_image/3` and
    `reset_image_field/2` are on `ImageDrawer`.
  - The file drawer is `Form.FileDrawer.render/1`, with `close_file/1` and `reset_file_field/2`.
  - `Form.video_drawer/1` is `Form.VideoDrawer.render/1`; `reset_video_field/1,2`,
    `reset_video_thumbnail/1,2`, `parse_video_url/1,2`, `extract_thumbnail/1,2` and
    `close_video/0,1` move to `Form.VideoDrawer`.

- `Brando.Videos.Uploader.initiate_upload/3` returns `{:error, reason}` for every failure, adding
  `:provider_not_configured` and `:provider_error`.
  Drop a `rescue` around it, and show errors with `Brando.Uploads.video_upload_error_message/1`.

- All three video providers raise on missing credentials, Cloudflare included, and treat an
  empty-string credential as missing.
  Remove clauses matching `{:error, :not_configured}` on Cloudflare calls. `delete_remote/1`
  raises for an unconfigured provider.

- `Brando.CDN.key_exists?/2` is replaced by `Brando.CDN.key_available?/2`, which returns the
  opposite: `true` when the key is free, and `false` when the check fails.
  Invert the branch when renaming, or the call overwrites live objects:

  ```elixir
  # before
  if Brando.CDN.key_exists?(key, cfg), do: rename(key), else: key

  # after
  if Brando.CDN.key_available?(key, cfg), do: key, else: rename(key)
  ```

- `<.video>` resolves each playback setting from the tag's opt, then the record, then the default,
  with a `false` opt winning, and Mux and Bunny videos follow the record and render no `<source>`.
  Where a template passes an opt the record disagrees with, set the field in the admin instead.
  `autoplay` still forces `muted`. Cloudflare videos render `video-wrapper video-cloudflare`: add
  `.video-cloudflare` to selectors that relied on `.video-file`.

- The admin animates with Motion on `@brandocms/jupiter` `5.0.0-beta.19`, without GSAP
  ([#2939](https://github.com/brandocms/brando/pull/2939)).
  Set `@brandocms/jupiter` in `assets/backend/package.json` to `5.0.0-beta.19`.
  A custom admin hook that imports `gsap` from Jupiter uses `animate`, `stagger`, `scroll` and
  `motionValue`, or depends on `gsap` itself.
  Negate the `offsetY` passed to `app.scrollTo({y: el, offsetY})`.

- Public modules in the wrong layer are renamed; the old names warn and keep working until 0.57
  ([#3105](https://github.com/brandocms/brando/pull/3105)).
  `mix brando.migrate55` rewrites references in `config/`, `lib/` and `test/`; `mix brando.doctor`
  lists any left in `lib/`. Struct literals and patterns (`%Brando.Link{}`, `%Brando.Upload{}`) and
  a relation's `module: Brando.Link` stop compiling until renamed.
  `Brando.SEOController`, `Brando.SitemapController`, `Brando.PreviewController` and
  `Brando.ErrorHTML` move to `BrandoWeb.`; `Brando.UserChannel`, `Brando.LobbyChannel` and
  `Brando.LivePreviewChannel` to `BrandoAdmin.`; `Brando.Config`, `Brando.Link` and `Brando.Meta`
  to `Brando.Sites.` (`Brando.Meta.HTML` keeps its name); `Brando.Upload` is
  `Brando.Uploads.Store`.

- Blueprint migration generation compares a versioned storage schema and follows the Blueprint:
  enum and custom `Ecto.Type` column types, defaults, `source:` columns, indexes, foreign keys and
  auxiliary tables; `primary_key false` creates no `id`, a unique `:language` attribute gets a
  unique index, and colliding index or foreign-key names fail.
  Read `guides/blueprint_migrations.md` before upgrading. Generate with
  `mix brando.gen.blueprint_migration MyApp.Domain.Schema`, then:
  - Table or primary-key changes, and relation/embed renames on source-mapped tables: write the
    migration by hand, then run with `--rebaseline`.
  - Existing enum or custom-type columns: run the generated default/null migration if it matches the
    live change; otherwise write the type conversion by hand and run `--rebaseline` ("Field types,
    options, and defaults").
  - Source-mapped tables: inspect the live schema first; use `rename_from:` for an attribute whose
    old column still exists ("Physical Ecto sources").
  - Rebaseline directly only after checking the database already has the right types or uses the
    physical columns.
  - `attribute :language, :language, unique: true`: generate, review and run a migration.
  - `with:` on `prevent_collision` scopes the query, constraint and index together, and combines
    with arity-one callbacks and `message:`: add the persisted columns a callback narrows
    candidates by to `with:` and generate a migration.

- Blueprints are validated at compile time: options, names and primary key (integer `id`, UUID or
  none), fields, relations, assets and their configs, forms, datasources, metadata, JSON-LD,
  listings, translations, and Liquid in `identifier` and `absolute_url`. A custom `belongs_to` uses
  one foreign key throughout, array attributes need `{:array, type}`, listing default filters apply
  to the first query, and identifier titles are trimmed.
  Compile with warnings as errors, fix what is reported, and check your listing defaults:
  - A static form query's `:matches` is a map; transformer defaults a map, struct or arity-2
    function; listings arity-1 function components; transformer relations `:has_many` or
    `:embeds_many` with `cardinality: :many`.
  - `completed_callback` takes an arity-2 function or MFA and runs once the file is stored or
    processed, or a Mux/Bunny video is ready; it may retry, so make external side effects idempotent
    ("Asset configuration" in `guides/blueprint_fields.md`).
  - A fix that changes a column, foreign key or unique index needs a generated, reviewed Blueprint
    migration; for belongs-to storage or `on_delete:` also verify rollback, and use `--rebaseline`
    only if the live constraint was already corrected by hand ("Relation option corrections" in
    `guides/blueprint_migrations.md`). Write a table or primary-key change by hand and run it with
    `--rebaseline`.

- `use Brando.Blueprint` no longer imports the listing components. In Blueprints whose listing rows
  use `<.cover>`, `<.url>`, `<.update_link>`, `<.field>`, `<.children_button>` or `<.i18n>`, add:
  `import Brando.Blueprint.Listings.Components.Core`, plus `...Components.Cover` for `<.cover>` and
  `...Components.Children` for `<.children_button>`.

- `phoenix` 1.8.13 and `phoenix_live_view` 1.2.11, which fixes an open redirect in `redirect/2`
  (CVE-2026-64941). Pin `phoenix_live_view` to `1.2.11` in your `assets/package.json` and rebuild
  your backend assets.

- The Oban v14 migration (`brando_153`) fails with `must be owner of type oban_job_state` when
  objects are owned by a role other than the one migrating, as with the bundled `fabfile.py`.
  Fabric: update your `fabfile.py`'s `grant_db` task to Brando's and run `fab <env> grant_db`
  before migrating. Otherwise, once as a superuser:
  `ALTER TYPE public.oban_job_state OWNER TO <your_app_db_user>;`

- The admin's Svelte components need newer build tools in your project
  ([#2980](https://github.com/brandocms/brando/pull/2980)).
  In `assets/backend/package.json`: `svelte` `^5.57.2`, `vite` `^8.3.3`,
  `@sveltejs/vite-plugin-svelte` `7.3.1`. You can drop
  `optimizeDeps: { include: ['vex-js', 'vex-dialog'] }` from `assets/backend/vite.config.js`.

- `config_target` strings resolve only to Brando blueprint modules and their exported arity-0
  functions, closing a way for a crafted upload target to call arbitrary functions.
  Move config functions that live on plain helper modules onto a blueprint schema module.

#### Improvements

- Opening an entry shows its heading, tabs and fields at once, without a loading modal; an entry
  with many blocks shows outlines of them until they load ([#3112](https://github.com/brandocms/brando/pull/3112)).
  `BrandoAdmin.Components.Form.entry_loader/1` is removed; drop any calls to it.
  `Brando.Content.Blocks.count_entry_blocks/2` now counts nested blocks too;
  `count_entry_blocks_by_field/2` gives the count per field.

- The admin's colours are role tokens from `assets/css/tokens.css` (`--brando-ink`,
  `--brando-accent`, `--brando-surface-*`, …), and the legacy colour names are deprecated ([#3046](https://github.com/brandocms/brando/pull/3046)).
  If your `assets/backend` CSS uses the `--brando-color-*` custom properties or the Europa palette
  through `theme(colors.*)` or `@color` (`dark`, `blue`, `peach`, `input`, `gray`, `villain.*`, …),
  move it to the role tokens in `assets/css/tokens.css`.

- The entry editor is headed by the entry's title under a content-type breadcrumb, with its status as
  one control beside it and the save state next to Save; a blueprint form's `<:header>` slot is no
  longer shown or required ([#3005](https://github.com/brandocms/brando/pull/3005)).
  For a singleton settings screen, pass `layout={:settings}` to `BrandoAdmin.Components.Form` and
  head the screen with `Workspace.header` (which takes `eyebrow`).

- `mix brando.gen.blueprint_migration --all` plans a migration for every blueprint whose storage
  differs from its snapshot, to review and accept together ([#3012](https://github.com/brandocms/brando/pull/3012)).

- A listing's filters, `decorate`, row component and `selection_action` can depend on the signed-in
  user, a sort's `order` can be a function of the query, and a `selection_action` takes `confirm:`.
  Select and boolean filter values now reach the context unescaped (`"in_progress"`, not
  `"in\_progress"`); remove any unescaping of them in your context.

- Upgrading a 0.53/0.54 site takes fewer manual steps: `mix brando.migrate54` and `migrate55` run
  without compiling the application first and fix more themselves (Gettext backends, Villain
  parsers, Florist config, `Plural-Forms` headers) ([#2978](https://github.com/brandocms/brando/pull/2978)).
  Follow [Migrating from 0.53 or 0.54](guides/migrating_from_053.md), which now covers the
  dependency, Node, legacy-snapshot and test-database steps.
  `mix brando.gen.backend --upgrade` brings an existing `assets/backend` and the Dockerfile's
  `assets_backend` stage to the current pnpm template; `mix brando.assets.setup --backend-only`
  installs and builds the admin alone.
  The backend template no longer has `svelte.config.cjs` or `svelte-preprocess`; delete them from an
  existing `assets/backend`.

- `mix brando.migrations.check` lists the `brando_*` migration copies not yet run whose code differs
  from the current template, and `--update` replaces them ([#2972](https://github.com/brandocms/brando/pull/2972)).
  Run it before replaying an upgrade on a copy of production.

- New applications build `assets/backend` with pnpm 10.32.1, and `mix brando.assets.setup` maintains
  only `pnpm-lock.yaml` ([#2939](https://github.com/brandocms/brando/pull/2939)).
  To move an existing application off Yarn: copy the `assets_backend` stage from
  `priv/templates/brando.install/Dockerfile`, commit the `assets/backend/pnpm-lock.yaml` that
  `mix brando.assets.setup` writes, and delete `assets/backend/yarn.lock`.

- `mix brando.migrate54` covers only the 0.53 → 0.54 source changes and `mix brando.migrate55` the
  0.54 → 0.55 ones; `migrate55` archives the `mix brando.upgrade` task 0.54 installed, and
  `mix brando.install` no longer copies it into new applications.
  On 0.54, run `mix brando.migrate55`; on 0.53, run `mix brando.migrate54`, then
  `mix brando.migrate55`. `mix igniter.upgrade brando` runs `brando.migrate55` for 0.54 → 0.55.

- Admin form fields expose their errors and required state to screen readers, modals are dialogs
  that keep focus, and a failed save focuses the first invalid control ([#2752](https://github.com/brandocms/brando/pull/2752)).
  If you style `.field-error`: the messages are now wrapped in a `.field-errors` container, which
  does the positioning, so a selector like `.label-wrapper > span.field-error` no longer matches.

- Long unique and foreign-key violations come back as changeset errors, since Blueprint index and
  constraint names use PostgreSQL's 63-byte form.

- A Blueprint nested entry marked for deletion is deleted even when its other fields are invalid.

- Blueprint uniqueness scopes reject repeated columns and a scope that repeats the unique field.

- Required `has_many`, `many_to_many` and `entries` relations reject every empty value and report
  `required_message`; many-to-many casting turns malformed IDs into changeset errors.

- Blueprint migration snapshots reject unknown or malformed formats, and restoring a revision checks
  that it belongs to the same entry.

- Arity-one `prevent_collision` callbacks run as documented and recheck when only a scope field
  changes.

- `fallback/2` and `try_path/2` follow mixed map, keyword and list paths, returning `nil` where a
  step does not fit.

- Save-error summaries show the field's visible label, such as "Cover video" for `cover_video_id`.

- `Brando.Blueprint.preloads_for/2` includes `has_one` relations, and `has_many` preloads keep a
  declared `preload_order`.

- Blueprints define a `t/0` type unless the schema defines its own.

- Asset `config_target` values resolve through one validator, and an invalid target falls back to
  the default config.

- Generated `:blocks` and `:entries` join schemas point at the actual Blueprint owner module.

- Blueprint migration generation reads table and key types of referenced schemas that are not
  loaded yet, so UUID references stay UUIDs.

- Deep relation paths in identifier and absolute URL templates are preloaded, and unknown paths no
  longer fail compilation.

- Blueprints can read config at compile time with `Brando.RuntimeConfig.get/1` in place of
  `Brando.config/1`, which avoids compile cycles.

- Built-in traits have shorthands (`trait :sequenced`, `:status`, `:timestamped`, `:creator`,
  `:soft_delete`, `:translatable`, `:meta`, `:scheduled_publishing`, `:ensure_uid`,
  `:validate_var_keys`) that keep runtime trait code out of schema compilation; custom traits can
  opt in with `compile_with:` or `Brando.Trait.NoopCompiler`.

- `inputs_for` accepts `:vars`, `:gallery_objects`, `:identity_type_config` and `:page_vars` in
  place of the admin component modules.

- Block edits are no longer lost to a parent re-render, and the block outline shows the live block
  structure.

- `guides/block_editor.md` covers wiring blocks into a blueprint, rendering them and debugging the
  editor.

- Inserting, deleting or reordering a block re-renders only that block.

- Typing in a block or entry field no longer renders blocks while the live preview is closed.

- Module and container Liquid templates are parsed once and cached.

- Opening a form loads the block tree in fewer queries, with no limit on nesting depth.

- Saving one block after opening the live preview updates only that block's row.

- Block rendering builds iodata, which is faster.

- Dominant image colours are extracted with imagequant, which is more accurate.

- Live preview has cache fixes and compile-time assets.

- Cookies are set with `SameSite` and `Secure`.

- CI tests Elixir 1.19/1.20 on OTP 28/29; OTP 26 is no longer tested.

#### Features

- The video and file libraries get the image library's Sort by use and Delete unused; both now need
  the update and delete permissions on the asset type, and "Not in use" counts assets in table
  blocks, trashed entries and recovery drafts as used ([#3100](https://github.com/brandocms/brando/pull/3100)).
  Code reading `image_ids` from `BrandoAdmin.Images.Sweep` plans or results reads `ids` now.
  Rank shared videos and files with `sweep_priority:` under `Brando.Videos` and `Brando.Files`
  (otherwise the images' list is used).

- Listings have a Views menu where editors save filters, status, sort and page size under a name,
  for themselves or shared with everyone who can open the listing ([#3089](https://github.com/brandocms/brando/pull/3089)).
  Run `mix brando.gen.migrations` for `brando_215`; until it runs, the menu lists no views.
  Leave the menu out of a listing with `saved_views={false}`.

- Configuration → Integrations → Notifications sends mentions, scheduled publishing and failed jobs
  to Slack, Microsoft Teams or email, and users can choose a daily or weekly email summary instead ([#3091](https://github.com/brandocms/brando/pull/3091)).

- Calendar in the sidebar shows scheduled publishing, revisions and expiries by month or week, and
  an item moves to another day by dragging it ([#3092](https://github.com/brandocms/brando/pull/3092)).

- Entries with `trait :scheduled_publishing` can expire: at its Expires time (`unpublish_at`) the
  entry is deactivated, and the dashboard lists what expires in the next 14 days ([#3092](https://github.com/brandocms/brando/pull/3092)).

- Block modules → a module → Resolve blocks moves or drops the refs and vars the module no longer
  defines, bringing blocks left on older versions up to date; `mix brando.modules resolve --uid UID`
  does it from the terminal ([#3062](https://github.com/brandocms/brando/pull/3062)).

- Brando ships usage rules and five site-building skills for coding agents in the Hex package;
  `mix brando.install` copies the skills to `.claude/skills/`, and `mix brando.upgrade FROM TO` adds
  missing ones ([#3034](https://github.com/brandocms/brando/pull/3034)).

- Configuration → SEO can block AI crawlers one by one and set the `ai-train` content signal, written
  to a generated block in `robots.txt`, which is now served as `text/plain` ([#3026](https://github.com/brandocms/brando/pull/3026)).

- The meta drawer has No snippet and Snippet length for the page's robots meta tag, and
  `put_robots/2` adds directives of your own ([#3026](https://github.com/brandocms/brando/pull/3026)).

- Configuration → SEO can turn on IndexNow, which tells Bing and the engines using its index when an
  entry is published, updated, unpublished or deleted ([#3026](https://github.com/brandocms/brando/pull/3026)).
  Turn it off for a whole deployment with `config :brando, Brando.IndexNow, enabled: false`.

- The meta drawer's Previews tab shows the entry as a search result, an Open Graph card and an X
  card as it is edited ([#3026](https://github.com/brandocms/brando/pull/3026)).

- An entry's page is also served as Markdown, at its URL with `.md` and for `Accept: text/markdown`,
  for blueprints with a URL, blocks and `trait :meta` ([#3026](https://github.com/brandocms/brando/pull/3026)).
  Turn it off for a blueprint with `trait :meta, markdown: false`.

- `/admin/search` finds entries by title, fields and block text, with filters for content type,
  language and status; the command palette links to it ([#3028](https://github.com/brandocms/brando/pull/3028)).

- People with the new Connected AI tools → Connect permission and two-factor authentication can
  connect Claude, ChatGPT and other MCP clients to read content and prepare proposals ([#3029](https://github.com/brandocms/brando/pull/3029)).
  Mount it with `mcp_routes()` and turn it on per environment under Configuration → Integrations →
  Connected AI tools; see [Connected AI tools](guides/mcp.md).

- Entry changes become content events (`entry.created`, `entry.published`, …) delivered to the
  subscribers in `config :brando, Brando.ContentEvents, subscribers: [...]`, and Configuration →
  Integrations → Webhooks posts them, signed, to your URLs ([#3024](https://github.com/brandocms/brando/pull/3024)).

- Editors in one entry's blocks share an edit session: changes reach everyone as they type, someone
  opening the entry sees the unsaved work, and Assistant proposals arrive without a reload ([#3030](https://github.com/brandocms/brando/pull/3030)).

- Two people can edit one block: blocks are no longer locked, each field shows who is in it, and
  clicking an editor's avatar follows them ([#3031](https://github.com/brandocms/brando/pull/3031)).

- Editors can leave notes on an entry, a block, a field or selected text, with replies, resolving
  and `@Name` mentions by email ([#3016](https://github.com/brandocms/brando/pull/3016)).

- Activity marks each change as made by a person, the Assistant, an MCP tool or an automatic job,
  names who approved a proposal, and filters by kind of actor ([#3087](https://github.com/brandocms/brando/pull/3087)).

- The Assistant lists proposals from MCP-connected tools such as Claude Code under From connected
  tools, to review and apply like its own ([#3017](https://github.com/brandocms/brando/pull/3017)).

- JSON-LD describes an entry's videos as `VideoObject` nodes and, with the new `:person` field type,
  its authors as `Person` nodes ([#3003](https://github.com/brandocms/brando/pull/3003)).
  Run `mix brando.gen.migrations` for `brando_202` (users' Job title and Profile links).
  Map authors with `field :author, :person, & &1.creator`; `videos false` in a `json_ld_schema`
  turns the video nodes off.

- `render_meta` writes X card tags from the Open Graph values, and the meta drawer has a Canonical
  URL field for syndicated or duplicated content ([#3000](https://github.com/brandocms/brando/pull/3000)).

- The 404 log is stored in the database, so it survives deploys, and Redirect works from it ([#3000](https://github.com/brandocms/brando/pull/3000)).
  Run `mix brando.gen.migrations` for `brando_201`.
  Apps with their own Oban crontab add `Brando.Worker.NotFoundPurger` (05:25 UTC in Brando's).

- `trait :meta` adds `content_modified_at`, moved only when a save changes the entry's text
  noticeably; Page's JSON-LD `dateModified` and the sitemap template use it ([#3000](https://github.com/brandocms/brando/pull/3000)).
  Point your own blueprints' `dateModified`, sitemap `lastmod` and any "Updated" line at
  `Brando.Blueprint.Value.modified_at/1`.

- A transformer's `listing:` card can change a field of its entry in place with
  `BrandoAdmin.Components.Form.Transformer.set_field/4`, and `listing_context true` on the
  `inputs_for` gives it `@index` and `@entries` ([#2967](https://github.com/brandocms/brando/pull/2967)).

- `Brando.Uploads.Direct` lets a site's own forms upload files straight to the bucket, without an
  admin user ([#2968](https://github.com/brandocms/brando/pull/2968)).

- An image field whose CDN config sets `direct: true` uploads straight to the bucket, like files ([#2968](https://github.com/brandocms/brando/pull/2968)).

- `hidden_folder` on an image or file config files the field's uploads in a folder kept out of the
  media library ([#2968](https://github.com/brandocms/brando/pull/2968)).
  Run `mix brando.gen.migrations` for `brando_199`.

- Blueprints set an icon with `content_icon "folder-kanban"` (a Lucide name), shown in the sidebar,
  dashboard, link picker and listing headers; `menu_item` and `menu_subitem` take `icon:`.
  Show it in a listing header with `<Workspace.header icon={@page_icon}>`.

- Image sizes are checked when a blueprint compiles, `sizes: :standard` gives Brando's preset list,
  and Utilities recreates only the images whose size config changed ([#2929](https://github.com/brandocms/brando/pull/2929)).
  Fix size configs the build now rejects: unknown keys, unreadable geometry, a cropped
  single-dimension size without `"ratio"`, a `srcset` naming a size not in `sizes`.
  Run `mix brando.gen.migrations` for `brando_197`, then `mix brando.images.adopt` to fingerprint
  existing images whose files already match their config.

- Signed-in admins can edit a page's blocks, and the fields a template marks, on the published site
  in a sidebar ([#2918](https://github.com/brandocms/brando/pull/2918)).
  Turn it on with `config :brando, Brando.FrontendEdit, enabled: true` and
  `plug Brando.Plug.FrontendEdit` in the browser pipeline.
  Mark editable fields with `<.editable_field entry={@page} field={:title} />` or `<.editable …>` in
  HEEx, `{% editable_field entry.title %}` or `{% editable … %}…{% endeditable %}` in Liquex; see
  the [Frontend edit guide](guides/frontend_edit.md).

- Brando sends its own email, such as user notifications, through the application's Swoosh
  mailer ([#2915](https://github.com/brandocms/brando/pull/2915)).
  Set the mailer and sender (`mix brando.gen.mail` and `mix brando.migrate55` set the mailer when
  the application has one):

  ```elixir
  config :brando, mailer: MyApp.Mailer
  config :brando, Brando.Mailer, from: {"My site", "noreply@example.com"}
  ```

  An application without a mailer sets `config :swoosh, api_client: Swoosh.ApiClient.Req`
  (`mix brando.migrate55` does). See the [Email guide](guides/email.md).

- Users can turn on two-factor authentication with an authenticator app, a superuser can require it
  of everyone or some roles under Users → Sign-in policy, and repeated failed sign-ins lock the
  account for a while ([#3018](https://github.com/brandocms/brando/pull/3018)).

- Users can sign in with passkeys, sensitive actions ask for the password, a code or a passkey again
  after ten minutes, and Security lists the user's sessions and logs them out ([#3019](https://github.com/brandocms/brando/pull/3019)).
  Opt a screen in with `on_mount {BrandoAdmin.Reauth, :screen}` or
  `on_mount {BrandoAdmin.Reauth, events: [...]}`.

- The login page has "Forgot password?", which emails a reset link, and a superuser sends a user a
  reset link instead of setting the password in the user form ([#3001](https://github.com/brandocms/brando/pull/3001)).
  `UserNotifier.deliver_confirmation_instructions/2` and `deliver_update_email_instructions/2` are
  removed; drop any calls. Reset email needs the mailer from the [Email guide](guides/email.md).

- Editors build forms for visitors under Configuration → Forms, put them in blocks with a module's
  Form variable, and read or export the submissions under Content → Forms.
  Run `mix brando.gen.migrations` for `brando_194` and `brando_195`; statically delivered sites also
  add `form_routes()` to their router. Brando's default production CSP now allows
  `challenges.cloudflare.com`. See the [Forms guide](guides/forms.md).

- A form emails each submission to chosen recipients, can send the visitor a confirmation, and
  deletes submissions after a set number of days ([#2922](https://github.com/brandocms/brando/pull/2922)).
  Run `mix brando.gen.migrations` for `brando_196`.
  Applications that set their own `config :brando, Oban` add `Brando.Worker.FormSubmissionPurger` to
  their crontab.

- Configuration → Activity lists who created, changed, published, trashed, restored and deleted
  entries, with filters and a compare view; the editor's **Revisions** button is now **History**,
  with an Activity tab ([#2909](https://github.com/brandocms/brando/pull/2909)).
  Run `mix brando.gen.migrations` for `brando_193`.
  With group authorization, grant `brando.activity.read` to the groups that should see it.

- The video picker can add a video that is already in Mux, Bunny, Cloudflare or Vimeo without
  uploading it again; Brando never deletes these from the provider
  ([#2893](https://github.com/brandocms/brando/pull/2893)).

- `upload_strategy: :vimeo` uploads from the browser straight to Vimeo
  ([#2893](https://github.com/brandocms/brando/pull/2893)).
  Needs a Vimeo plan with video file access and a token with the `video_files` scope.

- A media ref can hold a file: add `"file"` to its `available_blocks`.

- An element marked `data-lp-preserve="VALUE"` keeps what a site's script set on it through live
  preview updates while the value is unchanged.

- Live preview dispatches `brando:livepreview:patched` on `document` after each update, so a site
  can re-initialise sliders and other widgets in the patched elements
  ([#2896](https://github.com/brandocms/brando/pull/2896)).

- A site without tenancy can remove the files of deleted media with the nightly orphan cleanup,
  which now leaves dotfiles alone.
  Enable it with `config :brando, media_orphan_cleanup: true`.
  `Brando.Media.OrphanCleanup.run(nil, dry_run: true)` reports what it would remove.

- An empty block field offers its namespace's content templates as a starting point; the
  field's `template_namespace` option works again.

- Utilities → Loose blocks lists block trees nothing links to, and removes the ones no revision
  can bring back, with restore from an archive.
  Run `mix brando.gen.migrations` for `brando_192`.

- The image library can sort a full folder into folders for the entries that use its images,
  and with **Not in use** on, delete every unused image in view;
  `config :brando, Brando.Images, sweep_priority: [...]` decides who gets a shared image.

- System → Assistant turns a conversation into content changes across entries that the editor
  reviews and applies, with a preview of each entry as proposed; `Brando.Content.Proposals` works
  without it ([#2865](https://github.com/brandocms/brando/pull/2865)).
  Run `mix brando.gen.migrations` for `brando_183`–`brando_187`.
  Configure `Brando.AI.Agent` with a model and budgets.
  With group authorization, grant `brando.assistant.use`.

- Pages can be synchronized across languages, and a translation's links and parent follow the
  source to the version in its own language.
  Enable with `config :brando, Brando.Pages.Page, translatable: [mode: :synchronized, ...]`
  (`translatable_sites` per site in a tenant installation).
  `language_controlled_fields` lets each language keep its own chosen assets.
  Creating a translation needs a duplicate mutation in the context; without one it returns
  `{:error, :not_duplicable}` and the admin does not offer it.

- A synchronized translation opens with the text to translate or review and its source-controlled
  values locked; the source gets **Save minor text corrections** (`minor: true` on
  `Brando.Blueprint.AfterSave.run/5`), translations **Make independent** and **Make source**.

- `source_controlled_fields` accepts subform fields and block-module variables, and
  `Brando.Translations.check_config/1` checks module selectors against the database.

- **Build with AI** in the block editor opens the assistant for that entry and block field.

- Configuration → Assistant guidance gives the assistant a site's conventions per site and
  environment, also settable as `config :brando, Brando.AI.Agent, guidance: …`; it needs
  `brando.assistant.configure`, which only superusers have by default.

- The assistant can attach every image or video in a named media folder.

- `Brando.AI` takes named models, so alt text can use a cheaper model that reads images; app
  `fields` config now fills in what a trait's AI options leave out.
  Set `models: [default: "...", image: "..."]`; `default_model:` still works.
  Run `mix deps.update llm_db` for Claude Opus 5.5's prices.

- `absolute_url ..., only: %{field: value}` names the entries that have a URL on the site; the
  rest get `nil` and drop out of the SEO audit, and `__url_filter__/0` gives a sitemap the same
  filter.

- Configuration → Identity has a **Services** tab; services render as JSON-LD `Service` nodes,
  and `<Brando.HTML.Services.list>` renders them on the page.
  Run `mix brando.gen.migrations` for `brando_177`.

- Identity `area_served` and `knows_about` are lists, edited with a new `:string_list` input.
  Run `mix brando.gen.migrations` for `brando_176`, which rewrites stored rows.

- Datasource blocks can emit JSON-LD for the entries they render, with the `json_ld` Liquex
  filter or the `<.json_ld>` HEEx component.

- Configuration → SEO has a **Content SEO** tab, in English and Norwegian, that scores published
  entries on their meta fields, sharing image, URL and sitemap, and offers redirects for recorded
  404s; blueprints add checks by overriding `__seo_checks__/1`.

- Content SEO writes missing meta descriptions in bulk as suggestions to review, at most
  `config :brando, Brando.SEO, max_batch: 200` per run.
  Run `mix brando.gen.migrations` for `brando_179`.

- **Review with AI** critiques an entry's meta title and description against its content.

- `:i18n_string` inputs show one tab per language and take `languages: :content`; a plain string
  cast to the type now lands under the default content language instead of `"en"`.

- AI entry translation leaves a placement alone when its image already has text in the target
  language.

- Assets → Images → Alt text lists images without alt text, estimates the cost, and writes alt
  text in the background for review, using the `:alt` field's AI options
  (`config :brando, Brando.AI, fields: [alt: [model: ...]]`).

- Content SEO checks heading structure, image alt text and how language versions differ.

- Content SEO shows visitors and searches per entry from Plausible and Google Search Console
  when `config :brando, Brando.SEO.Analytics, ...` is set; see the Content SEO guide.

- Content SEO flags thin content, under `config :brando, Brando.SEO, thin_content_words: 300`,
  and a meta description that opens by repeating the title.

- Content SEO writes one entry's meta description without opening it, with the prompt from
  `trait :meta, ai: [...]`; hidden unless `Brando.AI` has a provider.

- Entries record who last edited them and when (`updated_by`, `edited_at`), and the listing
  shows the editor; `trait :creator, derived: [...]` names fields that do not count as edits.
  Run `mix brando.gen.migrations` for `brando_175`.
  Run `mix brando.gen.blueprint_migration --all` for your own blueprints.

- `mix brando.setup` runs asset builds, the database, a superuser and seeds after
  `mix brando.install`, and resumes after a failure.

- `mix brando.gen.seeds` seeds what a new installation needs to serve `/`: identity, SEO,
  modules, a welcome `index` page, a `main` menu and a footer fragment.

- The installed frontend has a dark default theme with shared `.label`, `.button`, `.textlink`
  and `.section-head` styles.

- Replacing phx.new's homepage route with CMS pages also removes its generated request test,
  unless you changed it.

- Module definitions export and import as DSL files with HEEx or Liquid templates, from the admin
  or `mix brando.modules` ([#2790](https://github.com/brandocms/brando/pull/2790)).
  Run `mix brando.gen.migrations` for `brando_172`.

- `BRANDO_VITE_FRONTEND_HOST`/`_PORT` and `BRANDO_VITE_ADMIN_HOST`/`_PORT` set the Vite
  development servers, so several projects can run HMR at once.

- Text refs and rich-text fields can have footnotes, and blocks refs can have named regions; see
  [Footnotes and block regions](guides/footnotes.md) ([#2760](https://github.com/brandocms/brando/pull/2760)).
  Run `mix brando.gen.migrations` for `brando_169`.

- File listings offer **Replace file**, which keeps the file's ID, URL and references
  ([#2756](https://github.com/brandocms/brando/pull/2756)).

- Blueprint forms keep recovery copies of unsaved changes that the editor can compare and restore
  ([#2757](https://github.com/brandocms/brando/pull/2757)).
  Run `mix brando.gen.migrations` for `brando_168`.

- `trait :permalink` offers a 301 redirect from the old URL when an editor changes an entry's URL
  ([#2754](https://github.com/brandocms/brando/pull/2754)).

- Saving a module keeps the references it no longer declares instead of deleting them from every
  block, warns before a save that orphans content, and versions modules and blocks
  ([#2750](https://github.com/brandocms/brando/pull/2750)).
  Run `mix brando.gen.migrations` and `mix brando.migrate` for `brando_167`.

- `mix brando.setup.tenancy` configures tenancy in an existing application
  ([#2742](https://github.com/brandocms/brando/pull/2742)).

- Sites with `delivery_mode: :static` get a Publishing screen that builds, versions, previews,
  deploys and rolls back static builds ([#2742](https://github.com/brandocms/brando/pull/2742)).

- A video input takes playback defaults for new videos:
  `input :video, :video, defaults: %{loop: true, muted: true}`.

- Brando logs misconfigured video providers at boot;
  `config :brando, :strict_video_provider_config, true` raises instead.

- `Brando.Videos.Uploaders.Mux`, `.Bunny` and `.Cloudflare` have `configured?/0`.

- A failed provider video upload shows editors a readable message from
  `Brando.Uploads.video_upload_error_message/1`.

- Blueprint fields take `one_of:` and `exactly_one_of:` constraints (an image or a video) and
  `check:` for the matching database constraint, on attributes, relations and assets.
  Asset `constraints:` are now verified at compile time, so a typo there fails the build.

- Transformer subforms take a mixed drop of images and videos, show a placeholder card per file in
  filename order, let you pick or swap an existing asset per entry, and gain the subform options
  `layout: :list | :grid` and `add_entry: false`.

- Module variables have a width, a row break and a placement (block, configure modal or hidden),
  replacing `important`, and the module editor lays them out on a drag-and-drop canvas with a live
  preview; existing vars keep one var per row ([#2522](https://github.com/brandocms/brando/issues/2522)).

- Multi-user block editing syncs on blur, includes child blocks and structural changes, catches late
  joiners up on unsaved block and entry-field edits, and keeps block and field locks in place.

- Deleting a block shows an undo toast that restores the whole subtree, including its database rows.

- All uploads go through one upload manager with its own queue and drawer, so progress no longer
  re-renders the form and large entries upload much faster.
  Optional: `config :brando, Brando.Uploads, max_concurrent_transfers: 3`; direct S3/Spaces
  uploads with `cdn: %Brando.CDN.Config{enabled: true, direct: true}` on `Brando.Files`.

- Gallery fields take video uploads through an "Upload videos" button when the video strategy is
  `:local`, and the whole gallery input accepts dropped images.

- The live preview drawer has a Refresh button, and the admin's breakpoint debug overlay is off unless
  the `:show_breakpoint_debug` config is set.

- Block field relations accept `constraints: [require_blocks: ["header"]]` to require blocks of
  given module classes on save (drafts are not checked) ([#2573](https://github.com/brandocms/brando/issues/2573)).

- The block field dropdown opens a block outline drawer with a tree of all blocks, click to scroll and
  drag-and-drop reordering ([#2667](https://github.com/brandocms/brando/issues/2667)).

- Several users can edit the same entry at once, with presence indicators on fields and blocks.

- The TipTap editor links to content identifiers ([#2527](https://github.com/brandocms/brando/issues/2527)).

- Mux and Bunny are supported as video upload and streaming providers.

- Media browser folders can be reordered by drag and drop.

- Blueprints pass an `extensions` option to Spark for external blueprint extensions.

- JSON-LD output is one connected `@graph` document, with a `WebPage` entity added on every page
  and an `@id` on content entities; see `guides/jsonld.md`.

- Pages have a JSON-LD type (`WebPage`, `Article`, `AboutPage`, `ContactPage`,
  `CollectionPage`, `ItemPage`, `ProfilePage`), set in the admin's Advanced tab.

- The Identity form has fields per organisation type, such as founding date, opening hours or
  cuisine ([#2734](https://github.com/brandocms/brando/issues/2734)).

- The JSON-LD DSL has a `{:list, SchemaModule}` field type, and `put_json_ld/3` can be called
  several times to add more entities to a page.

- `identifier` and `absolute_url` accept `~H` templates, and associations used in either
  template are preloaded automatically.

- Text blocks support style presets for `p`, `h1`–`h6` and `span`, shown in the TipTap
  toolbar, and new text refs start with a `p.lede` style; see `guides/villain_text_styles.md`.

- `:text`, `:textarea` and `:rich_text` inputs, and the Meta trait's fields, can generate
  their content with AI through an `ai: [...]` option.

#### Fixes

- In a multi-select over a `has_many` relation, removing a selection whose option is no longer offered
  removes that selection ([#3116](https://github.com/brandocms/brando/pull/3116)).

- Duplicating a module works again and copies its refs, vars, child modules and module sets, with the
  class `<class>-copy` ([#3103](https://github.com/brandocms/brando/pull/3103)).

- Mention emails no longer go to someone who has lost read access to the entry, and summaries over
  their limit send the rest in another email ([#3120](https://github.com/brandocms/brando/pull/3120)).

- The Assistant recovers from a stopped, reconnected or interrupted run, and from a failed apply,
  without a reload ([#3104](https://github.com/brandocms/brando/pull/3104)).

- Two editors in an entry's fields keep each other's changes, and a field unlocks when its editor
  leaves it ([#3071](https://github.com/brandocms/brando/pull/3071)).

- With group authorization, a scheduled publication its user may no longer make is cancelled and the
  entry goes back to draft, instead of being retried ten times; a schedule whose user no longer exists
  runs as the system ([#3121](https://github.com/brandocms/brando/pull/3121)).

- Every editor in an entry sees an image or video finish processing without reloading
  ([#3079](https://github.com/brandocms/brando/pull/3079)).

- Image sizes given only a height (`"x400"`) are made, and cropped sizes come out at their exact size
  ([#3058](https://github.com/brandocms/brando/pull/3058)).
  Recreate the affected images to get the new files.

- Restoring a revision no longer moves the entry into or out of the trash, and a scheduled revision
  that comes due while its entry is in the trash is cancelled
  ([#3123](https://github.com/brandocms/brando/pull/3123)).

- A change to an entry in the trash sends no `entry.updated` webhook or IndexNow submission
  ([#3123](https://github.com/brandocms/brando/pull/3123)).

- A width-only image size such as `"700"` is that wide for portraits too, and no size is enlarged
  beyond the original, for images uploaded or recreated from now on
  ([#3060](https://github.com/brandocms/brando/pull/3060)).

- A `srcset` lists each file's real width, and sizes that end up equally wide once
  ([#3060](https://github.com/brandocms/brando/pull/3060)).

- `ai_actions:` and `write_with_ai:` that read blocks get the block editor's unsaved content
  ([#3119](https://github.com/brandocms/brando/pull/3119)).

- Saving no longer takes focus from the field being typed in or loses keystrokes, and unsaved work in
  a block another editor removed comes back in place
  ([#3055](https://github.com/brandocms/brando/pull/3055)).

- Saving a revision loaded as a working copy writes it
  ([#3038](https://github.com/brandocms/brando/pull/3038)).

- Activating a revision loaded as a working copy no longer brings back the unsaved changes it replaced
  ([#3037](https://github.com/brandocms/brando/pull/3037)).

- After an edit session restarts, a running save keeps a returning editor's changes, and the returning
  editor's changes to a block replace only the fields they changed
  ([#3124](https://github.com/brandocms/brando/pull/3124)).

- A block moved into another container keeps its module, refs, vars and child blocks, and saves
  ([#3127](https://github.com/brandocms/brando/pull/3127)).

- Restoring a revision puts blocks back in the container and position the revision had them
  ([#3131](https://github.com/brandocms/brando/pull/3131)).

- An editor rejoining with changes to a new block another editor also held gets them back as a copy
  ([#3134](https://github.com/brandocms/brando/pull/3134)).

- A row another save removed is no longer saved back as an empty row, and a block removed while the
  edit session restarted comes back with the returning editor's changes
  ([#3133](https://github.com/brandocms/brando/pull/3133)).

- Pages emit their Article in structured data again
  ([#3027](https://github.com/brandocms/brando/pull/3027)).

- `mix brando.assets.setup` builds the admin in fresh installs again
  ([#3009](https://github.com/brandocms/brando/pull/3009)).
  Existing projects: run `mix brando.gen.backend --upgrade` to pin `@codemirror/language` to 6.12.4
  through `pnpm.overrides`.

- Listings with two or more alternates render again
  ([#2978](https://github.com/brandocms/brando/pull/2978)).

- `{% picture %}` renders a gallery object's image, and module code that loops over a variable
  assigned from a gallery ref is rewritten ([#2978](https://github.com/brandocms/brando/pull/2978)).
  Run `mix brando.gen.migrations` and migrate for `brando_200`. `brando_141` is now a no-op.

- `Brando.Users.create_user/2` and `update_user/3` hash the password
  ([#2977](https://github.com/brandocms/brando/pull/2977)).
  Code that passed a pre-hashed password to the context must pass the plain text.
  Reset the passwords of users stored in plain text:
  `SELECT id, email FROM users WHERE password NOT LIKE '$2%'`.

- Context `create_*` and `update_*` set `publish_at` and queue the sync of synchronized translations
  ([#2977](https://github.com/brandocms/brando/pull/2977)).
  Drop any `Brando.Translations.source_saved/2` call made after a context save.
  `minor: true` is now a mutation option.
  `Brando.Blueprint.AfterSave.run/4` runs only the traits' `after_save/3` and takes no options.

- The migration chain replays on a 0.51 database
  ([#2968](https://github.com/brandocms/brando/pull/2968)).

- Boolean globals render their value ([#2972](https://github.com/brandocms/brando/pull/2972)).

- `mix brando.identifiers.sync` carries on past a failing entry, lists failures and exits with status 1
  ([#2972](https://github.com/brandocms/brando/pull/2972)).

- `localized_path/3` works in development
  ([#2968](https://github.com/brandocms/brando/pull/2968)).

- Image processing and CDN jobs run without an admin user
  ([#2968](https://github.com/brandocms/brando/pull/2968)).

- A form with errors says the live preview can't open until the fields are corrected
  ([#3126](https://github.com/brandocms/brando/pull/3126)).

- Live preview block updates keep a block's `<style>`, `<script>`, `<link>` and `<meta>` markup and
  table rows ([#2896](https://github.com/brandocms/brando/pull/2896)).

- "Add from URL" on an entry's video field no longer crashes the form
  ([#2890](https://github.com/brandocms/brando/pull/2890)).

- Unlisted Vimeo videos play ([#2893](https://github.com/brandocms/brando/pull/2893)).

- Shared preview links no longer break on deploy
  ([#2799](https://github.com/brandocms/brando/pull/2799)).
  Run the `brando_173_add_asset_set_to_previews` upgrade migration; recreate broken previews made
  before it.
  Deployment tooling must delete asset sets through `Brando.Assets.SiteAssets.Retention`.

- Container blocks can be inserted, nested and copied again
  ([#2761](https://github.com/brandocms/brando/pull/2761)).

- Text in modal dialogs is the size of the controls beside it, and footer buttons have a gap
  ([#2750](https://github.com/brandocms/brando/pull/2750)).

- The identifier picker's filter works, its schema buttons show the selected type, and a picker limited
  to one schema renders.

- The block picker shows a library badge only on shared and customized modules.

- The link var's identifier modal gives the entry list the full width.

- A missing module renders a placeholder for its block and no longer breaks the whole render.

- About 450 admin strings that showed in English are translated to Norwegian.

- A multi module's children stay in live preview on edit, and reactivating one renders them instead of
  `[$ content $]`.

- Block var modals no longer take the block's input styles.

- Picture and video captions use the rich text editor again; `rich_text/1` takes `reset` and
  `default_value` attrs.

- Gallery refs render their images and videos.

- The `playsinline` settings that had no effect are removed from the video drawer, the video block and
  the `{% video %}` tag; videos still play inline.

- A block's identifiers keep their order across re-renders.

- Picture and video refs keep their block-level settings (lazyload, placeholder, moonwalk, play button,
  loop, cover) and a site's parser overrides are called again; video blocks without `cover` lose the
  SVG cover, `loop: false` stops looping, and the video block gains a `progress` setting.
  Re-render blocks saved with the broken code: `mix brando.entries.resave`.

- `BrandoWeb.Plugs.MuxWebhook` answers a malformed signature header with a 401.

- The video upload control no longer shows when a provider's credential is not a string.

- S3 credentials no longer appear in exception messages or `inspect/1` of a media config.
  Code that interpolates `Brando.CDN.get_s3_config/2` with `as: :keyword_list` must drop the
  credentials itself.

- The Bunny video provider no longer sends its API key along a redirect to another host.

- `overwrite: true` and `force_filename` overwrite on the CDN path.

- The admin login screen no longer flashes before it animates in.

- Presence and block sync work on a new entry straight after the first save-and-continue, without a
  reload.

- Edits, inserts and deletes of nested child blocks persist on save, including deleting a parent's
  last child.

- The video block has a button to reset it to the ref's defaults.

- A video or map block keeps its newly picked video or embed URL when another block is inserted or
  deleted.

- Inserting a map block no longer crashes the form.

- The upload manager survives storage errors, honours the folder browser's folder, shows rejected
  and failed files as errors, no longer wedges its queue, pushes server uploads to the CDN, and
  delivers to nested image and file fields.

- Known limitation: the upload manager ignores a function `upload_path` in gallery asset options
  and stores under the config's static `upload_path`.

- JSON-LD uses `https://schema.org` as `@context` throughout, breadcrumb URLs are absolute,
  `PostalAddress.addressRegion` maps to the region, `CreativeWork.build/1` works, and pages include
  their `meta_image` as `image`.

- Block recovery no longer triggers on a fresh navigation.

- Deleting a user transfers their content instead of leaving orphaned records.

- Form inputs render their `placeholder`.

- The `EntryRenderer` and `EntryCascade` Oban workers deduplicate in-flight jobs.

- A freshly picked picture or video ref stays in the live preview when another part of the block is
  edited.

- A picture ref's "Pick an existing image" button opens the image drawer directly.

#### Dependencies

- `oban` `~> 2.23` (locked at 2.24.1); the old configuration shape and module names keep working.

- `req_llm` 1.21.1, then 1.26.

- `image` 0.69, `req` 0.7.5, `sentry` 13.5, `postgrex` 0.22, `mox` 1.3, `ecto_nested_changeset` 1.1,
  `spark` 2.7.6, `tz` 0.28.4, and `earmark`, `floki`, `credo`, `ex_doc`, `igniter`.

- `ecto` and `ecto_sql` 3.14.

- `mdex` `~> 0.14.0`; rendered output is unchanged.

- brandojs drops `vex-js`, `vex-dialog`, `vanilla-click-outside`, `lodash.throttle`, `linkifyjs`,
  `phoenix_html` and `@fontsource/jetbrains-mono` ([#2980](https://github.com/brandocms/brando/pull/2980)).

#### Security

- `html_sanitize_ex` 1.5.5 fixes two CPU-exhaustion denials of service in the scrubber Brando runs on
  user content (CVE-2026-68749, CVE-2026-68750), and `xml_builder` moves to 2.4.1.

- `postgrex` 0.22.4 fixes SQL injection through the `:comment` option of `Postgrex.stream/4`
  (CVE-2026-66838).

- Admin JS: `@tiptap/*` 3.31.4 and `prosemirror-view` 1.42.6 fix an XSS in paste handling, and
  `dompurify` moves to 3.4.16 ([#2980](https://github.com/brandocms/brando/pull/2980)).

## 0.54.0

Before running the migration script, move parameters passed to the `form` macro into their own
calls:

```elixir
# before
form default_params: %{"status" => "draft"} do
  # ...
end

# after
form do
  default_params %{"status" => "draft"}
  # ...
end
```

Then:

1. `mix brando.upgrade` to pull down the migrations.
2. Commit all changes, then `mix brando.migrate54`.
3. `mix ecto.migrate`.
4. `mix brando.entries.resave` and `mix brando.identifiers.sync`.
5. Sync translations: `chmod +x scripts/sync_gettext.sh`, then
   `./scripts/sync_gettext.sh priv/gettext/backend/no/LC_MESSAGES`.

### Features

- Listing filters take `type: :boolean` (a toggle switch) and `type: :select` (a dropdown with
  static `option "News", "news"` entries or an `options &fun/1`); filter state lives in the URL.
  In the block form (`filter do … end`), set every property inside the block.
- Form inputs take `hidden:` as a boolean, a `{:field, value}` tuple (atoms and strings compare
  equal) or `fn form -> boolean end`.
- Galleries hold videos as well as images.
- Galleries have their own listing and a reworked admin.
- An image editor with live crop previews, also opened from picture and gallery blocks.
- A compact image input variant for subforms.
- Picture block uploads run in the background with live progress.
- Gallery blocks and image and file vars upload through LiveView.
- Live preview recovers from a lost connection, and shared previews carry better metadata.
- `livepreview.js` uses newer `morphdom` features.
- Block toolbar actions sit in a dropdown menu.
- Module export and import include table templates.
- A listing action re-renders an entry's blocks.
- Cascades and revisions are processed in background Oban jobs.
- Generated mix templates include listeners.
- Generated frontend templates use `pnpm`.

### Fixes

- An upload submits once when its event fires several times.
- Fixed video rendering edge cases for `:upload` and `:external_file` videos.
- The video pipeline parses HLS manifests.
- Invalid block refs are cleaned out.
- Table and template workflows generate unique IDs.
- Updating relations when the entries are absent no longer crashes.
- Fixed listing filter shortcuts.

### Breaking Changes

- Listing filters name their field `key:`.
  Replace `filter label: "Title", filter: "title"` with `filter label: "Title", key: "title"`.
- Galleries have `gallery_objects` ([#2639](https://github.com/brandocms/brando/pull/2639)).
  In templates, replace `{{ entry.my_gallery.gallery_images }}` with
  `{{ entry.my_gallery.gallery_objects }}`.
- `mix brando.digest` replaces `mix phx.digest` for Vite projects, so chunks load once.
  Change it in your Dockerfile and install the latest Vite.
- Remove `?vsn=d` from your `fonts.css` and from the fonts preloaded in `<.head>`.
- Brando needs the repo module in config.
  Add `config :brando, repo_module: MyApp.Repo` to `config/brando.exs`.
- Vite 5+ writes its manifest to `.vite` by default.
  In `assets/front/vite.config.js`, replace `manifest: true` with `manifest: 'manifest.json'`.
- The Listings DSL moved to Spark; see the full example in `guides/listings.md`.
- The JSON-LD DSL moved to Spark; see `guides/jsonld.md`. Rename `json_ld_field` to `field`.
- The Meta DSL moved to Spark; see `guides/meta.md`. Rename `meta_field` to `field`.
- Gettext's new API changes how you use it.
  Replace `import MyAppAdmin.Gettext` with `use Gettext, backend: MyAppAdmin.Gettext`, and in your
  app's `gettext.ex` replace `use Gettext, otp_app: :my_app, priv: "priv/gettext/backend"` with
  `use Gettext.Backend, otp_app: :my_app, priv: "priv/gettext/backend"`.
- Admin `Create` and `Update` views are one `Form` view
  ([#2389](https://github.com/brandocms/brando/pull/2389)).
  Move custom logic from your `Create` view into the `Update` view's mount, behind
  `if socket.assigns.live_action == :create do … end`, and switch the heading in `render`:
  ```heex
  <%= if @live_action == :create do %>
    <%= gettext("Create project") %>
  <% else %>
    <%= gettext("Update project") %>
  <% end %>
  ```
  Rename the `Update` view (e.g. to `ProjectFormLive`), delete the `Create` view and change the
  routes in `router.ex`:
  ```elixir
  scope "/projects", MyAppAdmin.Projects do
    live "/projects", ProjectListLive
    live "/projects/create", ProjectFormLive, :create
    live "/projects/update/:entry_id", ProjectFormLive, :update
  end
  ```
- `:entries` relations (related entries) have no generated `_identifiers` association: with
  `relation :related_entries, :entries, constraints: [max_length: 3]`, `:related_entries` is the
  join table between your schema and the identifiers table.
  Load the entries through it:
  ```elixir
  identifiers = Enum.map(case.related_entries, & &1.identifier)
  case_ids = Enum.map(case.related_entries, & &1.identifier.entry_id)
  related_cases = Cases.list_cases!(%{matches: %{ids: case_ids}})

  # or
  Brando.Content.get_entries_from_identifiers(identifiers, %{preload: [:categories, :cover]})
  ```
- Blocks are stored in their own table ([#2361](https://github.com/brandocms/brando/pull/2361)).
  - Rename `Brando.Villain.list_villains/0` to `Brando.Villain.list_blocks/0`.
  - Replace `trait Brando.Trait.Villain` with `trait Brando.Trait.Blocks`.
  - Remove the old `:villain` type `data` attributes and add the relation:
    ```elixir
    relations do
      relation :blocks, :has_many, module: :blocks
    end
    ```
  - Resave your entries: `mix brando.entries.resave`.
- Identifiers have a `url` field ([#2361](https://github.com/brandocms/brando/pull/2361)).
  Set `persist_identifier false` in every blueprint that should not create identifiers, then run
  `mix brando.identifiers.sync` to create missing identifiers, delete orphaned ones and update
  URLs.
- Navigation items have `link` type vars, iterated with the `<.menu>` and `<.menu_item>`
  components:
  ```heex
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
- A `<.head>` component orders head elements.
  Replace the `<head>` in your frontend app with it:
  ```heex
  <.head
    conn={@conn}
    fonts={[{:woff2, "/fonts/MyFont-Regular.woff2"}]}
  >
    <:prefetch>
      <link href="//player.vimeo.com" rel="dns-prefetch" />
    </:prefetch>

    <link rel="shortcut icon" href="/ico/favicon.ico" />
    <meta name="format-detection" content="telephone=no" />
  </.head>
  ```
- Multi selects take a `wrapped_labels` option.

## 0.53.0

- Replace `import Phoenix.LiveView.Helpers` with `import Phoenix.Component`.
- Bump dependencies:
  ```elixir
  {:phoenix_live_view, "~> 0.20"},
  {:phoenix_live_dashboard, "~> 0.8"},
  ```
- Vite 3 outputs `admin/main.css` in place of `admin/admin.css`.
  In `assets/backend/vite.config.js`, replace `manifest: false` with
  `manifest: 'admin_manifest.json'`. With a manifest you can hash the file names:
  ```js
  entryFileNames: `assets/admin/admin-[hash].js`,
  chunkFileNames: `assets/admin/__[name]-[hash].js`,
  assetFileNames: `assets/admin/admin-[hash].[ext]`
  ```
- Svelte's Vite plugin requires ES modules.
  - Upgrade Vite and its plugins past 4.
  - Set `"type": "module"` in `assets/backend/package.json`.
  - Rename `assets/backend/postcss.config.js` to `postcss.config.cjs` and
    `assets/backend/europa.config.js` to `europa.config.cjs`.
  - Upgrade europacss in `assets/backend` past 0.12.
- Sentry 10.x.
  Add to your `Dockerfile` before `mix release`:
  ```dockerfile
  RUN mix sentry.package_source_code
  RUN mix release
  ```
  Remove the `included_environments` key from the `:sentry` config in `config/prod.exs`, and copy
  the Sentry config to the other environments that should report, e.g. `config/staging.exs`.
- The Presence module changed.
  In `lib/my_app/presence.ex`:
  ```elixir
  use BrandoAdmin.Presence,
    otp_app: :my_app,
    pubsub_server: MyApp.PubSub,
    presence: __MODULE__
  ```
- Update forms show who else is editing ([#1856](https://github.com/brandocms/brando/pull/1856)).
  Add `presences={@presences}` to the `Form` live component in your update views:
  ```heex
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
- Replace `<%= csrf_meta_tag %>` with `<.csrf_meta_tag />`.
- Replace `<%= google_analytics(...) %>` calls with `<.google_analytics code="...." />`.
- Brando dropped `use Phoenix.HTML`, so `error_tag` in `error_helpers.ex` stops working.
  Implement frontend errors as in Phoenix's
  [`core_components.ex`](https://github.com/phoenixframework/phoenix/blob/main/installer/templates/phx_web/components/core_components.ex).
- Vite 5 needs the manifest path set.
  Replace `manifest: true` with `manifest: 'manifest.json'`.
- Related entries (`:entries`) store identifiers in a table and reference it. The blueprint and
  form setup stay as before:
  ```elixir
  relation :related_entries, :entries, constraints: [max_length: 3]

  input :related_entries, :entries,
    label: t("Related entries"),
    sources: [{__MODULE__, %{preload: [], order: "asc title", status: :published}}],
    filter_language: true
  ```
- Datasource selection callbacks work on identifiers.
  The list callback returns identifiers, and the select callback receives them as its only
  argument:
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
- `mix brando.upgrade` changed.
  Copy the new script into your application:
  ```sh
  cp deps/brando/priv/templates/brando.install/lib/mix/brando.upgrade.ex lib/mix/brando.upgrade.ex
  ```
- `:many_to_many` relations are deprecated in favour of `:has_many` `through` associations
  ([#1960](https://github.com/brandocms/brando/pull/1960)).
  Replace
  ```elixir
  relation :contributors, :many_to_many,
    module: Articles.Contributor,
    join_through: Articles.ArticleContributor,
    on_replace: :delete,
    cast: true
  ```
  with
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
  To use `ArticleContributor` in a multi select, add `@allow_mark_as_deleted true` to that schema
  and a `relation_key` to the input:
  ```elixir
  input :article_contributors, :multi_select,
    options: &__MODULE__.get_contributors/2,
    relation_key: :contributor_id,
    resetable: true,
    label: t("Contributors")
  ```
- `ErrorView` is now `ErrorHTML` ([#1855](https://github.com/brandocms/brando/pull/1855)).
  If you use Brando's error templates, set your endpoint's `render_errors`:
  ```elixir
  config :my_app, MyApp.Endpoint,
    render_errors: [
      formats: [html: Brando.ErrorHTML, json: Brando.ErrorJSON], layout: false
    ]
  ```
  and the view in `fallback_controller.ex`: `|> put_view(html: MyAppWeb.ErrorHTML)`.
- `delete_selected` is a built-in listing selection action.
  Remove your own `delete_selected` from the listing's `selection_actions`.
- Listing rows have default `edit`, `delete` and `duplicate` actions.
  Remove these from your listings, or they show twice.
- `@identity` is the current language's identity, where it was a map of all languages.
- Module blocks with a datasource replace datasource blocks.
  Run `mix brando.upgrade && mix ecto.migrate` to convert existing datasource blocks.
- The admin reads JS and CSS from `priv/static/admin_manifest.json`.
  Set `manifest: 'admin_manifest.json'` in `assets/backend/vite.config.js`.
- CDN config is set per asset module.
  Replace `config :brando, Brando.CDN, …` with, e.g.:
  ```elixir
  config :brando, Brando.Images, cdn: [enabled: false]
  config :brando, Brando.Files, cdn: [enabled: true, ...]
  ```
- Replace the `<%= live_patch gettext("Create new") ...` calls in your list views
  ([#1855](https://github.com/brandocms/brando/pull/1855)):
  ```heex
  <.link navigate={@admin_create_url} class="primary">
    <%= gettext("Create new") %>
  </.link>
  ```
- Brando uses Phoenix 1.7's `embed_templates` and dropped Phoenix.View
  ([#1855](https://github.com/brandocms/brando/pull/1855)).
  - If your app depends on Phoenix.View, add `{:phoenix_view, "~> 2.0"}`.
  - Optionally replace `use MyAppWeb, :controller` (etc.) with `use BrandoWeb, :controller` (etc.),
    or `use BrandoWeb, :legacy_controller` for the new layouts with regular template views.
  - Convert your layout templates to HEEx, rename the layout view to `MyAppWeb.Layouts`, move it
    to `my_app_web/components/layouts.ex` and add:
    ```elixir
    use BrandoWeb, :html

    embed_templates "components/layouts/*"
    embed_templates "components/partials/*"
    ```
  - Move your partials from `templates/page` to `components/partials`, drop their leading `_`,
    and call them in `app.html.heex` as `<.navigation {assigns} />`, `<.footer {assigns} />` etc.
- `live_preview.ex` sets layout and template in a new format
  ([#1855](https://github.com/brandocms/brando/pull/1855)).
  Replace `layout_module`/`layout_template`/`view_module`/`view_template` with, for
  Phoenix.Template:
  ```elixir
  layout {MyAppWeb.Layouts, :app}
  template {MyAppWeb.ProjectHTML, "detail"}
  # or
  template fn e -> {MyAppWeb.ProjectHTML, e.template} end
  ```
  or for Phoenix.View:
  ```elixir
  layout {MyAppWeb.LayoutView, "app.html"}
  template {MyAppWeb.ProjectView, "detail.html"}
  # or
  template fn e -> {MyAppWeb.ProjectView, e.template} end
  ```
- Emails are sent through Finch.
  Add `{:finch, "~> 0.13"}` to `mix.exs`, `config :swoosh, :api_client, MyApp.Finch` to your
  config, and `{Finch, name: MyApp.Finch}` to the children in `lib/my_app/application.ex`, after
  `{Phoenix.PubSub, name: MyApp.PubSub}` and before `MyAppWeb.Endpoint`.
- Preview links expire after `config :brando, :preview_expiry_days, 31`; the default is two days.
- Alternate entries.
- A `select` var type.
- Villain parsers take a `video_file_options/1` callback returning a keyword list of options for
  video blocks.
- A split dropdown button on form tabs for more save options.
- Saving an entry without redirecting updates its revisions.
- Scheduled publishing for revisions.
- Fixed the max width of `#content`.
- Uploaded gallery images are added to the gallery.
- Forms take an `after_save: &fun/2` option and an `alert :info, t("…")` element.
- Password inputs take `confirmation: true`.
- Users with `reset_password_on_first_login` set in their config must change their password on
  first login.
  Run `mix brando.upgrade` for the migration that sets it to false for existing users.
- The file assets listing shows the media URL.
- The module list in the block editor updates when modules are added, deleted or updated.
- Multi select relations reach the live preview.
- Image fields and picture blocks accept SVG uploads.
- Images with a `dominant_color` or `svg` placeholder get a transparent SVG as `data-src`.
- Live preview shows the page shrunk in an iframe.
- Module refs are reapplied on update.
- Slug fields show the entry URL with `show_url: true`.
- Better pagination limits in listings.

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
