- **`mix brando.migrate55` sets `persist_identifier false` on Blueprints with
  no admin editor.** It only advised it. A Blueprint whose
  `admin_<singular>_form_path` (or `admin_<router_scope>_<singular>_form_path`)
  no `live …, :update` route in the router produces, that no admin LiveView
  names and that has no `absolute_url`, now gets `persist_identifier false`
  after its `identifier`, and the notice lists each one. Embedded
  Blueprints, Blueprints with `identifier false` and Blueprints that already
  set `persist_identifier` are left alone. A Blueprint with admin LiveViews
  but no `:update` route, one with an `absolute_url` (menus and entry
  pickers may link to it), or one whose options the task cannot read, is
  listed instead, and when the task cannot read the router it keeps the
  advice as a warning.
