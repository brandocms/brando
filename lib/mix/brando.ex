defmodule Mix.Brando do
  # Conveniences for generators

  @moduledoc false

  @valid_attributes [
    :array,
    :boolean,
    :date,
    :datetime,
    :decimal,
    :file,
    :float,
    :gallery,
    :image,
    :integer,
    :language,
    :map,
    :references,
    :slug,
    :status,
    :string,
    :text,
    :time,
    :uuid,
    :video,
    :villain
  ]

  @doc """
  Copies files from source dir to target dir
  according to the given map.
  Files are evaluated against EEx according to
  the given binding.
  """
  def copy_from(apps, source_dir, target_dir, binding, mapping) when is_list(mapping) do
    roots = Enum.map(apps, &to_app_source(&1, source_dir))

    for {format, source_file_path, target_file_path} <- mapping do
      target_file_path =
        String.replace(target_file_path, "application_name", to_string(otp_app()))

      source =
        Enum.find_value(roots, fn root ->
          source = Path.join(root, source_file_path)
          if File.exists?(source), do: source
        end) || raise "could not find #{source_file_path} in any of the sources"

      target = Path.join(target_dir, target_file_path)

      case format do
        :keep ->
          Mix.Generator.create_directory(target)

        :copy ->
          File.mkdir_p!(Path.dirname(target))
          File.copy!(source, target)

        _ ->
          contents =
            case format do
              :text -> File.read!(source)
              :eex -> EEx.eval_file(source, binding)
              :eex_trim -> EEx.eval_file(source, binding, trim: true)
            end

          Mix.Generator.create_file(target, contents, force: true)
      end
    end
  end

  defp to_app_source(path, source_dir) when is_binary(path),
    do: Path.join(path, source_dir)

  defp to_app_source(app, source_dir) when is_atom(app),
    do: Application.app_dir(app, source_dir)

  @doc """
  Inflect path, scope, alias and more from the given name.
      iex> Mix.Phoenix.inflect("user")
      [alias: "User",
       human: "User",
       base: "Phoenix",
       module: "Phoenix.User",
       scoped: "User",
       singular: "user",
       path: "user"]
      iex> Mix.Phoenix.inflect("Admin.User")
      [alias: "User",
       human: "User",
       base: "Phoenix",
       module: "Phoenix.Admin.User",
       scoped: "Admin.User",
       singular: "user",
       path: "admin/user"]
      iex> Mix.Phoenix.inflect("Admin.SuperUser")
      [alias: "SuperUser",
       human: "Super user",
       base: "Phoenix",
       module: "Phoenix.Admin.SuperUser",
       scoped: "Admin.SuperUser",
       singular: "super_user",
       path: "admin/super_user"]
  """
  def inflect(singular) do
    base = Mix.Phoenix.base()
    scoped = Phoenix.Naming.camelize(singular)
    path = Phoenix.Naming.underscore(scoped)
    singular = path |> String.split("/") |> List.last()
    module = base |> Module.concat(scoped) |> inspect
    alias = module |> String.split(".") |> List.last()
    human = Phoenix.Naming.humanize(singular)

    [
      alias: alias,
      human: human,
      base: base,
      module: module,
      scoped: scoped,
      singular: singular,
      path: path
    ]
  end

  @doc """
  Parses the attrs as received by generators.
  """
  def attrs(blueprint) do
    attrs =
      Enum.map(blueprint.attributes, fn
        %{name: name, type: :slug, opts: %{from: target}} ->
          validate_attr!({name, {:slug, target}})

        %{name: name, type: type} ->
          validate_attr!({name, type})
      end)

    rels =
      blueprint.relations
      |> Enum.filter(&(&1.type == :belongs_to))
      |> Enum.map(fn %{name: name, opts: opts} ->
        target_module = opts.module
        target_source = target_module.__schema__(:source)
        validate_attr!({name, {:references, target_source}})
      end)

    attrs ++ rels
  end

  @doc """
  Generates some sample params based on the parsed attributes.
  """
  def params(attrs) do
    attrs
    |> Enum.reject(fn
      {_, {:references, _}} -> true
      {_, _} -> false
    end)
    |> Enum.into(%{}, fn
      {k, {:array, _}} ->
        {k, []}

      {k, {:slug, _}} ->
        {k, "some-content"}

      {k, :integer} ->
        {k, 42}

      {k, :float} ->
        {k, "120.5"}

      {k, :decimal} ->
        {k, "120.5"}

      {k, :boolean} ->
        {k, true}

      {k, :map} ->
        {k, %{}}

      {k, :text} ->
        {k, "some content"}

      {k, :date} ->
        {k, "2010-04-17"}

      {k, :time} ->
        {k, "14:00:00"}

      {k, :datetime} ->
        {k, "2010-04-17 14:00:00"}

      {k, :uuid} ->
        {k, "7488a646-e31f-11e4-aace-600308960662"}

      {k, :villain} ->
        k = (k == :data && :data) || String.to_atom(Atom.to_string(k) <> "_data")
        {k, []}

      {k, :image} ->
        {k, nil}

      {k, :video} ->
        {k, nil}

      {k, :status} ->
        {k, :published}

      {k, _} ->
        {k, "some content"}
    end)
  end

  @doc """
  Checks the availability of a given module name.
  """
  def check_module_name_availability(name) do
    name = Module.concat(Elixir, name)

    if Code.ensure_loaded?(name) do
      {:error, "Module name #{inspect(name)} is already taken, please choose another name"}
    else
      :ok
    end
  end

  @doc """
  Returns the module base name based on the configuration value.
      config :my_app
        app_namespace: My.App
  """
  def base do
    app = Mix.Project.config() |> Keyword.fetch!(:app)

    case Application.get_env(app, :app_namespace, app) do
      ^app -> app |> to_string |> Phoenix.Naming.camelize()
      mod -> mod |> inspect
    end
  end

  @doc """
  Add content to file under marker
  """
  def add_to_file(file, marker, content, opts \\ []) do
    type = (Keyword.get(opts, :prepend) && :prepend) || :append
    position = (type == :prepend && "\\+\\+") || "__"
    content = (Keyword.get(opts, :comma) && "#{content},") || content
    marker_token = get_marker_token(file, position)

    exists? =
      if Keyword.get(opts, :singular) do
        file
        |> File.stream!()
        |> Enum.map(&String.contains?(&1, content))
        |> Enum.any?(&(&1 == true))
      else
        false
      end

    unless exists? do
      marker = "#{marker_token}#{marker}"

      new_content =
        file
        |> File.stream!()
        |> Enum.map(&process_line(&1, marker, content, type))

      File.write(file, new_content)
    end
  end

  defp get_marker_token(file, position) do
    case Path.extname(file) do
      ".ex" ->
        "# #{position}"

      ".js" ->
        "// #{position}"

      ".vue" ->
        "// #{position}"
    end
  end

  defp process_line(line, marker, content, :append) do
    marker_regex = ~r/(\s+)?(#{marker})/

    case Regex.run(marker_regex, line, capture: :all_but_first) do
      nil ->
        line

      [whitespace, marker] ->
        content_split =
          content
          |> String.split("\n")
          |> Enum.map(&"#{whitespace}#{&1}")
          |> Enum.join("\n")

        content = "#{content_split}\n#{whitespace}#{marker}"
        String.replace(line, whitespace <> marker, content)
    end
  end

  defp process_line(line, marker, content, :prepend) do
    marker_regex = ~r/(\s+)?(#{marker})/

    case Regex.run(marker_regex, line, capture: :all_but_first) do
      nil ->
        line

      [whitespace, marker] ->
        content_split =
          content
          |> String.split("\n")
          |> Enum.map(&"#{whitespace}#{&1}")
          |> Enum.join("\n")

        content = "#{whitespace}#{marker}\n#{content_split}"
        String.replace(line, whitespace <> marker, content)
    end
  end

  @doc """
  Returns all compiled modules in a project.
  """
  def modules do
    Mix.Project.compile_path()
    |> Path.join("*.beam")
    |> Path.wildcard()
    |> Enum.map(&beam_to_module/1)
  end

  defp beam_to_module(path) do
    path
    |> Path.basename(".beam")
    |> String.to_atom()
  end

  def otp_app do
    Mix.Project.config() |> Keyword.fetch!(:app)
  end

  defp validate_attr!({_name, type} = attr) when type in @valid_attributes, do: attr
  defp validate_attr!({_name, {type, _}} = attr) when type in @valid_attributes, do: attr

  defp validate_attr!({_, type}),
    do: Mix.raise("Unknown type `#{inspect(type)}` given to generator")
end
