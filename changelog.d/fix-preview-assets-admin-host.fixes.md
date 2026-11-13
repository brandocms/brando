- With `tenancy_mode: :multi`, live previews and shared previews of a site with an uploaded asset set load the set's scripts, styles, fonts and images on the admin's host, except a path that sites hold with different content (`favicon.ico`, an unhashed font or logo with the same name), which no site's preview gets there; sharing a preview stores it in `public` instead of failing.

- With `tenancy_mode: :multi`, a site's host no longer opens a shared preview pinned to another site's asset set.
