- **`mix brando.install` takes phx.new's files out of `priv/static`.** The
  Docker build Florist runs makes `priv/static` from the two Vite builds, so
  what `mix phx.new` put there worked in development and was missing from the
  release. The installer now removes phx.new's `favicon.ico` (Brando writes
  its own to `assets/frontend/public`) and moves `images/logo.svg` to
  `assets/frontend/public/images/logo.svg`. With the CMS public site, and in
  `mix brando.gen.site`, it also removes phx.new's `robots.txt` and the
  `robots.txt` entry in `static_paths/0`, which made development serve that
  file instead of the robots text from the SEO settings. Only files still as
  phx.new wrote them are touched; a changed one is kept, with a notice.
