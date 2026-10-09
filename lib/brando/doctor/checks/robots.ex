defmodule Brando.Doctor.Checks.Robots do
  @moduledoc """
  `/robots.txt` is served by Brando (`page_routes/1` in the router), so it
  carries the robots text from SEO settings and names the sitemap, and no
  static `priv/static/robots.txt` stands in front of it.
  """
  use Brando.Doctor.Check
  use Gettext, backend: Brando.Gettext

  @impl true
  def id, do: "robots"

  @impl true
  def label, do: dgettext("doctor", "robots.txt")

  @impl true
  def run(_context) do
    evaluate(route(), static_file?())
  end

  @doc "`route` is the plug `/robots.txt` resolves to (or nil); `static?` whether a static file exists."
  def evaluate(route, static?) do
    cond do
      # The deprecated `Brando.SEOController` still serves it; the
      # Deprecations check names the rename
      route not in [BrandoWeb.SEOController, Brando.SEOController] ->
        warning(dgettext("doctor", "not served by Brando"),
          fix: dgettext("doctor", "call page_routes() in the router's browser scope"),
          items: [dgettext("doctor", "GET /robots.txt goes to %{plug}", plug: inspect(route))]
        )

      static? ->
        warning(dgettext("doctor", "a static robots.txt may stand in front of the SEO text"),
          fix: dgettext("doctor", "delete priv/static/robots.txt and remove it from static_paths"),
          link: {BrandoAdmin.Sites.SEOLive, dgettext("doctor", "Open SEO")}
        )

      true ->
        ok(dgettext("doctor", "served from SEO settings"))
    end
  end

  defp route do
    case Phoenix.Router.route_info(Brando.router(), "GET", "/robots.txt", nil) do
      %{plug: plug} -> plug
      _ -> nil
    end
  rescue
    _ -> nil
  end

  defp static_file? do
    case Brando.otp_app() do
      nil -> false
      app -> app |> Application.app_dir("priv/static/robots.txt") |> File.exists?()
    end
  rescue
    _ -> false
  end
end
