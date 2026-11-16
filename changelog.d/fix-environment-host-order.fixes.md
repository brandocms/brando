- Creating an environment with a domain no longer serves its host before the environment is ready: the domain and redirect hosts are bound once its schema is migrated (for a new site, once it is provisioned), a host that is taken is refused before any schema work, and a failed create leaves none bound.

- Deleting an environment no longer answers a request on its host with a 500 while the schema is dropped: its hosts stop resolving, on every node, before the schema goes, also when they were released just before the delete.

- Creating an environment from the admin no longer logs each tenant migration instruction at info level.
