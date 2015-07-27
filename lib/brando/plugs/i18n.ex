defmodule Brando.Plug.I18n do
  @moduledoc """
  A plug for checking i18n
  """
  import Brando.I18n

  def set_locale(%{private: %{plug_session: %{"language" => language}}} = conn, _) do
    language = check_path(conn) || language
    conn
    |> assign_language(language)
  end

  def set_locale(conn, _) do
    language = check_path(conn) || Brando.config(:default_language)
    conn
    |> put_language(language)
    |> assign_language(language)
  end

  def check_path(conn) do
    if lang = List.first(conn.path_info) do
      langs =
        Brando.config(:languages)
        |> List.flatten
        |> Keyword.get_values(:value)
      if lang in langs do
        lang
      end
    end
  end
end