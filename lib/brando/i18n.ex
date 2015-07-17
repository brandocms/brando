defmodule Brando.I18n do
  @moduledoc """
  Helper functions for I18n.
  """
  import Plug.Conn, only: [put_session: 3]

  @doc """
  Put `language` in session.
  """
  def put_language(conn, language) do
    conn |> put_session(:language, language)
  end
end