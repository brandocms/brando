defmodule Brando.Utils do
  @moduledoc """
  Assorted utility functions.
  """
  @filtered_deps [
    :brando,
    :brando_analytics,
    :brando_blog,
    :brando_instagram,
    :brando_news,
    :brando_pages,
    :brando_portfolio,
    :brando_villain,
    :hrafn
  ]

  @kb_size 1024
  @mb_size 1024 * @kb_size

  @sec_time 1000
  @min_time 60 * @sec_time
  @hour_time 60 * @min_time
  @day_time 24 * @hour_time

  @doc """
  Converts `string` to an ascii slug. Removes all unicode, spaces,
  extraneous dashes and punctuation and downcases the slug
  """
  @spec slugify(String.t()) :: String.t()
  def slugify(string), do: Slugger.slugify_downcase(string)

  @doc """
  Converts `filename` to an ascii slug, as per slugify/1.
  This function retains the extension of the filename, only converting
  the basename.

  ## Example

        iex(1)> slugify_filename("test with spaces.jpeg")
        "test-with-spaces.jpeg"

  """
  @spec slugify_filename(String.t()) :: String.t()
  def slugify_filename(filename) do
    {basename, ext} = split_filename(filename)
    slugged_filename = slugify(basename)
    "#{slugged_filename}#{ext}"
  end

  @doc """
  Generates a random basename for `filename`.
  Keeps the original extension.
  """
  @spec random_filename(String.t()) :: String.t()
  def random_filename(filename) do
    ext = Path.extname(filename)

    rnd_basename_1 =
      {filename, :os.timestamp()}
      |> :erlang.phash2()
      |> Integer.to_string(32)
      |> String.downcase()

    rnd_basename_2 =
      {:os.timestamp(), filename}
      |> :erlang.phash2()
      |> Integer.to_string(32)
      |> String.downcase()

    "#{rnd_basename_1}#{rnd_basename_2}#{ext}"
  end

  @doc """
  Adds an unique postfix to `filename`
  """
  @spec unique_filename(String.t()) :: String.t()
  def unique_filename(filename) do
    ext = Path.extname(filename)
    base = String.replace(filename, ext, "")

    rnd_basename =
      {filename, :os.timestamp()}
      |> :erlang.phash2()
      |> Integer.to_string(32)
      |> String.downcase()

    "#{base}-#{rnd_basename}#{ext}"
  end

  @doc """
  Splits `file` (a path and filename).
  Return {`path`, `filename`}

  ## Example

      iex> split_path("test/dir/filename.jpg")
      {"test/dir", "filename.jpg"}
  """
  @spec split_path(String.t()) :: {String.t(), String.t()}
  def split_path(file) do
    if String.contains?(file, "/") do
      filename =
        file
        |> Path.split()
        |> List.last()

      path =
        file
        |> Path.split()
        |> List.delete_at(-1)
        |> Path.join()

      {path, filename}
    else
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
  @spec split_filename(String.t()) :: {String.t(), String.t()}
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
    if Map.has_key?(coll, :__struct__) do
      coll
      |> Map.delete(:__struct__)
      |> Enum.map(fn {k, v} -> {Atom.to_string(k), v} end)
      |> Enum.into(%{})
    else
      coll
    end
  end

  @doc """
  Converts `coll` to a map with safe atom keys
  """
  def to_atom_map(coll) do
    for {key, val} <- coll, into: %{} do
      if is_atom(key), do: {key, val}, else: {String.to_existing_atom(key), val}
    end
  end

  @doc """
  Convert string map to struct
  """
  def stringy_struct(string_struct, params) when is_map(params) do
    keys =
      string_struct
      |> struct([])
      |> Map.from_struct()
      |> Map.keys()
      |> Enum.map(&Atom.to_string/1)

    params =
      params
      |> Map.take(keys)
      |> Enum.map(fn {key, value} -> {String.to_atom(key), value} end)

    struct(string_struct, params)
  end

  @doc """
  Returns current date & time
  """
  @spec get_now :: String.t()
  def get_now do
    :calendar.local_time()
    |> NaiveDateTime.from_erl!()
    |> NaiveDateTime.to_string()
  end

  @doc """
  Returns current date
  """
  @spec get_date_now :: String.t()
  def get_date_now do
    :calendar.local_time()
    |> elem(0)
    |> Date.from_erl!()
    |> Date.to_string()
  end

  @doc """
  Split `records` by `attr`.
  Creates a new map with `attr`'s values as keys
  """
  def split_by(records, attr) do
    {_, split_records} =
      Enum.map_reduce(records, %{}, fn record, agg ->
        insert =
          if agg[Map.get(record, attr)] do
            [record | agg[Map.get(record, attr)]]
          else
            [record]
          end

        {record, Map.put(agg, Map.get(record, attr), insert)}
      end)

    split_records
  end

  @doc """
  Returns scheme, host and port (if non-standard)
  """
  @spec hostname() :: String.t()
  def hostname() do
    url_cfg = Brando.endpoint().config(:url)
    scheme = Keyword.get(url_cfg, :scheme, "http")
    host = Keyword.get(url_cfg, :host, "localhost")
    "#{scheme}://#{host}"
  end

  @doc """
  Returns full url path with scheme and host.
  """
  @spec current_url(Plug.Conn.t(), String.t()) :: String.t()
  def current_url(conn, url \\ nil) do
    path = (url && url) || conn.request_path
    "#{hostname()}#{path}"
  end

  @doc """
  Returns URI encoded www form of current url
  """
  @spec escape_current_url(Plug.Conn.t()) :: String.t()
  def escape_current_url(conn) do
    conn
    |> current_url
    |> URI.encode_www_form()
  end

  @doc """
  Prefix `media` with scheme / host and port from `conn`.
  Returns URI encoded www form.
  """
  @spec escape_and_prefix_host(Plug.Conn.t(), String.t()) :: String.t()
  def escape_and_prefix_host(conn, media) do
    url = current_url(conn, media)
    URI.encode_www_form(url)
  end

  @doc """
  Return link with :https scheme
  """
  def https_url(conn) do
    port = (conn.port == 80 && "") || ":#{conn.port}"
    "https://#{conn.host}#{port}#{conn.request_path}"
  end

  @doc """
  Return joined path of `file` and the :media_url config option
  as set in your app's config.exs.
  """
  @spec media_url :: String.t() | nil
  def media_url do
    Brando.config(:media_url)
  end

  @spec media_url(String.t() | nil) :: String.t() | nil
  def media_url(nil) do
    Brando.config(:media_url)
  end

  def media_url(file) do
    Path.join([Brando.config(:media_url), file])
  end

  @doc """
  Get title assign from `conn`
  """
  @spec get_page_title(Plug.Conn.t()) :: String.t()
  def get_page_title(%{assigns: %{page_title: title}}) do
    (Brando.config(:title_prefix) && Brando.config(:title_prefix) <> title) ||
      Brando.config(:app_name) <> " | " <> title
  end

  def get_page_title(_) do
    Brando.config(:app_name)
  end

  @doc """
  Returns hostname and media directory.
  """
  @spec host_and_media_url() :: String.t()
  def host_and_media_url() do
    hostname() <> Brando.config(:media_url)
  end

  @doc """
  Runs some config checks.
  """
  def run_checks do
    # noop, deprecated
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
  defdelegate current_user(conn), to: Guardian.Plug, as: :current_resource

  @doc """
  Checks if `conn`'s `full_path` matches `current_path`.
  """
  @spec active_path?(Plug.Conn.t(), String.t()) :: boolean
  def active_path?(conn, url_to_match) do
    current_path = Path.join(["/" | conn.path_info])
    chunks = String.split(url_to_match, "/")

    {url, current_path} =
      if List.last(chunks) == "*" do
        url_without_star =
          chunks
          |> List.delete_at(Enum.count(chunks) - 1)
          |> Enum.reject(&(&1 == ""))

        chunks_count = Enum.count(url_without_star)

        split_current_path =
          current_path
          |> String.split("/")
          |> Enum.reject(&(&1 == ""))

        shortened_path =
          for {path, x} <- Enum.with_index(split_current_path) do
            if x < chunks_count do
              path
            else
              ""
            end
          end
          |> Enum.reject(&(&1 == ""))
          |> Enum.join("/")


        {Enum.join(url_without_star, "/"), shortened_path}
      else
        {url_to_match, current_path}
      end

    current_path == url
  end

  @doc """
  Returns the application name set in config.exs
  """
  def app_name do
    Brando.config(:app_name)
  end

  @doc """
  Grabs `path` from the file field struct
  """
  def file_url(file_field, opts \\ [])

  def file_url(nil, _) do
    nil
  end

  def file_url(file_field, opts) do
    prefix = Keyword.get(opts, :prefix, nil)
    (prefix && Path.join([prefix, file_field.path])) || file_field.path
  end

  @doc """
  Grabs `size` from the `image_field` json struct.
  If default is passed, return size_dir of `default`.
  Can also be passed `:original` as `size` to pass unmodified image.
  Returns path to image.
  """
  def img_url(image_field, size, opts \\ [])

  def img_url(nil, size, opts) do
    default = Keyword.get(opts, :default, nil)
    (default && Brando.Images.Utils.size_dir(default, size)) || ""
  end

  def img_url("", size, opts) do
    default = Keyword.get(opts, :default, nil)
    (default && Brando.Images.Utils.size_dir(default, size)) || ""
  end

  def img_url(image_field, :original, opts) do
    prefix = Keyword.get(opts, :prefix, nil)
    (prefix && Path.join([prefix, image_field.path])) || image_field.path
  end

  def img_url(image_field, size, opts) do
    size = (is_atom(size) && Atom.to_string(size)) || size
    prefix = Keyword.get(opts, :prefix, nil)

    size_dir =
      try do
        if Map.has_key?(image_field.sizes, size) do
          image_field.sizes[size]
        else
          IO.warn(
            ~s(Wrong key for img_url. Size `#{size}` does not exist for #{inspect(image_field)})
          )

          "non_existing"
        end
      rescue
        KeyError ->
          if Map.has_key?(image_field["sizes"], size) do
            image_field["sizes"][size]
          end
      end


    url = (prefix && Path.join([prefix, size_dir])) || size_dir

    case Map.get(image_field, :optimized) do
      true -> Brando.Images.Utils.optimized_filename(url)
      false -> url
      nil -> url
    end
  end

  @doc """
  Return `size` as human formatted size

  Example:
  iex(1)> Brando.Utils.human_size(100000000)
  "95 MB"
  """
  def human_size(size) when size < @kb_size * 10,
    do: "#{human_spaced_number(size)} B"

  def human_size(size) when size < @mb_size * 10,
    do: "#{human_spaced_number(div(size, @kb_size))} kB"

  def human_size(size),
    do: "#{human_spaced_number(div(size, @mb_size))} MB"

  @doc """
  Return `ms` as human formatted time

  Example:
  iex(1)> Brando.Utils.human_time(1000000000)
  "11 days"
  """
  def human_time(ms) when ms < @min_time,
    do: "#{human_spaced_number(div(ms, @sec_time))} secs"

  def human_time(ms) when ms < @hour_time,
    do: "#{human_spaced_number(div(ms, @min_time))} mins"

  def human_time(ms) when ms < @day_time,
    do: "#{human_spaced_number(div(ms, @hour_time))} hours"

  def human_time(ms),
    do: "#{human_spaced_number(div(ms, @day_time))} days"

  @doc """
  Show binary `string` as a spaced number

  Example:
  iex(1)> Brando.Utils.human_spaced_number("1000000000")
  "1 000 000 000"
  """
  def human_spaced_number(string) when is_binary(string) do
    split = rem(byte_size(string), 3)
    string = :erlang.binary_to_list(string)
    {first, rest} = Enum.split(string, split)
    rest = Enum.chunk_every(rest, 3) |> Enum.map(&[" ", &1])
    IO.iodata_to_binary([first, rest]) |> String.trim_leading()
  end

  def human_spaced_number(int) when is_integer(int) do
    human_spaced_number(Integer.to_string(int))
  end

  def get_deps_versions do
    :application.which_applications()
    |> Enum.filter(&(elem(&1, 0) in @filtered_deps))
    |> Enum.reverse()
    |> Enum.map(&%{app: elem(&1, 0), version: to_string(elem(&1, 2))})
  end
end
