- With `tenancy_mode: :multi`, `og:site_name` and the title of a page's first breadcrumb are the identity's name for the page's language, else the site's name, else `app_name`. Saving an identity with a new name computes its language's stored breadcrumbs again, and a new site's identities are seeded with the site's name.
  Stored breadcrumbs keep the old title until they are computed again: run `Brando.Pages.update_breadcrumbs_for_language/1` per site, environment and language, for example
  `Brando.Tenant.with_prefix("tenant_acme_production", fn -> for language <- ["en", "no"], do: Brando.Pages.update_breadcrumbs_for_language(language) end)`, which computes every page of the language that is not deleted.

- A content transfer computes the stored breadcrumbs of the pages it creates or updates from the destination, instead of keeping the source's, and its undo computes those of the pages it restores again.

- A `mutation :update` callback can take the changeset as a second argument, whose `data` is the entry as it was before the save.

- A site's frontend module can define `admin_brand/0`, the HTML the admin navigation shows while that site is selected, in place of `client_brand`; the login screen keeps `client_brand`.

- With a site selected, the block editor's wrapper and its loading skeleton carry `data-site="<site key>"`, so `assets/backend/css/app.css` can scope one site's module preview rules with `[data-site="acme"] { … }`; `mix brando.gen.site --site` says where they go.
