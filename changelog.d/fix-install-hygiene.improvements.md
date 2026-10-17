- **Brando no longer needs a `Jason.Encoder` for `Tuple`** (#3231). The query
  cache hashed each query key through `Jason.encode!/1`, and keys hold tuples,
  so every application carried a global `defimpl Jason.Encoder, for: Tuple`
  in `lib/<app>/tuple.ex`. It now hashes the key as an Erlang term, and
  `mix brando.install` no longer writes `tuple.ex`. An existing application
  can delete its `lib/<app>/tuple.ex` unless its own code JSON-encodes
  tuples. Query cache keys change with this; the cache lives in memory, so a
  deploy starts it empty either way.
