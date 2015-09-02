defmodule Brando.Plug.I18n do
  @moduledoc """
  A plug for checking i18n
  """
  import Brando.I18n

  @doc """
  Assign current language.

  Here it already is in `conn`, so we only add to `conn.assigns`
  """
  def put_locale(%{private: %{plug_session: %{"language" => lang}}} = conn, _) do
    lang = check_path(conn) || lang
    assign_language(conn, lang)
  end

  @doc """
  Add current language to `conn`.

  Adds to session and assigns
  """
  def put_locale(conn, _) do
    language = check_path(conn) || Brando.config(:default_language)
    conn
    |> put_language(language)
    |> assign_language(language)
  end

  @doc """
  Add language from current_user to `conn`'s assigns.

  This is separated from `put_locale` since we can have different
  languages on the frontend and on the backend.
  """
  def put_admin_locale(%{private: %{plug_session: %{"current_user" => current_user}}} = conn, _) do
    default_language = Brando.config(:default_admin_language)
    assign_language(conn, Map.get(current_user, :language, default_language))
  end

  @doc """
  Add default language to `conn`'s assigns.
  """
  def put_admin_locale(conn, _) do
    conn
    |> assign_language(Brando.config(:default_admin_language))
  end

  defp check_path(conn) do
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
