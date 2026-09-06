# Groups and authorization

Brando supports an explicit transition from legacy roles to configurable groups.
Authentication still uses the existing Phoenix session tokens. Authorization decides
which resources and actions that authenticated account may use in a specific scope.

For account creation, restricted-editor setup, login/session behavior, deactivation,
and content transfer, see [User accounts and sessions](users.md).

## Enable for an existing application

1. Run `mix brando.upgrade`, review migration 170, and run `mix ecto.migrate`.
   Rebuild the application's backend assets to include the scope-aware channels.
   Security tables live in `public`; they are never copied with site content.
2. Run `mix brando.authorization.migrate --dry-run`. Review the accounts, site
   assignments, and custom legacy rules reported by the command.
3. Run `mix brando.authorization.migrate`. Review seeded groups and permission keys
   before the configuration switch. Map custom/conditional application rules to
   explicit permissions and resource policies. The old rule DSL is not translated
   silently and is not combined with the new resolver.
4. Configure `config :brando, authorization_mode: :groups` and restart the application.
5. Test with representative accounts on every site and environment, including
   direct URLs and denied writes. Review `/admin/groups` for each scope.

The default mode remains `:legacy` until that explicit switch. Old
`MyApp.Authorization.Can.can?/3` calls retain their original tuple return contract
and consult group authority after cutover. Replace broad `:manage` calls with
explicit actions and move administration code to `Brando.Authorization`. Reverting
the configuration reactivates old role rules, which can restore access previously
revoked in groups. Treat this as an authority migration, not a routine rollback.

The import is retry-safe: it preserves edited preset grants and records each
legacy assignment it imports. Re-running does not resurrect memberships removed
through the group editor. New capabilities require an explicit group edit.

## Scopes and defaults

| Mode / scope | Membership source on migration | Defaults |
| --- | --- | --- |
| Standalone | Each account's legacy role | User, Editor, Admin |
| Single site | Legacy roles mapped to the configured site | User, Editor, Admin |
| Multiple sites | Explicit `user_sites` assignments only | User, Editor, Admin per site |
| Installation | Legacy global Superusers | Protected Superuser |

An unassigned global Editor/Admin is not given every site's access. Site groups
apply across that site's environments, while the selected environment controls
which schema is queried. Installation permissions do not inherit from a site's
Admin group. Suspended sites and disabled/deleted accounts are denied, including
for Superusers.

User starts without backend access. Editor receives content/media capabilities,
including publishing, plus read access to reusable definitions. Admin adds site
settings and group administration. Superuser is a protected installation group;
its members have all supported capabilities across active sites. It cannot be
renamed into an ordinary group, deleted, or stripped of its permissions. At least
one active member must remain. Naming a custom group “Superuser” grants nothing.

Membership in several groups combines their grants. There are no group hierarchies,
implicit priority, or explicit-deny rules in v1. Missing and unknown permissions
are denied. Removing one membership leaves access granted by other groups intact.

## Working with the group editor

Open **Configuration → Permissions** to manage access. The editor shows the current
workspace or installation scope explicitly. Select a
group to inspect its permissions, members, and recent activity. Permission tables
align supported actions across resources; unavailable actions are shown separately
from unchecked grants. Search filters the table without dropping hidden selections.
The checkbox beside a resource selects or clears the permissions you can change
in that row. A dash indicates a partial selection; search limits row selection to
visible permissions. On narrow screens, each resource becomes a labeled set of
checkboxes.

Group details and permissions are saved together. Review shows the final name and
description, grants added and removed, and affected member count before committing.
Switching tabs keeps the draft. Leaving the page or choosing another group prompts
before discarding it. A concurrent edit preserves the draft and offers an explicit
reload of the latest version. The protected Superuser group explains its full access
without displaying an editable permission table.

Membership changes apply immediately and preserve any unsaved permission draft.
The person picker excludes current members. View access combines a member's grants
from all groups in the selected scope and identifies the contributing groups.

## Application code

Build the scope from the authenticated account and server-resolved context:

```elixir
alias Brando.Authorization
alias Brando.Authorization.Scope

scope = Scope.site(current_user, current_site, current_environment)

# A presentation snapshot avoids repeated queries in a render.
permissions = Authorization.snapshot(scope)
Authorization.can?(permissions, :update, MyApp.Projects.Project)

# Writes always reload current authority, even when given an old snapshot.
with :ok <- Authorization.authorize(scope, :update, project) do
  MyApp.Projects.update_project(project, params, scope)
end

# Apply resource policies and the environment prefix before counts/pagination.
query = Authorization.scope(scope, :read, MyApp.Projects.Project)
```

`authorize/3` returns `:ok | {:error, :forbidden}`. `can?/3` returns a boolean.
`explain/3` returns the permission key, scope, result/reason, and contributing groups.
Do not expose explanations for arbitrary users or scopes from a public endpoint;
`Groups.effective/2` provides the authorized administration wrapper.

Generated context mutations accept an authenticated user or `Scope` and enforce
permissions when group mode is enabled. Ordinary frontend queries retain their
existing behavior outside a scoped administration request. Custom administration
reads should use `Authorization.scope/3` or `Boundary.with_scope/2`. Query caches
are bypassed for scoped admin reads to prevent public cached results from escaping
resource filters.

`:system` is an explicit trusted maintenance actor. Never derive it from a browser
parameter or use it as a fallback for a missing account. Do not store a resolved
permission snapshot in an Oban job. Retain the initiating account and tenant,
and authorize again when the operation executes.

### Resource metadata and policies

Blueprint permissions use stable keys based on application, schema source, and
operation, for example `brando.pages.update`. Labels and group names are display
text. The catalog is code-owned; database values cannot introduce executable
operations or modules. Declare a stable key before renaming a resource:

```elixir
authorization key: "my_app.projects",
  section: "Content",
  actions: [:approve],
  policy: MyApp.ProjectPolicy
```

A policy implements `authorize(scope, action, subject)` returning `:ok`/`true`
for allowed operations. It must accept schema modules for resource-level checks
and records for target checks. For read policies, implement `scope/3` to add the
same constraints to the Ecto query. A policy without a query scope fails closed
for scoped reads. It must preserve the input query and tenant prefix.

Read and export policies may differ; implement both in `scope/3` when exports
need stricter filtering. Listing exports use this scope and return a download in
the authenticated LiveView response instead of writing public files under `/media`.

```elixir
defmodule MyApp.ProjectPolicy do
  import Ecto.Query, only: [where: 3]

  def authorize(_scope, _action, MyApp.Projects.Project), do: :ok
  def authorize(scope, _action, project), do: project.creator_id == scope.user_id

  def scope(scope, _action, query),
    do: where(query, [project], project.creator_id == ^scope.user_id)
end
```

Custom capabilities require server-side enforcement at their operation boundary;
adding a checkbox to the catalog alone cannot protect a custom operation. Direct
`Repo` and SQL calls remain trusted low-level primitives and must never be exposed
as unguarded administration actions.

Generated listing/form LiveViews declare their resource automatically. Custom
admin views implement `__authorization__/0` returning `{action, resource}`. Unknown
views fail closed in group mode. The router hook runs after tenant resolution and
before the view loads its data, then rechecks current authority on navigation,
events, and authorization broadcasts. LiveComponents must still use guarded
context operations because parent LiveView event hooks do not intercept their
events.

### Managing groups from code

```elixir
alias Brando.Authorization.Groups

{:ok, group} = Groups.create(scope, %{name: "Campaign editors"}, [
  "brando.admin.access", "brando.pages.read", "brando.pages.update"
])
{:ok, :ok} = Groups.add_member(scope, group.id, existing_user.id)
{:ok, saved} = Groups.update(scope, group.id, %{description: "Seasonal campaigns"},
  reviewed_permission_keys, group.lock_version)
```

Writes reload authority inside a transaction. An administrator can delegate only
supported, delegable permissions already held in the same scope. Group updates
require the version that was reviewed; a stale version returns `{:error, :stale}`.
Group/membership changes and their audit events commit atomically. Revocation
broadcasts occur after commit. Account changes and protected-group membership
changes share an administration lock to preserve the last-active-Superuser rule.

Site administrators can select existing accounts already associated with their
site. Installation administrators handle new site assignments. Account credentials
are not included in the site membership directory.

## Uploads and recovery

The upload bridge captures a signed account/site/environment scope at enqueue time.
Intake verifies that scope before transfer or presigning; finalization verifies
it again before writing. A sticky upload manager cannot silently adopt a different
site after navigation. Configuration targets and delivery destinations still pass
through `Brando.Uploads.AssetIntent` and the existing canonical delivery adapters.

If all administrator access is lost, an operator with application-shell/database
access can run `mix brando.authorization.recover admin@example.com`. It restores
protected membership for that existing active account and records an audit event.
It does not create an account, enable a disabled one, or reset a password.

## Live previews and activity

Unsaved live previews are private to the editor who opened them. Their cached
content and channel are bound to that account, resource, site, and environment.
Reads, recovery, and streamed updates check current access and record policies;
revoking access stops subsequent updates and denies the preview URL. A preview
from another form or environment cannot be reused to overwrite its content.

**Share preview** creates a separate, expiring link and requires the resource's
Export permission as well as edit/create access. Shared links remain intentionally
accessible without signing in until they expire. Expiry is checked when reading
the link, even if background cleanup is delayed.

The activity panel shows colleagues with backend access in the selected workspace.
Live URLs are limited to its environment. Global last-seen timestamps are omitted
in site workspaces because they can reveal activity elsewhere. Mutation notices
also check the selected environment and permission to read the affected record.
Field and block collaboration is isolated by resource type, record, and environment;
identical record IDs in different resources or environments do not share edits.

## Testing application permissions

Run the ordinary unit suite with `mix test`. The authorization tests include
real PostgreSQL schemas with identical IDs in multiple sites/environments,
revocation, record policies, delegation, and concurrent Superuser removal.

The repository's browser checks use its isolated E2E consumer:

```sh
cd e2e
source .envrc
pnpm --dir assets/backend build
BRANDO_AUTHORIZATION_MODE=groups ./test_e2e.sh --reset tests/users/groups.spec.js
BRANDO_AUTHORIZATION_MODE=groups BRANDO_TENANCY_MODE=multi ./test_e2e.sh tests/users/authorization-sites.spec.js
BRANDO_AUTHORIZATION_MODE=groups BRANDO_TENANCY_MODE=single ./test_e2e.sh tests/users/authorization-sites.spec.js
```

Keep application-specific resource-policy tests alongside their Blueprints.
Use different permissions in each site and test denied requests directly,
including already connected sessions and queued work after revocation.
