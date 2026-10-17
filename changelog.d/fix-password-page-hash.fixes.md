- **The superuser created by `mix brando.setup` or `mix brando.gen.admin` is
  not asked to change its password on first login** (#3228). Whoever ran the task
  chose that password. Users created in the admin still have to replace the
  password they were given.
