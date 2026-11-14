- `Brando.Assets.SiteAssets.sets_root/1` takes a site key as well as a site.

- The default `Brando.Tenant.Seeder` gives a newly provisioned site, in each of its languages, what `mix brando.setup` seeds without tenancy: the modules, a published homepage, the footer fragment and a main menu, so its hosts answer `/` at once. It writes as the system, so a site created suspended, or by a user whose groups grant no content in it, is seeded too.

- With `tenancy_mode: :single`, `mix brando.setup` creates the configured site after the first account, with Production and Staging and the default content, so `/` answers once setup has finished; a site with the key that exists is left alone.
