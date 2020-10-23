defmodule Brando.Plug.I18n do
  @moduledoc """
  A plug for checking i18n
  """
  import Brando.Utils, only: [current_user: 1]
  alias Brando.I18n

  @doc """
  Assign current locale.

  If the locale was already found in `conn`'s session, so we set it
  through Gettext as well as assigning it to `conn`.

  Otherwise adds to session and assigns, and sets it through gettext
  """
  @spec put_locale(Plug.Conn.t(), Keyword.t()) :: Plug.Conn.t()
  def put_locale(%{private: %{plug_session: %{"language" => _}}} = conn, []) do
    {extracted_language, _} = I18n.parse_path(conn.path_info)
    Gettext.put_locale(Brando.web_module(Gettext), extracted_language)

    conn
    |> I18n.put_language(extracted_language)
    |> I18n.assign_language(extracted_language)
  end

  def put_locale(conn, []) do
    {extracted_language, _} = I18n.parse_path(conn.path_info)
    Gettext.put_locale(Brando.web_module(Gettext), extracted_language)

    conn
    |> I18n.put_language(extracted_language)
    |> I18n.assign_language(extracted_language)
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
end
