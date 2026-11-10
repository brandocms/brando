- `mix brando.install` starts new sites' releases in interactive mode, which loads each module when first used: an idle site uses about a quarter of the memory it did. Existing sites can opt in.
  Add `export RELEASE_MODE=${RELEASE_MODE:-interactive}` to `rel/env.sh.eex`, after the line that sources `.envrc.runtime`.
