- **A new application's release builds again** (#3232). The Dockerfile
  `mix brando.install` writes built on `twined/fehn:4.0`, which has Elixir
  1.17 on OTP 27.1, below the `~> 1.18` Brando requires, so a Florist release
  build could not compile Brando. It now builds on `twined/fehn:4.2`: Elixir
  1.20.4 on OTP 28.5.0.8, on Ubuntu 24.04. In an existing application, change
  the Dockerfile's `FROM --platform=linux/amd64 twined/fehn:<tag> as deps` to
  the 4.2 variant for the server's Ubuntu release: `twined/fehn:4.2` (or
  `4.2-noble`) for Ubuntu 24.04, `twined/fehn:4.2-jammy` for Ubuntu 22.04.
  A release does not start on a server with an older glibc or without
  OpenSSL 3. There is no variant for Ubuntu 20.04, which fehn 3.x built on:
  upgrade such a server to 22.04 or 24.04, or provision a new one, first. From
  fehn 4.0 or 4.1, also Ubuntu 24.04, the server needs nothing new.
  `mix brando.gen.backend --upgrade` names an older tag in a notice but does
  not change it; "The Docker build" in `guides/deployment.md` has the variants
  and how to check a server.
