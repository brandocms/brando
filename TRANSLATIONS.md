# Brando admin translations

From the repository root, extract current strings and merge the Norwegian catalog:

```sh
mix gettext.extract --merge --locale no --no-fuzzy
```

Translate the new entries in `priv/gettext/no/LC_MESSAGES/*.po`, including both
plural forms. Keep `%{interpolation}` keys intact. Review translations explicitly;
fuzzy matches can silently substitute unrelated wording when UI copy changes.

Use `gettext/1` for UI text. For module attributes containing option labels, use
`gettext_noop/1` to extract the strings and translate them when assigning options
in the LiveView process. The shared user mount hook sets the administrator's
locale for connected views and their children.

```sh
mix test test/brando/gettext_test.exs
mix gettext.extract --check-up-to-date
```

The catalog test rejects missing, empty, or fuzzy Norwegian translations and
checks interpolation keys and plural forms. Verify changed screens with a
Norwegian administrator after the WebSocket connects, including client-side
tooltips and confirmations. Consumer application catalogs use their own paths;
see [Languages and translations](guides/i18n.md).
