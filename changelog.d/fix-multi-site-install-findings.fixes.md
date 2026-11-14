- `mix brando.setup` finishes on a `:single` or `:multi` installation: its seeds create only the shared modules in `public`, and a failed seed run leaves nothing behind.

- Blocks the setup seeds create carry their module's version, so `mix brando.doctor` no longer reports them on an outdated module version.

- `mix brando.doctor` counts an incomplete identity's languages apart from its environments, and keeps a long check label apart from its summary.
