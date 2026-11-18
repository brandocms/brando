- In development with the Vite dev server, the head's inlined critical CSS follows a `pnpm build` without a server restart.

- In development with the Vite dev server, `<.head>` loads the site's `css/app.css` render-blocking, so the first render is styled and cross-document view transitions no longer animate an unstyled page.
