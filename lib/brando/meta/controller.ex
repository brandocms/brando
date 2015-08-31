defmodule Brando.Meta.Controller do
  @moduledoc """
  Functions for putting and getting meta keys on `conn`.
  """

  import Plug.Conn, only: [put_private: 3]

  @doc """
  Puts `key` with `value` in `:brando_meta` key in `conn.private`.
  """
  def put_meta(conn, key, value) do
    meta =
      get_meta(conn)
      |> Map.put(key, value)

    conn
    |> put_private(:brando_meta, meta)
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