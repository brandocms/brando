- With `tenancy_mode: :multi`, the admin and MCP answer on the endpoint's host (`PHX_HOST`) only: on a site's host their paths answer as paths that do not exist, with the site's own 404 page, and frontend edit mode adds nothing to the sites' pages.
  Give `socket "/admin/socket"` in the endpoint the admin socket's origin check:
  `websocket: [check_origin: {BrandoAdmin.AdminHost, :check_origin, []}]` and
  `longpoll: [check_origin: {BrandoAdmin.AdminHost, :check_origin, []}]`.
  Open the admin on the endpoint's host, `localhost:4000/admin` in development.

- With `tenancy_mode: :multi`, a site's default `robots.txt` no longer names `/admin/`, and a newly provisioned site's seeded homepage, menu and footer have no admin links.
