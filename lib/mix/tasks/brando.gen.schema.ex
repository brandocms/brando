defmodule Mix.Tasks.Brando.Gen.Schema do
  # use Mix.Task

  @shortdoc "Generates an Ecto schema"

  @moduledoc """
  Generates an Ecto schema in your Brando application.

      mix brando.gen.schema User users name:string age:integer

  The first argument is the module name followed by its plural
  name (used for the schema).

  The generated schema will contain:

    * a schema in web/schemas
    * a migration file for the repository

  ## Attributes

  The resource fields are given using `name:type` syntax
  where type are the types supported by Ecto. Ommitting
  the type makes it default to `:string`:

      mix brando.gen.schema User users name age:integer

  The generator also supports `belongs_to` associations:

      mix brando.gen.schema Post posts title user:references

  This will result in a migration with an `:integer` column
  of `:user_id` and create an index. It will also generate
  the appropriate `belongs_to` entry in the schema's schema.

  Furthermore an array type can also be given if it is
  supported by your database, although it requires the
  type of the underlying array element to be given too:

      mix brando.gen.schema User users nicknames:array:string

  ## Namespaced resources

  Resources can be namespaced, for such, it is just necessary
  to namespace the first argument of the generator:

      mix brando.gen.schema Admin.User users name:string age:integer

  """
  def run(args, domain) do
    snake_domain =
      domain
      |> Phoenix.Naming.underscore
      |> String.split("/")
      |> List.last

    {opts, parsed, _} = OptionParser.parse(args, switches: [sequenced: :boolean])
    [singular, plural, attrs] = parsed

    sequenced? = opts[:sequenced] && true || false

    attrs      = Mix.Brando.attrs(attrs)
    binding    = Mix.Brando.inflect(singular)
    params     = Mix.Brando.params(attrs)
    path       = binding[:path]
    migration  = String.replace(path, "/", "_")
    img_fields = attrs
                 |> Enum.map(fn({k, v}) -> {v, k} end)
                 |> Enum.filter(fn({k, _}) -> k == :image end)
    file_fields = attrs
                 |> Enum.map(fn({k, v}) -> {v, k} end)
                 |> Enum.filter(fn({k, _}) -> k == :file end)

    villain_fields = attrs
                     |> Enum.map(fn({k, v}) -> {v, k} end)
                     |> Enum.filter(fn({k, _}) -> k == :villain end)

    Mix.Brando.check_module_name_availability!(binding[:module])

    {assocs, attrs} = partition_attrs_and_assocs(attrs)

    mig_types = Enum.map(attrs, &migration_type/1)
    types     = types(attrs)
    defs      = defaults(attrs)

    migrations =
      attrs
      |> Enum.map(fn ({k, v}) ->
        case v do
          :villain -> "villain"
          _        -> "add #{inspect k}, #{inspect(mig_types[k])}#{defs[k]}"
        end
      end)

    schema_fields =
      attrs
      |> Enum.map(fn ({k, v}) ->
        case v do
          :villain -> "villain"
          _        -> "field #{inspect k}, #{inspect types[k]}#{defs[k]}"
        end
      end)

    binding = binding ++
              [attrs: attrs, img_fields: img_fields, file_fields: file_fields,
               plural: plural, types: types, villain_fields: villain_fields,
               sequenced: sequenced?,
               migrations: migrations, schema_fields: schema_fields,
               assocs: assocs(assocs), indexes: indexes(plural, assocs),
               defaults: defs, params: params]

    Mix.Brando.copy_from(
      apps(),
      "priv/templates/brando.gen.schema",
      "",
      binding, [
        {:eex, "migration.exs",   "priv/repo/migrations/" <>
                                  "#{timestamp()}_create_#{migration}.exs"},
        {:eex, "schema.ex",       "lib/#{snake_domain}/#{path}.ex"},
        {:eex, "schema_test.exs", "test/schemas/#{path}_test.exs"},
      ]
    )
    binding
  end

  def migration_type({k, :image}) do
    {k, :text}
  end
  def migration_type({k, :file}) do
    {k, :text}
  end
  def migration_type({k, :status}) do
    {k, :integer}
  end
  def migration_type({k, type}) do
    {k, type}
  end

  defp partition_attrs_and_assocs(attrs) do
    Enum.partition attrs, fn {_, kind} ->
      kind == :references
    end
  end

  defp assocs(assocs) do
    Enum.reduce assocs, [], fn {key, _}, acc ->
      assoc = Mix.Brando.inflect Atom.to_string(key)
      [{key, :"#{key}_id", assoc[:module]} | acc]
    end
  end

  defp indexes(plural, assocs) do
    Enum.reduce assocs, [], fn {key, _}, acc ->
      ["create index(:#{plural}, [:#{key}_id])" | acc]
    end
  end

  defp timestamp do
    {{y, m, d}, {hh, mm, ss}} = :calendar.universal_time()
    "#{y}#{pad(m)}#{pad(d)}#{pad(hh)}#{pad(mm)}#{pad(ss)}"
  end

  defp pad(i) when i < 10, do: << ?0, ?0 + i >>
  defp pad(i), do: to_string(i)

  defp types(attrs) do
    Enum.into attrs, %{}, fn
      {k, {c, v}} -> {k, {c, value_to_type(v)}}
      {k, v}      -> {k, value_to_type(v)}
    end
  end

  defp defaults(attrs) do
    Enum.into attrs, %{}, fn
      {k, :boolean}  -> {k, ", default: false"}
      {k, _}         -> {k, ""}
    end
  end

  defp value_to_type(:text), do: :string
  defp value_to_type(:uuid), do: Ecto.UUID
  defp value_to_type(:date), do: :date
  defp value_to_type(:time), do: :time
  defp value_to_type(:datetime), do: :naive_datetime
  defp value_to_type(:status), do: Brando.Type.Status
  defp value_to_type(:image), do: Brando.Type.Image
  defp value_to_type(:file), do: Brando.Type.File
  defp value_to_type(:villain), do: :villain
  defp value_to_type(v) do
    if Code.ensure_loaded?(Ecto.Type) and not Ecto.Type.primitive?(v) do
      Mix.raise "Unknown type `#{v}` given to generator"
    else
      v
    end
  end

  defp apps do
    [".", :brando]
  end
end
