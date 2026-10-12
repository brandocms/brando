- **`mix brando.upgrade.snapshot` diffs a site's public pages before and after
  an upgrade.** `urls` writes the URL set from the database (every published
  page per language, one entry per language for every other Blueprint with an
  `absolute_url`, a 404 per language, `/robots.txt`, `/sitemap.xml`);
  `capture DIR --base-url URL [--urls FILE]` saves each response's status and
  body; `diff BEFORE AFTER` reports, per URL, what changed in four layers kept
  apart: status, visible text, `<head>` tags as a set, and element structure
  (tag, classes and `data-*` names, so a `data-src` that moved shows). Head
  changes every page shares are listed once. Capture needs only the URL list
  and a running site, so the old site is captured from the upgraded code: see
  the task's documentation for the order.
