- `mix brando.migrate_to_tenant` removes the new site when the copy fails under group authorization or raises, and when the site cannot be removed it says what is left and how to remove it, instead of reporting it removed.

- `mix brando.migrate_to_tenant --move` keeps the new site when a step after the move fails, since its Production schema then holds the only copy of the content, and says which step failed and how to finish it, instead of removing the site.
