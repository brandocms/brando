---
name: brando-auth
description: Work on Brando user sessions, login eligibility, scoped user groups, grants, resource policies, authorization boundaries, revocation, or protected admin operations.
user-invocable: true
---

# Users and authorization

Paths are repository-relative. Read `guides/authorization.md` before changing
permissions. Brando supports legacy role rules and an opt-in scoped group engine;
do not assume every installation uses the same mode.

## Authentication and scope

- `lib/brando/users/users.ex` owns user mutations, session-token lookup, login
  eligibility, last-login/last-seen, and content-transfer deletion.
  `lib/brando_admin/controllers/user_auth.ex` connects sessions to Plug and
  LiveView mount behavior. `lib/brando/users/user.ex` defines fields and forms.
- `lib/brando/authorization/scope.ex` constructs standalone, installation, or
  site/environment scopes from authenticated server context. Browser-supplied
  IDs/prefixes do not constitute an authorization scope.
- `lib/brando/authorization/engine.ex` evaluates group snapshots and policies.
  `catalog.ex` resolves known resources; `operations.ex` defines operation
  contracts. Avoid creating atoms/modules directly from untrusted action data.

## Enforced boundaries

- `lib/brando/authorization/boundary.ex` wraps generated context mutations and
  scoped admin reads. Public frontend reads outside an admin scope retain their
  behavior. Test the distinction rather than applying an admin filter globally.
- UI helpers in `lib/brando_admin/authorization.ex` are presentation. Enforce
  permission at mutation, query, upload, preview, and recovery boundaries too.
- `:system` intentionally bypasses user authorization for trusted maintenance;
  replacing a denied actor with `:system` is not a permission fix.
- `groups.ex` owns group/membership mutations and concurrency protection.
  Preserve the final-administrator/account protection and transaction boundaries.
- `realtime.ex` handles live permission changes. Previously mounted forms and
  sockets need to respect revocation; a cached UI snapshot cannot authorize a
  later write by itself.
- `preview.ex` and `media.ex` govern preview ownership and media operations.
  Recheck delayed upload finalization and recovered draft/preview writes, not
  only the original picker or preview-open event.
- User-content transfer excludes authorization and site-membership records;
  transferring authored content must not transfer privileges to another user.

## Verification

Select cases from `test/brando/authorization/`, including `concurrency_test.exs`,
`operations_test.exs`, and `realtime_test.exs`. Browser tests live in
`e2e/e2e/playwright/tests/users/groups.spec.js` and `authorization-sites.spec.js`
under the same directory. Test allowed and denied direct operations, legacy mode,
and site/environment isolation when relevant; UI visibility alone is insufficient.
