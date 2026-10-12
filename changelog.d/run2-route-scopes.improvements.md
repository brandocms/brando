- **`mix brando.migrate54` gives a domain's admin routes their own helper
  prefix when two FormLives would share one.** `Articles.CategoryFormLive`
  and `Menu.CategoryFormLive` both routed `admin_category_form_path`, so one
  Blueprint's links opened the other's form, and the task only said how to
  fix it. When a colliding FormLive is routed in a plain
  `scope "/menu", MyAppAdmin.Menu do` that holds only that domain's admin
  LiveViews, the task adds `as: :menu` to the scope and
  `router_scope: :menu` to every Blueprint routed in it, and lists both in
  its notice. Other shapes (a flat route, a scope with other routes, code
  that calls the helpers being renamed) are still listed, now with each
  route's file and line and the reason the task left it.
