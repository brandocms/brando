- Without JavaScript, a generated site now shows its palette sections, cookie banner and smart videos: the CMS root and lockdown layouts give `<html>` the `no-js` class the frontend's `.no-js` rules expect, and `critical.css` shows `[b-section]` under it. A site generated before this adds both:
  - `<html class="no-js" lang={@language}>` in `lib/<app>_web/cms/layouts.ex` (and `lockdown_html.ex`);
  - `.no-js [b-section] { opacity: 1; }` after the `[b-section]` rule in `assets/frontend/css/critical.css`.

- The admin bundle's `src/main.js` template registers `app.initialize` for `DOMContentLoaded` instead of calling it at once. A site generated before this changes its listener to `document.addEventListener('DOMContentLoaded', () => app.initialize())`.

- Rerunning `mix brando.setup.tenancy` no longer replaces an edited tenant migration in `priv/repo/tenant_migrations/`.
