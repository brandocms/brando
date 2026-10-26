- In legacy authorization mode an Editor could save HEEx module code, which runs in the server, and change a superuser's email to take the account over through a password reset; an Admin could raise an account to superuser, and an Editor could disable or delete superusers. These now take a superuser.

- In group authorization mode a site's Admin group could save HEEx module code, which runs in the server for every site; module and container writes now take a superuser.
