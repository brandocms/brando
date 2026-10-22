- A new application's release builds again: its Dockerfile builds on `twined/fehn:4.2` (Elixir
  1.20.4 on OTP 28.5.0.8) ([#3232](https://github.com/brandocms/brando/pull/3232)).
  In an existing application, change the Dockerfile's `FROM --platform=linux/amd64 twined/fehn:<tag>
  as deps` to the 4.2 variant for the server's Ubuntu release: `twined/fehn:4.2` (or `4.2-noble`)
  for 24.04, `4.2-jammy` for 22.04, `4.2-focal` for 20.04.
  `4.2-focal` has Elixir 1.19.5 on OTP 28.4.3, so a site on it pins those. A server already on fehn
  4.0 or 4.1 needs nothing new.
  "The Docker build" in `guides/deployment.md` lists the variants and how to check a server.
