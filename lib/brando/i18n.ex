defmodule Brando.I18n do
  @moduledoc """
  Helper functions for I18n.
  """
  import Plug.Conn, only: [put_session: 3, assign: 3]

  @doc """
  Put `language` in session.
  """
  def put_language(conn, language), do:
    put_session(conn, :language, language)

  @doc """
  Put `language` in assigns.
  """
  def assign_language(conn, language), do:
    assign(conn, :language, language)

  @doc """
  Get `language` from assigns.
  """
  def get_language(conn), do:
    Map.get(conn.assigns, :language, Brando.config(:default_admin_language))

  @doc """
  Puts `language` as locale for all registered gettext modules
  """
  def put_locale_for_all_modules(language) do
    modules = Brando.Registry.gettext_modules()

    for module <- modules do
      Gettext.put_locale(module, language)
    end
  end
end
