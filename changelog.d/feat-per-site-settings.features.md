- With `tenancy_mode: :multi`, `og:site_name` and the title of a page's first breadcrumb are the identity's name for the page's language, else the site's name, else `app_name`.
  Stored breadcrumbs keep the old title until they are computed again: run `Brando.Pages.update_breadcrumbs/1` per site and environment, for example
  `Brando.Tenant.with_prefix("tenant_acme_production", fn -> {:ok, roots} = Brando.Pages.list_pages(%{filter: %{parents: true}}); for page <- roots, do: Brando.Pages.update_breadcrumbs(page) end)`, which takes the root pages that are not deleted and computes the pages under them too.

- A site's frontend module can define `admin_brand/0`, the HTML the admin navigation shows while that site is selected, in place of `client_brand`; the login screen keeps `client_brand`.

- With a site selected, the block editor's wrapper and its loading skeleton carry `data-site="<site key>"`, so `assets/backend/css/app.css` can scope one site's module preview rules with `[data-site="acme"] { … }`; `mix brando.gen.site --site` says where they go.
