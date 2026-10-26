- A page fills in the visitor's CSRF token only in a form's hidden `_csrf_token` input. Before, `$csrftoken` anywhere in rendered content, such as an image URL in synced Markdown, was replaced too, sending each visitor's token to that URL's host.

- A second `$__CONTENT__` in content rendered with `Brando.HTML.render_data/1` stays as text instead of making the page fail to render.
