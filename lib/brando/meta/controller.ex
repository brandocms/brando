defmodule Brando.Meta.Controller do
  @moduledoc """
  Functions for putting and getting meta keys on `conn`.
  Usually you would only deal with setting meta keys, the getting is handled in your
  `app.html.eex` template.

  ## Example

      conn =
        conn
        |> put_meta("og:title", title)
        |> put_meta("og:site_name", app_name)
        |> put_meta("og:type", "article")
  """

  import Plug.Conn, only: [put_private: 3]

  @doc """
  Puts `key` with `value` in `:brando_meta` key in `conn.private`.
  """
  def put_meta(conn, key, value) do
    meta =
      conn
      |> get_meta
      |> Map.put(key, value)

    put_private(conn, :brando_meta, meta)
  end

  @doc """
  Merges `opts` in with `:brando_meta` key in `conn.private`.
  """
  def put_meta(conn, opts) do
    meta =
      conn
      |> get_meta
      |> Map.merge(opts)

    put_private(conn, :brando_meta, meta)
  end

  @doc """
  Get all `:brando_meta` keys from `conn.private`
  """
  def get_meta(conn) do
    conn.private[:brando_meta] || %{}
  end

  @doc """
  Get `key` from `:brando_meta` map in `conn.private`.
  """
  def get_meta(conn, key) do
    Map.get(conn.private[:brando_meta], key)
  end
end
