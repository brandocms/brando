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
  def put_meta(conn, _key, "") do
    conn
  end

  def put_meta(conn, _key, nil) do
    conn
  end

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

  @doc """
  Extract all possible meta information from a record, including
    * cover image (`cover`)
    * `meta_title`
    * `meta_description`
  """
  def extract_meta(conn, record) do
    meta_image =
      if Map.get(record, :cover, nil) do
        Enum.join(
          [
            Brando.Utils.host_and_media_url(),
            record.cover.sizes["crop_lg"]
          ],
          "/"
        )
      else
        nil
      end

    meta_title = Map.get(record, :meta_title, nil)

    conn =
      conn
      |> put_meta("description", record.meta_description)
      |> put_meta("og:description", record.meta_description)

    conn =
      if meta_image do
        put_meta(conn, "og:image", meta_image)
      else
        conn
      end

    if meta_title do
      put_meta(conn, "title", meta_title)
    else
      conn
    end
  end
end
