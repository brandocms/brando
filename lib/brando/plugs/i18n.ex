defmodule Brando.Plug.I18n do
  @moduledoc """
  A plug for checking i18n
  """
  import Brando.I18n
  import Brando.Utils, only: [current_user: 1]

  @doc """
  Assign current locale.

  If the locale was already found in `conn`'s session, so we set it
  through Gettext as well as assigning it to `conn`.

  Otherwise adds to session and assigns, and sets it through gettext
  """
  @spec put_locale(Plug.Conn.t(), Keyword.t()) :: Plug.Conn.t()
  def put_locale(%{private: %{plug_session: %{"language" => language}}} = conn, []) do
    language = extract_language_from_path(conn) || language
    Gettext.put_locale(Brando.app_module(Gettext), language)

    conn
    |> put_language(language)
    |> assign_language(language)
  end

  def put_locale(conn, []) do
    language = extract_language_from_path(conn)
    Gettext.put_locale(Brando.app_module(Gettext), language)

    conn
    |> put_language(language)
    |> assign_language(language)
  end

  @doc """
  Set locale to current user's language

  This sets both Brando.Gettext (the default gettext we use in the backend),
  as well as delegating to the I18n module for setting proper locale for all
  registered gettext modules.
  """
  @spec put_admin_locale(Plug.Conn.t(), Keyword.t()) :: Plug.Conn.t()
  def put_admin_locale(conn, []) do
    language =
      case current_user(conn) do
        nil ->
          Brando.config(:default_admin_language)

        user ->
          Map.get(user, :language, Brando.config(:default_admin_language))
      end

    # set for default brando backend
    Gettext.put_locale(Brando.Gettext, language)
    conn
  end

  @spec extract_language_from_path(Plug.Conn.t()) :: binary | nil
  defp extract_language_from_path(conn) do
    lang = List.first(conn.path_info)

    if lang do
      langs =
        :languages
        |> Brando.config()
        |> List.flatten()
        |> Keyword.get_values(:value)

      if lang in langs, do: lang, else: Brando.config(:default_language)
    else
      Brando.config(:default_language)
    end
  end
end
