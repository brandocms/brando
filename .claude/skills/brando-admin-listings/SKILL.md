---
name: brando-admin-listings
description: Work on Brando admin list queries, URL filters/sorts, pagination, custom row components, selection, exports, or bulk actions. Use brando-blueprint for listing DSL changes and brando-auth for permission changes.
user-invocable: true
---

# Admin listings

Paths are repository-relative. Read `lib/brando_admin/live_view/listing.ex`,
its `compiler.ex` and `hooks.ex` under `lib/brando_admin/live_view/listing/`, and
`lib/brando_admin/components/content/list.ex`. The facade installs behavior;
the List component owns interactive list options and selection.

## Query and interaction flow

- `assign_defaults`, `build_list_opts`, and `assign_entries` resolve Blueprint
  listing configuration, language, filters, status, ordering, preloads, and
  query execution. Read them before adding another source of query state.
- `push_query_params` serializes controls into URL params. Filter/sort/page
  events patch those params; preserve deep links and back/forward behavior.
- Text, boolean, and select filters have different empty/default handling.
  Test clearing a filter as well as applying it. A string `"false"` is truthy
  in Elixir and must not be treated as boolean false by accident.
- Row components receive `@entry`. The reusable layout components live in
  `lib/brando/blueprint/listings/components/core.ex`; preserve links and column
  layout when changing summaries. Query preloads must match fields used by rows.
- Selection supports toggles and ranges over the current entries. Review
  `select_row`, `range_ids_between`, and `clear_selection` for stale selection
  after filtering, paging, or a mutation.
- Exports and selection actions use their configured action names. Validate the
  operation server-side; hiding a menu item is only presentation.
- Listing hooks process mutations and subscribe to updates. Shared topics and
  cache refreshes can affect other lists; use the existing tenant/topic helpers.

## Verification

Use `test/brando_admin/view/project_list_live_test.exs` for a real routed list.
Browser tests in `e2e/e2e/playwright/tests/projects/listing-filters.spec.js`
exercise filter controls; add persistence/deep-link checks when changing URL
state. Use a restricted account for operations whose authorization changes.
Follow AGENTS.md's consumer asset build and targeted E2E commands.

Read [Blueprint](../brando-blueprint/SKILL.md) for DSL contracts and
[authorization](../brando-auth/SKILL.md) for enforced operation boundaries.
