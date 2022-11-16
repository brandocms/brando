#!/usr/bin/env bash
# BRANDO INSTALL SCRIPT
clear
echo "╓─────────────────────────────────────────────╖"
echo "║             BRANDO Installation             ║"
echo "╙─────────────────────────────────────────────╜"
echo   # new line
MODULE=$(cat mix.exs | sed -n 's/defmodule \(.*\)\.MixProject.*/\1/p')
echo "==> Extracted module from mix.exs => $MODULE"
echo   # new line
read -p "Do you want to continue installation? " -n 1 -r
echo   # new line
if [[ $REPLY =~ ^[Yy]$ ]]
then
  echo "==> Starting installation"
  gsed -i '/{:phoenix,/i\      {:brando, github: "brandocms/brando"},' mix.exs
  mix do deps.get, brando.install --module $MODULE, deps.get, deps.compile
  direnv allow
  cd assets/frontend && yarn && yarn upgrade @brandocms/jupiter @brandocms/europacss && cd ../backend && yalc add @brandocms/brandojs && yarn && yarn build && cd ../../
  mix deps.get && mix brando.upgrade
  mix ecto.setup
  mix ecto.dump
  mix brando.gen.languages
  mix brando.gen.admin
fi
