- `mix brando.doctor` warns when a test library such as ExMachina ships in the release. Installers before 0.55 added ExMachina to every environment, with the factory under `lib/`.
  Give the dependency `only: :test` in `mix.exs`, move `lib/<app>/factory.ex` to `test/support/`, and make sure `elixirc_paths(:test)` includes `"test/support"`.
