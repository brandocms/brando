#!/bin/zsh
MIX_ENV=e2e mix do ecto.drop, ecto.create, ecto.migrate, run priv/repo/e2e_seeds.exs && cd e2e/playwright && yarn test:ui