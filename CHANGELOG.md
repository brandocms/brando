## 0.55.0 (Unreleased)

### Upgrading

Brando 0.55 continues the `next` line that diverged from the 0.54 release in
February 2026. Projects on the `0.54` branch run `mix brando.migrate55`;
projects still on 0.53 run `mix brando.migrate54` followed by
`mix brando.migrate55`. Both tasks rewrite source only and are safe to rerun.
`mix brando.migrate54` and the deprecated Blueprint syntax it rewrites are
removed in 0.56; see "How long source migrations ship" in `UPGRADE.md`.
For a version jump, `mix igniter.upgrade brando` calls
`mix brando.upgrade FROM TO`, which runs `mix brando.migrate55` and then
copies the missing migrations. Without `FROM TO`, `mix brando.upgrade` only
points to `mix brando.gen.migrations`, and with the same version twice it does
nothing.

Then bring the database up to date. A project already on a 0.55 development
build has no source tasks to run and starts here:

1. `mix brando.gen.migrations` copies the Brando migrations the project does
   not have yet (for a 0.53 or 0.54 project, everything since `brando_130`).
2. `mix brando.gen.blueprint_migration --all` plans the columns that
   `trait :meta` and `trait :creator` now add to application schemas.
3. Review the migrations. `mix brando.migrations.check` lists Brando copies
   that have not run yet and differ from Brando's current templates.
4. `mix brando.migrate` runs them. Brando migrations whose notes below say
   "in every environment" change `public` and every environment schema in the
   same run.
5. `mix brando.migrate --tenants`, when the app has named environments, runs
   the tenant migrations in each environment, including the Blueprint
   migrations of content stored there.
6. `mix brando.entries.resave` and `mix brando.identifiers.sync`.
7. `mix brando.images.adopt`, once: images processed before 0.55 have no
   record of the config they were made with, and it records it for those
   whose files already match, so **Recreate changed images** only recreates
   the rest (see [Media](guides/media.md#images-made-before-fingerprints)).

Then the steps particular to some features, each described under Breaking:
rebuild the search index in each environment, add the `Brando.Plug.Markdown`
and `Brando.Plug.IndexNow` endpoint plugs, and, in an application that sets
`config :brando, Oban` itself, add the `content_events`, `webhooks` and
`search_index` queues and the webhook delivery purger to its crontab.
`mix brando.doctor` reports migrations that have not
run and queues that are missing.

There are no migrations numbered `brando_206` or `brando_208`: both numbers
were reserved and never needed, so the gap is not a missed migration.

Environment archives are not migrated. Restoring one taken before a
`brando_2xx` migration that changes every environment runs that migration in
the restored environment; an archive that cannot be brought up to date is
refused, and nothing is restored.

The full ordered workflow, including Blueprint snapshot handling and Gettext
recovery, is in [Migrating from 0.53 or 0.54](guides/migrating_from_053.md).
Sites still on 0.51 (the `legacy` branch, with the Vue admin) have no
automated path; [Migrating from 0.51](guides/migrating_from_051.md) is the
ordered port, with the traps of replaying the migration chain on a
production dump.

#### Breaking

- **`ai:` on a form input is deprecated, and AI no longer writes into a
  field** (#3094). `ai_actions:` (#3083) is the one per-field AI API. Every
  AI result for an entry's text, textarea or rich text field, block text
  included, is now a suggestion the editor can change, accept or discard.

  - `input …, ai: [prompt: …, context: …]` still works in 0.55, as one action
    named **Generate** beside the field's label, in place of the button
    inside the field that wrote its reply straight in. The Blueprint warns
    when it compiles, at the input, with the `ai_actions:` to write. `ai:`
    is removed in a later release. Projects that compile with
    `--warnings-as-errors` must change their inputs first. On a `:rich_text`
    input `ai:` keeps feeding Write with AI, read as `write_with_ai:` (below);
    on a `:hidden` input for a meta field it is the Meta drawer's Generate. A
    custom component still gets `ai:` in its options.
  - The Meta drawer's **Generate** on `meta_title` and `meta_description` is
    the same kind of action, from the site prompt (`trait :meta, ai_prompts:`
    or `config :brando, Brando.AI, prompts:`, renamed below); an input for a
    meta field, usually `:hidden`, can add its own `ai_actions:`.
  - **Suggest alt text** on an image's form, in the image drawer and in a
    picture block is a suggestion per language under the alt field, written
    only on Accept. It asks for the languages the field has no text in (as
    the form has it, unsaved), and Accept leaves a language written in since.
    Its request now runs in the environment the image is in;
    in a named environment it used to look for the image in the default one.
  - **Write with AI** in the rich-text toolbar gives a suggestion that can
    be edited before Accept. Where it shows is opt-in, below.
  - Site prompts still drive the Meta drawer's Generate, the Content SEO
    batch, the SEO review's model, image alt text and Write with AI in block
    text. They are documented under "Site prompts" in the forms guide, and
    renamed below.

  To upgrade, replace each input's `ai:` with the `ai_actions:` the warning
  prints:

  ```elixir
  # Before
  input :summary, :textarea, ai: [prompt: "Summarize.", context: [:title, :blocks]]

  # After
  input :summary, :textarea,
    ai_actions: [generate: [label: t("Generate"), prompt: "Summarize.", from: [:title, :blocks]]]
  ```

  `context:` becomes `from:`, which is required; name the fields the prompt
  reads where `ai:` had none. `model:` carries over. On a `:rich_text`
  input, write `write_with_ai: [prompt: …, from: […], model: …]` instead,
  as the warning prints. Move `api_key:` to
  `providers:` and request options such as `temperature:` to
  `default_opts:` in `config :brando, Brando.AI`.

- **Write with AI is opt-in, and the site prompt options are renamed**
  (#3101). Every Write with AI request is a paid call, so it shows only
  where a site asks for it.

  - A `:rich_text` input turns it on with `write_with_ai: true`, or with
    `write_with_ai: [prompt:, from:, model:]`. Without `write_with_ai:`, or
    with `false`, it is off. A deprecated `ai:` on a rich text input still
    turns it on, and its warning prints the `write_with_ai:` to write
    (`write_with_ai: true` when it had no options).
  - In block text, each module turns it on for its text blocks with
    **Write with AI** under Overview in the module editor (`write_with_ai`
    in module definition files). `brando_218` adds
    `content_modules.write_with_ai` in every environment, off in every
    existing module. Duplicating, exporting and importing a module, its
    definition files and the shared library carry the setting, and changing
    it bumps the module's version. `prompts: [block_text: [write_with_ai:
    false]]` turns it off in every module.
  - `config :brando, Brando.AI, fields:` is now `prompts:`, and
    `trait :meta, ai:` is now `trait :meta, ai_prompts:`. They hold the
    site prompts, the instructions for the AI jobs that are not a field's
    `ai_actions:`, and the names now read with `ai_actions:` and
    `write_with_ai:` rather than suggesting form fields or a field's `ai:`.
    The old names still work in 0.55 and are removed in a later release:
    Brando warns at boot about `fields:` and the Blueprint warns when it
    compiles about `ai:`, each printing the name to write. When both names
    are set, the new one wins and the warning says to remove the old one.

  To upgrade, run `mix brando.gen.migrations` and `mix brando.migrate`, add
  `write_with_ai: true` to the rich text inputs that should keep Write with
  AI, turn it on in the modules whose text blocks should have it, and rename
  the options:

  ```elixir
  # Before
  config :brando, Brando.AI, fields: [block_text: [prompt: "Keep it plain."]]
  trait :meta, ai: [meta_description: [prompt: "Write an SEO description", context: [:title]]]

  # After
  config :brando, Brando.AI, prompts: [block_text: [prompt: "Keep it plain."]]
  trait :meta, ai_prompts: [meta_description: [prompt: "Write an SEO description", context: [:title]]]
  ```

- **SEO settings, pages and `trait :meta` have new columns.** `brando_210`
  adds `crawler_policy` to `sites_seos` and `meta_nosnippet` and
  `meta_max_snippet` to `pages`, in every environment. Every application
  schema with `trait :meta` gets the two snippet columns too: run
  `mix brando.gen.migrations` and `mix brando.gen.blueprint_migration --all`,
  then `mix brando.migrate` (and `mix brando.migrate --tenants` with named
  environments); until then, loading SEO settings or those schemas fails with
  a missing-column error. Nothing changes in robots.txt or the
  page head until an editor sets the new options.

- **Modules have a `markdown_code` column, and IndexNow a table.**
  `brando_211` adds `markdown_code` (a module's optional Markdown template)
  to `content_modules` and creates `sites_indexnow` in every environment;
  run it with `brando_210`. Until then, loading modules fails with a
  missing-column error.

- **`trait :scheduled_publishing` has a new column, `unpublish_at`.**
  `brando_214` adds it to `pages` and `pages_fragments`, with an index, in
  every environment. Every application schema with
  `trait :scheduled_publishing` gets it too: run `mix brando.gen.migrations`
  and `mix brando.gen.blueprint_migration --all`, then `mix brando.migrate`
  (and `mix brando.migrate --tenants` with named environments); until then,
  loading those schemas fails with a missing-column error. Existing entries
  have no expiry. **An application that sets `config :brando, Oban` itself
  must add `{"*/10 * * * *", Brando.Worker.ScheduledPublishingSweep}` to its
  crontab**: it publishes and expires entries whose dates passed with no job,
  as after an environment clone or an archive restore, and `mix brando.doctor`
  warns when it is missing. It only takes dates from the last seven days, so
  older ones are left alone. `mix brando.scheduled_publishing.sweep` lists
  what it would do, and `Brando.Publisher.sweep(dry_run: true)` in a release.
- **A publishing job publishes only a pending entry.** A future `publish_at`
  on a draft or a deactivated entry used to publish it when the job ran; the
  job now does nothing unless the entry is still pending, and clearing
  `publish_at` or moving it into the past removes the job. The Scheduled
  publishing drawer says so on a draft with a date. **Delete job** on the
  Scheduled Publishing screen asks first, and now clears the date with the
  job (a pending entry goes back to draft), so the sweep does not publish it
  later; `Brando.Publisher.delete_job/2` takes the user to save as.

- **Markdown alternates and IndexNow need two plugs.** Add
  `plug Brando.Plug.Markdown` and `plug Brando.Plug.IndexNow` to the
  endpoint, before the router (after `Brando.Plug.LivePreview`). The first
  serves entries as Markdown at their URL + `.md`; without it, the page head
  still names the Markdown URL, and requests for it are not found. The
  second serves the IndexNow key file; without it, turning IndexNow on gets
  `403` answers. See [Markdown alternates](guides/markdown_alternates.md) and
  [IndexNow](guides/identity_and_seo.md#indexnow).

- **The admin search needs a table and an Oban queue.** `brando_212` creates
  `search_documents` in every environment. Run `mix brando.gen.migrations`
  and `mix brando.migrate`, then rebuild the index once in each environment
  from Configuration → Utilities → Search index ("Rebuild search index");
  from then on, saving keeps it up to date. The card says when the index was
  last rebuilt, or "Never rebuilt" until it is. Until the migration runs, the
  search page says search is not set up and saves carry on without it.
  Brando's default Oban configuration has the new `search_index` queue. **An
  application that sets `config :brando, Oban` itself must add it
  (`search_index: [limit: 2]`), or the index is never updated**;
  `mix brando.doctor` warns when it is missing. See `Brando.Search`.

- **Connected AI tools need four tables.** `brando_213` creates
  `mcp_settings`, `mcp_grants`, `mcp_tokens` and `mcp_authorization_codes`
  in `public`. Run `mix brando.gen.migrations` and `mix brando.migrate`. The
  remote MCP endpoint itself is opt-in: nothing is mounted until the router
  calls `mcp_routes()`, and each site environment stays off until an
  administrator turns it on. Projects that still mount BrandoMCP's old
  `plug BrandoMCP` route must remove it; `mcp_routes()` is the only network
  path to MCP. `Brando.MCP.BodyLimit`, optional, refuses an oversized MCP
  request before `Plug.Parsers` reads it. See
  [Connected AI tools](guides/mcp.md).

- **Notifications need two tables.** `brando_217` creates
  `notification_routes` and `notification_deliveries` in every environment.
  Run `mix brando.gen.migrations` and `mix brando.migrate`; until then, there
  are no notification routes and saves, notes and jobs carry on without them.
  Brando's default Oban configuration has the new `notifications` queue. **An
  application that sets `config :brando, Oban` itself must add it
  (`notifications: [limit: 2]`), or no notification is sent**;
  `mix brando.doctor` warns when it is missing. Add the Notifications permission
  (`brando.notifications.manage`) to the groups that should manage routes;
  no existing group gets it. See [Notifications](guides/notifications.md).

- **Webhooks need two tables and two Oban queues.** `brando_209` creates
  `webhooks` and `webhook_deliveries` in every environment. Run
  `mix brando.gen.migrations` and `mix brando.migrate`; until then, content
  events find no webhooks and saves carry on without them. Brando's default
  Oban configuration has the new `content_events` and `webhooks` queues. **An
  application that sets `config :brando, Oban` itself must declare both
  (`content_events: [limit: 1], webhooks: [limit: 5]`), or no content events
  and no webhook deliveries ever run**; `mix brando.doctor` warns when they
  are missing. Add `{"35 5 * * *", Brando.Worker.WebhookDeliveryPurger}` to
  its crontab as well. See
  [Webhooks and content events](guides/webhooks.md).

- **Signing out takes a DELETE, and the admin socket belongs to a session.**
  `GET /admin/logout` no longer signs out: it asks "Sign out?" and signs out
  from a button, so another site cannot sign an admin out with a link or an
  image. Links to it keep working, one click later. Brando's own sign-out
  buttons send `DELETE /admin/logout` with the CSRF token (`POST` works too,
  for an endpoint without `Plug.MethodOverride`). The admin socket's token now
  names the session, and the socket shares the session's id with its
  LiveViews: ending a session (signing out, revoking it, a password change or
  reset, a two-factor reset, deactivating or deleting the user) disconnects
  both, and the old token no longer connects. The session's socket id
  (`live_socket_id`) is now made from a hash of its token; a session from
  before the upgrade gets the new id on its next request.
  `Brando.Users.build_token/1`
  and `verify_token/1` are deprecated, and `BrandoAdmin.AdminSocket` no
  longer accepts their tokens; use `build_socket_token/2` and
  `verify_socket_token/1`. Open admin tabs pick up a new token when their
  LiveView reconnects after the deploy; open live previews need a reload. See
  [User accounts and sessions](guides/users.md#understand-sign-in-and-session-lifetime).

- **Notes need two tables.** `brando_203` creates `entry_notes` and
  `note_mentions` in every environment. Run `mix brando.gen.migrations` and
  `mix brando.migrate`; until then the entry editor's Notes panel stays empty
  and saves carry on without it.

- **The activity log has two new columns.** `brando_216` adds
  `proposal_id` and `approver_id` to `activity_events` in every environment.
  Run `mix brando.gen.migrations` and `mix brando.migrate`; until then,
  Configuration → Activity fails with a missing-column error and new events
  are dropped with a warning. Earlier changes by the Assistant or a connected
  tool get their user as the approver.

- **Content proposals have two new columns.** `origin` and `client` record
  where a proposal came from (the Assistant, or a tool connected over MCP).
  Run `mix brando.gen.migrations` and `mix brando.migrate` for `brando_207`;
  until then, loading proposals fails with a missing-column error.

- **Passkeys and session details.** `brando_205` creates `users_passkeys` and
  adds `ip`, `user_agent`, `last_used_at` and `confirmed_at` to
  `users_tokens`. Run it with `brando_204`. Sessions from before it have no
  `confirmed_at`, so their first sensitive action asks for the password.

- **Two-factor authentication adds four tables.** `brando_204` creates
  `users_security`, `users_recovery_codes`, `users_security_events` and
  `users_security_policy` in `public`. Run `mix brando.gen.migrations` and
  `mix brando.migrate`; until then, logging in fails with a missing-table error.
  Applications with their own `:shared_tables` need no change; Brando lists
  the new tables itself. Behind a reverse proxy that is not on the same
  server, list it in `config :brando, :trusted_proxies` (loopback is trusted
  by default), add `:peer_data` and `:x_headers` to the `/live` socket's
  `connect_info`, and add `"code"`, `"proof"` and `"secret"` to
  `config :phoenix, :filter_parameters`; see
  [Behind a proxy](guides/users.md#behind-a-proxy).

- **Users have two new columns.** `job_title` and `same_as` back the user
  form's Job title and Profile links. Run `mix brando.gen.migrations` and
  `mix brando.migrate` for `brando_202`; until then, loading users fails with a
  missing-column error.

- **`trait :meta` adds two columns.** Every schema with the meta trait now has
  `meta_canonical_url` and `content_modified_at`. Run `mix brando.gen.migrations`
  for Brando's pages (`brando_201`) and
  `mix brando.gen.blueprint_migration --all` for the application blueprints
  with `trait :meta`, then `mix brando.migrate` (and
  `mix brando.migrate --tenants` with named environments); until then, queries
  on those schemas fail with a missing-column error. Both migrations start
  `content_modified_at` from each row's last edit.

- **Admin icons are Lucide.** Heroicons and `assets/css/heroicons.css` are
  gone. `<.icon name="…" />` now renders `<span data-icon class="lucide-name">`,
  masked by a stylesheet Brando generates from the vendored Lucide set.
  `admin_routes` serves it at `/__brando/icons` and the admin layouts link it,
  so routers need no change. Old `hero-*` names still render through a legacy
  map (`Brando.Icons.resolve/1`), but use Lucide names in new code. App CSS
  that targets `[class^="hero-"]` or `.hero-*` must target `[data-icon]` or
  `.lucide-name` instead; colour icons with `color`.

- **Image configs with a mistyped size key or a `srcset` naming a missing
  size no longer compile.** Brando used to ignore unknown keys in a size such
  as `"crp" => true`, and a `srcset` naming a size `sizes` doesn't have only
  warned at render. Both now raise a `BlueprintError` naming the field and the
  size; fix the config it points to. A config that replaces `sizes` without
  its own `srcset` no longer inherits a default `srcset` naming sizes it lacks:
  that srcset is dropped instead of rendering broken URLs.

- **Image sizes with an ImageMagick flag other than `>` no longer compile.**
  Brando read past the flags, so `"400x400^"` was processed like `"400x400"`
  and `"50%"` as 50 pixels. A size using `^`, `!`, `%` or `<` now raises a
  `BlueprintError` naming the size and what to write instead: `"crop" =>
  true` for `^`, `"crop" => true` with a `"ratio"` for `!`, a width in pixels
  for `%` (a `srcset` needs fixed widths), and nothing for `<`, since sizes
  only shrink. A trailing `>`, as in `"400x400>"`, stays valid and changes
  nothing. Configs from a function or the `default_config` setting are
  checked when they are first read, as before.

- **Video uploads are opt-in.** `default_video_upload_strategy` now defaults
  to `:none`, and a video field without its own `upload_strategy` follows it
  instead of uploading to the server. A site that never set it loses its
  "Upload" buttons for video; picking from the library and adding by URL still
  work. To keep server uploads, add
  `config :brando, :default_video_upload_strategy, :local`, or set
  `upload_strategy: :local` on the fields that should upload.

- **Brando requires Elixir 1.18 or later.** Its dependencies already did:
  `req_llm` depends on `llm_db`, which requires 1.18. Upgrade Elixir before
  updating Brando. New sites are generated with the same requirement.
- **A `:boolean` listing filter switched off stops applying.** Switching a
  toggle off used to send `"false"` to the context filter, so the same off
  position showed every entry before the toggle was touched and only entries
  without the value after. Off now means all entries. Set `off: false` on the
  filter to keep filtering on false; it then starts there. `default: true`
  toggles can now be switched off. Active-filter chips and the reset button show
  only while a filter differs from where it starts.

- **`accept` is gone from video and file configs.** `Brando.Type.VideoConfig`
  and `Brando.Type.FileConfig` carried `accept: :any`, which nothing read (the
  file input's `accept` comes from `allowed_mimetypes`). A Blueprint asset
  `cfg` that still sets `accept:` now fails to compile with "unknown config
  fields"; remove the key.

- **Source maps are no longer published.** `mix brando.digest` deletes every
  `*.map` file under `priv/static` instead of digesting it, including the
  `assets/__srcmaps/` copies older Dockerfiles moved there, where `Plug.Static`
  still served them. `mix brando.migrate55` switches `sourcemap: true` to
  `'hidden'` in the Vite configs under `assets/`, so built scripts stop
  pointing at maps that no longer exist. A site whose Sentry fetched public
  maps to symbolicate frontend errors must upload them during the build:
  see "Source maps" in the [deployment guide](guides/deployment.md). Pass
  `--keep-source-maps` to the digest to publish them as before.

- **Module definition baselines ignore empty values.** A Brando upgrade that
  added a field to a block type made every module using that block a
  `conflict` on its next definition import ("target changed since export"),
  since the baseline digest covered the new empty key. Baselines are now
  version 2 and leave empty values out. Existing lockfiles keep exact
  comparison until the next import or export rewrites them; if one reports
  conflicts after this upgrade, export a fresh baseline first.
- **Var labels are translated.** `Brando.Content.Var`'s `label` is now a map
  of admin language → text (`:i18n_string`), like a module's name, so editors
  see labels in their own admin language. The `brando_190` migration moves
  each label under the default language. The module editor and the entry var
  editor take one label per admin language; module definitions accept
  `label "Size"` (read as the default language) or `label %{"en" => "Size",
  "no" => "Størrelse"}`, and export writes the map. Code that read
  `var.label` as a string now gets a map: use
  `Brando.Type.I18nString.localized(var.label)`. Run `mix brando.gen.migrations`
  for `brando_190`, then re-export module definitions: their lock baselines
  were taken from the string labels.
  A select var's options are translated the same way: an option's `label` is
  a language map, edited per admin language in the var editor. `brando_191`
  moves existing option labels under the default language; definitions accept
  `{"Light", "light"}` or `%{"label" => %{"en" => "Light", "no" => "Lys"},
  "value" => "light"}`.
- **Image alt text, title and credits are translated.** `Brando.Images.Image`'s
  `alt`, `title` and `credits` are now maps of content language → text
  (`:i18n_string`). The `brando_180` migration moves existing text under the
  default language. Brando's own rendering picks the entry's language — the
  page's, falling back to the default — and placement overrides still win.
  Application code that read `image.alt`, `image.title` or `image.credits`
  as a string now gets a map: use `Brando.Images.text(image, :alt, language)`,
  or `Brando.Images.resolve_texts(image, language)` for all three.
  `<.picture>` takes a `language:` opt and otherwise uses the request's
  locale. `Brando.Villain.map_images/2` takes the language for Liquid
  templates. Run `mix brando.gen.migrations` for `brando_180` and
  `brando_181`. `mix brando.migrate55` lists application code that looks like
  it reads these fields as strings (by name: the Blueprints' image asset
  fields and common image variable names), and `mix brando.check.image_texts`
  lists module, container and menu templates in the database that print them
  without the `i18n` filter — `{{ entry.cover.alt | i18n }}`. Both only
  report. Neither can see JSON built from an image, which now carries the
  maps.

- **A page with `has_url: false` has no URL.** Page's `absolute_url` now
  declares `only: %{has_url: true}`, so `Page.__absolute_url__/1` returns
  `nil` for organisational sections and the 404 and 410 pages instead of a
  path nobody can open, and the content SEO audit leaves them out. Code that
  built a link for such a page from its URL gets `nil` now.

- **`trait :creator` adds two columns.** Every schema with the creator trait now
  has `updated_by_id` and `edited_at`. Run `mix brando.gen.migrations` for
  Brando's tables and `mix brando.gen.blueprint_migration --all` for the
  application blueprints, then `mix brando.migrate` (and
  `mix brando.migrate --tenants` with named environments); until then, queries
  on those schemas fail with a missing-column error.

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

- **Refs have been split out to their own table.** Run `mix brando.gen.migrations` to get migrations.
  The refs structure has changed significantly:
  - Refs are now stored in a separate table with foreign keys to media
  - Picture refs: `{{ refs.my_image.data.data.path }}` becomes `{{ refs.my_image.path }}`
  - Gallery refs: `{{ refs.my_gallery_ref.data.images }}` becomes `{{ refs.my_gallery_ref.gallery.gallery_objects }}`
  - Video refs work similarly with direct property access

- **The form's input primitives moved out of `BrandoAdmin.Components.Form` into
  `BrandoAdmin.Components.Form.Primitives`.** Twelve public functions:

      Form.field_base/1              Form.inputs_for_block/1
      Form.input/1                   Form.inputs_for_poly/1
      Form.label/1                   Form.array_inputs/1
      Form.error_tag/1               Form.array_inputs_from_data/1
      Form.submit_button/1           Form.map_inputs/1
      Form.translate_error/1         Form.map_value_inputs/1

  **What to change.** Alias the new module and call them there — the functions
  and their assigns are unchanged, so it is a rename:

      # before
      alias BrandoAdmin.Components.Form
      <Form.field_base field={@field} label={@label}>…</Form.field_base>

      # after
      alias BrandoAdmin.Components.Form.Primitives
      <Primitives.field_base field={@field} label={@label}>…</Primitives.field_base>

  This affects any application with custom admin form inputs or field
  components, which is the normal way to extend the admin. Within Brando itself
  it was 165 call sites across 26 modules, 25 of which no longer reference
  `Form` at all.

  They were in the wrong module by their own usage: 26 modules called them —
  `field_base/1` alone ~90 times — while `Form` used exactly two. Note this was
  **not** done to reduce compile coupling and does not: the admin's compile
  cycle runs through `use BrandoAdmin, :component`, so every component is inside
  it regardless of who calls whom.

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

- **`<.video>` now resolves playback settings as opt → record → default, and
  Mux and Bunny videos read the record at all.** `autoplay`, `controls`, `loop`,
  `muted`, `preload`, `width`, `height` and `aspect_ratio` exist both as opts on
  the tag and as fields on `%Brando.Videos.Video{}`, editable in the admin. Two
  things were wrong:

  1. The Mux and Bunny clauses were hand-written copies of the file renderer
     that read **only** opts. An editor could switch "Autoplay" on for a Mux
     video and the front end ignored it. Cloudflare, `:upload` and
     `:external_file` honoured it.
  2. Where the record *was* consulted it was through `record || opt || default`,
     which cannot tell "unset" from "set to false". A record with `loop: false`
     fell through to the default and looped anyway.

  Both clauses now render through the one renderer, and resolution is explicit:
  an opt passed at the call site wins (**including `false`**), then the record's
  value if the editor set one, then the default.

  **What changes for you.** A template that passes an opt the record disagrees
  with now behaves differently — `{% video entry.video { autoplay: false } %}`
  over a record with autoplay on used to autoplay and no longer does, and a Mux
  or Bunny video whose record says autoplay/controls/loop will now obey it.
  If a site was relying on the old behaviour, the fix is to set the field in the
  admin rather than around it.

  Two related dead settings were wired up while the resolution was being fixed.

  `muted` was accepted by the tag grammar and never read; it resolves through
  the same opt → record → default chain now, so an editor can mute a video that
  is not autoplaying. **What did not change: `autoplay` still forces `muted`.**
  The attribute renders as `@autoplay || @muted`, exactly as before, because
  browsers block unmuted autoplay. A template passing `autoplay: true` and no
  `muted` therefore behaves as it always did, and `muted: false` neither does
  nor can un-mute an autoplaying video — the setting is only reachable with
  autoplay off. This is the one setting the precedence rule above does not fully
  describe.

  `caption: true` could only resolve to `opts[:title]`, never the record's own
  caption. Captions remain opt-in — a record with a caption does not start
  rendering a `<figcaption>` on templates that never asked for one.

  The Mux and Bunny wrapper classes (`video-mux`, `video-bunny`) are unchanged,
  as is the file markup, byte for byte. Two other markup changes:

  - **Cloudflare videos now render `video-wrapper video-cloudflare`, not
    `video-wrapper video-file`.** Every other provider had a class naming it;
    Cloudflare was rendering as a plain file because it was the one provider
    already going through the shared renderer. If you style `.video-file` and
    rely on it catching Cloudflare, add `.video-cloudflare` to the selector.
  - Mux and Bunny videos no longer emit a `<source type="application/x-mpegURL">`
    child: with a single source it is equivalent to the `src` attribute the
    shared renderer uses, and it defeated `preload` by making the browser fetch
    the manifest eagerly.

- **The admin animates with Motion, on Jupiter 5** (#2814). BrandoJS depends
  on `@brandocms/jupiter` `5.0.0-beta.19` and no longer on GSAP. Jupiter 5
  exports Motion's `animate`, `stagger`, `scroll` and `motionValue` in place
  of `gsap`, so a custom admin hook in `assets/backend` that imports `gsap`
  from Jupiter must move to those or depend on `gsap` itself. Set
  `@brandocms/jupiter` in `assets/backend/package.json` to the same version.
  Jupiter 5's `app.scrollTo({y: el, offsetY})` adds the offset to the target,
  where GSAP subtracted it: negate offsets passed from custom hooks.

- **Public modules that sat in the wrong layer are renamed** (#2833). The old
  names are deprecated and keep working until 0.57: a router, socket or
  endpoint config that names one logs a warning the first time it is used,
  and calling a function on one warns when the caller compiles.
  `mix brando.migrate55` rewrites the references in `config/`, `lib/` and
  `test/`, and `mix brando.doctor` lists any left in `lib/`. Applications
  that route with `page_routes()` need no change.

  | Old name | New name |
  | --- | --- |
  | `Brando.SEOController` | `BrandoWeb.SEOController` |
  | `Brando.SitemapController` | `BrandoWeb.SitemapController` |
  | `Brando.PreviewController` | `BrandoWeb.PreviewController` |
  | `Brando.UserChannel` | `BrandoAdmin.UserChannel` |
  | `Brando.LobbyChannel` | `BrandoAdmin.LobbyChannel` |
  | `Brando.LivePreviewChannel` | `BrandoAdmin.LivePreviewChannel` |
  | `Brando.ErrorHTML` | `BrandoWeb.ErrorHTML` |
  | `Brando.Config` | `Brando.Sites.Config` |
  | `Brando.Link` | `Brando.Sites.Link` |
  | `Brando.Meta` | `Brando.Sites.Meta` |
  | `Brando.Upload` | `Brando.Uploads.Store` |

  The three controllers serve the site's public routes (`/robots.txt`,
  `/sitemaps/:file` and the shared preview links at `/__p__/:preview_key`),
  and `ErrorHTML` renders the public site's error pages as its endpoint's
  `render_errors`, so they moved to `BrandoWeb` with their files. A router that `mix
  brando.gen.site` generated before 0.55 names them directly; rerunning the
  task accepts either name.

  `Brando.Config`, `Brando.Link` and `Brando.Meta` are the Identity's
  embedded schemas (its `configs`, `links` and `metas`), filed under
  `lib/brando/sites/` but named as if they were Brando-wide. Only their
  module names change; the data does not. A struct cannot answer to two
  names, so `%Brando.Link{}` as a literal or a pattern, and a relation's
  `module: Brando.Link`, stop compiling until they use the new name;
  `changeset` calls on the old names still work. `Brando.Meta.HTML`, which
  renders a page's `<meta>` tags, keeps its name: it was never part of the
  schema.

  `Brando.Upload` sat beside the `Brando.Uploads` context with only the
  plural to tell them apart. It stores an uploaded file and creates its
  image, file or video row, so it is `Brando.Uploads.Store` now, under the
  context that calls it (`Brando.Uploads.store_upload/4`). `Brando.Uploads`,
  which decides the transport and finalizes direct uploads, keeps its name.
  `%Brando.Upload{}` needs the new name too.

#### Improvements

- **Opening an entry shows the entry, not a loading modal.** The form reads
  the entry before its first render, so its heading, tabs and fields appear
  at once. An entry with up to 20 blocks (nested ones counted) opens complete
  while the listing stays on screen, the clicked row tinted and saying
  "Opening"; a heavier one shows its fields read-only beside outlines of its
  blocks, with "Loading 115 blocks" in the toolbar and Save disabled until
  they have loaded. A reload shows the form as a skeleton until LiveView
  connects. `Brando.Content.Blocks.count_entry_blocks/2` now counts nested
  blocks too, and `count_entry_blocks_by_field/2` gives them per field.
  `BrandoAdmin.Components.Form.entry_loader/1` is removed.

- **The admin's colours are role tokens** (#2981). Every admin stylesheet
  uses the custom properties in `assets/css/tokens.css` (`--brando-ink`,
  `--brando-accent`, `--brando-surface-*`, the status and success/error
  roles); CI rejects new hex colours outside that file. Native checkboxes,
  radios and range inputs take the accent. The legacy names are deprecated
  and will be removed in a later release: the `--brando-color-*` custom
  properties (`-dark`, `-blue`, `-peach`, `-input`, `-white` and the rest)
  and the Europa palette behind `theme(colors.*)` and `@color` (`dark`,
  `blue`, `peach`, `input`, `gray`, `villain.*`, ...). Brando no longer uses
  them; if your `assets/backend` CSS does, move it to the role names listed
  in `docs/admin-ui-design.md`.

- **The entry editor heads itself with the entry.** The heading is the
  entry's title (or "New case" for a new one) under a breadcrumb with the
  content type, and its status is one compact control beside it instead of
  four radios in the form. A blueprint form's `<:header>` slot is no longer
  shown and no longer required; LiveViews may keep passing one. Every toolbar
  button has a label, and the save state ("Saved 23:20", "Unsaved changes")
  sits next to Save. Pass `layout={:settings}` to `BrandoAdmin.Components.Form`
  for a singleton settings screen: it renders no heading of its own (use
  `Workspace.header`, which now takes an `eyebrow`) and saves in place from a
  sticky bar.

- **One command plans storage for every blueprint.**
  `mix brando.gen.blueprint_migration --all` plans a migration and snapshot
  for each application blueprint whose storage differs from its snapshot, or
  that has none yet, and lists the rest as up to date. You review them once
  and accept them together. Each blueprint keeps the migration path a single
  run would pick (classic, tenant or public history), and the migrations get
  increasing versions, ordered so a table exists before a foreign key to it.
  Every plan is checked again before anything is written; if one is stale,
  no files are written. `--dry-run` previews them all. A blueprint whose
  destination needs `--migration-path` is left out with a warning.

- **Listings that depend on who is looking.** A listing passes the signed-in
  user to its context, and a `filters` function whose clauses take a third
  argument receives `%{current_user: user}`, for filters like "hide what I have
  reviewed". `decorate` may take the user as a second argument, and a row
  component gets `@current_user`. A sort's `order` may be a function of the
  list query, for orders columns cannot express (a total over an association);
  the listing keeps it in the URL as `?sort=<key>`. A `selection_action` takes
  `confirm:` (the question to ask first) and `visible:` (a function of the user).
  Select and boolean filter values reach the context unescaped, so a select
  value such as `"in_progress"` no longer arrives as `"in\_progress"`.

- **Upgrading a 0.53/0.54 site takes fewer manual steps** (from the smartwatt
  upgrade). See [Migrating from 0.53 or 0.54](guides/migrating_from_053.md),
  which now also covers the dependency, Node, legacy-snapshot and test-database
  steps.
  - `mix brando.migrate54` and `migrate55` no longer compile the application
    first, so they run on the source they are meant to fix. Gettext backends
    are rewritten in the same plan rather than by a separate
    `igniter.update_gettext`, which compiled the application and pinned
    `gettext ~> 0.26`. The consumer-owned `brando.upgrade` task is found by
    content anywhere under `lib/`.
  - `migrate54` replaces a copy of the 0.54 `scripts/sync_gettext.sh` instead of
    aborting, and both tasks remove `processor_module:
    Brando.Images.Processor.Sharp` from config.
  - `migrate55` gives Villain parsers back the `use Phoenix.Component`,
    `Brando.HTML`/`Phoenix.HTML` imports and aliases they used from the old
    `use Brando.Villain.Parser`, and reports overrides of blocks Brando no
    longer renders; completes
    `Plural-Forms` headers Gettext 1.0 warns about; takes Florist domains and
    ports from `.envrc.<flavor>`, `etc/nginx` and `etc/supervisord`/`etc/systemd`
    instead of defaults, reporting placeholder URLs and the process manager;
    and adds `plug Brando.Plug.Health` when it creates `florist.config.exs`.
  - `mix brando.gen.backend --upgrade` brings an existing `assets/backend` and
    the Dockerfile's `assets_backend` stage to the current pnpm template, and
    `mix brando.assets.setup --backend-only` installs and builds the admin
    alone.
  - `mix brando.gen.blueprint_migration` backfills `edited_at` from
    `updated_at` when it adds the Creator trait to an existing table, and
    warns when a plan adds a table or column the database already has or
    drops legacy Villain columns. `mix brando.gen.migrations` copies tenant
    migrations only when tenancy is on.
  - The backend template drops `svelte.config.cjs`, which vite-plugin-svelte
    7 ignores (it logged "no Svelte config found"), and `svelte-preprocess`.

- **`mix brando.migrations.check` finds outdated migration copies.**
  `mix brando.gen.migrations` matches copies by name and never updates one,
  so a copy made before a template was fixed replays the old code. The check
  lists the `brando_*` copies the database has not run yet whose code differs
  from the current template (formatting and comments aside), and pending
  copies of renumbered templates. `--update` replaces the outdated ones.
  Run it before replaying an upgrade on a copy of production (#2969).

- **The backend assets build with pnpm, like the frontend** (#2814). New
  applications' Dockerfiles install `assets/backend` with pnpm 10.32.1 and
  `--frozen-lockfile`, and the backend template pins the same version in
  `packageManager`. An existing Dockerfile that runs Yarn in its
  `assets_backend` stage keeps building, but `mix brando.assets.setup` only
  maintains `pnpm-lock.yaml`. To switch, copy the `assets_backend` stage from
  `priv/templates/brando.install/Dockerfile`, commit the
  `assets/backend/pnpm-lock.yaml` that `mix brando.assets.setup` writes, and
  delete `assets/backend/yarn.lock`.

- **The source upgrade task is split by version.** `mix brando.migrate54` now
  covers only the 0.53 to 0.54 source changes and `mix brando.migrate55` covers
  the 0.54 to 0.55 changes: the explicit listing component imports, the Req
  Swoosh client, the `phoenix_live_view` JavaScript pin, Florist conversion,
  the refreshed gettext helper, and archiving the consumer-owned
  `mix brando.upgrade` task that 0.54 installed. Applications on 0.54 run
  `mix brando.migrate55` only; applications on 0.53 run both. Both tasks are
  idempotent, and `mix igniter.upgrade brando` composes `brando.migrate55`
  for a 0.54 to 0.55 upgrade. `mix brando.install` no longer copies a
  consumer-owned `brando.upgrade` task into new applications.
- **The 251-module compile-connected dependency cycle is gone** (#2737), and the
  CI gate is back to `--fail-above 0`.

  It was never the Blueprint DSL. Every edge holding it together was an
  accidental compile-time call from one module into another whose own
  dependencies led back:

  - `BrandoAdmin.live_view/0` and `UploadManager` called `Brando.config/1` during
    macro expansion; they read the same value off the leaf
    `Brando.RuntimeConfig` now.
  - `SharedLibrary`'s `@definitions` and `Content`'s `@module_cache_opts`
    resolved `Ref.preloads/0` into module attributes; both are functions now.
  - `Block.Render` read `Content.Block.carried_var_attrs/0` into an attribute;
    the lists moved to the new leaf `Brando.Content.VarAttrs`, which
    `Content.Block` re-exports.
  - `Content.Module`'s listing action called `BrandoAdmin.Utils.show_modal/2` at
    compile time — a core schema recompiling with the admin. The JS command
    builders moved to the new leaf `BrandoAdmin.JSCommands`; `BrandoAdmin.Utils`
    delegates to it, so existing call sites are unchanged.
  - The last one was a single struct literal: `default %Palette.Color{}` in
    `Content.Palette`'s form. `default` also takes a 2-arity function, which
    defers it.

  The pattern to watch for is in `Brando.Blueprint.Forms`' docs now: a
  compile-time call — module attribute, `%Struct{}` literal, or a function call
  during macro expansion — that crosses into a module the callee's own
  dependencies reach back to.

  A `trait` declaration is one of those compile-time references, so a trait that
  calls back into a module holding the schema's struct closes the same loop:
  `Brando.Content.ModuleDiff` therefore types its arguments as `map()` and
  matches on shape rather than on `%Module{}`.

- **Accessible form validation in the admin** (#1996). The admin is essentially
  one large form application and shipped exactly one ARIA attribute in its whole
  form layer: no error association, no live regions, no required exposure, no
  dialog semantics, no focus management.

  - `Input.input/1` — the single place every control in the admin is rendered —
    now emits `aria-invalid`, `aria-describedby` and `aria-required`. Required
    comes from the blueprint's `__required_attrs__/0`; hidden inputs get nothing.
  - `Primitives.error_tag/1` renders one `role="alert"` container instead of a
    span per message, present whether or not it has anything to say (a live
    region added *with* its content is not reliably announced). This also fixes
    two errors on one field being drawn on top of each other, and each claiming
    the same DOM id.
  - Modals are `role="dialog" aria-modal="true"`, named by their own heading. The
    new `Brando.Modal` hook takes focus on open, wraps Tab, and returns focus to
    whatever opened them.
  - A failed save focuses the first invalid control instead of only scrolling to
    it.

  **If you style `.field-error`:** the messages are now wrapped in a
  `.field-errors` container, and positioning moved to it. A selector like
  `.label-wrapper > span.field-error` no longer matches.

  Not yet done: associating a field's `help-text` instructions with its control.

#### Features

- **Sort by use and Delete unused for videos and files** (#3098). The video
  and file libraries get the image library's **Sort by use**: a preview of a
  folder per entry using the folder's videos or files (with video thumbnails
  and file type icons), renaming, per-entry opt-out, the move, and Undo. With
  **Not in use** switched on, they offer to delete every unused video or file
  in view, through the same delete as the listing's, so a provider that
  deletes on delete loses the remote copy too. One implementation serves all
  three, `BrandoAdmin.Media.Sweep` (`BrandoAdmin.Images.Sweep` stays as the
  image entry point; plans and results name the moved assets `ids`, no
  longer `image_ids`). Videos and files rank shared assets by
  `sweep_priority:` under `Brando.Videos` and `Brando.Files`, falling back to
  the images' list. Sorting and deleting unused assets now need the update
  and delete permissions on the asset type. Undo now also puts back what
  went into a folder that already existed, and removes only folders the
  sort made itself. Delete unused deletes what its confirmation offered and
  the list, with all its filters, still shows, in the background. "Not in
  use" for images, videos and files now counts as used an asset in a table
  block's rows (a "Downloads" table's files were listed as unused), in an
  entry in the trash, or in an open recovery draft, and finds Blueprint
  asset fields in a tenant's own schema. See "Tidy a folder that has filled
  up" in the media guide.

- **Saved listing views.** The listing toolbar has a Views menu: an editor
  saves the listing's filters, status, sort and page size under a name, for
  themselves or shared with everyone who can open the listing, and gets back
  to them in one click. Applying a view changes the URL, so the back button
  returns to the list as it was. The menu updates, renames, shares and
  deletes the view in use (one's own, or a shared one with the new
  **Shared listing views** permission, the admin role without groups) and
  sets a view to open the listing with. A filter or sort a view names that
  the listing no longer has is left out. `brando_215` creates
  `listing_views` and `listing_view_defaults` in every environment; until it
  runs, the menu lists no views and saving one is refused. The image, file and video libraries have no
  menu; another listing can leave it out with `saved_views={false}`. See
  `Brando.ListingViews` and "Saved views" in the listings guide.

- **Notifications to Slack, Teams and email.** Configuration → Integrations →
  Notifications routes mentions, scheduled publishing and unpublishing, and
  failed jobs (jobs Oban gave up, and webhooks paused after failures) to a
  Slack or Microsoft Teams incoming webhook, or by email to chosen users,
  optionally for some content types only. Slack gets blocks and Teams an
  Adaptive Card, with a link to the entry in the admin; each message is sent
  through Oban with retries and listed in a delivery log. Webhook URLs are
  stored encrypted, shown only by host and last characters, and limited to
  Slack's and Teams' hosts; email goes only to members of the site. A burst
  of the same event on a Slack or Teams route is one message, and email comes
  at most every ten minutes. In their profile, users can choose a daily or
  weekly email summary of their mentions and notifications instead. A failed
  or cancelled message can be sent again from the log, and the dashboard says
  when a route was paused after failures. Copying an environment pauses
  its routes, as it does webhooks. See [Notifications](guides/notifications.md).

- **A calendar of what is planned** (#3081). **Calendar** in the sidebar
  shows entries to be published, scheduled revisions and expiries by day, a
  month or a week at a time, in the site's time zone, across the content
  types with scheduled publishing, with a filter for one type. It lists only
  entries the user may read. An item moves to another day, at the same time,
  by dragging it or with **Move to…**, after a confirmation, and only where
  the user may reschedule it; the move saves the entry the way its form does,
  or reschedules the revision as the revisions drawer does. On a phone the
  days are a list. See [Scheduled publishing](guides/scheduled_publishing.md#see-it-in-the-calendar).

- **Entries can expire** (#3080). `trait :scheduled_publishing` adds
  `unpublish_at` beside `publish_at`: **Expires** in the entry's Scheduled
  publishing drawer. When it comes, the publisher deactivates the entry
  through its context, the same status change as deactivating it by hand,
  so Activity records it and the content events (webhooks, IndexNow, the
  search index), the cache and the rendered pages follow, with the actor
  "scheduler". It has to come after `publish_at`; clearing it cancels the
  job, and a time that has already passed deactivates the entry at once.
  Setting or clearing an expiry takes the rights to schedule and to
  publish. Listings show "Expires 12 Oct" under the status, the dashboard
  has an "Expiring soon" panel for the next 14 days, and the publishing
  queue marks expiry jobs. Restoring a revision keeps the expiry the entry
  has. A changed publishing date now replaces the entry's earlier job
  whoever scheduled it, and a job left from before a reschedule (of a
  date or a scheduled revision) does nothing when it runs. See [Scheduled publishing](guides/scheduled_publishing.md).

- **Blocks on older module versions can be resolved.** A module save keeps
  refs and vars the new version no longer defines, and leaves the blocks
  holding them on their old version, so `mix brando.doctor` warned about them
  for good: `mix brando.modules refresh` re-rendered them and left them stale.
  Block modules → the module → **Resolve blocks** (linked from the system
  check, and from a notice on the module's screen) lists those blocks with
  their entries, versions and the leftover values, and drops each leftover or
  moves it onto a ref or var the module defines now, in every block at once,
  with exceptions per block. A value moves only between compatible types;
  other mappings are refused with the reason. A review lists what is lost
  before the confirmation. Resolving stores a revision of each entry first,
  re-syncs, stamps and renders the blocks, records the change in Activity and
  moves editors who have an entry open onto the new rows; it needs the right
  to update the module and the entries. Entries in the trash are among them,
  marked as such; the review names entries that keep no revisions (templates),
  which History cannot restore. `mix brando.modules resolve --uid UID`
  does the same from the terminal (a dry run until `--apply`, with `--drop
  KEY` and `--map OLD=NEW`), and `refresh` now says what keeps blocks stale
  and points there. See `Brando.Content.StaleBlocks` and "Blocks left on an
  older version" in the module definitions guide.

- **Documentation for coding agents.** `usage-rules.md` is now generated
  from the guides by `mix brando.docs.agents`, which copies the regions
  marked `<!-- usage-rules:start -->` … `<!-- usage-rules:end -->` under a
  heading per guide. It holds the core rules for building a site, about
  32 KB, and ends with an index of fifteen topic files in `usage-rules/`
  (SEO, media, tenancy and so on), generated from regions marked
  `<!-- usage-rules:start topic="seo" -->`. They ship in the Hex package,
  where `usage_rules` finds them (the topics as `brando:<topic>`), and a test
  compiles their Elixir examples so wrong function names and arities fail
  CI. The HexDocs build gets an `llms.txt`
  that describes each guide in one line, and `llms-full.txt` with every
  guide joined. Five site-building skills (Blueprints, blocks and modules,
  live preview, media fields, Florist deploys) ship in
  `usage-rules/skills/`: `mix brando.install` copies them to
  `.claude/skills/` and links the usage rules from `AGENTS.md`, and a
  versioned `mix brando.upgrade FROM TO` adds them when missing, never replacing
  edited copies.
- **AI crawler policy.** Configuration → SEO lists the crawlers AI products
  send, grouped by purpose (AI search, fetches for a user, model training),
  each with Allow / Block, and a setting for the `ai-train` content signal.
  `robots.txt` gets a generated block after the editors' own lines, which are
  never rewritten: a `Disallow: /` group per blocked crawler and a
  `Content-Signal:` line ([contentsignals.org](https://contentsignals.org)).
  Nothing is written until a crawler is blocked or a training preference is
  chosen. robots.txt is now served as `text/plain`. See
  [Identity, SEO settings, and redirects](guides/identity_and_seo.md#ai-crawlers-and-content-signals).
- **Snippet limits per entry.** The meta drawer has **No snippet** and
  **Snippet length**, written as the page's robots meta tag (`nosnippet`,
  `max-snippet:N`). They are what keeps a page's text out of Google's AI
  Overviews. `put_robots/2` adds directives of your own to the same tag.
- **IndexNow.** Configuration → SEO can turn on IndexNow, which tells Bing,
  Copilot, Yandex and the other search engines that use Bing's index when an
  entry is published, updated while published, unpublished or deleted
  (Google doesn't take part). It is a content event subscriber
  (`Brando.IndexNow`): URLs are gathered for a minute and sent as one request
  per host, by `Brando.Worker.IndexNowSubmission` on the existing `:webhooks`
  queue, so no new queue is needed. The site's key is served at
  `/<key>.txt`; the last submission and its answer show under the toggle.
  Off by default, and only the live environment submits; turn it off for a
  whole deployment with `config :brando, Brando.IndexNow, enabled: false`.
- **Previews in the meta drawer.** A Previews tab shows the entry as a
  search result, an Open Graph card and an X card, following the form as it
  is edited, with the image that is shared, cut the way it is shared and a
  ring on its focal point, and the start of the entry's Markdown version.
- **Markdown alternates.** An entry's page is also served as Markdown, at its
  URL with `.md` appended and for `Accept: text/markdown`, with
  `Vary: Accept`, an `ETag` and a canonical `Link` header, and named in the
  head with `<link rel="alternate" type="text/markdown">`. Only entries the
  page's controller loads, published and not scheduled, are served. On for
  blueprints with a URL, blocks and `trait :meta`; turn it off with
  `trait :meta, markdown: false`. `Brando.Villain.Markdown` renders the
  blocks: a module's HTML becomes Markdown, refs written plainly (pictures as
  images, videos and files as links), or a module can have a **Markdown
  template** of its own in the module editor. See
  [Markdown alternates](guides/markdown_alternates.md).


- **Admin search.** `/admin/search` finds every entry the user may read by
  its title, slug, meta description, text fields and the text of all its
  blocks (rich text, headings, lists, table cells, picture and gallery
  texts, container children and module variables), ranked by an exact
  title, then titles starting with the query, then relevance, with
  published entries first among equals. It has filters for content type,
  language and status, shows a highlighted snippet per result, and pages of
  twenty. The command palette's entries end with a "See all results" row
  that opens it, and phones and tablets get a search button in the top
  right corner to open the palette, where the sidebar is hidden. The index
  is one Postgres full-text table per environment (`norwegian`, `english` or
  `simple` text search per language, no extension needed), kept up to date
  from content events on the new `search_index` queue, so saves do not wait
  for it. On 10,000 entries a search takes 2–40 ms, and about 80 ms for a
  word on every entry. See `Brando.Search`.

- **Connected AI tools: a remote MCP endpoint.** People with the new
  **Connected AI tools → Connect** permission (`brando.mcp.connect`, in no
  preset) and two-factor authentication can connect Claude, ChatGPT, Claude
  Code, VS Code and other MCP clients to a site environment, to read content
  and prepare proposals they review and apply in the Assistant under "From
  connected tools". Mount it with `mcp_routes()` and turn it on per site
  environment under Configuration → Integrations → Connected AI tools
  (`brando.mcp.manage`); while off, every route answers 404. Streamable HTTP
  for both MCP protocol eras (`2026-07-28` and `2025-xx`), OAuth 2.1 with
  PKCE (S256 only), resource indicators and Client ID Metadata Documents,
  hashed one-hour access tokens and rotating refresh tokens with reuse
  detection, revocation, and a consent screen that names the client, its
  host, the redirect host and the site environment and asks to confirm. The
  person's account, two-factor authentication, permission and the switch are
  checked on every call; every tool call is in Activity with the person, the
  client and the token's row id, and is rate limited per connection and per
  person. Security → Connected apps lists and disconnects a person's
  connections; administrators see and revoke everyone's, and turning the
  endpoint off disconnects them all. A password change, "log out
  everywhere", turning two-factor authentication off and deactivating a user
  revoke a person's connections, and every connection expires 90 days after
  consent. The threat model is in [Connected AI tools](guides/mcp.md).

- **Content events and outbound webhooks.** Every change Activity records
  for an entry becomes a content event (`entry.created`, `entry.updated`,
  `entry.published`, `entry.unpublished`, `entry.deleted`,
  `entry.restored`), delivered after commit through Oban to subscribers
  listed in `config :brando, Brando.ContentEvents, subscribers: [...]`;
  scheduled publishing fires `entry.published` like a manual publish, and
  quick successive saves are one `entry.updated`. Webhooks, under
  Configuration → Integrations → Webhooks, post a small signed JSON envelope
  (HMAC-SHA256 in `Brando-Signature: t=…,v1=…`, no entry content) to `https`
  URLs on public addresses, with retries for about a day, a delivery log,
  redelivery and a test event. Managing them needs the new Webhooks
  permission (`brando.webhooks.manage`; admins and superusers without
  groups) and a recent password. Copying an environment, or restoring an
  archive, pauses the copy's webhooks; they resume when that environment
  goes live. See [Webhooks and content events](guides/webhooks.md).

- **One edit session per open entry.** When several people edit an entry's
  blocks, a process per entry (`Brando.EditSession`, after Livebook's
  session) now puts their changes in one order. Each editor's block store is
  a replica: its own changes apply at once and go to the session, which
  numbers them and sends them to everyone, so all editors end up with the
  same blocks. Changes arrive as people type instead of when they leave a
  block, someone opening the entry sees the unsaved work at once, and save,
  live preview and recovery copies read the session. After a save the
  session continues from the saved rows, keeping what others typed while it
  ran. An Assistant proposal applied while the entry is open, or a revision
  activated in another tab, comes into open editors as changes instead of
  needing a reload, and their unsaved work is kept. The session stops 30
  seconds after its last editor leaves (`config :brando, Brando.EditSession,
  grace_period: …`). If it crashes, the editors seed a new one from what
  they hold, and everyone's unsaved work is merged into it. Applying a
  recovery copy keeps other editors' unsaved work. If another save removes a
  block you have unsaved changes in, it comes back at the end as a new block
  with your changes (inside the container it was in, if that was removed
  too), and you are told. A save that an Assistant proposal or another
  write overtakes collects the blocks again, so it keeps what that write
  added; editors follow such writes only once they have committed. People
  who may view but not update the entry follow along without sending
  changes.

- **Field presence and follow mode.** Two people can work in one block: a
  keystroke, or any change in a block, reaches the edit session as the
  fields it changed, and the last change to a field wins, so each keeps
  their own field. Items two people add to or remove from one list (a
  block's refs, a table's rows) are all kept. Blocks are no
  longer locked while someone is in them; the field another editor is in
  shows their colour and first name, and the block's toolbar says "Ingrid ·
  Caption". The value someone is typing stays theirs until the session has
  it, so nothing flickers back, and a field someone else typed in last shows
  their value once you leave it. Click another editor's avatar to follow
  them: the editor scrolls to the field they move to until you scroll or
  click. Blocks added at the same place by two people at once both stay, in
  the same order for everyone (the session orders blocks by fractional keys;
  saves still write the usual sequence).

- **Notes on entries.** Editors can leave each other notes in the entry
  editor, in a panel docked beside the content: on the entry, a block (the
  note button in its toolbar), a field (a button beside its label) or text
  selected in a block's rich text ("Add note" over the selection, ⌥⌘M).
  Threads have replies and can be resolved and reopened; resolved threads
  collapse and can be searched. `@Name` mentions anyone who can read the
  entry: they get a toast if they are online and an email, at most one every
  ten minutes (`Brando.Worker.NoteMentions`). Blocks with open notes show an
  amber count and marked text is highlighted, in the editor only: the mark
  (`<span data-brando-note>`) is stripped from every render, so it never
  reaches the site or the live preview. Notes belong to the entry, not a
  revision: restoring a revision keeps them, a note on a deleted block is
  kept as detached, and one whose text was deleted becomes a note on its
  block. Notes follow the entry to the trash and back, are kept per site
  like revisions, and adding, resolving and reopening them shows in the
  entry's activity. Anyone who may update an entry may write notes on it.
  See `Brando.Notes`.

- **Agents in Activity.** Activity marks who made each change by kind: a
  person, the Assistant (AI), a tool connected over MCP (MCP, with its name)
  or an automatic job (scheduled publishing and the system). A change from a
  proposal records the proposal and the person who approved and applied it,
  and that person gets a link to the proposal; undoing it is recorded against
  the same proposal. Filter the log by kind of actor or by MCP client; the
  entry's history shows the same badge and approver.
  `Brando.Activity.actor_kind/1`, `with_proposal/5` and the `:actor`,
  `:client` and `:proposal_id` filters. See the activity guide.

- **Review proposals from connected tools.** Proposals a coding agent such
  as Claude Code prepares through BrandoMCP have no conversation; the
  Assistant now lists them under **From connected tools**, with a count of
  those waiting, marked "From Claude Code via MCP". They are reviewed,
  previewed, applied or rejected like the Assistant's own, and Activity names
  the tool as the source of an applied one. `Proposals.Tools.Context` takes
  `origin` and `client`. See
  [Content assistant](guides/content_assistant.md#proposals-from-connected-tools).

- **Videos and authors in JSON-LD.** Entries whose schema has a `video`
  property (`Article`, `CreativeWork`) now describe the videos they show — the
  blueprint's video fields and the preloaded videos in its blocks — as
  `VideoObject` nodes linked from `video`, with no blueprint change. A video
  gets a node only when Google's required `name`, `thumbnailUrl` and
  `uploadDate` are known; Mux, Bunny, Cloudflare Stream and Vimeo supply the
  poster frame, stream and player. `videos false` in a `json_ld_schema` turns
  it off. The new `:person` field type (`field :author, :person, & &1.creator`)
  maps Brando users and People entries to linked `Person` nodes with a stable
  `@id`; nothing is emitted for authors a blueprint doesn't map, and a user
  gives only name, job title, profile links and avatar. A People entry on its
  own page becomes a `ProfilePage` about the same Person. Users get optional
  **Job title** and **Profile links** fields for this (`brando_202` adds the
  columns). See [JSON-LD](guides/jsonld.md#authors).
- **X cards and a canonical override.** `render_meta` writes `twitter:card`
  (`summary_large_image` with an image, `summary` without), `twitter:title`,
  `twitter:description` and `twitter:image` from the Open Graph values, and
  `twitter:site` from an X profile among the identity's links. Tags a page sets
  itself win. The meta drawer has a **Canonical URL** field
  (`meta_canonical_url`, an absolute `http(s)` URL) for syndicated or
  duplicated content; `put_meta/3` and `put_hreflang/2` pass it to the
  canonical link and `og:url`, and `put_canonical/2` sets one by hand. Empty
  keeps the entry's own URL. See [Page metadata](guides/meta.md).
- **The 404 log survives deploys.** `Brando.Sites.FourOhFour` still counts
  misses in memory, but now writes them every minute (and on shutdown) to a
  `sites_not_found_hits` table, one row per URL, referrer and day, with one
  upsert per batch rather than a write per request. The SEO settings list
  totals per URL with the referrer that sent most hits, and **Redirect** works
  from the stored log. `Brando.Worker.NotFoundPurger` deletes rows older than
  90 days (`config :brando, Brando.Sites.FourOhFour, retention_days: …`) at
  05:25 UTC; apps with their own Oban crontab must add it. `brando_201`
  creates the table in every environment. See "Find the URLs worth
  redirecting" in [Identity, SEO settings, and redirects](guides/identity_and_seo.md).
- **An honest `dateModified`.** `trait :meta` adds `content_modified_at`, set
  on insert and moved only when a save changes the entry's text (its text
  inputs and rendered blocks) by at least 10% of its words, between 5 and 20
  words: typo fixes, reordered blocks, meta edits, resaves and `:system`
  saves leave it alone. `Brando.Blueprint.Value.modified_at/1` reads it,
  falling back to `edited_at` and `updated_at`; Page's JSON-LD `dateModified`
  and the `mix brando.gen.sitemap` template now use it, so the two agree.
  Point your own blueprints' `dateModified`, sitemap `lastmod` and any
  "Updated" line at it too; see [JSON-LD](guides/jsonld.md#datemodified).
- **Transformer cards can act on their entry and see their neighbours.** A
  transformer's `listing:` component now also gets `@dom_id` and `@target`,
  and `BrandoAdmin.Components.Form.Transformer.set_field/4` builds a click
  that changes one of the entry's fields in place (a size switch on a card),
  saved like an edit in the entry's own fields. `listing_context true` on the
  `inputs_for` adds `@index` and `@entries`, every entry in order, and
  re-renders every card when one changes — for position numbers, or cards that
  show which entries share a row. The grid layout's hover tools are white
  chips, as in the gallery grid, instead of dark ones on a peach hover.
- **Direct uploads for a site's own forms.** `Brando.Uploads.Direct` gives a
  site page — an application portal, a submission form — the admin's
  browser-to-bucket transport without an admin user: `presign/4` checks the
  file against the field and presigns a PUT, `complete/2` verifies the object
  and creates the `Image`, `File` or `Video`, and `cancel/1` drops it.
  Uploads run as `:system`; deciding who may upload stays the site's job.
  See "Uploads from a site's own forms" in the [media guide](guides/media.md).
- **Images can upload straight to the bucket too.** An image field whose CDN
  config sets `direct: true` presigns a PUT like files do; on completion
  Brando fetches the original back, creates the image and processes it, and
  the sizes are delivered as usual. Fields without `direct: true` are
  unchanged. The admin's UploadManager takes the same path for such fields.
- **`hidden_folder` on image and file configs** files a field's uploads in a
  folder outside the media library (`media_folders.library = false`). The
  image, file and video lists, the alt-text page, the image picker's
  browse-all and the assistant's folder search leave it out. Run
  `mix brando.gen.migrations` for `brando_199`.

- **Blueprints and sidebar items have icons.** A blueprint sets one with
  `content_icon "folder-kanban"` (a Lucide name, checked at compile time).
  The sidebar, dashboard shortcuts, link picker, entry identifiers and listing
  headers (`<Workspace.header icon={@page_icon}>`) show it. Every sidebar row
  now leads with an icon; `menu_item` and `menu_subitem` take `icon:` for
  items that aren't blueprints, and items without one show a dot.

- **Image sizes are checked when a Blueprint compiles, can start from a
  preset, and only changed images need recreating** (#1322). A size entry with
  an unknown key (`"crp"`, `"qualty"`), an unreadable geometry, or a cropped
  single-dimension size without a `"ratio"` now fails the build, and so does a
  `srcset` naming a size that isn't in `sizes`; these were ignored or warned
  only at render. `%Brando.Images.Size{}` and atom-keyed sizes are accepted and
  stored as the usual string-keyed maps. `sizes: :standard` gives Brando's
  micro…xlarge list and `sizes: {:standard, %{"hero" => …}}` adds to it,
  instead of copying the list. Each processed image stores a fingerprint of the
  sizes and formats it was made with, and Utilities counts the images whose
  config has changed and offers **Recreate changed images** next to
  **Recreate image sizes**. Run `mix brando.gen.migrations` for `brando_197`.
  Images processed before it have no fingerprint. `mix brando.images.adopt`
  records the current one for those whose files already match their config
  (formats, size keys, files and their pixel dimensions, read from the
  headers; not quality), and **Recreate changed images** does the same before
  recreating only the rest. `mix brando.doctor` counts both as a dry run.

- **Frontend edit mode.** Signed-in admins can edit blocks on the published
  site: an **Edit page** button switches edit mode on, a click on a block opens
  it alone in a sidebar with the admin's block editor, the page updates as it
  changes, and saving stores it through its entry. The sidebar shows who else
  has the entry open (the admin form shows website editors too), refuses to
  save over someone else's newer save, says when a block belongs to a shared
  fragment or a scheduled revision will replace it, and links to the block in
  the full editor, which scrolls to it. Switch it on with
  `config :brando, Brando.FrontendEdit, enabled: true` and
  `plug Brando.Plug.FrontendEdit` in the browser pipeline. Visitors and caches
  never see the edit-mode markup. Entry fields become editable where a
  template marks them: `<.editable_field entry={@page} field={:title} />` and
  `<.editable …>` in HEEx, `{% editable_field entry.title %}` and
  `{% editable … %}…{% endeditable %}` in Liquex modules; the sidebar then
  shows that field's input alone, and the page shows the value as it is typed.
  Datasource selections are edited in place like any block. See the
  [Frontend edit guide](guides/frontend_edit.md).

- **Brando sends email.** Brando now sends its own email through the
  application's Swoosh mailer: set `config :brando, mailer: MyApp.Mailer` and
  the address to send from, `config :brando, Brando.Mailer, from: {"My site",
  "noreply@example.com"}`, with an optional `reply_to` and a sender per site key
  on multi-site installations. `mix brando.gen.mail` and `mix brando.migrate55`
  set the mailer when the application has one. `Brando.Mailer.deliver_later/1`
  sends from a background job that keeps the site and retries, and
  `Brando.Mailer.Layout` puts a message in a shared HTML and plain-text layout.
  Without a mailer, sending raises in development and test, and logs a warning
  in production. `Brando.Users.UserNotifier` sends real email now instead of
  logging it. Brando depends on Swoosh now, and Swoosh does not start without
  an API client: an application created without a mailer must set one, as
  `mix brando.migrate55` and `mix brando.install` do
  (`config :swoosh, api_client: Swoosh.ApiClient.Req`). See the
  [Email guide](guides/email.md).

- **Two-factor authentication.** Users turn on codes from an authenticator
  app under **Security** in the account menu, with ten one-time recovery codes.
  Logging in then takes two steps: no session, and no remember-me cookie, until
  the code is given. A code works once. Turning it off or making new recovery
  codes asks for the password or a current code. A superuser can reset it for a
  user who lost their phone, and can require it of everyone or of some roles
  (groups, with group authorization) under **Users → Sign-in policy**; users it
  applies to set it up at their next login. Sign-in attempts, codes and reset
  requests are limited per IP address and account, and five failures within 15
  minutes lock the account for 15 minutes, an hour the second time in a day
  and four hours after that, with an email to the user (`Brando.Users.Throttle`). Sign-ins, failures,
  lockouts and security changes go to a security log, shown on the user's
  Security page. The TOTP secret is encrypted at rest (`Brando.Crypto`). See
  [User accounts and sessions](guides/users.md#two-factor-authentication).

- **Passkeys, confirming again, and sessions.** Users add passkeys (WebAuthn,
  with `wax_`) under **Security**, name them per device and remove them. A
  passkey is a second factor, satisfies a policy that requires two-factor
  authentication, and logs in on its own from the login page; the app and
  recovery codes stay as the fallback. Sensitive actions — the user form, the
  sign-in policy, groups, disabling or deleting users, a site's lifecycle and
  access, static builds and deploys, copying into an environment (a copy into
  the live one must also be ticked), deleting a site, an environment or its
  archives, setting an environment live, adding a passkey or setting up the app — ask
  for the password, a code or a passkey again when the session last gave one
  more than ten minutes ago: `on_mount {BrandoAdmin.Reauth, :screen}` or
  `on_mount {BrandoAdmin.Reauth, events: [...]}` opts a screen in. **Security**
  lists the user's sessions and logs them out, and a superuser can log a user
  out everywhere from their form. See
  [User accounts and sessions](guides/users.md#passkeys).

- **Password reset.** The login page has a "Forgot password?" link to
  `/admin/reset-password`, which emails a link to choose a new password. The
  page answers the same whether or not the email belongs to an account, and
  only active, undeleted accounts get an email. The link works once, for an
  hour, and only the newest one works; the token is stored hashed. Choosing a
  new password logs the user out everywhere and disconnects their open admin
  views. A saved user's form no longer has a password field: a superuser sends
  another user a reset link (valid for 24 hours), or, on a site without email,
  sets a password in a dialog behind "Set a password instead", which logs the
  user out everywhere and makes them choose their own at the next login. Your
  own form links to `/admin/users/password`, which asks for the current
  password and logs out your other sessions. The first-login password change
  uses the same page. Users are emailed when their password changes.
  `Brando.Users` has `request_password_reset/1`, `send_password_reset/2`,
  `set_user_password/3`, `reset_user_password/2` and
  `update_user_password/4`; the unused
  `UserNotifier.deliver_confirmation_instructions/2` and
  `deliver_update_email_instructions/2` are gone. Reset email needs the mailer
  from the [Email guide](guides/email.md); see
  [User accounts and sessions](guides/users.md#reset-a-forgotten-password).

- **Forms.** Editors build forms visitors fill in, such as a contact form, under
  **Configuration → Forms**, laying out fields on the same 12-unit canvas as module
  variables, beside the form as visitors will see it. Forms are synchronized
  translations: the source decides the fields, keys, layout and option values,
  and each translation words them in its own language. A module's new **Form**
  variable and `{% form %}` tag (or `<.site_form>` in HEEx modules) put a form in
  a block, shown in each page's language; sites can also render one with
  `Brando.HTML.Forms.site_form/1`, whose slots replace any field's markup.
  Submissions are checked, stored in `public` so promoting an environment keeps
  them, and read, deleted or exported as CSV under **Content → Forms**, which
  appears once a form has been built. The wording visitors
  read around forms — the submit button, sent and error messages — is set once
  per site under **Configuration → Forms → Messages**, in every content language. Content
  transfer matches a block's form by key. Forms carry the visitor's CSRF token,
  refreshed before sending so cached pages still work, refuse posts from other
  sites, and use a honeypot, rate limiting and optional Cloudflare Turnstile. Run `mix brando.gen.migrations`
  for `brando_194` and `brando_195`; statically delivered sites also add
  `form_routes()` to their router. Brando's default production CSP now allows
  `challenges.cloudflare.com`. See the [Forms guide](guides/forms.md).

- **Forms email their submissions.** A form's new **Submissions** tab takes
  recipients (name, address, and whether it is a blind copy) and a subject,
  which can carry what the visitor filled in (`{{ name }}`). Each submission
  is emailed to them in Brando's mail layout from a background job, with
  replies going to the visitor's address. The submissions admin shows whether
  it was sent, queued or why it was not, and **Send again** sends it once
  more. A form can also send the visitor a confirmation with a copy of what
  they sent. The source of a synchronized form owns its recipients; each
  language words its own subjects. The same tab sets how many days
  submissions are kept: `Brando.Worker.FormSubmissionPurger` deletes older ones
  every night at 05:15 UTC, in every active environment. A form can send
  visitors to a page once it is sent, instead of showing the success message,
  with or without JavaScript. The form's screen lists the entries whose
  blocks hold it, and deleting a form names them. `Brando.HTML.Forms.LiveForm`
  renders a form inside a LiveView, checked as the visitor types, with the
  same slots as `site_form/1`. Run `mix brando.gen.migrations` for
  `brando_196`. Applications that set their own `config :brando, Oban` add the
  purger to their crontab to keep submissions for a limited time.

- **Activity log.** Configuration → Activity lists who created, changed,
  published, trashed, restored and deleted entries, and when: by day, with
  the fields that changed, filters for person, content type, action and
  period, and Compare to see a change against the revision before it.
  Scheduled publishing, the assistant and content imports show as the source,
  with the person behind them. The editor's **Revisions** button is now
  **History**, with an Activity tab for the entry and the revisions on the
  second tab. The trash listing names who deleted an entry instead of
  guessing from the last editor. Events keep titles and field names, not
  values; they are removed after `retention_days` (365). Run
  `mix brando.gen.migrations` for `brando_193`. With group authorization,
  grant `brando.activity.read` to existing groups that should see it. See
  the activity guide and `Brando.Activity`.

- **Add a video that is already in Mux, Bunny, Cloudflare or Vimeo.** The video
  picker has an "Add from …" button for every configured provider. It lists
  the provider's library, with search where the API has it, and adds a video
  to Brando without uploading it again. A video already in Brando is selected
  rather than duplicated. Added videos are never deleted from the provider,
  whatever `delete_remote_on` says. Available in code as
  `Brando.Videos.ProviderLibrary`.

- **Vimeo upload strategy.** `upload_strategy: :vimeo` uploads straight from
  the browser to Vimeo with tus; the access token stays on the server. Vimeo
  has no webhooks, so `Brando.Worker.VimeoStatus` polls each upload until it is
  ready. Ready videos are stored as `:vimeo_account` and play through the
  `<video>` component from Vimeo's non-expiring HLS file link, falling back to
  Vimeo's player when the account has no file access. Needs a plan with video
  file access and a token with the `video_files` scope. See the videos guide.

- **A media ref can hold a file.** Add `"file"` to a media ref's
  `available_blocks` and the editor can pick a file there, next to picture,
  video, gallery and svg. The slot's `template_file` sets the file ref's
  defaults (class, download, `config_target`). A file in a media slot renders
  as any file ref does; a module that wants something else for some files (a
  Lottie player, an embedded PDF) declares the slot with `headless_ref` and
  branches on `refs.NAME.data.type` in its template. The assistant can put a
  file in such a slot too.

- **`data-lp-preserve` keeps a frontend widget through live preview updates.**
  The preview patches the page as the editor types, which stripped what a
  site's script had set on an element it took over (a canvas's size, a loaded
  marker). An element marked `data-lp-preserve="VALUE"` is left alone while
  the value is unchanged.

- **Live preview tells the site's scripts what it patched.** After each
  update the preview dispatches `brando:livepreview:patched` on `document`,
  with `detail.type` (`block`, `update` or `rerender`), the block's `uid` and
  the patched `elements`. A site can re-initialise sliders, lightboxes and
  other widgets in those elements; until now they stayed inert until the
  preview reloaded.

- **A site without tenancy can clean up its media files.** Deleting an image
  soft-deletes the row and the purge removes it after 30 days, but the files
  stayed on disk for good: the nightly `Brando.Worker.MediaOrphanCleanup`
  only ran with tenancy. `config :brando, media_orphan_cleanup: true` switches
  it on for a site without; `Brando.Media.OrphanCleanup.run(nil, dry_run: true)`
  reports what it would remove. The cleanup now leaves dotfiles alone.

- **Start from a template.** An empty block field offers the content
  templates of its namespace as cards; choosing one fills the field with
  copies of the template's blocks. The namespace is the field's
  `template_namespace` option, which had stopped doing anything, or else the
  one named after the schema (`cases` for `MyApp.Cases.Case`). See
  `Brando.Content.StartingTemplates`.

- **Utilities → Loose blocks.** Removing a block from an entry keeps the
  block, so an older revision can be restored with it; nothing removed them
  once no revision held them, and a site collected unreachable blocks whose
  media then looked in use. The audit lists every block tree no table links
  to (the linking tables are read from the database's foreign keys), and
  marks a tree removable only when no stored revision holds any of its
  blocks and no recovery copy mentions them. Removing copies the tree's rows
  to `content_block_archive` first, and the screen restores from it. Run
  `mix brando.gen.migrations` for `brando_192`. `Brando.Content.BlockAudit`
  does the same from code.

- **Sort by use in the image library.** A folder that has filled up with
  block images can be sorted into folders for the entries that use them
  (`cases/sommerro`, `pages/about`): a preview with the folders to make,
  renaming, per-entry opt-out and undo. Translations share their entry's
  folder; `config :brando, Brando.Images, sweep_priority: [...]` decides who
  gets an image several entries use. With **Not in use** switched on, the
  library offers to delete every unused image in view. See the media guide.

- **System → Assistant** turns a conversation into reviewed content changes
  across entries: create entries, insert blocks, and place text, images and
  videos. The model runs in the backend and only reads content and prepares
  proposals, through in-process tools called as the editor. There is no MCP
  endpoint. The editor applies a proposal with one click, which approves
  exactly that version and applies it atomically. New entries are drafts.
  Configure `Brando.AI.Agent` with a model and budgets, and grant
  `brando.assistant.use` with groups authorization. **Preview page** renders
  each entry as proposed, or as saved, through the site's own live-preview
  targets, and outlines the changed blocks. See
  [Content assistant](guides/content_assistant.md).
- `Brando.Content.Proposals` stores, validates, previews and applies these
  proposals, and can be used without the assistant.
- **Synchronized pages, and translations that follow their links.**
  - `config :brando, Brando.Pages.Page, translatable: [mode: :synchronized, ...]`
    synchronizes pages; independent stays the default. It is read at runtime,
    and `translatable_sites` sets it per site in a tenant installation.
    Brando validates it at boot.
  - A relation to the schema itself, like a page's parent, follows the source
    mapped to the parent's version in the translation's language.
  - `language_controlled_fields` gives chosen assets (a listing image, a
    brochure) to each language instead of the source.
  - A link to content without a version in the translation's language keeps
    pointing at the source-language content instead of being emptied, and
    moves once that version exists. Identifiers made before a schema was
    translatable are mapped by their entry's language.
  - Link pickers offer content in the entry's language. A link's typed URL
    is kept per language like text (translate when new, review when the
    source changes it); whether a link points at an entry or a URL follows
    the source.
  - A content transfer that updates a synchronized source queues its
    translations' sync, as a save does.
  - Creating a translation keeps the source's text instead of the duplicate's
    "(copy)" marks, leaves out child pages and fragments, and requires a
    duplicate mutation in the context (`{:error, :not_duplicable}` otherwise,
    and the admin no longer offers it). A failed copy leaves no group behind.
  - A pending version computed before its translation last changed (a
    published revision, a scheduled release) is recomputed before the editor
    applies it. Stale shared updates are no longer carried to the next version.
- **Synchronized translations in the admin.** A translation opens with its
  pending version in the form, lists the text to translate or review, and
  resolves only what the editor completed when saved. Its structure, media and
  source-controlled values are locked and enforced on save. The source gets
  **Save minor text corrections**; translations get **Make independent** and
  **Make source**, and missing languages can be created from the entry.
  Listings show each language's open work. See
  [Synchronized translations](guides/i18n.md#synchronized-translations).
- `source_controlled_fields` accepts subform fields (`credits: [:url]`) and
  block-module variables (`{:module, "hero-banner", [:layout]}`);
  `Brando.Translations.check_config/1` checks module selectors against the
  database.
- `Brando.Blueprint.AfterSave.run/5` takes `minor: true`.
- Run `mix brando.gen.migrations` for `brando_183`–`brando_187`, which add
  proposals, their receipts, and assistant conversations. All live in `public`.
- **Build with AI** in the block editor opens the assistant for that entry
  and block field. The assistant reads the saved entry and says so.
- `config :brando, Brando.AI.Agent, guidance: …` gives the assistant the
  site's conventions for its modules, per site, environment and content type.
  See `Brando.AI.Agent.Guidance`. **Configuration → Assistant guidance**
  edits it per site and environment, with history and copying from other
  sites. It needs the new `brando.assistant.configure` capability, which only
  superusers have by default.
- The assistant can attach every image or video in a named media folder,
  page by page, and asks when a folder name is ambiguous.
- `Brando.AI` takes named models: `models: [default: "...", image: "..."]`.
  Alt text asks for `:image`, so a cheaper model that reads images can write
  it while a stronger one writes copy; a name that is not set falls back to
  `:default`, and a field's `model:` accepts a name or a full spec.
  `default_model:` still works. App `fields` config now fills in what a
  trait's AI options leave out (a `model:` for Page's meta fields, say)
  instead of being ignored whenever the trait has any. A model outside the
  `llm_db` catalogue is reported as unknown (price and image input) rather
  than as unable to read images, which blocked alt text for Claude Opus 5.5
  on the 2026.9.1 catalogue; run `mix deps.update llm_db` for its prices. The
  alt text page and the Content SEO tab name the model each job uses.

- `absolute_url ..., only: %{field: value}` names the entries that have a URL on
  this site; the rest (a case that only links to the client, say) get `nil`
  from `__absolute_url__/1` and are left out of the content SEO audit. The same
  map is `__url_filter__/0` for a sitemap's list query, and `__has_url__/1`
  answers for one entry, so the rule is declared once. A one-arity function
  works too, without the query filter.

- Services are configurable on the identity. A new **Services** tab in
  Configuration → Identity takes a repeatable list (name, description,
  alternate names, service type, URL, area served) and an optional link to
  an entry; a linked service takes that page's URL and — when it has no
  description of its own — the page's meta description or block text, so the
  markup describes content that is actually published. Every service is
  rendered into the JSON-LD graph as a `Service` node joined to `#identity`,
  inheriting the organization's `areaServed` unless it names its own.
  `<Brando.HTML.Services.list language={@language}>` renders them as a visible
  section so the markup has a real counterpart. The `brando_177` migration
  adds `sites_services`.
- Identity `area_served` and `knows_about` are lists. A site with eleven
  services no longer emits one long `knowsAbout` string that a consumer reads
  as a single topic, and `areaServed` can name the actual markets. The admin
  gets a `:string_list` input (one entry per row; the last row is always empty
  and clearing a row removes it). `Brando.Type.StringList` still loads the old
  comma-separated shape, and the `brando_176` migration rewrites stored rows.
- Datasource blocks can emit JSON-LD for the entries they rendered. The
  `json_ld` Liquex filter (`{{ entries | json_ld: "CreativeWork" }}`) and the
  `<.json_ld entries={@entries} type="CreativeWork" />` HEEx component build an
  `ItemList` — or a `CollectionPage` with the `page` flag — through
  `Brando.JSONLD.Collection` from the same list the template iterated, so the
  markup is cached with `rendered_<field>` and cannot drift from the HTML.
  Entries without an `absolute_url` are skipped. `ListItem.build/3` no longer
  double-prefixes the host on an already absolute URL.
- Configuration → SEO gains a **Content SEO** tab that audits published entries
  with a page of their own: meta title and description present and of display
  length, an own description rather than the site fallback, a sharing image,
  a resolvable URL, sitemap membership, and titles or descriptions shared with
  other entries in the language. Each entry gets a weighted score, the tab a
  badge, and the overview lists duplicates and counts. Runs on demand with one
  read per content type that leaves the rendered block HTML out. Blueprints
  can add checks by overriding `__seo_checks__/1` with
  `Brando.SEO.Check` structs. Recorded 404s whose slug matches an audited
  entry are listed as missing redirects with a one-click "Create redirect"
  that appends to the SEO settings.
- **Write missing meta descriptions in bulk** from the Content SEO tab. The
  tab says how many entries it will send to the model — at most
  `config :brando, Brando.SEO, max_batch: 200` per run — and asks first. Each
  entry is written by a background job into a suggestion (new table
  `seo_meta_suggestions`, migration `brando_179`), never into the entry;
  suggestions appear in a review list as they finish, and can be edited,
  accepted, rejected or all accepted at once. Accepting saves through the
  entry's own context as the reviewing user, so revisions and "edited by"
  apply, and an entry that fails its own validation says which fields to fix.
- **Review with AI**: an advisory critique of an entry's meta title and
  description against its content — at most three points, in the admin
  language, never written anywhere.
- The Content SEO tab and its checks are translated into Norwegian.
- `:i18n_string` inputs (`:i18n_text`, `:i18n_textarea`) show one tab per
  language, mark a language only while another one has text, and take
  `languages: :content` for content
  languages (admin languages remain the default). A plain string cast to the
  type lands under the default content language instead of `"en"`.
- AI entry translation leaves a placement alone when the image it inherits
  from already has text in the target language.
- **Write alt text with AI**: Assets → Images → Alt text lists images without
  alt text in any content language, estimates what describing them would cost with the configured
  model (from ReqLLM's catalogue prices and each image's size, via
  `Brando.AI.Cost`), and describes them in the background from a mid-sized
  rendition. Suggestions wait for review — edit, accept, reject or accept all —
  and accepting fills in the image's own `alt` for every language it lacks —
  one request per image covers all of them, since the image, not the extra
  sentences, is what costs. Uses
  the `:alt` field's AI options (`config :brando, Brando.AI, fields: [alt:
  [model: ...]]`) and refuses models that cannot read images. The image
  library links to it with the missing count, and so does the Content SEO
  image check. `Brando.AI.generate_text/2` now also takes ReqLLM messages.
- Content SEO checks **heading structure** (at most one H1 in the body, no
  skipped levels), **image alt text** (present, not a filename or a generic
  word) and **language versions** (a published translation much longer, with
  more images or headings, or edited months later). All three are measured by
  the database from `rendered_<field>`.
- Content SEO reads traffic from **Plausible** and **Google Search Console**
  when configured (`config :brando, Brando.SEO.Analytics, ...`): visitors and
  search clicks per entry, sorting by the busiest pages, a count of pages
  nobody visited, the searches a page is shown for, and a click-through check
  for first-page results few searchers click. The AI review weighs the
  description against those searches. Search Console signs in with a service
  account; site and property default to the SEO base URL's host. Setup is in
  the new [Content SEO guide](guides/content_seo.md).
- The Content SEO audit flags **thin content**: an entry whose rendered blocks
  hold fewer than 300 words warns, and one with no body text fails. The words
  are counted by the database from the `rendered_<field>` columns, so the HTML
  still never leaves it. Change the threshold with
  `config :brando, Brando.SEO, thin_content_words: 300`. A meta description
  that opens by repeating the title now warns as well.
- Write an entry's meta description from the Content SEO tab, without opening
  the entry. The prompt is the one the blueprint declares through
  `trait :meta, ai: [...]`, and the tab lets you pick which of the entry's
  fields it reads — stored per content type on the site's SEO settings, so the
  choice outlives a deploy. Block fields are read from the entry's rendered
  HTML rather than by re-rendering the block tree, which the new
  `Brando.AI.Context` does for both the form and everything outside one. All
  of it is hidden unless `Brando.AI` has a provider configured.
- Entries record who last edited them. `Brando.Trait.Creator` now adds
  `updated_by` and `edited_at` next to `creator`; they stay empty on insert and
  move only on later user-initiated saves (`:system` saves, block re-rendering,
  migrations and `mix brando.entries.resave` leave them alone, while
  `updated_at` keeps its Ecto meaning). `trait :creator, derived: [...]` names
  fields a processing pipeline writes, so image sizes or a video provider's
  status do not count as edits either. Deleting a user transfers their edits
  along with their content. The entry listing shows "Edited by <editor> · edited_at" once an
  entry has been edited, and "Created by <creator> · inserted_at" before that —
  it no longer pairs the creator with `updated_at`. Brando's own tables get the
  columns from the `brando_175` migration (`mix brando.gen.migrations`);
  application blueprints get them planned by
  `mix brando.gen.blueprint_migration --all`.
- Add `mix brando.setup`, which runs the operational steps after
  `mix brando.install`: asset builds, `ecto.create`/`ecto.migrate`, a superuser
  account and default content seeds. Every step is skipped when its result
  already exists, so a rerun after a failure resumes instead of duplicating.
  Skip steps with `--no-assets`, `--no-db`, `--no-account` and `--no-seeds`;
  supply `--email`, `--name` and `--password` for an unattended account.

- Add `mix brando.gen.seeds`, seeding the content a new installation needs
  before its first request succeeds: identity and SEO per configured language,
  seven modules, a published `index` page built from six of them, a `main`
  navigation menu and a `partials/footer` fragment. Previously a fresh install
  had no published page, so `/` responded 404 until one was created by hand.
  The seeds are idempotent and never modify existing content.

  The seeded page is a designed welcome page rather than placeholder copy: a
  hero with a fact row stating what the installer made, a three-step quick
  start, a grid linking the framework guides, six tips, and a Toolbox module
  rendering the mix tasks Brando adds — marking the ones that show a diff
  before writing. Delete it when it has served its purpose; nothing is wired
  into the templates.

- Retune the installed frontend for a dark default: `europa.config.cjs` ships
  a flat deep green ground (`#030e0a`), bone foregrounds at five opacities and
  a single champagne accent, plus `heading/7xl` and `code/sm` type sizes. The
  scaffold CSS is rewritten against it, and `.label`, `.button`, `.textlink`
  and `.section-head` are available as shared furniture for your own modules.

- `mix brando.install --public-site --replace-phoenix-home` now retires the
  generated Phoenix homepage request test along with the route it covers.
  A customized test is preserved with a notice instead.

- Add bidirectional module-definition DSL export/import with adjacent HEEx or
  Liquid files, complete ref/var settings, child and table-template dependencies,
  baseline conflict checks, dry-run plans and atomic imports. The new
  `mix brando.modules` command supports standalone and explicit tenant scopes.
  The admin can download DSL ZIPs, preview and apply uploaded bundles, inspect
  field changes/conflicts, and download an updated baseline for the next edit.
  Migration 172 adds stable table-template UIDs. See the module definitions guide.

- Configure Vite development servers independently with `BRANDO_VITE_FRONTEND_HOST`
  / `BRANDO_VITE_FRONTEND_PORT` and `BRANDO_VITE_ADMIN_HOST` / `BRANDO_VITE_ADMIN_PORT`.
  Brando's HMR script URLs and installer Vite configs read the same environment
  variables, allowing multiple local projects to use HMR on different ports.
  Defaults remain `localhost:3000` and `localhost:3333`; production and `hmr: false`
  continue using the Vite manifests.

- **Opt-in rich footnotes and named block regions.** Text refs and top-level
  Blueprint rich-text fields can enable notes backed by a configured set of
  ordinary modules, including image, video and file controls. References load
  as numbered editor buttons; Villain numbers them in final rendered order
  with accessible endnotes and return links. Blocks refs expose independent
  named collections in both Liquid and HEEx templates. Upgrade migration 169
  adds the internal slot fields; Floki is now a runtime dependency. See
  [the setup and rendering guide](docs/FOOTNOTES.md). (#1523, #2651)

- File resource listings offer **Replace file** (#2638). Replacements preserve
  the file ID, filename, URL, title, folder, and existing references. Uploads use
  the shared manager and validate the original file's configuration before
  replacing local or CDN contents. Entries using the file in block refs, vars,
  or table rows are queued for rendering so embedded file metadata stays current.

- **Automatic entry recovery copies** (#2694). Blueprint forms keep user-owned
  recovery copies of unsaved fields, blocks, and completed transformer rows.
  Editors can compare, restore, download, or dismiss a copy. Changed modules
  require review before incompatible blocks are applied; failed attempts leave
  the original available and offer a clean editor without a restore loop.
  Explicit saves resolve the matching copy. Requires migration 168. See
  [the walkthrough and screenshots](docs/entry-drafts/README.md).

- `trait :permalink` offers to create an exact 301 redirect after an editor changes
  an existing entry's URL. Built-in pages enable it; confirmation stores the rule
  in the previous language's SEO settings and continues the selected save action.
  Saving a changed URL removes its existing exact permalink redirect even when
  the editor continues without creating a redirect from the old URL.

- **Module migration tracking, and a warning before a module save destroys
  content** (#2642). Saving a module has always been a site-wide migration: every
  block using it is re-synced, and any reference the module no longer declares was
  deleted from every block, in every entry, with no warning and no way back.

  - **References are now retained instead of deleted.** A removal is
    indistinguishable from a rename at this level, and the data is the editor's,
    not the module's. Orphaned references lie dormant — the template no longer
    renders them — until an explicit upgrade resolves them. Variables were
    already retained; references now match.
  - **`content_modules.version` counts definition revisions.** It bumps on an
    effective change (see `Brando.Content.ModuleDiff` for what counts) and not on
    a save that changed nothing. The bump doubles as an optimistic lock, so two
    editors on the same module can no longer silently publish two different next
    revisions — the second is told to reload.
  - **`content_blocks.module_version` records how far each block got.** A block
    holding data the current definition cannot read — an orphaned reference or
    variable, or a reference whose block type the module swapped — is left behind
    its module rather than stamped as current, and is findable through
    `Brando.Content.Blocks.list_stale_block_ids/2` and `count_stale_blocks/2`. A
    block whose write fails mid-migration stays behind too, so a partial migration
    is a visible queue instead of silent mixed state.
  - **The module editor asks before a destructive save**, naming each reference
    and variable that will be orphaned and how many blocks on the site use the
    module.
  - **`content_modules.uid`** is the new lineage identity, for the import
    replacement still to come. Name and namespace cannot serve: both are i18n
    JSON maps, neither is unique, and both are editable. Export and import mint a
    fresh `uid` at v1 for now — importing has always produced copies, and
    recognising a re-import as the same lineage needs the versioned envelope and
    conflict handling still to be built.

  Requires `brando_167`. Run `mix brando.gen.migrations` and `mix brando.migrate`. Existing
  modules are given a `uid`, and existing blocks are backfilled as current, so
  upgrading does not flag a site as stale on day one.

- **Igniter-assisted tenancy setup for existing applications.** The opt-in
  `mix brando.setup.tenancy` task configures `:single` or `:multi` mode, inserts
  `Brando.Plug.Tenant` idempotently into recognized browser pipelines before
  Brando content-loading plugs, and installs Brando's tenant migration support.
  It reports unsupported router layouts and prints the ordered migration and
  provisioning workflow without inferring application tables, touching the
  database, or copying production data.

- **Versioned static-site publishing for sites with `delivery_mode: :static`.**
  The new Publishing screen builds any named content environment on a serial
  Oban queue, records monotonic versions, progress, logs, and failed URLs, and
  provides expiring previews. Successful artifacts persist outside OTP
  releases and can be deployed or rolled back through rsync or S3, with
  optional automatic deployment, webhooks, and retention pruning. The
  interactive `mix brando.ssg` task now calls the same tenant-safe renderer and
  retains a non-tenant dry-run/non-interactive workflow.

  This lifecycle is intentionally separate from Florist: Florist deploys and
  rolls back the running Phoenix release; Brando republishes static artifacts.
  See `guides/tenancy_and_environments.md` and `guides/deployment.md`.

- **A video form field can declare playback defaults for new videos.**

      input :video, :video,
        label: t("Video"),
        defaults: %{loop: true, muted: true}

  `BrandoAdmin.Components.Form` merges these onto the blank `%Brando.Videos.Video{}`
  before building the drawer's changeset, so the drawer's switches show them and
  saving persists them.

  Both ends of this were already built — `Form.Input.Video` carried a `defaults`
  assign and `Form.update(%{action: :open_video_drawer, …})` consumed it — but
  nothing populated it: the generic input renderer passes a fixed assign list
  with no `defaults` in it, so `assign_new` always won with `%{}`. The input now
  reads it from the form field's opts, and raises on a key
  `Brando.Videos.Video` has no field for rather than letting `struct/2` drop it.

  This matters because the video's playback columns carry no default, so a new
  record has `autoplay`, `preload`, `loop`, `muted` and `controls` all nil.
  `Brando.HTML.Video` reads nil as "use the built-in default" — `true` for
  `loop`, `false` for the rest — while the drawer draws them as plain
  checkboxes, which have no way to render "unset". A freshly uploaded video
  therefore showed **Loop: off** while looping.

  These set the video *record*, the middle layer of the resolution chain: a
  block or `{% video %}` override still wins over them, and they in turn beat
  `Brando.HTML.Video`'s built-ins.

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

- **Duplicating a module works again, and copies the whole module.** It
  failed on the unique module `uid`. The copy is now a new module at
  version 1 with its own `uid`, without the original's shared-library link.
  It gets copies of the original's references, variables and child (entry)
  modules, joins the module sets the original is in, and gets the class
  `<class>-copy` (`-copy-2` and on when taken) instead of `<class> (copy)`.

- **The Assistant recovers from a stopped, reconnected or interrupted run,
  and from a failed apply.** Stopping a run while the model answered with
  tool calls left the message box disabled until a reload, while a reload
  or another tab could start a second run before the first had finished
  writing. A stopped run now shows "Stopping…" everywhere and holds the
  conversation until its call returns. A conversation opened again while
  its run worked showed no progress and no **Stop**. A run left behind by a
  restart or a deploy blocked the conversation for ten minutes; runs now
  show a heartbeat, so one whose server is gone lets go after a minute,
  also across the two colours of a blue/green deploy, and the page notices
  without a reload. When applying a proposal failed and rolled back, every later
  **Apply** was refused as no longer under review; it now applies once the
  cause is gone, and a click in a second tab after the first applied shows
  the receipt. A run whose user loses **Content assistant → use** stops
  before its next model call. See "Operating the assistant" in
  [Content assistant](guides/content_assistant.md#operating-the-assistant).
- **Two editors in an entry's fields keep each other's changes, and a
  field is unlocked when its editor leaves it.** Each editor now sends the
  entry fields (title, URI and the other fields, not blocks) they changed
  since they last sent, a field set back to its saved value included, and
  never a value they only hold. A title set back to the saved one used to
  stay as the other editor's own text on their screen, and their next field
  sent the old title back to everyone. Leaving a field straight after typing
  in it no longer sends the field before the last keystrokes. A change to
  the field someone is in waits until they leave it, and applies unless
  they typed. Leaving a field, a rich text field included, unlocks it for
  the others; before, it stayed locked until the editor focused another
  field or left the entry. An image, video or file field is locked while
  its drawer is open and unlocked when it closes (Done, ×, the backdrop or
  Escape), and a multi-select when its options close. Locks belong to a
  browser tab: someone with the entry open in two tabs locks a field in
  each, and closing one tab unlocks only its field. Two editors who leave
  one field at once end with the same value. AI text and other values the
  form fills in reach the other editors at once, an editor who opens an
  entry without block fields gets the others' unsaved values, and a
  reconnect no longer sends the browser's old values over newer ones, while
  what was typed during it still wins. An edit made after a save or a
  reload wins over the edits before it.
- **Every editor sees an image finish processing.** With two editors in one
  entry, an image the first uploaded or replaced showed "Processing image…"
  in the second editor's field, picture ref, image variable or gallery until
  that editor reloaded, and an editor who opened the entry while an image was
  processing saw the same. Only the form that uploaded an image heard that it
  was processed. Processing now also reports on a topic per asset
  (`Brando.Assets.ProcessingStatus`), and each open form follows the images
  it shows in processing, and the videos it shows uploading to or processing
  at their provider, until they are done, and takes the finished asset into
  the form and its live preview. A video field now takes its provider's
  reports as they come; before, it caught up only when something else
  re-rendered it, in every editor. Image and video fields in a form no
  longer read their asset from the database on every render while it is
  processing.

- **Image sizes given only a height are made, and crops come out at their
  size.** A size such as `"x400"` stopped processing with an error; it is
  now fitted to the height. A cropped size could come out a pixel or two
  short of its geometry on originals of unusual proportions (`399×400` for a
  `400x400` crop); the size that covers the crop is now worked out from one
  scale, so it is exact. Recreate the affected images to get the new files.

- **A width-only image size is that width, and no size is enlarged.** Since
  the move to libvips, a size such as `"700"` was fitted inside a 700×700
  square, so a portrait came out 700 tall and narrower than its `srcset`
  said (525×700 from a 3000×4000 original). It is now 700 wide for portraits
  and landscapes alike, as it was with sharp in 0.54. Every size used to be
  enlarged from an original smaller than it; now none is. An uncropped size
  keeps the original's size, and a cropped size is the largest part of the
  original with its proportions (`200×200` for a `400x400` crop of a
  300×200 original). A trailing `>`, as in `"400x400>"`, is still accepted
  and changes nothing. Cropped sizes of photos stored on their side (EXIF
  orientation) are now cut from the upright image, at their size and around
  the right focal point. This changes only images uploaded or recreated from
  now on. Existing files stay as they are and still count as matching their
  config, so `mix brando.images.adopt` and **Recreate changed images** don't
  recreate them for this.

- **A `srcset` says how wide each file really is.** The `w` widths in an
  image config's `srcset` were printed as written, so a 600-pixel original
  rendered its `"1400"` size as `1400w` although the file is 600 wide, and
  several sizes as different widths of the same picture. When the image's
  width and height are known, each width is now lowered to the size's real
  one, and sizes that end up equally wide are listed once: 400, 700, 1100 and
  1400 for a 600-pixel original render `400w` and `600w`. Media query
  sources do the same. An image's width and height are now recorded as it is
  shown, turned by its EXIF orientation; images uploaded earlier get them
  when they are next processed.

- **Nothing typed or changed in a shared entry is lost on the way to a
  save.** The save button and ⌘S no longer submit the form, which took the
  focus from the field being typed in and ignored every key until the save
  was done. A save slower than 30 seconds no longer shows what it saved as
  unsaved changes. Unsaved work in a block another write removes comes back
  also when the editor who did it has left (the others are told), and a
  child block comes back in its parent, or inside its removed parents, not
  as a root; work two editors had in one removed container comes back in
  one copy. Two editors adding a select option or a gallery image each
  both keep theirs, and a gallery showing one image twice keeps both
  copies apart. Pressing Save and ⌘S together saves once.

- **Saving a revision loaded as a working copy writes it.** The revisions
  drawer loaded a revision by making it the form's saved data, so the form
  held no changes and Save wrote nothing, while the editor showed the
  revision as restored. A loaded revision is now unsaved changes to the
  entry as it is saved: its fields, its entry vars and its blocks, with
  their refs and vars. Save writes them; blocks the revision lacks are
  deleted, and blocks the entry has lost since come back as new ones. The
  editor shows unsaved changes until then.

- **Activating a revision loaded as a working copy keeps the working copy.**
  Loading a revision into the editor replaces its unsaved changes, but the
  entry's edit session still held them: when the revision was activated
  they were carried back over it, and a later save wrote them. The editor
  now leaves the session marking what it replaced, so a write of the working
  copy keeps only what others changed after it was loaded, and its block
  fields no longer rejoin the session with the replaced changes.

- **Pages emit their Article again.** A page's structured data type
  (`WebPage`, `AboutPage`, `ContactPage`, …) was given to the page's Article as
  well, so the Article took the page's `@id` and the graph kept only the page.
  Page types now type the page alone; other values of `json_ld_type` still
  replace the entity's type.

- **Fresh installs build the admin again.** `@codemirror/language` 6.13.0
  (7 October 2026) imports `@codemirror/streamparser` without declaring it, so
  `mix brando.assets.setup` failed to resolve it in new projects. The backend
  `package.json` pins `@codemirror/language` to 6.12.4 through
  `pnpm.overrides`, and `mix brando.gen.backend --upgrade` adds the pin to
  existing projects.

- **Listings with two or more alternates render again.** The alternates
  column keyed its rows on identifiers built in memory, whose `id` is nil, and
  LiveView 1.2 raised "found duplicate key nil in comprehension".
- **`{% picture %}` renders a gallery object's image.** Since `brando_136`, a
  loop over a gallery ref yields `GalleryObject`s; passing one to `picture`
  raised `FunctionClauseError`. `brando_200` also rewrites stored module code
  that loops over a variable assigned from a gallery ref
  (`{% assign images = refs.slider.gallery.gallery_objects %}`), which
  `brando_141` missed, so `image.alt` and friends read `image.image.alt`. Run
  `mix brando.gen.migrations` for `brando_200`. `brando_141` is now a no-op:
  it also rewrote HTML that named the loop variable (`class="image"`) and lost
  the loop at a nested `{% endfor %}`, and `brando_200` repairs the loops it
  handled. Sites that already ran it are unaffected; a copy that has not run
  yet shows up in `mix brando.migrations.check`.
- **Passwords saved through the context are hashed.** `trait :password`
  hashed only in the admin form's save, so `Brando.Users.create_user/2` and
  `update_user/3` stored a plain-text password as given, although the users
  guide says they hash it. The trait now hashes a changed password when the
  entry is written, from any save. Code that passed a pre-hashed password to
  the context (`Bcrypt.hash_pwd_salt/1` before `create_user`) must pass the
  plain text instead, or its users cannot sign in; inserting a struct with
  `Repo.insert` is unchanged. Brando's own account creation (the admin form,
  `mix brando.setup`, `mix brando.gen.admin`) always hashed; only application
  code that set passwords through the context was affected. Such rows are not
  Bcrypt hashes: `SELECT id, email FROM users WHERE password NOT LIKE '$2%'`
  lists them, and their passwords should be reset.
- **Context saves set `publish_at` and sync translations.**
  `trait :scheduled_publishing` gives an entry published without a
  `publish_at` the time it was saved from any save, not only the admin form's.
  Context `create_*` and `update_*` calls now queue the sync of synchronized
  translations (`Brando.Translations.source_saved/2`) themselves, as the admin
  form, revisions, proposals and content transfer already did, so translations
  of a source saved from code no longer go stale. Drop any
  `source_saved/2` call made after a context save: a second call queues a
  second sync. `minor: true` is now a mutation option. An editor's save of a
  synchronized translation no longer also queues a background recompute,
  which could run before the save's own recompute and replace the version
  the editor had just reviewed. `Brando.Blueprint.AfterSave.run/4` now runs only the traits'
  `after_save/3` and takes no options.
- **Replaying the migration chain on a 0.51 database.** `brando_80` no
  longer queries a Blueprint whose table or embedded image column does not
  exist yet (a Blueprint added in the same upgrade), and Blueprint
  snapshots written by 0.51 — before Blueprints had assets — decode again
  instead of failing with "Invalid legacy Blueprint snapshot field: :assets".
  Fixed for #2969 as well: `brando_80` drops every foreign key that points
  at `images_series` or `images_categories`, so a site table's
  `image_series_id` no longer blocks the drop. `brando_95` stops with an
  explanation when the site already has a `videos` table. `brando_146`
  numbers each gallery's images in `(sequence, id)` order, since legacy
  series often had tied sequences, and gallery objects preload with an `id`
  tiebreak, so tied images no longer reshuffle between requests.
  `brando_69`, `brando_75` and `brando_76` give the existing global sets,
  identity and SEO the configured `:default_language` instead of `"en"`, and
  copy identity and SEO to every other configured language.
- **Boolean globals render.** `Brando.Sites.render_global/3` read `:value`,
  which boolean vars never set, so a boolean global always rendered `nil`. It
  now reads `value_boolean` (#2969).
- **`mix brando.identifiers.sync` carries on past a failing entry.** One
  entry whose identifier raised, for example an `absolute_url` reading a
  missing association, stopped the whole sync. Each entry is now synced on
  its own; failures are listed at the end and the task exits with status 1
  (#2969).
- **`localized_path/3` in development.** It checked the router helpers with
  `function_exported?/3` without loading them, so in interactive mode every
  localized link could come out as `/<url cannot be localized>`.
- **Background media jobs without an admin user.** Image processing and CDN
  delivery recorded `user.id` and crashed for `:system`; they now record
  `nil` and read it back as `:system`. Image, File and Video no longer
  require a creator.

- **Live preview block updates keep all of a block's markup.** A block whose
  HTML started with `<style>`, `<script>`, `<link>` or `<meta>` lost it on its
  first edit, and table rows outside a table vanished. A block whose top-level
  element changed tag stopped updating after that edit. An entry-field update
  threw on a template without `<main>`, and went to a detached element after a
  full rerender had replaced `<main>`.

- **"Add from URL" on an entry's video field no longer crashes the form.** The
  picker hands the new video to the field as an update the field had no
  clause for, so creating one took the entry form down with its unsaved
  changes. The field now selects it.

- **Unlisted Vimeo videos play.** An unlisted Vimeo video only plays when its
  embed URL carries its privacy hash, and every embed dropped it — the picker
  even saved `123/abcdef` as the video id. The hash is now read from the
  pasted URL wherever Vimeo is embedded and in the oEmbed lookup. Existing
  videos are fixed without a migration.

- **Shared preview links no longer break on deploy.** The stored preview HTML
  links the digested asset names of the build it was rendered with, and the
  next release removed those files. Sharing now pins the preview to an
  immutable asset set: the active uploaded set when it is self-contained,
  otherwise a copy of the release's `priv/static` captured into
  `site_assets/sets/capture-<identity>` and registered without activation.
  `Brando.Plug.SiteAssets` serves the content-addressed files of every set an
  unexpired preview references at their original URLs, and now sends a
  `content-type` header. `Brando.Assets.SiteAssets.Retention` protects pinned,
  active, and build-referenced sets from pruning and is the API deployment
  tooling must use to delete sets. Run the `brando_173_add_asset_set_to_previews`
  upgrade migration; previews created before it keep the legacy behaviour and
  must be recreated if already broken.

- Container blocks render without reading a module-only `multi` flag, restoring
  insertion, nested content and copy/paste after the footnote changes.

- **Modal dialogs sized their prose like page content, and stacked their footer
  buttons edge to edge.** `.modal-body` inherited `body`'s `@fontsize base` —
  20px on desktop, 23px at xl — so loose text in a dialog came out oversized
  beside the 13–16px controls next to it; it is `@fontsize sm` now. Fields and
  labels set their own sizes, so nothing else moves. `.modal-footer` was a flex
  row with `justify-content: flex-end` and no `gap`, which left two buttons
  touching.

- **The identifier picker's filter input did nothing.** `Brando.SelectFilter`
  toggles `.filter-hidden` on each option it filters out, but the only rule for
  that class lived nested under `.multiselect .options .options-option` in
  `Select.css`. An `.identifier` therefore got the class and stayed on screen —
  `.identifier` sets `display: flex` at the same specificity from a stylesheet
  imported later. `.filter-hidden` and the `.no-results` empty state are now
  global utilities in `app.css`, so every consumer of the hook is covered.

  Two adjacent problems in the same picker: the schema buttons never showed
  which type was selected (`selected_schema_raw` holds the *string* pushed back
  by `phx-value-schema`, and was compared against the module atom), and a picker
  restricted to a single schema crashed on render — the lone schema was
  preselected but `@identifiers` was only ever assigned by the `select_schema`
  event, which never fired.

  `.select-filter` also named two unrelated components: the hook's wrapper and
  the content list's filter dropdowns, whose `display: flex` and
  `margin-bottom: 0 !important` leaked into every filter modal. The list one is
  now `.list-filter-select`.

- **Every module in the block picker wore an identical "site" badge.** The card
  rendered its `library_origin` unconditionally, so with no shared library in
  play — every module local — the badge stamped the same word on all of them and
  distinguished nothing. It now appears only for `shared`/`customized` modules,
  where it is the thing that separates them from the site's own.

- **The link var's identifier modal was laid out in a narrow column.** Its two
  panels were type-radios on the left and *everything else* on the right, so the
  content-type buttons and the whole entry list were squeezed into half the
  modal while the left panel sat nearly empty. Type, link text and target now
  share one row above, and the identifier picker gets the full width for its
  own `schema buttons | entries` columns — the same shape the TipTap link dialog
  already used.

- **A missing module took down the whole render instead of one block.** The
  multi-module clause of `Parser.module/2` matched `{:ok, module} =
  Content.find_module(...)` for both the parent and every child, so one
  soft-deleted or uncached module raised `MatchError` out of `Villain.parse/3`.
  On the live-preview path that kills the entire render, and the preview then
  looks frozen rather than showing the broken block. Both lookups now fall back
  to the same `module-not-found` placeholder the single-module clause has always
  rendered.

- **Norwegian translations were ~450 strings behind the source.** The `.pot`
  files had not been re-extracted since a large batch of admin work landed, so
  the block picker, the environment/site/publishing views, the var layout
  canvas, the asset browsers and the AI and revision flows all fell through to
  English. Extracted and merged, then translated — including the 104 entries
  gettext had fuzzy-matched from unrelated strings, which is worse than
  untranslated because they render (`Paste` → *Plakat*, `Pages` → *Bilder*,
  `Author` → *Auto*). The `.po` headers were also missing `Content-Type`, which
  made `msgattrib`/`msgfmt` mangle every non-ASCII msgid.

- **A multi module's children vanished from live preview on any edit.** The
  `update_block` handler in `livepreview.js` zipped the parsed HTML against the
  block's registered elements, but the two lists were built differently:
  `rebuildContentBlockRegistry` collects ELEMENT nodes only, while the parsed
  side was every child node — boundary comments and whitespace included. Index 0
  therefore paired the `[+:B<uid>]` comment against the block's first element,
  the nodeType check failed, and the replace branch removed the live element
  without ever reaching the `has_children` splice that puts the children back.
  The parsed nodes are now filtered to elements, matching the registry.

  Registry entries also never carried their own `uid`, so every
  `` `[-:C<${block.uid}` `` guard compared against the string `"[-:C<undefined"`
  and never matched. They carry it now.

- **Reactivating a multi module left `[$ content $]` on screen.** Two gates, one
  behind the other. `should_force_live_preview_update?/3` only asked for a
  children render when a `:container` flipped active — a `multi` module renders
  its children through the same annotated slot and needs the same treatment. And
  even once it did, `Parser.module/2` tested `if skip_children?` rather than
  `if skip_children? === true`; `:force_render` is truthy, so the placeholder
  branch ran anyway. The container clauses had always matched on `true`
  explicitly, which is why only containers ever worked.

- **Block var modals were styled by the block they sit in.** A var's editing
  modal is a descendant of `.variable`, not a portal, so block styles cascade in.
  `.brando-input:last-of-type .field-wrapper` zeroed the bottom margin of every
  wrapper nested below the last input — it is a direct-child selector now — and
  `.block-vars input[type="text"]` outranked `.modal-content input.text`,
  rendering the modal's fields 50px tall with 14px of vertical padding. The var
  widget rules now hand the modal's own chrome back inside `.modal-content`.

- **Picture and video captions lost their rich text editor** in `ad47cd205`,
  which left existing captions showing their markup as literal `<p></p>` in a
  plain text input. Both are `Input.rich_text` again. To keep the revert
  affordance that change was made for, `rich_text/1` takes two opt-in attrs:
  `reset` renders the same reset button, dispatching `brando:tiptap:clear` to
  the hook because the editor owns the document and only syncs outwards; and
  `default_value` prints the inherited value below the editor, since a rich text
  field has no placeholder to advertise it with. Both treat `<p></p>` — what an
  empty TipTap document serializes to — as empty.

- **Removed the dead `.important-vars` styles**, orphaned when `important`
  became `placement`.

- **Gallery refs rendered nothing at all.** Two defects stacked, and each hid
  the other:

  1. `merge_ref_associations/1` attached the resolved gallery with
     `struct(ref.data.data.__struct__, Map.put(override_data, :gallery, …))`,
     but `GalleryBlock.Data` has no `gallery` field — so `Kernel.struct/2`
     dropped it, exactly as it dropped the picture and video presentation
     settings. `GalleryBlock.Data` now declares `gallery` as a virtual
     attribute.
  2. `gallery/2`'s clauses matched `%{type: …, images: images}` — the flat list
     block data carried before galleries became their own domain in
     `44af5c449`. `GalleryBlock.Data` has never had an `images` key, so every
     gallery ref fell through to the `_ -> ""` catch-all.

  `gallery/2` now renders `gallery.gallery_objects` in sequence, images through
  the picture component and videos through the video component — galleries have
  held both since the Gallery domain landed, but the parser could only ever
  render images. The three display types (`:gallery`, `:slider`, `:slideshow`)
  keep their existing wrapper markup, and image output is unchanged. The
  `images` shape still works for direct callers.

  There was no test covering gallery ref rendering, which is how this survived;
  there are now six.

- **`playsinline` is gone from every place that pretended to configure it.**
  `Brando.HTML.Video` hardcodes the attribute on both `<video>` tags, so none of
  the three settings that claimed to control it could ever affect the output:
  the video drawer's "Plays inline (mobile)" switch (bound to
  `@video_form[:playsinline]`, a field `Brando.Videos.Video` does not even
  have), `Brando.Villain.Blocks.VideoBlock.Data`'s `:playsinline` attribute and
  its hidden inputs, and `:playsinline` in the `{% video %}` tag's allowed args.
  Playback is unchanged — inline playback stays on, as it always was.

- **A block's identifiers could reorder themselves on every re-render.**
  `Brando.Content.Block`'s `:block_identifiers` relation preloaded with
  `preload_order: [asc: :sequence]` and no tiebreaker. `Brando.Trait.Sequenced`
  documents `0` as the default sequence for a new entry, so rows sharing one are
  expected — the trait's own fallback is `desc: :inserted_at`, a column this join
  table does not have. Ties therefore resolved to physical row order, and any
  re-save that rewrote the rows silently reshuffled whatever the block rendered
  from them. Ordering is now `[asc: :sequence, asc: :id]`.

  Seen on a production dataset as case cards changing order inside
  "case entrances" blocks after `mix brando.entries.resave` — no content lost,
  but a different case led the list. Only blocks whose identifiers all share a
  sequence are affected; those written since `957c8a3a1` carry `0, 1, 2, …` and
  were always stable.

- **Block-level presentation settings on picture and video refs were silently
  dropped at render time, and a site's parser overrides were never called.**
  Re-rendering 62 case pages of one production dataset lost lazyloading on 284
  pictures, dominant-color placeholders on 340, `data-moonwalk` on 284, and
  every play button. The markup was structurally intact — same `<picture>`,
  `<video>` and `<article>` counts — so nothing looked broken until you read the
  attributes.

  Four independent defects, which compounded:

  1. **A site's parser overrides became dead code.** Every callback in
     `Brando.Villain.Parser` is `defoverridable`, and while the implementations
     lived inside the `__using__` quote a bare `video_file_options(data)` meant
     "the using module's version". Moving them into the module body changed that
     to "Brando's version", so `render_caption/1`, `video_file_options/1`,
     `header/2` and every block type reached through a container or a ref went
     to the default implementation. No warning, no error. Internal dispatch now
     goes through `Brando.Villain.Parser.parser_module/1`, which prefers the
     parser threaded through `opts` and falls back to the configured one.
  2. **`Brando.Content.OverrideResolver.merge_overrides/2` discarded keys the
     target struct could not hold.** It ends in `Kernel.struct/2`, which drops
     unknown keys without a word, and the picture/video call sites handed it 12
     and 10 keys respectively while `Brando.Images.Image` and
     `Brando.Videos.Video` had fields for only a handful. `picture_class`,
     `img_class`, `link`, `srcset`, `lazyload`, `moonwalk`, `placeholder`,
     `poster`, `opacity`, `play_button`, `cover` and `cover_image` all fell off,
     and the renderer's `Map.get(data, key, default)` used its defaults. Those
     settings are now virtual attributes on the two schemas — nothing is
     persisted, and no migration is needed — and `merge_overrides/2` raises
     rather than dropping a key it cannot hold.
  3. **`loop` and `muted` were missing from the video take-list**, so a block
     with `loop: false` still looped.
  4. **`video_file_options/1` hardcoded `cover: :svg` and never passed
     `progress:`.** The block's own `cover` attribute was unreachable, and
     `data-progress` could not be set by the default parser at all.

  `progress` is also a new setting on the video block, alongside "Play button"
  in the admin — the option existed in `Brando.HTML.Video` with no way to reach
  it. `Brando.HTML.Video` now resolves `cover`, `opacity`, `progress` and
  `play_button` through `setting/4` like every other viewer-configurable
  setting, instead of reading them straight off `opts`.

  Files do not have this problem — that branch builds a plain map, which holds
  anything. Galleries had it worse; see the next entry.

  **Re-render cached blocks after upgrading.** Any entry saved against the
  broken code has degraded HTML persisted in `rendered_blocks` /
  `rendered_html`; the fix only affects rendering, so those rows stay wrong
  until they are re-rendered (`mix brando.entries.resave`).

  **Two rendering changes to expect**, both of them the fix working as
  intended. Video blocks that never set `cover` no longer get an SVG cover — the
  attribute defaults to `"false"` and is now honoured. And blocks with
  `loop: false` stop looping, including entries that have been looping for a
  while.

- **`BrandoWeb.Plugs.MuxWebhook` answered a malformed signature header with a
  500 instead of a 401.** The `Mux-Signature` parser built its map with
  `Enum.into(%{}, fn [k, v] -> {k, v} end)` over `String.split(&1, "=")`, so any
  segment that was not exactly `key=value` raised `FunctionClauseError` — `t,v1`,
  `t=1,v1`, `nonsense` and a `v1` value containing `=` all crashed the plug on
  unauthenticated input, in the one branch whose whole job is to reject it
  cleanly.

  Parsing is total now, and `Integer.parse/1` must consume the whole timestamp:
  the `{timestamp, _}` match it replaces read `"123abc"` as `123`, letting a
  caller vary the signed payload with trailing bytes the tolerance check never
  saw. `verify_signature/4` also takes an injectable `now`, matching
  `CloudflareStreamWebhook`, so the replay window is testable rather than
  wall-clock-dependent.

  This plug had no test at all — the only one of the three video webhook plugs
  without one, and the only one with a hand-rolled header parser. It has eight
  now.

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
  [Asset configuration](guides/blueprint_fields.md#asset-configuration) and [Uploader](docs/UPLOADER.md).

- **Reliable Blueprint form runtime contracts**: Static form query maps now work
  as declared, retain the URL entry ID in `:matches`, and are checked for invalid
  match shapes; callback queries fail with a clear error when they do not return
  a map. Form alerts now execute the advertised function-component and MFA forms
  with documented form context assigns instead of passing callback tuples to the
  translation layer. This is a runtime and DSL correction only: no Ecto migration
  or Igniter upgrade script is required. Compile after upgrading, fix any static
  query whose `:matches` is not a map, and see [Blueprint forms](guides/blueprint_forms.md).

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
  defaults because they now take effect. See [Blueprint listings](guides/blueprint_listings.md).

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
  in [Attributes, relations, and assets](guides/blueprint_fields.md#relations).

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

- Bumped `phoenix` to `1.8.13` and `phoenix_live_view` to `1.2.11`. Both are pinned exactly,
  so when upgrading also pin `phoenix_live_view` to `1.2.11` in your `assets/package.json`
  (and rebuild your backend assets) — LiveView warns when the JS client and server versions
  differ. LiveView `1.2.9` fixes an open redirect in `redirect/2` (CVE-2026-64941), so this
  is a security update, not just a maintenance one.
- Bumped `oban` to `~> 2.23`, locked at `2.24.1`. The schema is upgraded to v14 via
  `brando_153` (see Migrations). Oban `2.24` unified queue, repo and service configuration
  and flattened the module names — `Oban.Plugins.Cron` is now `Oban.Cron`, and services are
  top-level keys rather than a `plugins:` list. Old configuration is rewritten transparently
  and the old modules delegate, so **nothing in your app has to change** — an app-level
  `config :brando, Oban` keeps working in either shape. Brando's own default now declares the
  new one.
- Bumped `req_llm` to `1.21.1`. No API change on the surface Brando uses
  (`ReqLLM.generate_text/3`, `ReqLLM.get_key/1`, `ReqLLM.Keys`, `ReqLLM.Response`) — the range
  is provider fixes and additions.
- Bumped `image` (0.69), `req` (0.7), `sentry` (13.5), `postgrex` (0.22),
  `mox` (1.3), `ecto_nested_changeset` (1.1), and `spark`, `tz`, `earmark`, `floki`, `credo`,
  `ex_doc`, `igniter`.
- **`html_sanitize_ex` to `1.5.5`, a security update.** `1.5.2` carries six advisories,
  two of them HIGH: quadratic backtracking in the CSS scrubber and quadratic sibling
  re-flattening in the traversal engine, both CPU-exhaustion denial of service
  (CVE-2026-68749, CVE-2026-68750). Brando runs the scrubber on user content —
  `strip_tags` in the Villain filters and the `:strip_tags` blueprint value transforms.
  `xml_builder` (its dependency) moves to `2.4.1` for three LOW advisories of its own.
- `postgrex` `0.22.4` fixes SQL injection via the `:comment` option in `Postgrex.stream/4`
  (CVE-2026-66838).
- Bumped `ecto`/`ecto_sql` to `3.14`. The `3.14.2` changeset fixes land close to Brando's
  `put_assoc` paths: stale `belongs_to` keys in `apply_changes/1`, `changed?/3` for removed
  one-to-one relations, and `prepare_changes` callbacks surviving `merge/2`.
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
- Bumped `req` (0.7.5), `req_llm` (1.26), `spark` (2.7.6), `tz` (0.28.4) and their
  transitive dependencies.
- Bumped `mdex` to `~> 0.14.0`. `0.14` moves syntax highlighting to optional
  per-language Lumis packages and turns it off by default. Brando never highlighted
  fenced code (it renders `<pre><code class="language-…">`), so the output is unchanged
  and Lumis is not pulled in.
- **Admin JS security updates.** `@tiptap/*` to `3.31.4` and the pinned ProseMirror
  overrides to `prosemirror-view` `1.42.6`, `prosemirror-model` `1.25.12` and
  `prosemirror-transform` `1.12.2`. The old `1.41.8` pin held `prosemirror-view` below the
  fix for an XSS in paste handling, and tiptap `3.31` requires `prosemirror-view` `^1.42.3`
  anyway. `dompurify` moves to `3.4.16` (a dozen advisories, mostly in `IN_PLACE` mode),
  and CodeMirror and `@floating-ui/dom` take minor updates.
- **Bump `svelte` to `^5.57.2`, `vite` to `^8.3.3` and `@sveltejs/vite-plugin-svelte` to
  `7.3.1` in your `assets/backend/package.json`.** Your backend build compiles the admin's
  Svelte components with your own copies, so Brando's bump does not reach your bundle
  alone. You can also drop `optimizeDeps: { include: ['vex-js', 'vex-dialog'] }` from
  `assets/backend/vite.config.js`: brandojs no longer ships either package.
- Removed unused JS dependencies from brandojs: `vex-js`, `vex-dialog`,
  `vanilla-click-outside`, `lodash.throttle`, `linkifyjs`, `phoenix_html` and
  `@fontsource/jetbrains-mono`. `morphdom` stays: it is the source of the vendored
  `priv/static/js/morphdom-umd.min.js` the live preview inlines.

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
  `mix brando.gen.migrations` and `mix brando.migrate` to bring in the migration.

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

## 0.54.0

Before running the migration script, you must fix some `form` syntax in your blueprints.
If you're passing parameters to the `form` macro, they must be moved to their own functions.
For instance, if you have:

```elixir
form default_params: %{"status" => "draft"} do
  # ...
end
```

You must change this to:

```elixir
form do
  default_params %{"status" => "draft"}
  # ...
end
```

Then pull down migration changes with `mix brando.upgrade`.

Commit all changes before running the migration script with `mix brando.migrate54`

Then run migrations with `mix ecto.migrate`

Finally resave entries with `mix brando.entries.resave`, sync identifiers with `mix brando.identifiers.sync`
then sync translations with `chmod +x scripts/sync_gettext.sh` then `./scripts/sync_gettext.sh priv/gettext/backend/no/LC_MESSAGES`

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
