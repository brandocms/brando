---
name: brando-pages
description: Work on Brando pages, page hierarchy and URLs, fragments, page variables, navigation menus, or linked menu items. Use brando-villain for rendering internals and brando-blocks for editor state.
user-invocable: true
---

# Pages, fragments, and navigation

Paths are repository-relative. Read the concrete schema and context together:
`lib/brando/pages/page.ex`, `lib/brando/pages/pages.ex`,
`lib/brando/pages/fragment.ex`, `lib/brando/navigation/menu.ex`,
`lib/brando/navigation/item.ex`, and `lib/brando/navigation/navigation.ex`.

## Pages and fragments

- A page has URI, language, template, parent/children, vars, fragments, and block
  relations. URI uniqueness is language-aware. The homepage uses the page's
  route helpers; tree position is not a replacement for the stored URI contract.
- `update_breadcrumbs/1` builds ancestor information and updates descendants.
  Exercise parent moves and homepage behavior when changing hierarchy or URLs.
- The permalink trait also updates redirect and identifier behavior. Read
  `lib/brando/traits/permalink.ex` and `lib/brando/sites/redirects.ex` before
  changing URI/slug saves; do not add a second ad hoc redirect path.
- Fragments are addressed using parent key, key, and language, with optional
  page association. `get_fragments`, `fetch_fragment`, and `render_fragment`
  have distinct map, record, and rendered-result contracts; inspect the arity
  being called before rewriting a query.
- Duplication explicitly copies vars, fragments, blocks, refs, and child pages.
  New IDs alone are insufficient when join rows and usage records are shared.

## Navigation

- Menus carry key/language and ordered items. Items have optional parent/children
  and a `Brando.Content.Var` link association, rather than a plain URL field.
  Links may reference identifiers; keep preloads for their current target URL.
- `Menu.form_query/1` and `preloads_for/0` are the form preload contract. Inspect
  them when a picker or child item loses its current selection after validation.
- Navigation mutations update `lib/brando/cache/navigation.ex` and invalidate
  dependent rendered content. A direct Repo update bypasses those callbacks.
- Cache shape is menu key then language. Use `Brando.Navigation.get_menu/2`
  for the context result or `Brando.Cache.Navigation.get/2` for the cached value;
  their return types differ.

## Verification

Use `test/brando/pages/pages_test.exs`,
`test/brando/pages/fragment_query_test.exs`, and affected navigation tests.
Browser coverage lives in `e2e/e2e/playwright/tests/pages/breadcrumbs.spec.js`,
`pages/permalink.spec.js`, and `configuration/navigation-link-identifier.spec.js`
under that tests directory. Check saved/reloaded hierarchy, copied child
independence, language isolation, and identifier-backed links as relevant.

Read [blocks](../brando-blocks/SKILL.md) before modifying block ownership and
[sites](../brando-sites/SKILL.md) for shared configuration invalidation.
