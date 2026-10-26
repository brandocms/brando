- The `b:alert` event shows `message` as text. An alert that needs markup sends it as `html`, with every interpolated value escaped.
  Replace `push_event(socket, "b:alert", %{title: t, message: "<a href=…>…</a>", type: "info"})` with
  `push_event(socket, "b:alert", %{title: t, html: ~s(<a href="#{BrandoAdmin.Alert.escape(url)}">…</a>), type: "info"})`.
  A `{:modal, type, title, message}` sent to a listing and `data-popover` tooltips are text too; a `phx-confirm-click-describe` reply sends markup as `html` instead of `message`.
