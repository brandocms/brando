defmodule Brando.ErrorHTML do
  @moduledoc false
  # Deprecated name for `BrandoWeb.ErrorHTML` (renamed in 0.55, #2833;
  # removed in 0.57). An endpoint's `render_errors: [formats: [html:
  # Brando.ErrorHTML]]` keeps rendering the same pages and logs a warning on
  # the first error page.

  alias Brando.Deprecated.RenamedModules

  # Phoenix falls back to `render/2` with "404.html" when the view has no
  # `404/1` function component
  def render(template, assigns) do
    RenamedModules.warn(__MODULE__)

    {name, format} =
      case String.split(template, ".", parts: 2) do
        [name, format] -> {name, format}
        [name] -> {name, "html"}
      end

    Phoenix.Template.render(BrandoWeb.ErrorHTML, name, format, assigns)
  end

  @deprecated "Use BrandoWeb.ErrorHTML.template_not_found/2 instead"
  defdelegate template_not_found(template, assigns), to: BrandoWeb.ErrorHTML
end
