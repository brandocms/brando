- Brando is qualified on Elixir 1.20.4 with OTP 28.5.0.8, which a new install pins in
  `.tool-versions` ([#3232](https://github.com/brandocms/brando/pull/3232)).
  In an existing application, move `.mise.toml` or `.tool-versions` to Erlang 28.5.0.8 and Elixir
  1.20.4-otp-28 and run `mise install` (or `asdf install`).
