- `bcrypt_elixir` 4.0 is allowed alongside 3.x, and Brando no longer depends on `comeonin`
  itself. If your application calls a `Comeonin` function or `Bcrypt.add_hash/2` or
  `Bcrypt.check_pass/3`, add `{:comeonin, "~> 5.0"}` and keep `bcrypt_elixir` at 3.x.

- `image` 0.74, `postgrex` 0.23, `eqrcode` 0.3, `req_llm` 1.31, `swoosh` 1.30 and `mdex` 0.14.8 in
  the lock.
