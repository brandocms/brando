defmodule Brando.Site.Frontend do
  @moduledoc """
  A site's layouts and page templates, picked per site from config.

      config :brando,
        site_frontends: %{
          "acme" => MyAppWeb.Sites.Acme,
          {"acme", "staging"} => MyAppWeb.Sites.AcmeNext
        },
        default_site_frontend: MyAppWeb.CMS

  A frontend module names its root layout and its `PageHTML`, and may add
  assigns for the layout and for each page:

      defmodule MyAppWeb.Sites.Acme do
        use Brando.Site.Frontend,
          root_layout: {MyAppWeb.Sites.Acme.Layouts, :root},
          page_html: MyAppWeb.Sites.Acme.PageHTML

        def layout_assigns(language),
          do: %{footer_menu: Brando.Cache.Navigation.get("footer", language)}

        def page_assigns(page, _assigns),
          do: %{footer_color: Brando.Pages.get_var(page, "footer_color")}
      end

  The callbacks take no `conn`, so the page controller, live preview and
  error pages all call them. The frontend is resolved from the process's
  tenant prefix (`current/0`); `Brando.Plug.SiteFrontend` applies it to a
  request.

  This module calls the application's modules only at runtime, through the
  config: a frontend module compiles against it.
  """

  import Plug.Conn, only: [merge_assigns: 2]

  alias Brando.Exception.ConfigError
  alias Brando.Tenant

  @callback root_layout() :: {module(), atom()}
  @callback page_html() :: module()
  @callback layout_assigns(language :: String.t()) :: map()
  @callback page_assigns(page :: struct(), assigns :: map()) :: map()

  defmacro __using__(opts) do
    root_layout = Keyword.fetch!(opts, :root_layout)
    page_html = Keyword.fetch!(opts, :page_html)

    quote do
      @behaviour Brando.Site.Frontend

      @impl Brando.Site.Frontend
      def root_layout, do: unquote(root_layout)

      @impl Brando.Site.Frontend
      def page_html, do: unquote(page_html)

      @impl Brando.Site.Frontend
      def layout_assigns(_language), do: %{}

      @impl Brando.Site.Frontend
      def page_assigns(_page, _assigns), do: %{}

      defoverridable root_layout: 0, page_html: 0, layout_assigns: 1, page_assigns: 2
    end
  end

  @doc """
  The frontend module for the process's tenant prefix, `nil` when its site
  has none, or `:legacy` when nothing is configured. In order:

    1. `site_frontends[{site_key, environment_key}]`
    2. `site_frontends[site_key]`
    3. In `:multi` with a non-empty `site_frontends`: `nil`
    4. `default_site_frontend`
    5. `:legacy`
  """
  @spec current() :: module() | nil | :legacy
  def current do
    frontends = Brando.config(:site_frontends) || %{}
    site_key = Tenant.current_site_key()

    with :error <- Map.fetch(frontends, {site_key, Tenant.current_environment_key()}),
         :error <- Map.fetch(frontends, site_key) do
      fallback(frontends)
    else
      {:ok, frontend} -> frontend
    end
  end

  defp fallback(frontends) do
    cond do
      Tenant.mode() == :multi and map_size(frontends) > 0 -> nil
      default = Brando.config(:default_site_frontend) -> default
      true -> :legacy
    end
  end

  @doc """
  The current site's frontend's `page_html/0`, or `nil` for a site with no
  frontend. With nothing configured: `:page_html_module`, then
  `Web.PageView` when it is loaded, then `Web.PageHTML`.
  """
  @spec page_html() :: module() | nil
  def page_html do
    case current() do
      :legacy -> legacy_page_html()
      nil -> nil
      frontend -> frontend.page_html()
    end
  end

  defp legacy_page_html do
    page_view = Brando.web_module(PageView)

    cond do
      configured = Brando.config(:page_html_module) -> configured
      Code.ensure_loaded?(page_view) -> page_view
      true -> Brando.web_module(PageHTML)
    end
  end

  @doc "Merges the current frontend's `page_assigns/2` for `page` into the conn's assigns."
  @spec put_page_assigns(Plug.Conn.t(), struct()) :: Plug.Conn.t()
  def put_page_assigns(conn, page) do
    case current() do
      frontend when frontend in [:legacy, nil] -> conn
      frontend -> merge_assigns(conn, Map.to_list(frontend.page_assigns(page, conn.assigns)))
    end
  end

  @doc """
  Raises `Brando.Exception.ConfigError` unless every `site_frontends` key is
  a site key or a `{site_key, environment_key}` tuple, and every registered
  module, `default_site_frontend` included, loads and defines
  `root_layout/0` and `page_html/0`.
  """
  @spec validate_config!() :: :ok
  def validate_config! do
    frontends = Brando.config(:site_frontends) || %{}

    unless is_map(frontends) do
      raise ConfigError,
        message: "Invalid :site_frontends configuration: expected a map, got #{inspect(frontends)}."
    end

    Enum.each(frontends, fn {key, module} ->
      valid_registry_key?(key) || raise_invalid_key(key)
      validate_module!(module, ":site_frontends entry #{inspect(key)}")
    end)

    case Brando.config(:default_site_frontend) do
      nil -> :ok
      module -> validate_module!(module, ":default_site_frontend")
    end

    :ok
  end

  defp valid_registry_key?({site_key, environment_key}),
    do: Tenant.valid_key?(site_key) and Tenant.valid_key?(environment_key)

  defp valid_registry_key?(site_key), do: Tenant.valid_key?(site_key)

  defp validate_module!(module, name) do
    cond do
      not (is_atom(module) and Code.ensure_loaded?(module)) ->
        raise ConfigError, message: "#{name}: #{inspect(module)} is not a module that loads."

      not (function_exported?(module, :root_layout, 0) and function_exported?(module, :page_html, 0)) ->
        raise ConfigError,
          message: """
          #{name}: #{inspect(module)} must define root_layout/0 and page_html/0:

              use Brando.Site.Frontend,
                root_layout: {MyAppWeb.Sites.Acme.Layouts, :root},
                page_html: MyAppWeb.Sites.Acme.PageHTML
          """

      true ->
        :ok
    end
  end

  defp raise_invalid_key(key) do
    raise ConfigError,
      message: """
      Invalid :site_frontends key: #{inspect(key)}.

      Expected a site key or a {site_key, environment_key} tuple of lowercase,
      URL-safe keys, for example "acme" or {"acme", "staging"}.
      """
  end
end
