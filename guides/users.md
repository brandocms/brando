# User accounts and sessions

Authentication establishes who signed in; [authorization](authorization.md)
determines what that account can do. A successful password check is not proof of
permission to edit pages, manage users, or enter a site.

This guide assumes public migrations are current and an administrator already has
user-management access. In tenancy modes, users and session tokens remain global
records in `public`; site content and group scope are separate.

## Create an editor account

Open **Users → Create new**, enter the name, email, interface language, and a
password, then save. The next sign-in redirects to `/admin/users/password`,
where the editor replaces it with their own; turn off
`reset_password_on_first_login` in the user's configuration to skip it. If you
would rather not hand over a password at all, save the user and send them a
reset link from their form (see [Reset a forgotten password](#reset-a-forgotten-password)).

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

Signing out is a `DELETE /admin/logout` with the CSRF token: the account
menu's **Log out** sends one. `GET /admin/logout` only asks "Sign out?", so a
link or an image on another site cannot sign anybody out, while links to it
keep working. Signing out deletes that session token, disconnects the
session's sockets, clears session data, and removes the remember-me cookie. It
does not mean “revoke every other browser belonging to this account”;
changing the password does (see below).

A session's sockets are its LiveViews and its admin socket
(`BrandoAdmin.AdminSocket`: presence, notifications and live preview). They
share one id per session, `Brando.Users.live_socket_id/1`, made from a
hash of the session token, and `Brando.Users.disconnect_session/1` closes
them, once the transaction that ended the session has committed. Whatever ends a session —
signing out, revoking it on the Security page, logging out everywhere, a
password change or reset, a two-factor reset, deactivating or deleting the
account — disconnects them, and the user's other sessions keep theirs. The
admin socket's token, in the page's `user_token` meta tag, names the session
by its row id (`Brando.Users.build_socket_token/2`); it lasts a day, and only
while the session does, so a disconnected socket cannot reconnect with it.

## Reset a forgotten password

Password reset email goes through the application's mailer, so set one up
first; see the [Email guide](email.md). Without a mailer, asking for a link
raises `Brando.Exception.ConfigError` in development and test. In production
it logs a warning, and the page says the site cannot send email.

**Forgot password.** The login page links to `/admin/reset-password`. The
user enters their email address and always gets the same answer, so the page
cannot be used to find out which addresses have accounts. The account is
looked up in a background job (`Brando.Worker.PasswordReset`), which emails
an active, undeleted account a link to `/admin/reset-password/:token`, and
sends nothing otherwise:

```elixir
:ok = Brando.Users.request_password_reset(email)
```

The link works once, for an hour (a day when an administrator sent it, see
below), and only the newest link for an account works, whoever sent it. Only a SHA-256 hash of its token is stored in `users_tokens`; a link
also stops working when the account is deactivated or its email changes.
Choosing a new password, with `Brando.Users.reset_user_password/2`, deletes
every token of the account — its sessions and remember-me cookies, and the
link itself — and disconnects its open admin views. The user then logs in
with the new password.

**From the user's form.** A superuser opens another user's form and chooses
**Send reset link**: the user is emailed a link, as above, saying an
administrator sent it. That link works for 24 hours, since the user did not
ask for it and may not be waiting for it. Their current password keeps
working until they use it. The call is:

```elixir
{:ok, user} = Brando.Users.send_password_reset(user.id, current_admin)
```

It returns `{:error, :forbidden}` unless `current_admin` is a superuser or the
user themselves, and `{:error, :inactive}` for a deactivated account.

A saved user's form has no password field. When the site cannot send email,
the superuser chooses **Set a password instead** under the reset button and
types a password twice in the dialog that opens. The user is logged out
everywhere, emailed that an administrator set their password if a mailer is
configured, and must choose their own password the next time they log in
(`reset_password_on_first_login` is switched on). Hand the password over
another way. The call is
`Brando.Users.set_user_password(user.id, attrs, current_admin)`; a superuser
cannot use it on their own account.

**Change your own password.** Your own form links to `/admin/users/password`,
which asks for the current password and the new one twice. Saving logs out
your other sessions and keeps the one you are using
(`Brando.Users.update_user_password/4`). The first-login password change is
the same page.

Whichever way a password changes, the user is emailed to say so, with a link
to reset it if they did not. Without a mailer the password still changes,
without the email.

## Two-factor authentication

A user turns it on from **Security** in the account menu
(`/admin/users/security`): they scan a QR code with an authenticator app, or
type its key, and confirm with a code the app shows. Turning it on logs out
their other sessions and shows ten one-time recovery codes, once. From then on
the password is the first of two steps: Brando does not create a session until
the user gives a code from the app, or a recovery code, at
`/admin/login/two-factor`. Until then the browser only holds a short-lived
token for that screen (ten minutes), and the remember-me cookie, which holds a
session token, is only written after the second step.

A code is six digits for a 30-second step; the step before and after are
accepted for clocks that drift. Each code works once: the last accepted step is
stored, and a code for it or an earlier step is refused. Each recovery code
works once. Turning it off, or making new recovery codes, asks for the password
or a current code from the app, and so does turning it on: a session alone
cannot add a factor. The user is emailed whenever two-factor authentication is
turned on, off or reset. The calls are in `Brando.Users.TwoFactor`.

**When a user loses their phone and their codes.** A superuser opens their
form and chooses **Reset two-factor**. It turns two-factor authentication off
(the app, every passkey and the recovery codes), ends a lockout, and logs the
user out everywhere; they log in with their
password and set it up again. The reset is recorded with who did it:

```elixir
{:ok, user} = Brando.Users.TwoFactor.reset(user.id, current_admin)
```

**Requiring it.** A superuser chooses who must use it under **Users →
Sign-in policy** (`/admin/users/sign-in-policy`): nobody, everyone, or the
users of some roles (with group authorization, some groups). Users are shared
by every site, so the policy is the installation's (`Brando.Users.SecurityPolicy`).
A user it applies to who has not set it up is logged out when the policy is
saved, emailed, and sets it up at their next login, before they get a session. A
superuser must use two-factor authentication before saving a policy that
applies to them.

**Secrets at rest.** The TOTP secret is encrypted with `Brando.Crypto`
(XChaCha20-Poly1305), with a key derived from the endpoint's
`secret_key_base`; recovery codes are stored as keyed hashes. Rotating
`secret_key_base` makes them unreadable, and users would set two-factor
authentication up again. To rotate it freely, give Brando its own secret:

```elixir
config :brando, Brando.Crypto, secret: System.fetch_env!("BRANDO_ENCRYPTION_SECRET")
```

## Passkeys

A passkey is a second factor in place of the app's code, and satisfies a
sign-in policy that requires two-factor authentication. Users add one or more
under **Security → Passkeys**, with a name for each device and their password
or a current code from their app — a passkey logs in on its own and outlasts a
password reset, so a session alone cannot add one — and remove them there. The
user is emailed when a passkey is added or removed. The first second factor a user adds — a passkey or the app — makes
their recovery codes and logs out their other sessions. Once a user has a
passkey, **Log in with a passkey** on the login page signs them in without the
password: the device asks for its PIN, fingerprint or face (user verification
is required for that), so the passkey is two factors on its own. After a
password, a passkey is also the second step. The app and recovery codes stay
as the fallback; the last second factor of a user the policy applies to cannot
be removed.

Passkeys are checked with [`wax_`](https://hex.pm/packages/wax_). The relying
party is the admin's own address — the endpoint's URL as the origin and its
host as the RP ID — unless the application sets them:

```elixir
config :brando, Brando.Users.Passkeys, origin: "https://admin.example.com", rp_id: "example.com"
```

A passkey only works for the RP ID it was made for, so keep it stable. Every
challenge is random, valid for five minutes, and answers once
(`Brando.Users.Passkeys`).

## Confirming it is you again

Some actions ask for the password, a code from the app or a passkey again when
the session last gave one more than ten minutes ago, even inside a valid
session (`BrandoAdmin.Reauth`): setting up the app, adding or removing a
passkey, logging out a session, the user form (creating users, changing email
or role, resetting another user's password or two-factor authentication,
logging them out), disabling, enabling and deleting users, the sign-in policy,
changing groups and their members, deleting, suspending or archiving a site
and changing who has access to it, a static site's deploy target and webhook,
building (which may deploy at once), deploying and rolling back, copying into
an environment, deleting an environment or its archives, and setting an
environment live. A copy into the live environment must also be ticked
explicitly, since it replaces what visitors see. Changing your own password, turning the app off
and adding a passkey ask for the current password or a code every time.

A screen opts in with one line, and so do some events of a LiveView:

```elixir
on_mount {BrandoAdmin.Reauth, :screen}
on_mount {BrandoAdmin.Reauth, events: ~w(delete_environment queue_set_live)}
```

A screen guarded as a whole asks before it opens, holds any event of the
LiveView once the confirmation has run out, and leaves for the confirm page
when it runs out while the screen is open (a LiveComponent's events, such as
the user form's Save, do not pass through the LiveView, so the screen is not
left open past the window). A controller route uses `plug :require_recent_auth`. The window is
configurable (`config :brando, BrandoAdmin.Reauth, window_minutes: 10`). When
the session last confirmed is kept with the session in `users_tokens`; logging
in counts as confirming.

## Sessions

**Security → Sessions** lists where the user is logged in — the browser, the
address, when it logged in and when it was last active — and logs out any of
them, or all but the current one. On another user's form, a superuser chooses
**Log out everywhere** (`Brando.Users.log_out_everywhere/3`); it is recorded in
the security log with who did it.

## Sign-in limits and lockout

`Brando.Users.Throttle` limits sign-in attempts, two-factor codes and
password reset requests per IP address and per account, in 15-minute windows.
Five failures within 15 minutes of the first — a wrong password, a wrong
code, or a wrong password or code when confirming a change — lock the account
for 15 minutes, on every node; the second lockout in a day lasts an hour, and
any after that four hours, counted over a rolling day for an account and for
an address without one alike. The user is emailed when their account is locked. While it is locked even the right password does not sign in, and an
address without an account gets the same answer after as many tries, so the
lockout tells nothing about which accounts exist. A successful sign-in starts
the count again. The limits are configurable:

```elixir
config :brando, Brando.Users.Throttle,
  login_per_ip: 30, login_per_account: 10, two_factor_per_ip: 30,
  reset_per_ip: 10, reset_per_account: 3, lockout_after: 5, lockout_minutes: 15,
  lockout_escalation_minutes: [60, 240]
```

### Behind a proxy

The per-IP limits and the security log need the visitor's address. Behind a
reverse proxy every request arrives from the proxy, so Brando believes the
proxy's `X-Forwarded-For` header — but only when the request comes from a
trusted proxy, since anyone can send the header (`Brando.ClientIP`). The
client is the right-most address in the header that is not a trusted proxy.

```elixir
config :brando, :trusted_proxies, ["127.0.0.1/32", "::1/128", "10.0.0.0/8"]
```

The trusted proxy must set or overwrite `X-Forwarded-For` itself, appending
the address it got the request from. Traefik does by default; with nginx use

```nginx
proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
```

A proxy that passes the client's own header through unchanged lets every
client choose its address for the per-IP limits.

Entries are addresses or CIDR ranges, IPv4 or IPv6. The default trusts the
loopback addresses only, which is what a proxy on the same server connects
from: Florist puts Traefik or nginx in front of each release on the server,
so a Florist deploy needs no setting. A load balancer on another machine
needs its addresses added; `[]` never believes the header. Without the right
setting every visitor shares the proxy's limits, and a burst of bad logins
from anyone locks everyone out.

LiveView screens (the reset request, the security page) read the address from
the socket, so its `connect_info` must give the peer and the forwarded
headers; `mix brando.install` writes this:

```elixir
socket "/live", Phoenix.LiveView.Socket,
  websocket: [connect_info: [:peer_data, :x_headers, :user_agent, session: @session_options]]
```

Two-factor codes and confirmation fields are kept out of the request logs
with `config :phoenix, :filter_parameters, ["password", "code", "proof", "secret"]`.

## Security log

Sign-ins, failed sign-ins, lockouts, password changes and changes to
two-factor settings are written to `public.users_security_events`
(`Brando.Users.SecurityLog`), with the IP address and browser. Users are
shared by every site, so this log is separate from the content activity log.
The user's Security page shows their latest events; it is kept as long as the
activity log (`retention_days`).

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
it is not an all-device API. A password reset deletes them all. Test both an
already open tab and a fresh request.

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
foreign-key references to `users` and moves every one to the recipient — content
ownership and edit history (`updated_by_id`) alike,
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
