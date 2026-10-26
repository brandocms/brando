- `phoenix` 1.8.16 and `phoenix_live_view` 1.2.13, which fix socket reconnect races, form recovery
  finishing before every recovered form has answered, and several upload error paths.
  Run `mix deps.update phoenix phoenix_live_view`. If your `assets/package.json` pins
  `phoenix_live_view`, pin it to `1.2.13` and rebuild your backend assets.
