- **A new application's release builds again** (#3232). The Dockerfile
  `mix brando.install` writes built on `twined/fehn:4.0`, which has Elixir
  1.17 on OTP 27.1, below the `~> 1.18` Brando requires, so a Florist release
  build could not compile Brando. It now builds on `twined/fehn:4.2`: Elixir
  1.20.4 on OTP 28.5.0.8, on Ubuntu 24.04. In an existing application, change
  the Dockerfile's `FROM --platform=linux/amd64 twined/fehn:<tag> as deps` to
  the 4.2 variant for the server's Ubuntu release, since a release does not
  start on a server with an older glibc or another OpenSSL: `twined/fehn:4.2`
  (or `4.2-noble`) for Ubuntu 24.04, `twined/fehn:4.2-jammy` for Ubuntu
  22.04, and `twined/fehn:4.2-focal` for Ubuntu 20.04, which fehn 3.x built
  on. `4.2-focal` has Elixir 1.19.5 on OTP 28.4.3, so a site on it pins those;
  upgrading such a server to 22.04 or 24.04 is the better path. From fehn 4.0
  or 4.1, also Ubuntu 24.04, the server needs nothing new.
  `mix brando.gen.backend --upgrade` names an older tag in a notice but does
  not change it; "The Docker build" in `guides/deployment.md` has the variants
  and how to check a server.
