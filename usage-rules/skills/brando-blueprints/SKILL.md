---
name: brando-blueprints
description: Add or change a Brando content type in this site. Use when creating a Blueprint, adding fields, relations, assets, traits, listings or forms, generating its context, admin views and migrations, or fixing a Blueprint that fails to compile.
---

# Brando Blueprints

A Blueprint (`use Brando.Blueprint`) declares one content type: its fields,
traits, identifier, URL, admin listing and form. Brando turns it into an Ecto
schema with a generated `changeset/5`, and generates its storage from it.

## Read first

- `deps/brando/usage-rules.md`: the Blueprints sections.
- `deps/brando/guides/blueprints.md`, then the guide for the part you change:
  `blueprint_fields.md`, `blueprint_traits.md`, `blueprint_listings.md`,
  `blueprint_forms.md`, `blueprint_migrations.md`.
- `deps/brando/guides/querying.md` for the context functions.

## A new content type

```sh
mix brando.gen.blueprint Catalog Product
mix compile --warnings-as-errors
mix brando.gen MyApp.Catalog.Product
mix brando.gen.blueprint_migration MyApp.Catalog.Product
mix ecto.migrate
```

Review the generated Blueprint before generating the resource and storage.
Then add a navigation entry and review the authorization policy.

## Changing a Blueprint

1. Edit the Blueprint. Keep its sections in the order the guides use.
2. `mix compile --warnings-as-errors`: form mistakes are only warnings
   otherwise.
3. If storage changed, `mix brando.gen.blueprint_migration MyApp.Catalog.Product`
   (or `--all`). Read `up/0` and `down/0`, migrate, roll back, migrate again.
4. Commit the Blueprint, migration and snapshot together. Never edit or delete
   a snapshot by hand.

## Rules that bite

- `use Brando.Blueprint` options are literals; module attributes are not
  available yet.
- Labels go through `t/1` so they are extracted into the Blueprint's Gettext
  domain.
- Relations the identifier or `absolute_url` template reads must be declared
  relations.
- Use the current DSL. `listing_query`, `form_query`, `filters`, `actions`,
  `field`/`template` in listings and `inputs_for` with options outside the
  block are deprecated and dropped.
- Run `mix brando.doctor` when something on the site looks out of date.
