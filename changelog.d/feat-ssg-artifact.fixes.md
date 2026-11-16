- A static build stores each page as the application answered it, without reformatting its HTML.

- A static build fails before it requests anything when the application writes HEEx debug comments or `data-phx-loc` attributes into its pages, rather than shipping them.
  Where builds run, set `config :phoenix_live_view, debug_heex_annotations: false, debug_attributes: false` and recompile.

- A static build's preview loads the build's own assets and media, serves its Markdown alternates, its links stay inside the preview, and a missing path shows the build's 404 page.

- The Publishing screen offers automatic deployment only once the site has a deployment target, and a build never tries to deploy without one.
