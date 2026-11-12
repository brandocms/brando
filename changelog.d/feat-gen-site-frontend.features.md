- `mix brando.gen.site --site KEY` generates one site's frontend (a `Brando.Site.Frontend` module with its layouts and `PageHTML` under `Web.Sites`, `--module` to name it) and registers it in `config :brando, site_frontends`; the CMS page controller, live preview, error pages and resource controllers the generators write now render each site's frontend.

- The System check warns, with tenancy in `:multi` and site frontends registered, about active sites without a frontend, registry entries that name no site, and pages whose template their site's `PageHTML` lacks.
