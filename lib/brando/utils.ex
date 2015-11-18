defmodule Brando.Utils do
  @moduledoc """
  Assorted utility functions.
  """

  import Ecto.Query

  @doc """
  Converts `string` to an ascii slug. Removes all unicode, spaces,
  extraneous dashes and punctuation and downcases the slug
  """
  @spec slugify(String.t) :: String.t
  def slugify(string), do:
    Slugger.slugify_downcase(string)

  @doc """
  Converts `filename` to an ascii slug, as per slugify/1.
  This function retains the extension of the filename, only converting
  the basename.

  ## Example

        iex(1)> slugify_filename("test with spaces.jpeg")
        "test-with-spaces.jpeg"

  """
  def slugify_filename(filename) do
    {basename, ext} = split_filename(filename)
    slugged_filename = slugify(basename)
    "#{slugged_filename}#{ext}"
  end

  @doc """
  Generates a random basename for `filename`.
  Keeps the original extension.
  """
  def random_filename(filename) do
    ext = Path.extname(filename)
    rnd_basename =
      ({filename, :os.timestamp}
      |> :erlang.phash2
      |> Integer.to_string(32)
      |> String.downcase) <>
      ({:os.timestamp, filename}
      |> :erlang.phash2
      |> Integer.to_string(32)
      |> String.downcase)
    "#{rnd_basename}#{ext}"
  end

  @doc """
  Adds an unique postfix to `filename`
  """
  def unique_filename(filename) do
    ext = Path.extname(filename)
    base = String.replace(filename, ext, "")
    rnd_basename =
      {filename, :os.timestamp}
      |> :erlang.phash2
      |> Integer.to_string(32)
      |> String.downcase
    base <> "-" <> rnd_basename <> ext
  end

  @doc """
  Splits `file` (a path and filename).
  Return {`path`, `filename`}

  ## Example

      iex> split_path("test/dir/filename.jpg")
      {"test/dir", "filename.jpg"}
  """
  def split_path(file) do
    case String.contains?(file, "/") do
      true ->
        filename =
          file
          |> Path.split
          |> List.last
        path =
          file
          |> Path.split()
          |> List.delete_at(-1)
          |> Path.join
        {path, filename}
      false ->
        {"", file}
    end
  end

  @doc """
  Splits `filename` into `basename` and `extension`
  Return {`basename`, `ext`}

  ## Example

      iex> split_filename("filename.jpg")
      {"filename", ".jpg"}
  """
  def split_filename(filename) do
    ext = Path.extname(filename)
    basename = Path.basename(filename, ext)
    {basename, ext}
  end

  @doc """
  Converts `coll` (if it's a struct) to a map with string keys
  """
  def to_string_map(nil), do: nil
  def to_string_map(coll) do
    case Map.has_key?(coll, :__struct__) do
      true ->
        coll
        |> Map.delete(:__struct__)
        |> Enum.map(fn({k, v}) -> {Atom.to_string(k), v} end)
        |> Enum.into(%{})
      false -> coll
    end
  end

  @doc """
  Maybe implementation. If `arg1` is nil, do nothing.
  Else, invoke `fun` on `item`.
  """
  def maybe(nil, _fun), do: nil
  def maybe(item, fun), do: fun.(item)

  @doc """
  Converts an ecto datetime record to ISO 8601 format.
  """
  @spec to_iso8601(Ecto.DateTime.t) :: String.t
  def to_iso8601(dt) do
    list = [dt.year, dt.month, dt.day, dt.hour, dt.min, dt.sec]
    "~4..0B-~2..0B-~2..0BT~2..0B:~2..0B:~2..0BZ"
    |> :io_lib.format(list)
    |> IO.iodata_to_binary
  end

  @doc """
  Convert string map to struct
  """
  def stringy_struct(string_struct, params) when is_map(params) do
    keys =
      string_struct
      |> struct([])
      |> Map.from_struct
      |> Map.keys
      |> Enum.map(&Atom.to_string/1)

    params =
      params
      |> Map.take(keys)
      |> Enum.map(fn {key, value} -> {String.to_atom(key), value} end)

    struct(string_struct, params)
  end

  @doc false
  def get_now do
    Ecto.DateTime.to_string(Ecto.DateTime.local)
  end

  @doc false
  def get_date_now do
    Ecto.Date.to_string(Ecto.Date.local)
  end

  @doc """
  Split `records` by `attr`.

  Creates a new map with `attr`'s values as keys
  """
  def split_by(records, attr) do
    {_, split_records} = Enum.map_reduce records, %{}, fn(record, agg) ->
      insert =
        if agg[Map.get(record, attr)] do
          [record|agg[Map.get(record, attr)]]
        else
          [record]
        end
      {record, Map.put(agg, Map.get(record, attr), insert)}
    end
    split_records
  end

  @doc """
  Search `model`'s tags field for `tags`
  """
  def search_model_by_tag(model, tag) do
    model |> where([m], ^tag in m.tags)
  end

  @doc """
  Returns scheme, host and port (if non-standard)
  """
  @spec hostname(Plug.Conn.t) :: String.t
  def hostname(conn) do
    port = conn.port == 80 && "" || ":#{conn.port}"
    "#{conn.scheme}://#{conn.host}#{port}"
  end

  @doc """
  Returns full url path with scheme and host.
  """
  @spec current_url(Plug.Conn.t) :: String.t
  def current_url(conn) do
    "#{hostname(conn)}#{conn.request_path}"
  end

  @doc """
  Returns URI encoded www form of current url
  """
  @spec escape_current_url(Plug.Conn.t) :: String.t
  def escape_current_url(conn) do
    conn
    |> current_url
    |> URI.encode_www_form
  end

  @doc """
  Prefix `media` with scheme / host and port from `conn`.
  Returns URI encoded www form.
  """
  @spec escape_and_prefix_host(Plug.Conn.t, String.t) :: String.t
  def escape_and_prefix_host(conn, media) do
    port = conn.port == 80 && "" || ":#{conn.port}"
    "#{conn.scheme}://#{conn.host}#{port}#{media}"
    |> URI.encode_www_form
  end

  @doc """
  Return joined path of `file` and the :media_url config option
  as set in your app's config.exs.
  """
  def media_url() do
    Brando.config(:media_url)
  end
  def media_url(nil) do
    Brando.config(:media_url)
  end
  def media_url(file) do
    Path.join([Brando.config(:media_url), file])
  end

  @doc """
  Get title assign from `conn`
  """
  def get_page_title(%{assigns: %{page_title: title}}) do
    Brando.config(:app_name) <> " | " <> title
  end
  def get_page_title(_) do
    Brando.config(:app_name)
  end

  @doc """
  Returns hostname and media directory.
  """
  @spec host_and_media_url(Plug.Conn.t) :: String.t
  def host_and_media_url(conn) do
    "#{hostname(conn)}#{Brando.config(:media_url)}"
  end

  @doc """
  Runs some config checks.
  """
  def run_checks do
    case Brando.config(:media_path) do
      "" ->
        raise Brando.Exception.ConfigError,
              message: "config :brando, :media_path must be an absolute " <>
                       "path to your media/ directory, e.g. " <>
                       "/sites/prod/my_app/media"
      nil ->
        raise Brando.Exception.ConfigError,
              message: "config :brando, :media_path must be set!"
      media_path ->
        unless String.starts_with?(media_path, "/") do
          raise Brando.Exception.ConfigError,
                message: "config :brando, :media_path must be an absolute path."
        end
    end
  end

  @doc """
  Returns the Helpers module from the router.
  """
  def helpers(conn) do
    Phoenix.Controller.router_module(conn).__helpers__
  end

  @doc """
  Return the current user set in session.
  """
  def current_user(conn) do
    Plug.Conn.get_session(conn, :current_user)
  end

  @doc """
  Checks if `conn`'s `full_path` matches `current_path`.
  """
  @spec active_path(Plug.Conn.t, String.t) :: boolean
  def active_path(conn, url_to_match) do
    conn.request_path == url_to_match
  end

  @doc """
  Returns the application name set in config.exs
  """
  def app_name do
    Brando.config(:app_name)
  end

  @doc """
  Grabs `size` from the `image_field` json struct.
  If default is passed, return size_dir of `default`.
  Returns path to image.
  """
  def img_url(image_field, size, opts \\ [])
  def img_url(nil, size, opts) do
    default = Keyword.get(opts, :default, nil)
    default && Brando.Images.Utils.size_dir(default, size)
            || ""
  end

  def img_url(image_field, size, opts) do
    size = is_atom(size) && Atom.to_string(size) || size
    prefix = Keyword.get(opts, :prefix, nil)
    url = prefix && Path.join([prefix, image_field.sizes[size]])
                 || image_field.sizes[size]
    case Map.get(image_field, :optimized) do
      true  -> Brando.Images.Utils.optimized_filename(url)
      false -> url
      nil   -> url
    end
  end
end
