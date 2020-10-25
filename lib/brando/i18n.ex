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
