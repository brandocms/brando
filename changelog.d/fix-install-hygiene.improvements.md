- Brando no longer needs a `Jason.Encoder` for `Tuple`, and `mix brando.install` no longer writes
  `tuple.ex` ([#3231](https://github.com/brandocms/brando/pull/3231)).
  An existing application can delete `lib/<app>/tuple.ex` unless its own code JSON-encodes tuples.
