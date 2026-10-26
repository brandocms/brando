- The `b:alert` event shows `message` as text. An alert that needs markup sends it as `html`, with every interpolated value escaped.
  Replace `push_event(socket, "b:alert", %{title: t, message: "<a href=…>…</a>", type: "info"})` with
  `push_event(socket, "b:alert", %{title: t, html: ~s(<a href="#{BrandoAdmin.Alert.escape(url)}">…</a>), type: "info"})`.
  A `{:modal, type, title, message}` sent to a listing, `phx-confirm-click-message` and listing actions' `confirm:` text, and `data-popover` tooltips are text too; a `phx-confirm-click-describe` reply sends markup as `html` instead of `message`.

- Colour fields (`:color` inputs, palette colours and colour vars, including defaults in definition files) accept only colours: hex, a CSS colour keyword, or colour functions such as `rgb()`, `oklch()`, `color-mix()` and `var(--name)`. Other text is refused on save; values already stored stay until they are edited.
  Change a definition file's colour `default:` that is not a colour before importing it.
