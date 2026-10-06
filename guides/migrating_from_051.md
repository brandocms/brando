# Migrating from Brando 0.51

This guide is for sites still on Brando 0.51, the `legacy` branch. These sites
have the Vue 2 + GraphQL admin, plain Ecto schemas (`use Brando.Schema`,
`villain :data`, `belongs_to :image_series`) and Waffle or embedded media. It
was written from two production sites that made the jump to 0.55.

Unlike [Migrating from 0.53 or 0.54](migrating_from_053.md), most of this jump
has no task to automate it. `mix brando.migrate54` and `mix brando.migrate55`
rewrite *Blueprint* syntax and configuration, and a 0.51 site has no
Blueprints. Plan it as a port: the application is rewritten by hand on a
branch, and the database is brought forward by Brando's migration chain. The
whole thing is rehearsed on a copy of production until a fresh dump replays
cleanly with `mix ecto.migrate` alone.

Brando migrations up to `brando_55` belong to 0.51, so a 0.51 database starts
the chain at `brando_56`. Problems in the chain that are still open upstream are
tracked in [brandocms/brando#2969](https://github.com/brandocms/brando/issues/2969).
Each one is described below where it bites, with the workaround.

## 1. Before you start

1. Work on a branch, and never point the new code at the production database
   or the production bucket.
2. Keep the old site runnable beside the new one. A git worktree of the old
   branch, with copies of its `deps`, `_build` and `node_modules` and its own
   toolchain (0.51 sites typically need Elixir 1.13 / OTP 25 / Node 16), gives
   you a baseline to compare every page and form against. Give it its own
   database restored from the same dump, and blank its storage credentials
   so it cannot write to a real bucket.
3. **Inventory the old admin before deleting it.** Custom Vue screens, such as
   drag-to-order lists, rankings and review screens, disappear without anything
   failing. Keep the old `assets/backend` (renamed, untracked) for reference
   until each screen has a replacement.
4. **Check your table names against the ones Brando creates.** The chain
   creates `videos`, `files`, `galleries`, `galleries_gallery_objects`,
   `content_*` tables, `forms` and others. A site table with the same name must
   be renamed in a site migration that runs before the Brando migration that
   creates it (see section 4).
5. Get a fresh production dump to rehearse against, and keep the commands that
   restore it in a script, because you will run it many times.

## 2. Dependencies, toolchain and configuration

Start from the [install templates](https://github.com/brandocms/brando/tree/main/priv/templates/brando.install)
for `mix.exs`, `config/*.exs`, the router, endpoint and `application_web.ex`,
and carry the site's own settings over by hand.

**The old `mix.lock` will not resolve forward.** Transitive pins from that era
(`elixir_make`, `hackney` via old HTTP clients, `decimal` via old JSON
libraries) conflict with current Brando. Start from the `mix.lock` of a site
already on 0.55, run `mix deps.get`, and only then `mix deps.unlock --unused`.
Run before the fetch, that command unlocks everything. Brando pins `phoenix`
and `phoenix_live_view` exactly, so `mix deps.unlock phoenix phoenix_live_view`
if resolution fails after updating Brando.

Remove what 0.55 replaces:

- Absinthe, `absinthe_plug` and Dataloader (the GraphQL admin);
- Guardian, its pipelines and its config in `config/brando.exs`;
- Waffle (uploads are Brando media now; see [Media](media.md));
- `scrivener_ecto`, Distillery, `plug_cowboy` (Bandit replaces it), Poison
  encoders and Timex;
- the `compilers: [:phoenix, :gettext]` line in `mix.exs`;
- any 0.51-era dependency nothing calls any more. These are what usually pin
  the old transitive versions.

Add `{:lazy_html, ">= 0.1.0", only: :test}` if you use `Phoenix.LiveViewTest`.
Libraries that need an older `req` than Brando's (Packmatic 2, for example) have
to go; Erlang's `:zip` covers small archives.

Configuration changes at the same time:

- `use Mix.Config` → `import Config`, and a `config/runtime.exs` for everything
  read from the environment. Wrap the endpoint block in
  `if config_env() != :test`, or it overrides `test.exs` and the test
  endpoint gets a `nil` secret key base.
- `config :brando, processor_module: Brando.Images.Processor.Vix` (Sharp is
  gone), `default_size: "medium"` as a string, plus `default_srcset`.
- `config :brando, admin_module: MyAppAdmin`, `repo_module: MyApp.Repo`, and
  `tenancy_mode: :none` unless you are deliberately adopting
  [tenancy](tenancy_and_environments.md).
- Cachex 4 renamed `ttl:` to `expire:`. Calls still passing `ttl:` silently
  lose their expiry.

Current Brando needs a current Elixir and OTP (pin them with mise or asdf), and
the admin's `engines` field rejects some Node versions, so pin Node as well.

## 3. Application source

### Schemas become Blueprints

There is no rewrite task. Generate each Blueprint with `mix brando.gen.blueprint`
or write it from the schema, following [Blueprints](blueprints.md):

- Keep **field and asset names identical to the legacy columns.** Several
  upgrade migrations (`brando_80`, `brando_146`, `brando_198`) call
  `Brando.Blueprint.list_blueprints/0` while they run, and convert what the
  current Blueprints declare. A renamed asset is not converted.
- Move asset options under `cfg:`. A top-level `upload_path:` left over from
  `has_image_series` no longer compiles. Keep the old path values, because files
  on disk are not moved.
- `many_to_many` becomes a join schema plus `has_many … through:`. A
  `multi_select` on the join relation needs `relation_key:`, and removing an
  item fails unless the join Blueprint sets `@allow_mark_as_deleted true`.
- Language fields are `Ecto.Enum`s now (`:no`, not `"no"`). Code that passes
  `entry.language` to `Gettext.with_locale/3` or compares it with a string
  crashes or silently misses. Call `to_string/1` first.
- `trait :creator` adds `updated_by_id` and `edited_at`; the snapshot work in
  section 5 has to account for them.
- Image `alt`, `title` and `credits` are language maps. Read them with
  `Brando.Images.text/3`, not by guarding on `is_binary/1`.

### The web layer

- Router: `use BrandoWeb, :router` (which generates the route helpers) and an
  `admin_routes do … end` block. The admin socket is `BrandoAdmin.AdminSocket`;
  delete the site's own admin socket, channels, session controller, Guardian
  pipeline and GraphQL schema.
- Start the endpoint last in `application.ex`. Started earlier, a restart makes
  open admin tabs drop out of presence until they are reloaded. Run
  `Brando.System.initialize/0` only when `Supervisor.start_link/2` returned
  `{:ok, _}`, or a boot failure is hidden behind "could not lookup Ecto repo".
- The app does not boot without `MyAppWeb.Villain.Filters`
  (`use Brando.Villain.Filters`) and a Presence module on
  `use BrandoAdmin.Presence, otp_app: …, pubsub_server: …, presence: …`.
- `mix brando.gen.authorization` generates the authorization module, and
  `MyAppAdmin.Menus` declares the admin menu ([Navigation](navigation.md)).
- Delete site-local copies of Brando's Mix tasks (`lib/mix/tasks/brando.*`)
  left over from 0.51.
- Fallback controllers written for 0.51 do not consult SEO redirects. Brando's
  own fallback does, so add the check to yours.

### Templates: EEx to HEEx

- HEEx rejects unbalanced tags that EEx passed through. Browsers had repaired
  those pages, often by nesting every following element inside the unclosed
  one, and the CSS was tuned against the repaired tree. To keep the layout,
  reproduce that tree on purpose (dump the old page's DOM from the browser),
  or re-tune the CSS. Screenshots catch this; HTML diffs mostly don't.
- `#{…}` is not interpolation inside `~H`; use `{…}`.
- `<%= cond && " checked" %>` produced `false=""` attributes; `checked={cond}`
  does not.
- phoenix_html 2 input helpers (`text_input`, `error_tag`, …) are gone. A small
  function-component module that renders the same markup keeps the site's CSS
  and JS working.
- Splitting a one-line `<a>` over several HEEx lines adds whitespace inside
  inline links.
- `page.key` is `page.uri` now. Catch-all page routes assign fragments
  themselves (`parent_key: page.uri`).

### Then run `mix brando.migrate55`

Once the application compiles and is committed, `mix brando.migrate55` adds
what it can find to add: the mailer and Swoosh client configuration, listing
component imports, the Gettext sync script, and a `florist.config.exs` from a
legacy `deployment.cfg`/`fabfile.py`. Review its output like any other diff.
`mix brando.migrate54` only rewrites 0.53 Blueprint syntax; skip it if your
Blueprints were written in the current syntax.

## 4. The database migration chain

Copy Brando's migrations with `mix brando.gen.migrations`. If the site already
copied them in an earlier attempt, read the next paragraph first.

**`gen.migrations` copies missing files only; it never updates a copy.** A
template fixed upstream after you copied it stays broken in your tree. Before a
rehearsal, diff every *unapplied* `brando_*` copy against
`priv/templates/brando.upgrade/migrations` in your Brando version, and replace
the ones that changed. Add `priv/repo/migrations/.formatter.exs` with
`import_deps: [:ecto_sql]`, or `mix format` adds parentheses to every copied
file and real drift drowns in formatting drift (diff with `-w`). When a template
is renumbered upstream, the next copy arrives under the new name beside your
old one; reconcile the two by hand.

### Site migrations interleave with the chain

Ecto runs migrations in timestamp order, so a site migration that must run
before or after a Brando migration needs a timestamp between the two. The
workarounds this needs:

- **Before `brando_56`:** drop or rename legacy embedded media columns named
  like an asset you declare now. For example, a Waffle `embeds_one :cv_file`
  (`{"file": "cv.pdf"}`) would be "extracted" by `brando_92` into a bogus
  `files` row if the Blueprint declares `asset :cv_file, :file`.
- **Before `brando_80`:** drop foreign keys that point at `images_series`,
  from `images` and from your own tables (`posts_image_series_id_fkey`, …).
  `brando_80` drops the table and only removes its own category key (#2969).
  `brando_80` preserves the series data before the drop, and `brando_146` turns
  it into galleries.
- **Before `brando_95`:** rename a site table called `videos`. `brando_95`
  creates Brando's `videos` table unconditionally (#2969). Move the site's
  video data into `Brando.Videos.Video` in a later migration. The legacy
  `remote` type becomes `youtube`/`vimeo` by URL. No dimensions come over, so
  non-16:9 embeds are letterboxed until you backfill `width`/`height`;
  hard-code them in the migration rather than calling oEmbed from it.
- **After `brando_108`:** anything that reads the legacy `*_data` villain
  columns or the converted blocks.
- **After the whole chain:** the tables of Blueprints that are new in this
  upgrade. A Blueprint added now has no table while an old database replays,
  and migrations that walk the Blueprints have to skip it.

### Language defaults

`brando_69`, `brando_75` and `brando_76` add `language` to global sets,
identity and SEO with a default of `"en"` (#2969). On a site whose default
language is something else, the site identity, SEO and every global set end
up `en`, so `Brando.Sites.global("no", …)` finds nothing and page titles lose
their prefix. Add a data migration after the chain that copies identity and
SEO to every configured language and moves single-instance global sets to the
default language. See [Identity and SEO](identity_and_seo.md) for how the
records are used per language.

### Gallery order

`brando_146` turns image series into galleries and copies the legacy
`sequence` values as they are, ties included (#2969). Galleries preload with
`order_by: sequence` only, so tied images come back in a different order from
one request to the next. Renumber `galleries_gallery_objects` by
`(sequence, id)` per gallery in a migration after `brando_146`.

### Permissions on the server

`brando_153` (Oban v14) alters the `oban_job_state` type. If the database owner
on the server is not the application role, it fails with `42501
insufficient_privilege`. Locally you connect as a superuser and never see it.
Transfer ownership of the type before deploying the chain.

### Data fixes are migrations

The production database will be dumped again before cutover, so every repair
belongs in the chain, never in an ad-hoc SQL session:

- name the rows it touches by id *and* slug, and stop if production differs;
- make it idempotent, for example guarded on a value the fixed version no
  longer contains;
- make no network calls;
- insert timestamps with `timezone('utc', now())`; raw `now()` is local time.

## 5. Blueprint snapshots

0.51 sites have either no snapshots or legacy ones. Both work, but the first
run of `mix brando.gen.blueprint_migration` needs care. See
[Blueprint migrations](blueprint_migrations.md#upgrading-legacy-snapshots).

- **Legacy snapshots** are read, but they were written against tables that
  were also changed by hand. The first migration may drop an index that was
  never created, or create one a hand-written migration already made. Compare
  `\d table` with every generated operation, switch to
  `drop_if_exists`/`create_if_not_exists` where they disagree, and roll back
  and forward once.
- **No snapshots:** the generator can only propose `create table`. Compare each
  Blueprint with its live table, write one alignment migration, then take a
  baseline with `--rebaseline`. Differences to expect: the `:creator` trait's
  new columns, `creator_id` without a foreign key, `slug` declared unique with
  no unique index, boolean defaults of `true` where the Blueprint says
  `false`, and `varchar` where the Blueprint says `text`.
- A unique index fails to build on duplicate data. Look for duplicate slugs
  before rebaselining; they also make pages unreachable.
- Columns no Blueprint declares (`posts.data`, `*_html`, old villain columns)
  stay behind. Don't drop them early: they are the only record of what the
  conversion started from, and repairs to converted content may need them.

## 6. Rehearse the replay

Repeat until it is boring:

1. Restore the production dump into a scratch database with
   `pg_restore --no-owner --no-acl` (or `psql` for a plain dump), keeping the
   restore errors in a log.
2. `mix ecto.migrate`. On a 0.51 dump the chain logs every row it rewrites,
   so the output looks as if it stopped halfway; check the result with
   `mix ecto.migrations`, not the scrollback.
3. `mix brando.entries.resave` (it prompts; `yes Y |` in a script) and
   `mix brando.identifiers.sync`. Run them only after the site's own Blueprint
   migrations, because resave fails on columns that don't exist yet.
   One entry whose `absolute_url` raises aborts the whole sync (#2969), so fix
   that entry and run it again. The preload `absolute_url` needs is extracted
   from the template's source, so the association must appear literally in it
   (`@entry.artists`).
4. Restart the server. Menus, globals and other caches are read at startup,
   so a page checked against a server that ran during the migration shows
   the old data.
5. Compare migration counts and per-table row counts with the dump.

## 7. Content after conversion

The chain converts villain data into blocks, refs and modules. What to check
afterwards:

- **Missing refs.** Legacy ref names (`H3_1`, `P_2`) may not match what the
  module renders (`refs.h1`). Open the converted entries in the admin and look
  for "Ref X is missing".
- **Paragraph markup.** Text blocks now render inside
  `<div class="paragraph">`. CSS such as `.inner > p` stops matching. To keep
  0.51's markup, override `text/2` in the site's Villain parser
  ([Villain parser](villain_parser.md)).
- **Blocks for fields you have since changed.** `brando_108` converts every
  villain column, including ones the new Blueprint turns into plain text; those
  blocks stay behind, joined to nothing.
- **Globals.** `Brando.Globals.get_global_value!/1` is gone; use
  `Brando.Sites.global/3`. Boolean globals keep their value in `value_boolean`,
  which `Brando.Sites.render_global/3` does not read yet (#2969).
- **Queries.** `status: :published` in the generic query API filters the
  top-level entry, not its preloads. A `has_many … through:` preload ignores the
  preload query's `order_by`, because Ecto returns join-table order.
- **Ordering.** Add an `id` tiebreak to every `ORDER BY` that matters. Ties
  that 0.51 happened to return in a stable order make pages differ between
  requests, and paginated lists repeat items.
- **Meta.** Check that each template still emits `og:image` and the JSON-LD you
  expect ([Meta](meta.md), [JSON-LD](jsonld.md)).

## 8. Admin assets

`mix brando.gen.backend` generates the new admin frontend; move the old one
aside first. It is Vite and Svelte on pnpm, with `@brandocms/brandojs` from
yalc. Copy the template's `vite.config.js`: its `watch.ignored` exception and
yalc auto-update plugin are what make Vite notice a new brandojs. Keep
`@brandocms/jupiter` on the exact version brandojs depends on. Admin icons are
Lucide, so leftover `hero-` names render nothing.

Other sites' Vite servers often hold the default ports. Set
`BRANDO_VITE_FRONTEND_PORT` and `BRANDO_VITE_ADMIN_PORT` for both Phoenix and
Vite.

## 9. The site frontend

- **Brunch/Webpack to Vite:** `static/` becomes `public/`, and assets are
  resolved through `<.head>` (or `<.include_legacy_assets />`) and the Vite
  manifest. Release builds run `mix brando.digest`, not `mix phx.digest`, or
  chunks load twice.
- **Fonts in dev:** CSS `url('/fonts/…')` is served by Phoenix from
  `priv/static`, not by Vite. Until a production build has copied `public/`
  there, the page silently falls back to system fonts.
- **pnpm:** `pnpm import` keeps the resolved versions of the old lockfile; a
  fresh resolve changes the bundle. pnpm 10 needs `onlyBuiltDependencies`.
- **EuropaCSS:** 0.51 sites use europacss 0.6. Its config, bundles and several
  at-rules changed meaning in the current compiler; follow the EuropaCSS
  migration guide, and compare the result against the old build.
- **Jupiter:** modules such as `MobileMenu`, `Toggler` and `Lightbox` assume
  current Brando markup. Do not expect them to replace a site's old jQuery
  one-for-one.
- **Tiptap 3** (if the site has its own rich-text fields) puts the class
  `tiptap` on its editable element, and its StarterKit now includes link and
  underline.

## 10. Tests

A 0.51 test suite may not have been running at all; check that `test_paths`
points at directories that exist. Load the test database from a fresh
`structure.sql` (`mix ecto.dump` from the migrated dev database) instead of
replaying the whole chain on an empty database.

Configuring Oban for tests replaces Brando's default Oban configuration, repo
included, so give the whole list:

```elixir
config :brando, Oban,
  repo: MyApp.Repo,
  testing: :manual,
  queues: false,
  plugins: false
```

## 11. Deploy

The 0.51 Docker setup (`mix distillery.release`, Node 10/14 stages) no longer
builds. Replace it with Florist rather than fixing it, and review the generated
configuration as described in
[Migrating from 0.53 or 0.54](migrating_from_053.md#review-a-generated-florist-configuration).

The cutover, in order:

1. Make the `oban_job_state` ownership change from section 4.
2. Deploy and run `mix ecto.migrate`.
3. Run `mix brando.entries.resave` and `mix brando.identifiers.sync`.
4. Generate the sitemap once (`Brando.Sitemap.generate_sitemap()`).
5. Restart.

## 12. Verifying parity

The old site is the specification. What caught regressions on the sites this
guide comes from:

- HTML snapshots of the same URLs on both, normalised for host names, asset
  digests and CSRF/LiveView tokens.
- Screenshots at several widths, with images disabled (lazy loading makes
  them nondeterministic). Blur slightly and compare by maximum channel delta,
  because sub-pixel rounding differences otherwise flag every page.
- Element geometry and computed styles compared between the two sites, which
  finds the cause of a screenshot difference quickly.
- A scripted browser run through every form and interactive widget. Assert
  something only the handler causes, or a check can pass without testing
  anything.

Classify every difference as parity or fix, and check suspected regressions
against production: some will be bugs the old site already had.
