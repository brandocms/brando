# Brando admin translations

Add strings in code, then extract and merge every catalogue from the
repository root:

```sh
mix gettext.extract --merge
```

Do not add or remove messages in the `.pot` or `.po` files by hand (runtime
msgids, below, are the exception), and do not pass `--locale`: the English
catalogues are merged too. On a clean `main` this command changes nothing, so
the diff it produces is exactly your change. CI runs it and fails if
`priv/gettext` changes.

Translate the new entries in `priv/gettext/no/LC_MESSAGES/*.po`, including both
plural forms. Keep `%{interpolation}` keys intact. Leave the English `.po`
entries empty.

`mix.exs` configures extraction (`gettext/0`): references name the file without
a line number, messages are sorted by msgid, and fuzzy matching is off. Gettext
serves fuzzy entries at runtime, so a reworded message would otherwise show its
old translation; with fuzzy matching off it arrives empty and the catalogue
test below fails until you translate it.

Use `gettext/1` for UI text. For module attributes containing option labels, use
`gettext_noop/1` to extract the strings and translate them when assigning options
in the LiveView process. Messages looked up with a runtime msgid
(`Gettext.dgettext(backend, domain, variable)`) are not extracted; add them to
the `.pot` and each `.po` without the `elixir-autogen` flag, and extraction
keeps them (see `months.pot`). The shared user
mount hook sets the administrator's locale for connected views and their
children.

```sh
mix test test/brando/gettext_test.exs
```

The catalog test rejects missing, empty, or fuzzy Norwegian translations and
checks interpolation keys and plural forms. Verify changed screens with a
Norwegian administrator after the WebSocket connects, including client-side
tooltips and confirmations. Consumer application catalogs use their own paths;
see [Languages and translations](guides/i18n.md).

## Rebases and merges

`scripts/gettext-merge-driver` merges `.po` and `.pot` files message by message,
so two branches that add different strings merge cleanly and every message
keeps its msgstr. It conflicts only when both sides change the same translation
differently. Register it once per clone, from the repository root (worktrees
share it):

```sh
python3 scripts/gettext-merge-driver --install
```

This sets `merge.gettext.driver` in the repository's git config. Without it,
git merges the catalogues line by line as before.

After a merge or rebase, run `mix gettext.extract --merge` once more if code
changed on both sides; it should change nothing else. The script's header
describes how it merges, and `scripts/gettext-merge-driver --self-test` tests it.
