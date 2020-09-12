defmodule Brando.Utils do
  @moduledoc """
  Assorted utility functions.
  """

  alias Brando.Cache

  @type changeset :: Ecto.Changeset.t()
  @type conn :: Plug.Conn.t()

  @filtered_deps [
    :brando,
    :brando_analytics,
    :brando_blog,
    :brando_instagram,
    :brando_news,
    :brando_pages,
    :brando_portfolio,
    :brando_villain
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
  @spec slugify(binary) :: binary
  def slugify(string), do: Slugger.slugify_downcase(string)

  @doc """
  Converts `filename` to an ascii slug, as per slugify/1.
  This function retains the extension of the filename, only converting
  the basename.

  ## Example

        iex(1)> slugify_filename("test with spaces.jpeg")
        "test-with-spaces.jpeg"

  """
  @spec slugify_filename(binary) :: binary
  def slugify_filename(filename) do
    {basename, ext} = split_filename(filename)
    slugged_filename = slugify(basename)
    ext = String.downcase(ext)
    "#{slugged_filename}#{ext}"
  end

  @doc """
  Generates a random basename for `filename`.
  Keeps the original extension.
  """
  @spec random_filename(binary) :: binary
  def random_filename(filename) do
    ext = filename |> Path.extname() |> String.downcase()
    random_str = random_string(filename)
    "#{random_str}#{ext}"
  end

  @doc """
  Sets a new basename for file.
  Keeps the original extension.
  """
  @spec change_basename(binary, binary) :: binary
  def change_basename(filename, new_basename) do
    ext = filename |> Path.extname() |> String.downcase()
    "#{new_basename}#{ext}"
  end

  @doc """
  Sets a new extension name for file
  """
  @spec change_extension(file :: binary, new_extension :: binary) :: binary
  def change_extension(file, new_extension) do
    Enum.join([Path.rootname(file), String.downcase(new_extension)], ".")
  end

  @doc """
  Sharp-cli for some dumb reason enforces the .jpg extension, so make sure that all jpegs are
  written as such.
  """
  @spec ensure_correct_extension(binary, atom | nil) :: binary
  def ensure_correct_extension(filename, type \\ nil) do
    if type do
      change_extension(filename, to_string(type))
    else
      case Path.extname(filename) |> String.downcase() do
        ".jpeg" ->
          change_extension(filename, "jpg")

        _ ->
          filename
      end
    end
  end

  @doc """
  Tries to access `keys` as a path to `map`
  """
  @spec try_path(map :: map, keys :: [atom] | nil) :: any | nil
  def try_path(_, nil), do: nil

  def try_path(map, keys) do
    Enum.reduce(keys, map, fn key, acc ->
      if acc, do: Map.get(acc, key)
    end)
  end

  @doc """
  Generate a random string from `seed`
  """
  def random_string(seed) do
    rnd_basename_1 =
      {seed, :os.timestamp()}
      |> :erlang.phash2()
      |> Integer.to_string(32)
      |> String.downcase()

    rnd_basename_2 =
      {:os.timestamp(), seed}
      |> :erlang.phash2()
      |> Integer.to_string(32)
      |> String.downcase()

    rnd_basename_1 <> rnd_basename_2
  end

  @doc """
  Adds an unique postfix to `filename`
  """
  @spec unique_filename(binary) :: binary
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
  @spec split_path(binary) :: {binary, binary}
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
  @spec split_filename(binary) :: {binary, binary}
  def split_filename(filename) do
    ext = Path.extname(filename)
    basename = Path.basename(filename, ext)
    {basename, ext}
  end

  @doc """
  Convert map atom keys to strings
  """
  def stringify_keys(nil), do: nil
  def stringify_keys(%{} = struct) when is_struct(struct), do: struct

  def stringify_keys(%{} = map) do
    map
    |> Enum.map(fn {k, v} -> {stringify_key(k), stringify_keys(v)} end)
    |> Enum.into(%{})
  end

  # Walk the list and stringify the keys of
  # of any map members
  def stringify_keys([head | rest]) do
    [stringify_keys(head) | stringify_keys(rest)]
  end

  def stringify_keys(not_a_map) do
    not_a_map
  end

  defp stringify_key(key) when is_atom(key), do: Atom.to_string(key)
  defp stringify_key(key), do: key

  def snake_case(map) when is_map(map) do
    map
    |> Enum.map(fn {k, v} -> {Recase.to_snake(k), snake_case(v)} end)
    |> Enum.into(%{})
  end

  def snake_case([head | rest]) do
    [snake_case(head) | snake_case(rest)]
  end

  def snake_case(not_a_map) do
    not_a_map
  end

  @doc """
  Converts `collection` to a map with safe atom keys
  """
  def to_atom_map(collection) do
    for {key, val} <- collection, into: %{} do
      if is_atom(key), do: {key, val}, else: {String.to_existing_atom(key), val}
    end
  end

  @doc """
  Convert string map to struct
  """
  def stringy_struct(string_struct, nil), do: struct(string_struct, %{})

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
  @spec get_now :: binary
  def get_now do
    :calendar.local_time()
    |> NaiveDateTime.from_erl!()
    |> NaiveDateTime.to_string()
  end

  @doc """
  Returns current date
  """
  @spec get_date_now :: binary
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
      records
      |> Enum.reverse()
      |> Enum.map_reduce(%{}, fn record, acc ->
        attr_in_record = Map.get(record, attr)

        insert =
          if acc[attr_in_record] do
            [record | acc[attr_in_record]]
          else
            [record]
          end

        {record, Map.put(acc, Map.get(record, attr), insert)}
      end)

    split_records
  end

  @doc """
  Returns scheme, host and port (if non-standard)
  """
  @spec hostname() :: binary
  @spec hostname(path :: binary) :: binary
  def hostname, do: "#{Brando.endpoint().url}"
  def hostname(path), do: Path.join(hostname(), path)

  @doc """
  Returns full url path with scheme and host.
  """
  @spec current_url(conn, binary | nil) :: binary
  def current_url(conn, url \\ nil) do
    path = url || conn.request_path
    Path.join(hostname(), path)
  end

  @doc """
  Returns URI encoded www form of current url
  """
  @spec escape_current_url(conn) :: binary
  def escape_current_url(conn) do
    conn
    |> current_url
    |> URI.encode_www_form()
  end

  @doc """
  Prefix `media` with scheme / host and port from `conn`.
  Returns URI encoded www form.
  """
  @spec escape_and_prefix_host(conn, binary) :: binary
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
  @spec media_url :: binary | nil
  def media_url, do: Brando.config(:media_url)
  @spec media_url(binary | nil) :: binary | nil
  def media_url(nil), do: Brando.config(:media_url)
  def media_url(path), do: Path.join([Brando.config(:media_url), path])

  @doc """
  Get title assign from `conn`
  """
  @spec get_page_title(conn) :: binary
  def get_page_title(%{assigns: %{page_title: title}}) do
    organization = Cache.get(:identity)

    if organization do
      %{title_prefix: title_prefix, title_postfix: title_postfix} = organization
      render_title(title_prefix, title, title_postfix)
    else
      ""
    end
  end

  def get_page_title(_) do
    organization = Cache.get(:identity)

    if organization do
      %{title_prefix: title_prefix, title: title, title_postfix: title_postfix} = organization
      render_title(title_prefix, title, title_postfix)
    else
      ""
    end
  end

  @spec render_title(binary | nil, binary, binary | nil) :: binary
  def render_title(nil, title, nil),
    do: "#{title}"

  def render_title(title_prefix, title, nil),
    do: "#{title_prefix}#{title}"

  def render_title(nil, title, title_postfix),
    do: "#{title}#{title_postfix}"

  def render_title(title_prefix, title, title_postfix),
    do: "#{title_prefix}#{title}#{title_postfix}"

  @doc """
  Returns hostname and media directory.
  """
  @spec host_and_media_url() :: binary
  def host_and_media_url do
    hostname() <> Brando.config(:media_url)
  end

  @doc """
  Returns the Helpers module from the router.
  """
  def helpers(conn), do: Phoenix.Controller.router_module(conn).__helpers__

  @doc """
  Return the current user set in session.
  """
  defdelegate current_user(conn), to: Guardian.Plug, as: :current_resource

  @doc """
  Checks if `conn`'s `full_path` matches `current_path`.
  """
  @spec active_path?(conn, binary) :: boolean
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
  def app_name, do: Brando.config(:app_name)

  @doc """
  Grabs `path` from the file field struct
  """
  def file_url(file_field, opts \\ [])
  def file_url(nil, _), do: nil

  def file_url(file_field, opts) do
    prefix = Keyword.get(opts, :prefix, nil)
    (prefix && Path.join([prefix, file_field.path])) || file_field.path
  end

  @doc """
  Create a cache string and return
  """
  def add_cache_string(opts) do
    case Keyword.get(opts, :cache, nil) do
      nil ->
        ""

      cache when is_binary(cache) ->
        "?#{cache}"

      cache ->
        stamp =
          cache
          |> DateTime.from_naive!("Etc/UTC")
          |> DateTime.to_unix()

        "?#{stamp}"
    end
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
    (default && Brando.Images.Utils.get_sized_path(default, size)) || "" <> add_cache_string(opts)
  end

  def img_url("", size, opts) do
    default = Keyword.get(opts, :default, nil)
    (default && Brando.Images.Utils.get_sized_path(default, size)) || "" <> add_cache_string(opts)
  end

  def img_url(image_field, :original, opts) do
    prefix = Keyword.get(opts, :prefix, nil)

    prefix =
      if image_field.cdn && Brando.CDN.enabled?() do
        if prefix do
          Path.join([Brando.CDN.get_prefix(), prefix])
        else
          Brando.CDN.get_prefix()
        end
      else
        prefix
      end

    (prefix && Path.join([prefix, image_field.path])) ||
      image_field.path <> add_cache_string(opts)
  end

  def img_url(image_field, size, opts) do
    size = (is_atom(size) && Atom.to_string(size)) || size
    size_dir = extract_size_dir(image_field, size)

    prefix = Keyword.get(opts, :prefix, nil)

    prefix =
      if image_field.cdn && Brando.CDN.enabled?() do
        if prefix do
          Path.join([Brando.CDN.get_prefix(), prefix])
        else
          Brando.CDN.get_prefix()
        end
      else
        prefix
      end

    url = (prefix && Path.join([prefix, size_dir])) || size_dir
    url <> add_cache_string(opts)
  end

  defp extract_size_dir(image_field, size) do
    if is_map(image_field.sizes) && Map.has_key?(image_field.sizes, size) do
      image_field.sizes[size]
    else
      IO.warn("""
      Wrong size key for img_url function.

      Size `#{size}` does not exist for image struct:

      #{inspect(image_field, pretty: true)})
      """)

      "non_existing"
    end
  rescue
    KeyError ->
      if Map.has_key?(image_field["sizes"], size) do
        image_field["sizes"][size]
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

  def human_spaced_number(int) when is_integer(int),
    do: human_spaced_number(Integer.to_string(int))

  @doc """
  Get dependencies' versions
  """
  def get_deps_versions do
    :application.which_applications()
    |> Enum.filter(&(elem(&1, 0) in @filtered_deps))
    |> Enum.reverse()
    |> Enum.map(&%{app: elem(&1, 0), version: to_string(elem(&1, 2))})
  end

  @doc """
  Checks changeset if `field_name` is changed.
  Returns :unchanged, or {:ok, change}
  """
  @spec field_has_changed(changeset, atom) :: {:ok, any()} | :unchanged
  def field_has_changed(changeset, field_name) do
    case Ecto.Changeset.get_change(changeset, field_name) do
      nil -> :unchanged
      change -> {:ok, change}
    end
  end

  @doc """
  Checks changeset for errors.
  No need to process upload if there are other errors.
  """
  @spec changeset_has_no_errors(changeset) :: {:ok, changeset} | :has_errors
  def changeset_has_no_errors(changeset) do
    case changeset.errors do
      [] -> {:ok, changeset}
      _ -> :has_errors
    end
  end

  @doc """
  Generates a secure cookie based on `:crypto.strong_rand_bytes/1`.
  """
  @spec generate_secure_cookie() :: atom
  def generate_secure_cookie do
    Stream.unfold(nil, fn _ -> {:crypto.strong_rand_bytes(1), nil} end)
    |> Stream.filter(fn <<b>> -> b >= ?! && b <= ?~ end)
    # special when erlexec parses vm.args
    |> Stream.reject(fn <<b>> -> b in [?-, ?+, ?', ?\", ?\\, ?\#, ?,] end)
    |> Enum.take(64)
    |> Enum.join()
    |> String.to_atom()
  end
end
