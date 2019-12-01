defmodule Mix.Tasks.Brando.Gen.Schema do
  # use Mix.Task

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

      mix brando.gen.schema Post posts title user:references:users

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
  import Inflex

  def run(args, domain) do
    snake_domain =
      domain
      |> Phoenix.Naming.underscore()
      |> String.split("/")
      |> List.last()

    {opts, parsed, _} = OptionParser.parse(args, switches: [sequenced: :boolean])
    [singular, plural, attrs] = parsed

    sequenced? = (opts[:sequenced] && true) || false
    soft_delete? = (opts[:softdelete] && true) || false
    gallery? = (opts[:gallery] && true) || false

    attrs = Mix.Brando.attrs(attrs)
    binding = Mix.Brando.inflect(singular)
    params = Mix.Brando.params(attrs)
    path = binding[:path]
    migration = String.replace(path, "/", "_")

    img_fields =
      attrs
      |> Enum.map(fn {k, v} -> {v, k} end)
      |> Enum.filter(fn {k, _} -> k == :image end)

    file_fields =
      attrs
      |> Enum.map(fn {k, v} -> {v, k} end)
      |> Enum.filter(fn {k, _} -> k == :file end)

    villain_fields =
      attrs
      |> Enum.map(fn {k, v} -> {v, k} end)
      |> Enum.filter(fn {k, _} -> k == :villain end)

    gallery_fields =
      attrs
      |> Enum.map(fn {k, v} -> {v, k} end)
      |> Enum.filter(fn {k, _} -> k == :gallery end)

    :ok = Mix.Brando.check_module_name_availability(binding[:module])

    {assocs, attrs} = partition_attrs_and_assocs(attrs)

    mig_types = Enum.map(attrs, &migration_type/1)
    types = types(attrs)
    defs = defaults(attrs)

    migrations = map_mig_attrs(attrs, mig_types, defs)
    mig_assocs = migration_assocs(assocs)

    schema_fields = map_schema_attrs(attrs, types, defs)

    module = Enum.join([binding[:base], domain, binding[:scoped]], ".")

    binding =
      Keyword.delete(binding, :module) ++
        [
          attrs: attrs,
          img_fields: img_fields,
          file_fields: file_fields,
          villain_fields: villain_fields,
          gallery_fields: gallery_fields,
          plural: plural,
          types: types,
          sequenced: sequenced?,
          soft_delete: soft_delete?,
          gallery: gallery?,
          domain: domain,
          snake_domain: snake_domain,
          migrations: migrations,
          schema_fields: schema_fields,
          schema_assocs: schema_assocs(binding[:base], domain, assocs),
          migration_assocs: mig_assocs,
          indexes: indexes(snake_domain, plural, assocs),
          defaults: defs,
          params: params,
          module: module
        ]

    binding =
      binding ++
        [
          required_fields: build_required_fields(binding),
          optional_fields: build_optional_fields(binding)
        ]

    migration_path = "priv/repo/migrations/" <> "#{timestamp()}_create_#{migration}.exs"
    schema_path = "lib/application_name/#{snake_domain}/#{path}.ex"
    schema_test_path = "test/schemas/#{path}_test.exs"

    Mix.Brando.copy_from(apps(), "priv/templates/brando.gen.schema", "", binding, [
      {:eex, "migration.exs", migration_path},
      {:eex, "schema.ex", schema_path},
      {:eex, "schema_test.exs", schema_test_path}
    ])

    binding
  end

  defp build_optional_fields(binding) do
    binding = Enum.into(binding, %{})

    fields = []

    {_, fields} =
      {binding, fields}
      |> maybe_add_gallery_fields()
      |> maybe_add_img_fields()
      |> maybe_add_file_fields()
      |> maybe_add_soft_delete()

    "~w(#{Enum.join(fields, " ")})a"
  end

  defp maybe_add_gallery_fields({%{gallery_fields: []} = binding, fields}), do: {binding, fields}

  defp maybe_add_gallery_fields({%{gallery_fields: gallery_fields} = binding, fields}) do
    gallery_fields = Enum.map(gallery_fields, fn {_, v} -> "#{v}_id" end)
    {binding, fields ++ gallery_fields}
  end

  defp maybe_add_img_fields({%{img_fields: []} = binding, fields}), do: {binding, fields}

  defp maybe_add_img_fields({%{img_fields: img_fields} = binding, fields}) do
    img_fields = Enum.map(img_fields, &elem(&1, 1))
    {binding, fields ++ img_fields}
  end

  defp maybe_add_file_fields({%{file_fields: []} = binding, fields}), do: {binding, fields}

  defp maybe_add_file_fields({%{file_fields: file_fields} = binding, fields}) do
    file_fields = Enum.map(file_fields, &elem(&1, 1))
    {binding, fields ++ file_fields}
  end

  defp maybe_add_soft_delete({%{soft_delete: false} = binding, fields}), do: {binding, fields}

  defp maybe_add_soft_delete({%{soft_delete: true} = binding, fields}) do
    {binding, fields ++ ["deleted_at"]}
  end

  defp build_required_fields(binding) do
    binding_map = Enum.into(binding, %{})

    fields =
      binding[:attrs]
      |> Keyword.drop(Keyword.values(binding[:img_fields]))
      |> Keyword.drop(Keyword.values(binding[:file_fields]))
      |> Keyword.drop(Keyword.values(binding[:villain_fields]))
      |> Keyword.drop(Keyword.values(binding[:gallery_fields]))
      |> Enum.map_join(" ", &elem(&1, 0))
      |> maybe_add_villain_fields(binding_map)
      |> maybe_add_schema_assocs(binding_map)

    "~w(#{fields})a"
  end

  defp maybe_add_villain_fields(fields, %{villain_fields: []}), do: fields

  defp maybe_add_villain_fields(fields, %{villain_fields: villain_fields}) do
    extra_fields =
      Enum.map_join(villain_fields, " ", fn {_k, v} ->
        if v == :data, do: "#{v}", else: "#{v}_data"
      end)

    Enum.join([fields, extra_fields], " ")
  end

  defp maybe_add_schema_assocs(fields, %{schema_assocs: []}), do: fields

  defp maybe_add_schema_assocs(fields, %{
         schema_assocs: schema_assocs,
         gallery_fields: gallery_fields
       }) do
    extra_fields =
      Enum.map_join(schema_assocs, " ", fn {_, y, _} ->
        if to_string(y) not in Keyword.values(gallery_fields), do: y, else: nil
      end)

    Enum.join([fields, extra_fields], " ")
  end

  defp map_mig_attrs(attrs, mig_types, defs) do
    attrs
    |> Enum.map(fn {k, v} ->
      case v do
        :villain -> (k == :data && "villain()") || "villain #{inspect(k)}"
        :gallery -> (k == :image_series && "gallery()") || "gallery #{inspect(k)}"
        _ -> "add #{inspect(k)}, #{inspect(mig_types[k])}#{defs[k]}"
      end
    end)
  end

  defp map_schema_attrs(attrs, types, defs) do
    attrs
    |> Enum.map(fn {k, v} ->
      case v do
        :villain -> (k == :data && "villain()") || "villain #{inspect(k)}"
        :gallery -> (k == :image_series && "gallery()") || "gallery #{inspect(k)}"
        _ -> "field #{inspect(k)}, #{inspect(types[k])}#{defs[k]}"
      end
    end)
  end

  def migration_type({k, :image}) do
    {k, :jsonb}
  end

  def migration_type({k, :file}) do
    {k, :text}
  end

  def migration_type({k, :text}) do
    {k, :text}
  end

  def migration_type({k, :status}) do
    {k, :integer}
  end

  def migration_type({k, type}) do
    {k, type}
  end

  defp partition_attrs_and_assocs(attrs) do
    Enum.split_with(attrs, fn
      {_, {_, _}} -> true
      _ -> false
    end)
  end

  defp migration_assocs(assocs) do
    Enum.reduce(assocs, [], fn
      {key, {:references, target}}, acc ->
        [{key, :"#{key}_id", target, :nothing} | acc]
    end)
  end

  defp schema_assocs(base, domain, assocs) do
    Enum.reduce(assocs, [], fn
      {key, {:references, :users}}, acc ->
        [{key, :"#{key}_id", "Brando.Users.User"} | acc]

      {key, {:references, target}}, acc ->
        inflected = singularize(to_string(target)) |> camelize()
        [{key, :"#{key}_id", Enum.join([base, domain, inflected], ".")} | acc]
    end)
  end

  defp indexes(snake_domain, plural, assocs) do
    Enum.reduce(assocs, [], fn {key, _}, acc ->
      ["create index(:#{snake_domain}_#{plural}, [:#{key}_id])" | acc]
    end)
  end

  defp timestamp do
    {{y, m, d}, {hh, mm, ss}} = :calendar.universal_time()
    "#{y}#{pad(m)}#{pad(d)}#{pad(hh)}#{pad(mm)}#{pad(ss)}"
  end

  defp pad(i) when i < 10, do: <<?0, ?0 + i>>
  defp pad(i), do: to_string(i)

  defp types(attrs) do
    Enum.into(attrs, %{}, fn
      {k, {:references, target}} ->
        {k, {:references, target}}

      {k, {c, v}} ->
        {k, {c, value_to_type(v)}}

      {k, v} ->
        {k, value_to_type(v)}
    end)
  end

  defp defaults(attrs) do
    Enum.into(attrs, %{}, fn
      {k, :boolean} -> {k, ", default: false"}
      {k, _} -> {k, ""}
    end)
  end

  defp value_to_type(:integer), do: :integer
  defp value_to_type(:text), do: :string
  defp value_to_type(:string), do: :string
  defp value_to_type(:uuid), do: Ecto.UUID
  defp value_to_type(:date), do: :date
  defp value_to_type(:time), do: :time
  defp value_to_type(:datetime), do: :naive_datetime
  defp value_to_type(:status), do: Brando.Type.Status
  defp value_to_type(:image), do: Brando.Type.Image
  defp value_to_type(:file), do: Brando.Type.File
  defp value_to_type(:villain), do: :villain
  defp value_to_type(:gallery), do: :gallery

  defp value_to_type(v) do
    if Code.ensure_loaded?(Ecto.Type) and not Ecto.Type.primitive?(v) do
      Mix.raise("Unknown type `#{v}` given to generator")
    else
      v
    end
  end

  defp apps, do: [".", :brando]
end
