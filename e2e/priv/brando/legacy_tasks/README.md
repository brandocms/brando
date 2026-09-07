The previous consumer-owned `brando.upgrade` task is preserved here outside
Elixir's compilation paths. It otherwise shadows Brando's native version-upgrade
hook and causes a module redefinition warning when compiling this consumer.

Use the library-owned `mix brando.gen.migrations` to plan missing framework
migration files, followed by the explicit database migration command. The reviewed
`mix brando.upgrade.prepare` compatibility path performs this archive step for
existing applications; see `guides/generators.md` in the Brando repository.
