- **Brando is qualified on Elixir 1.20.4 with OTP 28.5.0.8**, up from 1.20.3
  with 28.4.1. CI's newest leg, its quality gates, documentation, E2E and
  consumer smoke jobs run on it, Brando's `.mise.toml` pins it, and a new
  install's `.tool-versions` pins Erlang 28.5.0.8 and Elixir 1.20.4-otp-28
  (Node.js 24.22.0 and pnpm 10.32.1 are unchanged). The 1.18.1/OTP 27.2 and
  1.19.5/OTP 28 legs stay. In an existing application, move `.mise.toml` or
  `.tool-versions` to the same Erlang and Elixir and run `mise install` (or
  `asdf install`).
