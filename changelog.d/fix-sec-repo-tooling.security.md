- In a clone of the Brando repository, checking out, merging or rebasing a branch no longer runs that branch's Git hook or Gettext merge script: Git runs copies kept outside the working tree.
  Brando maintainers: run `scripts/install-git-helpers` once per existing clone, from a checkout of `main` you trust. Clones that have not run it keep working as before, without this protection, and `mix check` says so.

- The E2E app's server, whose test-only routes sign in without a credential, listens on 127.0.0.1 only in its test and e2e environments, instead of on every interface.
