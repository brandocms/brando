defmodule Brando.I18n do
  @moduledoc """
  Helper functions for I18n.
  """
  import Plug.Conn, only: [put_session: 3, assign: 3]

  @doc """
  Put `language` in session.
  """
  def put_language(conn, language) do
    put_session(conn, :language, language)
  end

  @doc """
  Put `language` in assigns.
  """
  def assign_language(conn, language) do
    assign(conn, :language, language)
  end

  @doc """
  Get `language` from assigns.
  """
  def get_language(conn) do
    Map.get(conn.assigns, :language, Brando.config(:default_admin_language))
  end
end
