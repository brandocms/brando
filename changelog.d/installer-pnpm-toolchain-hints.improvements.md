- `mix brando.assets.setup` names the pnpm it found when that pnpm is too old, and lists any other pnpm executables later on PATH, so a standalone pnpm that runs ahead of the one asdf or mise pins is easy to spot.

- The new-install notice for `.tool-versions` gives `mise install nodejs pnpm` (or `mise install erlang elixir nodejs pnpm` when it writes no file), so tools in a global mise configuration no longer stop it, and says how to update an asdf pnpm plugin too old for pnpm 12.
