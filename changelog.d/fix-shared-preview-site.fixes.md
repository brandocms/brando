- In multi-site mode a shared preview's link opens on the admin's host, also for a site with no domain yet, and a site's host no longer opens another site's previews; suspended and archived sites' previews do not open.
  Run `mix brando.gen.migrations` for `brando_227`, then `mix ecto.migrate`.
