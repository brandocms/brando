- Only superusers create, change, duplicate, import or delete block modules and containers, or customize and reset shared ones in a site, in both authorization modes, since their templates run as code in the server. Groups can no longer be granted these permissions: the Admin preset and existing groups lose them, and other users can still read and export modules.
  Give the people who maintain module templates a superuser account, or move the work to development.

- Only a superuser changes another user's email, in both authorization modes, as for their password. In legacy mode an Admin can no longer correct an Editor's email.
  Ask a superuser to change it, or let the user change it on their own form.

- In legacy authorization mode, Brando now enforces the roles' meaning itself: a User-role account changes nothing but its own profile, an Admin gives roles up to Admin, and only a superuser deactivates or deletes another superuser.
