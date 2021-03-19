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
           page_routes()
         end

         scope "/no", as: :no, assigns: %{language: "no"} do
           get "/nyheter", MyAppWeb.PostController, :list
           get "/nyheter/:slug", MyAppWeb.PostController, :detail
           page_routes()
         end
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

  In your templates:

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
  def get_language(conn),
    do: Map.get(conn.assigns, :language, Brando.config(:default_admin_language))

  @doc """
  Extract language from path or fall back to default language
  """
  @spec parse_path(list) :: {language :: binary, modified_path :: list} | nil
  def parse_path([]), do: {Brando.config(:default_language), ["index"]}

  def parse_path(path) do
    [first_path_segment | rest] = path

    langs =
      :languages
      |> Brando.config()
      |> List.flatten()
      |> Keyword.get_values(:value)

    if first_path_segment in langs do
      (Enum.empty?(rest) && {first_path_segment, ["index"]}) || {first_path_segment, rest}
    else
      {Brando.config(:default_language), path}
    end
  end
end
