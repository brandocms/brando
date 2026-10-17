- **A new application's release builds again.** The Dockerfile
  `mix brando.install` writes built on `twined/fehn:4.0`, which has Elixir
  1.17.3 on OTP 27.1, below the `~> 1.18` Brando requires, so a Florist
  release build could not compile Brando. It now builds on `twined/fehn:4.2`:
  Elixir 1.20.4 on OTP 28.5.0.8, on Ubuntu 24.04 like 4.0. In an existing
  application, change the Dockerfile's `FROM --platform=linux/amd64
  twined/fehn:<tag> as deps` to `twined/fehn:4.2`.
