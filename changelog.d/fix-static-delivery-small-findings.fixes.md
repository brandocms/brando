- A static build of a site without a sitemap says so in its log and in `mix brando.ssg`'s output: the application has no sitemap module, or it produced no entries.

- A failed static build's progress in the Publishing screen's build history says how many URLs it built and how many failed, when any did, instead of full progress.

- The build history's progress is labelled when the list stacks on a narrow screen.

- Setup and maintenance code can create a page, a fragment or any entry with a creator as `:system`, naming the creator with `creator:`: `Brando.Pages.create_page(params, :system, creator: user)`.

- After a restart the Environments screen names this server's addresses at once, instead of only once a host needs a lookup: the served hosts check looks them up at its first check.

- A served host whose lookup timed out is looked up again once after five to ten seconds, before the one-minute retry, so a new host with no DNS record shows **Does not resolve** within seconds instead of **Could not look it up** for a minute behind a slow caching resolver. `:timeout_retry_interval` in `config :brando, Brando.Tenant.ServedHosts` changes the delay.

- The Environments screen no longer repeats a domain on the state line under its field, unless the domain is too long for the field to show whole or the field holds a typed domain not saved yet.

- The Environments screen lists the live environment first, then the others by name.

- The presence avatars in the bottom right corner no longer cover a row's Delete button on the Environments and Publishing screens.

- The System check for a served build's static paths says, when skipped in a release, that it runs in development, where the endpoint's source can be read.
