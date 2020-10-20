defmodule Brando.I18n do
  @moduledoc """

  ### Routing

  In your `router.ex`

      scope "/", assigns: %{language: "no"} do
        pipe_through :browser

        get "/switch-language/:language", Brando.I18nController, :switch_language

        # collections // english
        scope "/en", assigns: %{language: "en"}, as: "en" do
          get "/projects", ProjectController, :list
          get "/project/:slug", ProjectController, :detail
        end

        get "/*path", PageController, :show
      end

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

  @doc """
  Get `language` from assigns.
  """
  def get_language(conn),
    do: Map.get(conn.assigns, :language, Brando.config(:default_admin_language))
end
