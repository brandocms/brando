# User accounts and sessions

Authentication establishes who signed in; [authorization](authorization.md)
determines what that account can do. A successful password check is not proof of
permission to edit pages, manage users, or enter a site.

This guide assumes public migrations are current and an administrator already has
user-management access. In tenancy modes, users and session tokens remain global
records in `public`; site content and group scope are separate.

## Create an editor account

Open **Users → Create new**, enter the name, email, interface language, and a
password, then save. If first-login password change is enabled in the user's
configuration, the next sign-in redirects to that password form. The current
`reset_user_password/2` function is not an implemented email-reset workflow;
do not advertise a reset email without an application implementation.

The equivalent context call uses plaintext input and lets the password trait
hash it:

```elixir
{:ok, editor} = Brando.Users.create_user(%{
  name: "Alex Editor",
  email: "alex@example.com",
  password: initial_password,
  password_confirmation: initial_password,
  language: "en",
  role: :editor,
  active: true
}, current_admin)
```

Supply `initial_password` through your secure account-creation flow. The schema
requires a name, unique email, role, and password, with a six-character minimum
password constraint and confirmation validation. Custom policy may be stricter.
Do not pre-hash a value before submitting it to this changeset or log the params.
Handle `{:error, changeset}` for invalid input and `{:error, :forbidden}` for a
denied operation.

In legacy mode, the role participates in the application's legacy rules.
In group mode, role assignment is not a substitute for membership. Add the
account to the intended group/site through the Permissions screen. Do not assume
a global Editor role grants every site.

## Give access to one editorial task

With group authorization enabled, create a **Page reviewers** group in the
intended scope containing:

```text
brando.admin.access
brando.pages.read
brando.pages.update
```

Add Alex and remove any broader membership that would independently grant
publication. Group permissions combine, so an Editor/Admin membership can undo
the intended restriction. The administration API is:

```elixir
alias Brando.Authorization.Groups

{:ok, group} = Groups.create(admin_scope, %{name: "Page reviewers"}, [
  "brando.admin.access", "brando.pages.read", "brando.pages.update"
])
{:ok, :ok} = Groups.add_member(admin_scope, group.id, editor.id)
```

`admin_scope` is a server-built standalone/site scope held by an administrator
allowed to delegate those grants. This group permits page review/editing but does
not grant creation, deletion, publishing, scheduling, or media management. Add
only the capabilities the workflow needs. For “only their own pages,” add the
resource policy and query scope shown in [Authorization](authorization.md#resource-metadata-and-policies).

Sign in as Alex in a separate browser session. Check a direct page URL, a permitted
edit, an attempted status change to published, and a denied configuration route.
Verify the server denies writes as well as hiding controls. Repeat after removing
the group membership while the editor remains open.

## Understand sign-in and session lifetime

The login controller queries an **active, non-deleted** account by email and
verifies its password. The separate `Brando.Users.can_login?/1` helper only checks
a legacy role value; it does not check activity, deletion, or group/site access.
It is not a complete authentication guard.

A successful login creates a random session token in `public.users_tokens`,
renews/clears the browser session, and records `last_login`. The optional signed
remember-me cookie and session-token validity are **60 days**. Token lookup also
requires that the account remains active and non-deleted. `last_seen` records
when the last tracked admin presence session goes away, so it answers a different
question from the last password sign-in.

Normal logout deletes that session token, broadcasts a disconnect for its
LiveView session, clears session data, and removes the remember-me cookie. It
does not mean “revoke every other browser belonging to this account.”

## Deactivate without transferring ownership

Choose **Disable user**, or call:

```elixir
{:ok, disabled} = Brando.Users.set_active(editor.id, false, current_admin)
```

Content retains its creator references. New login attempts and later token
lookups fail for the inactive account. Group mode broadcasts account authority
changes and rechecks open admin views; do not assume the same immediate socket
revocation behavior in a custom or legacy view that never rechecks authority.

Deactivation does not delete stored session tokens. If the account is re-enabled
before a token expires, that token can become valid again. For permanent session
revocation, delete the applicable session tokens as part of a controlled account
operation. `Brando.Users.delete_session_token(token)` revokes one known token;
it is not an all-device API. Test both an already open tab and a fresh request.

Group mode protects the last active Superuser from removal/deactivation. If an
operation is denied, retain the account and establish another authorized active
administrator first; do not work around the guard with a raw database update.

## Delete and transfer content

For a departing editor in a classic installation, open the user's **Delete**
action. Review the table/count summary, choose an active replacement account,
and confirm **Transfer & Delete**. Cancelling leaves ownership unchanged. The
underlying operation is:

```elixir
{:ok, deleted_user} = Brando.Users.delete_user_with_transfer(
  editor.id, replacement.id, current_admin
)
```

Use a real, different, active recipient selected by your application; the raw
context call should not be treated as a recipient-validation UI. Brando discovers
foreign-key references to `users`, moves content ownership to the recipient,
deletes the departing account's session-token rows, and soft-deletes the account.
It deliberately does **not** transfer authorization memberships or `user_sites`
access: the recipient keeps their own permissions.

The current transfer helper discovers table/column names and issues unqualified
SQL. It is **not a complete cross-environment migration tool** for a multi-site
installation. Audit actual references in every tenant schema before deleting a
global account there; use a schema-aware maintenance workflow for tenant content
rather than assuming the classic summary proves every reference was moved.
Also verify application foreign keys and constraints before transfer: an error
must be surfaced, not reported as a successful deletion.

After transfer, reopen representative content, verify the new creator, and check
that the old session no longer resolves. Restoring a soft-deleted account does
not transfer content back or recover its deleted session tokens. Account row
retention follows [soft deletion](content_lifecycle.md#retention-and-media).
