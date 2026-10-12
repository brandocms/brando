- **Generated Blueprint migrations end with a newline**, so
  `mix format --check-formatted` passes on them as written; it used to fail on
  every file `mix brando.gen.blueprint_migration` wrote. The five copied
  upgrade migrations (`brando_128`, `brando_130`, `brando_131`, `brando_132`,
  `brando_138`) that lacked one have it too. When a Blueprint's history has a
  snapshot without a migration, so that, say, snapshot `004` goes with
  migration `003`, the plan now says so and lists the history's snapshots and
  migrations: the numbers count separately, and no migration is missing.
