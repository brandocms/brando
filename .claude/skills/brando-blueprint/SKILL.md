---
name: brando-blueprint
description: Work on Brando Blueprint schemas, Spark DSLs, traits, generated changesets, forms/listings metadata, queries, or schema migrations. Use for compiler contracts and content-type definitions.
user-invocable: true
---

# Blueprint contracts

Paths below are relative to the repository root. Start with `guides/blueprints.md`
and the actual application Blueprint; use `guides/blueprint_migrations.md` for
persisted schema changes.

## Ownership and flow

- `lib/brando/blueprint.ex` is the public facade. `lib/brando/blueprint/dsl.ex`
  composes Spark extensions and generates schema metadata, Ecto fields, trait
  implementations, forms, and the changeset entry point.
- DSL entities live in `lib/brando/blueprint/attributes/`, `relations/`, `assets/`,
  `forms/`, and `listings/` beneath that Blueprint directory. Read the entity
  struct, DSL schema, transformer, and verifier together when adding an option.
- `lib/brando/blueprint/changeset_runner.ex` executes runtime casting, relation
  and asset changes, traits before required validation, constraints, traits after
  validation, and sequencing. Keep runtime dependencies out of generated code.
- `lib/brando/query/` generates context queries and mutations. Public contexts
  still use `Brando.Query`; read `guides/querying.md` before changing their
  option or return-value contracts.

## Decisions that matter

- A schema option is incomplete until generated metadata, validation, runtime
  consumers, and migration snapshots agree on its meaning. Follow existing
  verifier error conventions with module and DSL path context.
- Trait names have both module and symbolic forms. Read the trait's compiler and
  runtime implementation in `lib/brando/traits/` before changing injected fields
  or callback ordering.
- `:draft` bypasses required-field validation in ChangesetRunner. A validation
  test using a draft may miss the intended error; exercise a published entry too.
- Custom form queries supply their own preloads. See
  `lib/brando/blueprint/entry_query.ex` and the Form component's `add_preloads`.
- Form and listing components can be resolved from symbolic tokens at compile
  time. Preserve this boundary instead of resolving modules on every render.
- Migration snapshots are a storage contract. Do not regenerate or rebaseline
  unrelated history to make a verifier test pass.

## Focused verification

Use `test/brando/blueprints/verifier_test.exs`,
`test/brando/blueprints/secondary_verifier_test.exs`, and
`test/brando/blueprint/forms/component_resolution_test.exs` as fixture patterns.
Some Spark verifier tests compile a module and explicitly call `verify/1` to
inspect the reported error. For changeset/query behavior, test the persisted
result, not only the generated declaration.

Read [admin forms](../brando-admin-forms/SKILL.md) for interactive form behavior
and [blocks](../brando-blocks/SKILL.md) before changing block state.
