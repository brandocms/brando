#!/usr/bin/env bash
# BRANDO INSTALL SCRIPT
echo ">>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>"
echo ">>>>>>>>>>>>> BRANDO INSTALLATION >>>>>>>>>>>>>"
echo ">>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>"
echo   # new line
MODULE=$(cat mix.exs | sed -n 's/defmodule \(.*\)\.MixProject.*/\1/p')
echo "==> Extracted module from mix.exs => $MODULE"
echo   # new line
read -p "Do you want to continue installation? " -n 1 -r
echo   # new line
if [[ $REPLY =~ ^[Yy]$ ]]
then
  echo "==> Starting installation"
  gsed -i '/{:phoenix,/i\      {:brando, github: "twined/brando", branch: "develop"},' mix.exs
  mix do deps.get, deps.compile, brando.install --module $MODULE, deps.get, deps.compile
  gsed -i '/Import environment specific config/i\# import BRANDO config\nimport_config "brando.exs"\n' config/config.exs
  cd assets/frontend && yarn && yarn upgrade jupiter io && cd ../backend && yarn && yarn upgrade kurtz && cd ../../
  mix do deps.get, deps.compile --force && mix ecto.setup
  gsed -i '/pool_size:/i\  socket_options: [recbuf: 8192, sndbuf: 8192],' config/prod.secret.exs
  mix release.init
fi
