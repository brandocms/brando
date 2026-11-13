- `mix brando.migrate_to_tenant` removes the new site when the copy fails under group authorization or raises, and when the site cannot be removed it says what is left and how to remove it, instead of reporting it removed.

- `mix brando.migrate_to_tenant --move` keeps the new site when a step after the move fails, since its Production schema then holds the only copy of the content, and says which step failed and how to finish it, instead of removing the site.

- Creating a site removes the partly provisioned site when a provisioning step raises (a missing `pg_dump`, say), not only when it returns an error, so the key can be used again.
