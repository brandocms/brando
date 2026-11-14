defmodule Brando.I18n do
  @moduledoc """

  ### Routing

  In your `router.ex`

      scope "/", assigns: %{language: "en"} do
        pipe_through :browser
        get "/news", MyAppWeb.PostController, :list
        get "/news/:slug", MyAppWeb.PostController, :detail

        scope "/no", as: :no, assigns: %{language: "no"} do
          get "/nyheter", MyAppWeb.PostController, :list
          get "/nyheter/:slug", MyAppWeb.PostController, :detail
        end

        page_routes()
      end

  You can also scope your default language. Remember to set
  `config :brando, scope_default_language_routes: true` to ensure correct routes are generated
  when using `localized_path` in your templates. To scope your default language in your router:

       scope "/" do
         pipe_through :browser

         scope "/en", as: :en, assigns: %{language: "en"} do
           get "/news", MyAppWeb.PostController, :list
           get "/news/:slug", MyAppWeb.PostController, :detail
         end

         scope "/no", as: :no, assigns: %{language: "no"} do
           get "/nyheter", MyAppWeb.PostController, :list
           get "/nyheter/:slug", MyAppWeb.PostController, :detail
         end

        page_routes()
       end

  In your controller:

      def list(conn, _params) do
        language = Map.get(conn.assigns, :language)
        list_opts = %{filter: %{language: language}}

        with {:ok, posts} <- News.list_posts(list_opts) do
          conn
          |> assign(:posts, posts)
          |> put_section("news")
          |> render(:list)
        end
      end

  In your templates: (import Brando.I18n.Helpers)

      <a href="<%= localized_path(@language, :post_path, [@conn, :list]) %>"><%= gettext("List posts") %></a>


  """
  import Plug.Conn, only: [put_session: 3, assign: 3]

  @doc """
  Put `language` in session.
  """
  def put_language(conn, language), do: put_session(conn, :language, language)

  @doc """
  Put `language` in assigns.
  """
  def assign_language(conn, language), do: assign(conn, :language, language)

  @spec get_language(atom | %{assigns: map}) :: any
  @doc """
  Get `language` from assigns.
  """
  def get_language(conn), do: Map.get(conn.assigns, :language, Brando.config(:default_admin_language))

  @doc "Whether the site has only one content language. See `Brando.I18n.SingleLanguage`."
  defdelegate single_language?(form \\ nil), to: Brando.I18n.SingleLanguage

  @doc """
  Extract language from path or fall back to default language.

  The languages are `site`'s (`Brando.Languages`); by default the site the
  process works for, else the installation's. A first segment that is not one
  of them is not a locale.
  """
  @spec parse_path(list, map() | nil | :current) :: {language :: binary, modified_path :: list} | nil
  def parse_path(path, site \\ :current)

  def parse_path([], site), do: {to_string(default_language(site)), ["index"]}

  def parse_path([first_path_segment | rest] = path, site) do
    if first_path_segment in codes(site) do
      (Enum.empty?(rest) && {first_path_segment, ["index"]}) || {first_path_segment, rest}
    else
      {to_string(default_language(site)), path}
    end
  end

  defp codes(:current), do: Brando.Languages.codes()
  defp codes(site), do: Brando.Languages.codes(site)

  defp default_language(:current), do: Brando.Languages.default_language()
  defp default_language(site), do: Brando.Languages.default_language(site)
end
