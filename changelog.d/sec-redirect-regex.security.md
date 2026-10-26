- A redirect created from a 404 in the SEO settings ("Missing redirects", or "Add redirect" on a logged 404) matches that exact path, escaped like a permalink redirect, instead of reading the visitor's URL as a pattern that could make every later 404 in its language fail or run slowly.

- A redirect whose "from" pattern does not compile can no longer be saved, a stored one that does not compile matches nothing instead of failing every 404 in its language, and each pattern is compiled once rather than on every 404.
  A stored redirect that does not compile is logged as a warning when a 404 first checks it. Rules created from 404s before this release may still be patterns: review the redirects in the SEO settings and delete any whose "from" is a visitor's odd URL.
