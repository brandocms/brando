- **`mix brando.migrate55` gives public list queries a defined order.** The
  0.55 data migrations rewrite rows, so a query without `ORDER BY` returns
  them in a new storage order: on Lett the first menu tab changed, and
  articles with equal `sequence` reshuffled. Calls to your contexts'
  `list_<plural>/1` (from `Brando.Query`'s `query :list`) whose literal
  options map, in the call or bound to a variable earlier in the function,
  orders a Sequenced Blueprint only by `sequence` (`"asc sequence"`,
  `{:asc, :sequence}`, `[{:asc, :sequence}]`) now order by
  `"asc sequence, desc inserted_at"`, the admin listing's order, or by
  `"asc sequence, asc id"` when the Blueprint has no timestamps. Calls with
  no `order:` at all, in `.ex` files and `.heex` templates, are listed with
  file and line for you to choose an order, since adding one changes what
  the page shows.
