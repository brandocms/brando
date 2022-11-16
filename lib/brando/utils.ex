defmodule Brando.Utils do
  @moduledoc """
  Assorted utility functions.
  """

  alias Brando.Cache
  alias Brando.Files

  @type changeset :: Ecto.Changeset.t()
  @type conn :: Plug.Conn.t()
  @type uri :: URI.t()

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
  Capitalize and replace dashes and underscores with spaces

  ## Example

        iex(1)> humanize("field_base")
        "Field base"

  """
  @spec humanize(binary) :: binary
  def humanize(value) do
    value
    |> String.replace(["-", "_"], " ")
    |> String.capitalize()
  end

  @spec humanize(binary, :downcase) :: binary
  def humanize(value, :downcase) do
    value
    |> String.replace(["-", "_"], " ")
    |> String.downcase()
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

  ## Examples

      iex> try_path(%{title: "Hello", clients: [%{cover_id: 2}, %{}]}, [:title])
      "Hello"
      iex> try_path(%{title: "Hello", clients: [%{cover_id: 2}, %{}]}, [:clients, 0, :cover_id])
      2
      iex> try_path(%{title: "Hello", clients: [%{cover_id: 2}, %{}]}, [:clients, 1])
      %{}
      iex> try_path(%{title: "Hello", clients: [%{cover_id: 2}, %{}]}, [:clients, 2])
      nil
  """
  @spec try_path(data :: map | list, keys :: [atom | integer] | nil) :: any | nil
  def try_path(_, nil), do: nil

  def try_path(map, keys) when is_map(map) do
    Enum.reduce(keys, map, fn
      key, acc when is_atom(key) or is_binary(key) -> if acc, do: Map.get(acc, key)
      idx, acc when is_integer(idx) -> if acc, do: Enum.at(acc, idx)
    end)
  end

  def try_path(kw, keys) when is_list(kw) do
    Enum.reduce(keys, kw, fn key, acc ->
      if acc, do: Keyword.get(acc, key)
    end)
  end

  @doc """
  Takes a list of atoms and integers and builds a path with Access.key and Access.at
  """
  def build_access_path(path) do
    Enum.map(path, fn
      key when is_atom(key) -> Access.key(key)
      key when is_binary(key) -> Access.key(key)
      idx when is_integer(idx) -> Access.at(idx)
    end)
  end

  @doc """
  Tries to access map key as atom or string
  """
  def get_indifferent(map, key) when is_atom(key) do
    Map.get(map, key) || Map.get(map, Atom.to_string(key))
  end

  @doc """
  Generate a random string from `seed`
  """
  def random_string(length) when is_integer(length) do
    length
    |> :crypto.strong_rand_bytes()
    |> Base.url_encode64(padding: false)
    |> binary_part(0, length)
  end

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
  Pull multiple paths out of a data tree into a map.
  """
  @spec deep_select(Access.t(), map()) :: map
  def deep_select(map, paths) do
    Map.new(paths, fn {key, path} ->
      {key, get_in(map, Enum.map(List.wrap(path), &Access.key/1))}
    end)
  end

  def access_key(key) do
    fn
      :get, data, next ->
        next.(Keyword.get(data, key, []))

      :get_and_update, data, next ->
        value = Keyword.get(data, key, [])

        case next.(value) do
          {get, update} -> {get, Keyword.put(data, key, update)}
          :pop -> {value, Keyword.delete(data, key)}
        end
    end
  end

  def access_map(key) do
    fn
      :get, data, next ->
        next.(Map.get(data, key, %{}))

      :get_and_update, data, next ->
        value = Map.get(data, key, %{})

        case next.(value) do
          {get, update} -> {get, Map.put(data, key, update)}
          :pop -> {value, Map.delete(data, key)}
        end
    end
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
  def stringify_keys([head | rest]), do: [stringify_keys(head) | stringify_keys(rest)]
  def stringify_keys(not_a_map), do: not_a_map
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
  Converts string map `collection` to a map with safe atom keys
  """
  def to_atom_map(string_map) do
    for {key, val} <- string_map, into: %{} do
      if is_atom(key), do: {key, val}, else: {String.to_existing_atom(key), val}
    end
  end

  @doc """
  Convert string map to struct
  """
  def stringy_struct(schema, nil), do: struct(schema, %{})

  def stringy_struct(schema, params) when is_map(params) do
    keys =
      schema
      |> struct([])
      |> Map.from_struct()
      |> Map.keys()
      |> Enum.map(&Atom.to_string/1)

    params =
      params
      |> Map.take(keys)
      |> Enum.map(fn {key, value} -> {String.to_atom(key), value} end)

    struct(schema, params)
  end

  @doc """
  Recursive Schema to map function.
  """
  @spec map_from_struct(map) :: map
  def map_from_struct(%_{__meta__: %{__struct__: _}} = schema) when is_map(schema) do
    schema
    |> Map.from_struct()
    |> map_from_struct()
  end

  def map_from_struct(schema) when is_struct(schema) do
    schema
    |> Map.from_struct()
    |> map_from_struct()
  end

  def map_from_struct(map) when is_map(map) do
    map
    |> Enum.reduce(%{}, fn {key, value}, acc ->
      processed_value =
        case value do
          %_{__meta__: %{__struct__: _}} ->
            map_from_struct(value)

          s when is_struct(s) ->
            map_from_struct(s)

          list when is_list(list) ->
            Enum.map(list, &map_from_struct/1)

          _ ->
            value
        end

      Map.put_new(acc, key, processed_value)
    end)
  end

  def map_from_struct(value), do: value

  @doc """
  Force map into struct.

  Supports both atom and string keys
  """
  def map_to_struct(nil, string_struct), do: struct(string_struct, %{})

  def map_to_struct(source_map, target_struct) when is_map(source_map) do
    map_from_struct =
      target_struct
      |> struct([])
      |> Map.from_struct()

    atom_keys =
      map_from_struct
      |> Map.keys()
      |> Enum.map(&Atom.to_string/1)

    string_map = Map.take(source_map, atom_keys)
    atom_map = Map.take(source_map, Map.keys(map_from_struct))

    new_map =
      Enum.map(
        Map.merge(string_map, atom_map),
        fn
          {key, value} when is_binary(key) -> {String.to_existing_atom(key), value}
          {key, value} when is_atom(key) -> {key, value}
        end
      )

    struct(target_struct, new_map)
  end

  def camel_case_map(%Date{} = val), do: val
  def camel_case_map(%DateTime{} = val), do: val
  def camel_case_map(%NaiveDateTime{} = val), do: val

  def camel_case_map(map) when is_map(map) do
    for {key, val} <- map, into: %{} do
      {Recase.to_camel(key), camel_case_map(val)}
    end
  end

  def camel_case_map(val), do: val

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
  def get_page_title(%{assigns: %{page_title: title, language: language}}) do
    organization = Cache.Identity.get(language)

    if organization do
      %{title_prefix: title_prefix, title_postfix: title_postfix} = organization
      render_title(title_prefix, title, title_postfix)
    else
      ""
    end
  end

  def get_page_title(%{assigns: %{language: language}}) do
    organization = Cache.Identity.get(language)

    if map_size(organization) > 0 do
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
  Return the current user
  """
  def current_user(conn), do: Map.get(conn.assigns, :current_user)

  @doc """
  Checks if `conn`'s `full_path` matches `current_path`.
  """
  @spec active_path?(conn | binary | uri | nil, binary) :: boolean
  def active_path?(nil, _), do: false

  def active_path?(%Plug.Conn{} = conn, url_to_match) do
    do_active_path?(Path.join(["/" | conn.path_info]), url_to_match)
  end

  def active_path?(%URI{} = uri, url_to_match) do
    do_active_path?(uri.path, url_to_match)
  end

  def active_path?(current_path, url_to_match) when is_binary(current_path) do
    do_active_path?(current_path, url_to_match)
  end

  defp do_active_path?(current_path, url_to_match) do
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
  Create a cache string and return
  """
  def add_cache_string(opts) do
    case Keyword.get(opts, :cache, nil) do
      nil ->
        ""

      :timestamp ->
        "?#{DateTime.utc_now() |> DateTime.to_unix()}"

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

  def img_url(nil, _size, opts) do
    default = Keyword.get(opts, :default, nil)

    (default && Brando.Images.Utils.get_sized_path(default, :original)) ||
      "" <> add_cache_string(opts)
  end

  def img_url("", _size, opts) do
    default = Keyword.get(opts, :default, nil)

    (default && Brando.Images.Utils.get_sized_path(default, :original)) ||
      "" <> add_cache_string(opts)
  end

  def img_url(image_field, :largest, opts) do
    {:ok, cfg} = Brando.Images.get_config_for(image_field)

    {largest_key, _largest_size} =
      cfg.sizes
      |> Enum.map(fn {k, %{"size" => size}} -> {k, Integer.parse(size) |> elem(0)} end)
      |> Enum.sort(&(elem(&1, 1) >= elem(&2, 1)))
      |> List.first()

    img_url(image_field, largest_key, opts)
  end

  def img_url(image_field, :smallest, opts) do
    {:ok, cfg} = Brando.Images.get_config_for(image_field)

    {smallest, _smallest_size} =
      cfg.sizes
      |> Map.drop(["thumb", "micro"])
      |> Enum.map(fn {k, %{"size" => size}} -> {k, Integer.parse(size) |> elem(0)} end)
      |> Enum.sort(&(elem(&1, 1) <= elem(&2, 1)))
      |> List.first()

    img_url(image_field, smallest, opts)
  end

  def img_url(image_field, "original", opts) do
    img_url(image_field, :original, opts)
  end

  def img_url(image_field, :original, opts) do
    prefix = Keyword.get(opts, :prefix, nil)

    prefix =
      if image_field.cdn && Brando.CDN.enabled?(Brando.Images) do
        if prefix do
          Path.join([Brando.CDN.get_prefix(Brando.Images), prefix])
        else
          Brando.CDN.get_prefix(Brando.Images)
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
      if image_field.cdn && Brando.CDN.enabled?(Brando.Images) do
        cdn_prefix = Brando.CDN.get_prefix(Brando.Images)

        if prefix do
          Path.join([cdn_prefix, prefix])
        else
          cdn_prefix
        end
      else
        prefix
      end

    url = (prefix && Path.join([prefix, size_dir])) || size_dir
    url <> add_cache_string(opts)
  end

  def file_url(%{filename: filename, config_target: config_target})
      when not is_nil(config_target) do
    {:ok, config} = Files.get_config_for(config_target)

    config.upload_path
    |> Path.join(filename)
    |> media_url()
  end

  def file_url(_), do: ""

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

  def generate_uid do
    Base62.encode(:erlang.system_time(:nanosecond)) <>
      (:crypto.strong_rand_bytes(8)
       |> :binary.decode_unsigned()
       |> Base62.encode())
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

  def hmac_base64_encode(term) do
    key = Brando.endpoint().config(:secret_key_base)

    :hmac
    |> :crypto.mac(:sha256, key, Jason.encode!(term))
    |> Base.encode64()
  end

  def term_to_binary(term) do
    :erlang.term_to_binary(term, compressed: 9)
  end

  def binary_to_term(binary) do
    :erlang.binary_to_term(binary)
  end

  @doc """
  Forces map and its children into an Ecto `schema` struct.
  """
  def coerce_struct(map, schema, :take_keys) do
    keys =
      map
      |> Map.keys()
      |> Enum.map(&String.to_existing_atom/1)

    map
    |> coerce_struct(schema)
    |> Map.from_struct()
    |> Map.take(keys)
  end

  def coerce_struct(nil, _), do: nil
  def coerce_struct(%{__struct__: Ecto.Association.NotLoaded} = not_loaded, _), do: not_loaded

  def coerce_struct(list, schema) when is_list(list),
    do: Enum.map(list, &coerce_struct(&1, schema))

  def coerce_struct(map, schema) do
    initial_struct = map_to_struct(map, schema)
    schema_assocs = schema.__schema__(:associations)
    schema_fields = schema.__schema__(:fields)
    schema_meta = schema.__changeset__()

    coerced_fields_struct =
      Enum.reduce(schema_fields, initial_struct, fn field, final_struct ->
        field_meta = Map.get(schema_meta, field)
        Map.put(final_struct, field, coerce_field(Map.get(final_struct, field), field_meta))
      end)

    Enum.reduce(schema_assocs, coerced_fields_struct, fn assoc, final_struct ->
      queryable =
        if schema.__schema__(:association, assoc).__struct__ == Ecto.Association.HasThrough do
          schema.__schema__(:association, assoc).owner
        else
          schema.__schema__(:association, assoc).queryable
        end

      final_struct_assoc = Map.get(final_struct, assoc)

      Map.put(
        final_struct,
        assoc,
        coerce_struct(final_struct_assoc, queryable)
      )
    end)
  end

  def coerce_field(
        value,
        {:embed,
         %Ecto.Embedded{
           cardinality: :many,
           related: module
         }}
      ) do
    Enum.map(value, &coerce_struct(&1, module))
  end

  def coerce_field(
        value,
        {:embed,
         %Ecto.Embedded{
           cardinality: :one,
           related: module
         }}
      ) do
    coerce_struct(value, module)
  end

  def coerce_field(nil, _), do: nil

  def coerce_field(value, meta) when is_atom(meta) do
    if {:cast, 1} in meta.__info__(:functions) do
      value
      |> meta.cast()
      |> elem(1)
    else
      value
    end
  rescue
    UndefinedFunctionError ->
      value
  end

  def coerce_field(value, _) do
    value
  end

  def deep_merge(nil, right), do: right
  def deep_merge(left, nil), do: left

  def deep_merge(left, right) do
    Map.merge(left, right, &deep_resolve/3)
  end

  # Key exists in both maps, and both values are maps as well.
  # These can be merged recursively.
  defp deep_resolve(_key, %{} = left, %{} = right) do
    deep_merge(left, right)
  end

  # Key exists in both maps, but at least one of the values is
  # NOT a map. We fall back to standard merge behavior, preferring
  # the value on the right.
  defp deep_resolve(_key, _left, right) do
    right
  end

  def iv(%{source: %{data: data}}, field) do
    Map.get(data, field)
  end

  @doc """
  Shortens a string down to the number of characters passed as an argument. If
  the specified number of characters is less than the length of the string, an
  ellipsis (…) is appended to the string and is included in the character
  count.
  ## Examples
      iex> truncate("Ground control to Major Tom.", 20)
      "Ground control to..."
      iex> truncate("Ground control to Major Tom.", 25, ", and so on")
      "Ground control, and so on"
      iex> truncate("Ground control to Major Tom.", 20, "")
      "Ground control to Ma"
  """
  def truncate(value, length, ellipsis \\ "...") do
    value = to_string(value)

    if String.length(value) <= length do
      value
    else
      String.slice(
        value,
        0,
        length - String.length(ellipsis)
      ) <> ellipsis
    end
  end

  @doc """
  Extract a "path" (list of atoms) from a field's name

  ## Examples
      iex> get_path_from_field_name("post")
      []
      iex> get_path_from_field_name("post[clients]")
      [:clients]
      iex> get_path_from_field_name("post[clients][0]")
      [:clients, 0]
      iex> get_path_from_field_name("post[clients][0][avatar]")
      [:clients, 0, :avatar]
  """
  def get_path_from_field_name(form_name) do
    ~r/\[(\w+)\]/
    |> Regex.scan(form_name, capture: :all_but_first)
    |> Enum.reduce([], fn capture, acc ->
      segment = List.first(capture)

      case Integer.parse(segment) do
        {number, ""} -> [number | acc]
        :error -> [String.to_existing_atom(segment) | acc]
      end
    end)
    |> Enum.reverse()
  end

  @doc """
  Extract the parent module from a singular

  ## Examples:

      iex> get_parent_module_from_field_name("page[fragments][0]", Brando.Pages.Fragment)
      Brando.Pages.Page
      iex> get_parent_module_from_field_name("page", Brando.Pages.Page)
      Brando.Pages.Page
  """
  def get_parent_module_from_field_name(form_name, module) do
    case String.split(form_name, "[") do
      [_ | []] ->
        module

      [parent_singular | _] ->
        parent_singular
        |> String.to_existing_atom()
        |> module.__relation__()
        |> get_in([Access.key(:opts), :module])
    end
  end

  @doc """
  Set changeset action depending on if changeset has :id or not
  """
  def set_action(changeset) do
    mutation_type = (Ecto.Changeset.get_field(changeset, :id) && :update) || :create
    Map.put(changeset, :action, mutation_type)
  end
end
