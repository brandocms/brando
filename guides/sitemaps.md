# Sitemaps

Brando generates XML sitemaps from an application module and serves the generated
files through `page_routes()`. Your callbacks decide which entries belong in
search results; the generator does not infer publication or language rules.

This guide assumes a migrated consumer, a writable media directory, an accurate
public endpoint URL, and published pages with working URL definitions.

## Declare public URLs

Run `mix brando.gen.sitemap` to generate the module, then adapt it to the current
query and URL APIs:

```elixir
defmodule MyAppWeb.Sitemap do
  import Brando.Sitemap

  sitemap "pages" do
    Brando.Pages.list_pages(%{
      filter: %{has_url: true},
      status: :published,
      select: {:struct, [:id, :title, :uri, :language, :updated_at]},
      order: [{:asc, :id}]
    }, :stream)
    |> Stream.map(fn page ->
      url(%{
        loc: Brando.Blueprint.URL.resolve(page, :with_host),
        lastmod: page.updated_at,
        changefreq: :weekly,
        priority: 0.7
      })
    end)
  end
end
```

Use your configured web module name, normally `MyAppWeb.Sitemap`. Keep only the
sitemap callbacks public in this module: the generator enumerates its exported
functions and calls them with zero arguments. Helpers should be private or live
in another module.

The query excludes soft-deleted pages through the standard query defaults and
explicitly excludes drafts, pending/disabled entries, and pages with `has_url:
false`. It includes every language. Keep the returned Blueprint structs: selecting
a plain map of fields would make the URL resolver return an empty string. The
resolver uses each entry’s language and URI, including the homepage. Add another
`sitemap "products"` block for a custom schema, with equivalent public filters
and any preloads its URL definition needs. Every `loc` must be an absolute,
publicly reachable URL rather than an admin or preview route.

`url/1` constructs a `Sitemapper.URL`. A naive `lastmod` is interpreted as UTC
and converted to Brando's timezone; a `DateTime` already has a zone and is retained.
Use a content timestamp that really represents modification, not the time the
sitemap was generated.

## Generate and inspect

In a local consumer shell:

```elixir
{:ok, _files} = Brando.Sitemap.generate_sitemap(gzip: false)
```

Generation runs the streams inside a repo transaction, creates a `sitemaps`
directory under the current media root, and writes an index plus numbered URL
files. For the uncompressed run, inspect `sitemap.xml` and
`sitemap-00001.xml`; the default uses gzip for the sitemap output.

```bash
curl -f http://localhost:4000/sitemaps/sitemap.xml
curl -f http://localhost:4000/sitemaps/sitemap-00001.xml
```

Use the child filename actually listed by the index. Confirm that each `loc`
uses the intended public host and language path, that draft/disabled/deleted
content is absent, and that a no-content database does not advertise stale
content from a previous output directory. A missing file returns `404` through
the sitemap controller. With no application sitemap module, generation can be a
no-op; a command finishing is not sufficient verification that XML exists.

## Keep it current

The default Oban cron runs the sitemap generator at **02:00 UTC**.
It generates for each active site's live environment, or once for a classic
installation. This is different from the site's display timezone. An application
Oban override replaces the default configuration; re-declare the cron if you
want it to remain scheduled.

Generation writes under the tenant-aware media root. Named environments of a
site share media storage, so manually generating from Staging can replace that
site's sitemap files. Generate public files from the intended live environment,
and verify the endpoint/public host used by the URL callbacks. A tenant prefix
alone does not change a globally configured endpoint hostname.

A content save does not synchronously regenerate the sitemap. Regenerate after a
large import, URL migration, or launch when waiting for the nightly cron is
undesirable. For static deployment, include the generated sitemap files in the
published output and test the deployed route. Confirm `/robots.txt` points to the
correct public sitemap index; see [Identity and SEO](identity_and_seo.md).
