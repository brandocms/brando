# Content SEO audit

**Configuration → SEO → Content SEO** checks every published entry that has a
page of its own, in the current content language. Each entry gets a score from
0 to 100 and a list of checks with what to do about the ones that fail. The tab
badge is the average across the selected content types.

This guide assumes blueprints with `absolute_url` and `trait :meta` (see
[Meta](meta.md)), and the [SEO settings](identity_and_seo.md) filled in for the
language — the audit compares entries against the site fallbacks there.

## What is checked

| Check | Rule | Weight |
| --- | --- | --- |
| Meta title | Present | normal |
| Meta title length | 30–60 characters | low |
| Meta description | Present | critical |
| Meta description length | 120–160 characters | low |
| Own description | Not the site's fallback description | normal |
| Sharing image | A meta image or another image asset | normal |
| Title differs from description | Not identical, and the description does not open with the title | low |
| Unique title / description | Not shared with another entry in the language | normal |
| URL | `absolute_url` resolves | critical |
| In sitemap | The URL is in the generated sitemap | normal |
| Content length | At least 300 words of body text; none at all fails | normal |
| Heading structure | At most one H1 in the body, no skipped levels | low |
| Image descriptions | Every image has alt text that is not a filename or "image" | normal |
| Language versions | Not much shorter than, missing images or headings from, or months behind a published translation | normal |
| Search click-through | With Search Console: a first-page result clicked by under 1% of searchers | normal |

Failures earn nothing, warnings half their weight; weights are 1, 2 and 4.
Checks that cannot run — no sitemap yet, no block fields — are left out of the
score and show as "Not checked".

Body text, headings and images are measured by the database from the entries'
`rendered_<field>` columns, so the audit stays cheap on large sites. The page
title is normally the template's H1, which the audit cannot see: it counts
headings in the body only, continuing from an H1.

Change the thin-content threshold with:

```elixir
config :brando, Brando.SEO, thin_content_words: 300
```

## Add your own checks

Override `__seo_checks__/1` in a blueprint and return `Brando.SEO.Check`
structs. They are scored and shown with the built-in checks:

```elixir
def __seo_checks__(row) do
  [
    %Brando.SEO.Check{
      key: :client,
      status: if(row.title =~ "Untitled", do: :fail, else: :pass),
      weight: :normal,
      label: t("Named case"),
      hint: t("Give the case a proper title.")
    }
  ]
end
```

The argument is a `Brando.SEO.Audit.Row`: the entry's meta fields, URL, word
count, headings and image alt text — not the whole entry.

## Leave out entries without a page

An entry that only links elsewhere — a case that points at the client's own
site, say — has no page to audit. Name the entries that have a URL with
`only:` on `absolute_url`, and the audit leaves the rest out:

```elixir
absolute_url "{% route case_path detail { entry.slug } %}", only: %{type: :full_case}
```

The same declaration answers `__has_url__/1` for one entry and
`__url_filter__/0` for list queries, such as a sitemap's, and makes
`__absolute_url__/1` return `nil` for the rest. Pages with `has_url: false` are
left out the same way. See `Brando.Blueprint.AbsoluteURL` for the function
form.

## Write and review meta descriptions with AI

With `Brando.AI` configured, the tab can:

- write or rewrite one entry's meta description from its row;
- write every missing description in the background. Nothing is saved until
  each suggestion is accepted, edited first if needed. A run is capped:

  ```elixir
  config :brando, Brando.SEO, max_batch: 200
  ```

- review an entry's current title and description against its content — and,
  with Search Console, against the searches it is shown for. The review is
  advice only and is never stored.

"What the AI reads" picks, per content type, which fields a generated
description is written from. The choice is stored on the SEO settings.

## Write alt text for images

**Assets → Images → Alt text** lists the images in the library that have no
alt text. With `Brando.AI` configured, it shows what describing them would
cost — from the model's published prices and each image's size — and then
describes them in the background, one request per image. As with meta
descriptions, nothing is saved until each suggestion is accepted, edited
first if needed. The same `max_batch` cap applies to a run.

The text goes on the image itself, in every content language it lacks —
one request per image writes all of them; the image is what costs, so the
extra languages add only a sentence of output each. Each page shows the alt
text in its own language, falling back to the default language, unless a
picture block or gallery placement overrides it. An image missing alt text
in any language is listed.

Each image is sent at a mid-sized rendition (the smallest configured size at
least 512px wide), not the original, which keeps the cost down. The images
are sent to the AI provider. The model must accept image input — the page
says so when it does not — and can be set apart from the rest:

```elixir
config :brando, Brando.AI,
  fields: [alt: [model: "anthropic:claude-haiku-4-5"]]
```

The Content SEO **Image descriptions** check links here from any entry whose
body has images without usable alt text.

## Traffic from Plausible and Google Search Console

Configure either source, or both, to add traffic to the audit:

```elixir
config :brando, Brando.SEO.Analytics,
  period_days: 28,
  plausible: [
    api_key: System.get_env("PLAUSIBLE_API_KEY")
  ],
  search_console: [
    credentials: System.get_env("GOOGLE_SEARCH_CONSOLE_CREDENTIALS")
  ]
```

The tab then shows visitors and search clicks per entry, can sort by the most
visited or most searched pages — the ones worth fixing first — counts pages
nobody visited, and lists the searches a page is shown for when its row is
opened. Figures are cached for an hour; **Run again** reads them afresh.

`site_id` (Plausible) and `property` (Search Console) default to the host of
the SEO settings' base URL — `example.com` and `sc-domain:example.com` — so one
key serves every site of a multi-tenant install. Set them when the names differ.
A self-hosted Plausible takes `base_url: "https://plausible.example.com"`.

### Plausible

1. In Plausible, open **Account settings → API keys → New API key**, and choose
   **Stats API**. The key must belong to the team that owns the site.
2. Set it as `PLAUSIBLE_API_KEY`.

### Google Search Console

1. In Google Cloud, create a project (or use one), enable the **Google Search
   Console API**, and create a **service account** with a **JSON key**.
2. In Search Console, open the property's **Settings → Users and permissions**
   and add the service account's email address. **Restricted** is enough.
3. Set the key's JSON — or the path to the file — as
   `GOOGLE_SEARCH_CONSOLE_CREDENTIALS`.

Search Console reports with about two days' delay, so its period ends two days
ago. A source that fails is named above the table with Google's or Plausible's
own message; the audit runs regardless.
