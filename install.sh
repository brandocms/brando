#!/usr/bin/env bash
set -euo pipefail

cat >&2 <<'MESSAGE'
The legacy Brando shell installer has been retired.

Use the reviewed Igniter installer from your Phoenix application:

  mix igniter.install brando@path:/absolute/path/to/brando

Install Igniter in the consumer first if it is not already available:
  {:igniter, "~> 0.8.0", only: [:dev, :test]}
  mix deps.get

Then follow the ordered asset, database and account setup in:
  https://github.com/brandocms/brando/blob/next/guides/generators.md

Keep Brando and the Yalc JavaScript source on the same revision during development.
MESSAGE
exit 1
