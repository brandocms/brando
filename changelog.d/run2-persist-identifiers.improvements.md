- **`mix brando.migrate55` sets `persist_identifier false` on Blueprints
  nothing can open or select.** It only advised it. A Blueprint now gets
  `persist_identifier false` after its `identifier`, listed in the notice,
  when all of these hold: no `live …, :update` route in the router produces
  its `admin_<singular>_form_path` (or
  `admin_<router_scope>_<singular>_form_path`), no admin LiveView names it,
  it has no `absolute_url`, it has no `:selection` or `:single` datasource,
  and no `:entries` relation or input in the application could select it
  (one that names it, or one without `sources:`). The notice says that
  `mix brando.identifiers.sync` then deletes its existing identifiers and
  whatever still selects them. Embedded Blueprints, Blueprints with
  `identifier false` and Blueprints that already set `persist_identifier`
  are left alone; any other Blueprint without an editor is listed with the
  reason, and when the task cannot read the router it keeps the advice as a
  warning.
