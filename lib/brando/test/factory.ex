defmodule Brando.Test.Factory do
  @moduledoc """
  Valid entries for any blueprint, without a factory per schema. Imported by
  `use Brando.Test`; see `Brando.Test`.

  Values come from, in order of precedence:

    1. the attributes you pass;
    2. the blueprint's own `factory %{...}` defaults;
    3. defaults derived from the blueprint: every required attribute gets a
       value of its type (a unique string or slug, the default language, a
       published status, today's date…), and every required `belongs_to`
       relation gets an entry of its own, inserted the same way.

  The `:creator` trait's creator is the user you pass as `user:`, or a new
  superuser.

      project = insert_entry(MyApp.Projects.Project, %{title: "Sommerro"})
      params = params_for(MyApp.Projects.Project)
  """

  alias Brando.Blueprint.{Assets, Attributes, Relations}

  @doc """
  The params a valid entry of `schema` is created from, as a map with atom
  keys: derived defaults, the blueprint's `factory`, then `attrs`. Required
  `belongs_to` relations are inserted unless `attrs` names them.
  """
  @spec params_for(module(), map() | keyword(), keyword()) :: map()
  def params_for(schema, attrs \\ %{}, opts \\ []) do
    ensure_blueprint!(schema)
    attrs = Map.new(attrs)
    given = schema.__factory__(%{}) |> Map.merge(attrs)
    n = System.unique_integer([:positive])

    derived =
      (attribute_defaults(schema, given, n) ++
         relation_defaults(schema, given, opts) ++ asset_defaults(schema, given, opts))
      |> Map.new()

    Map.merge(derived, given)
  end

  @doc """
  A valid entry of `schema`, not inserted: `params_for/3` run through the
  blueprint's changeset. Raises with the changeset errors when the result is
  not valid. Required relations are inserted, since the entry refers to them
  by id.
  """
  @spec build_entry(module(), map() | keyword(), keyword()) :: struct()
  def build_entry(schema, attrs \\ %{}, opts \\ []) do
    user = opts[:user] || Brando.Test.Users.insert_user()
    params = params_for(schema, attrs, Keyword.put(opts, :user, user))

    case schema |> struct() |> schema.changeset(params, user) |> Ecto.Changeset.apply_action(:insert) do
      {:ok, entry} -> entry
      {:error, changeset} -> raise ArgumentError, invalid(schema, changeset)
    end
  end

  @doc """
  Insert a valid entry of `schema` through its context's `create_*`
  function, as the admin creates it: changeset, identifier, revision and
  rendered blocks included. Returns the entry.

  Options:

    * `:user` — the creating user; a new superuser by default.
    * `:blocks` — modules to add to the entry's first block field, in order:
      a module, or `{module, vars: %{…}, refs: %{…}}` (see `Brando.Test.render_block/2`).
  """
  @spec insert_entry(module(), map() | keyword(), keyword()) :: struct()
  def insert_entry(schema, attrs \\ %{}, opts \\ []) do
    user = opts[:user] || Brando.Test.Users.insert_user()
    params = params_for(schema, attrs, Keyword.put(opts, :user, user))

    entry =
      case create(schema, params, user) do
        {:ok, entry} -> entry
        {:error, %Ecto.Changeset{} = changeset} -> raise ArgumentError, invalid(schema, changeset)
        {:error, error} -> raise ArgumentError, "could not insert #{inspect(schema)}: #{inspect(error)}"
      end

    case Keyword.get(opts, :blocks, []) do
      [] ->
        entry

      blocks ->
        Enum.each(blocks, fn
          {module, block_opts} -> Brando.Test.Blocks.insert_block(entry, module, Keyword.put(block_opts, :user, user))
          module -> Brando.Test.Blocks.insert_block(entry, module, user: user)
        end)

        {:ok, entry} = Brando.Blueprint.EntryQuery.get(schema, entry.id)
        entry
    end
  end

  defp create(schema, params, user) do
    %{context: context} = schema.__modules__()
    fun = :"create_#{schema.__naming__().singular}"

    if Code.ensure_loaded?(context) and function_exported?(context, fun, 2),
      do: apply(context, fun, [params, user]),
      else: schema |> struct() |> schema.changeset(params, user) |> Brando.Repo.repo().insert()
  end

  defp invalid(schema, changeset) do
    errors =
      Ecto.Changeset.traverse_errors(changeset, fn {message, opts} ->
        Regex.replace(~r"%{(\w+)}", message, fn _, key ->
          opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
        end)
      end)

    "#{inspect(schema)} is not valid with the factory's params: #{inspect(errors)}. Pass the missing values as attrs."
  end

  defp ensure_blueprint!(schema) do
    unless Brando.Blueprint.blueprint?(schema), do: raise(ArgumentError, "#{inspect(schema)} is not a blueprint")
  end

  ## Attributes

  defp attribute_defaults(schema, given, n) do
    for %{name: name, type: type, opts: opts} <- Attributes.__attributes__(schema),
        opts[:required] == true,
        not Map.has_key?(given, name),
        value = attribute_value(type, name, opts, n),
        value != nil,
        do: {name, value}
  end

  defp attribute_value(:string, name, _opts, n), do: "#{humanize(name)} #{n}"
  defp attribute_value(:text, name, _opts, n), do: "#{humanize(name)} #{n}"
  defp attribute_value(:slug, name, _opts, n), do: "#{name |> to_string() |> String.replace("_", "-")}-#{n}"
  defp attribute_value(:i18n_string, name, _opts, n), do: %{to_string(default_language()) => "#{humanize(name)} #{n}"}
  defp attribute_value(:integer, _name, _opts, n), do: n
  defp attribute_value(:float, _name, _opts, n), do: n / 1
  defp attribute_value(:decimal, _name, _opts, n), do: Decimal.new(n)
  defp attribute_value(:boolean, _name, _opts, _n), do: false
  defp attribute_value(:status, _name, _opts, _n), do: :published
  defp attribute_value(:language, _name, _opts, _n), do: default_language()
  defp attribute_value(:date, _name, _opts, _n), do: Date.utc_today()
  defp attribute_value(:time, _name, _opts, _n), do: ~T[12:00:00]
  defp attribute_value(:naive_datetime, _name, _opts, _n), do: NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

  defp attribute_value(type, _name, _opts, _n) when type in [:datetime, :timestamp],
    do: DateTime.utc_now() |> DateTime.truncate(:second)

  defp attribute_value(:map, _name, _opts, _n), do: %{}
  defp attribute_value(:uuid, _name, _opts, _n), do: Ecto.UUID.generate()
  defp attribute_value(:enum, _name, opts, _n), do: opts |> Map.get(:values, []) |> List.first() |> enum_value()
  defp attribute_value({:array, _}, _name, _opts, _n), do: []
  defp attribute_value(_type, _name, _opts, _n), do: nil

  defp enum_value({value, _}), do: value
  defp enum_value(value), do: value

  defp humanize(name), do: name |> to_string() |> String.replace("_", " ") |> String.capitalize()
  defp default_language, do: Brando.config(:default_language) || "en"

  ## Relations

  defp relation_defaults(schema, given, opts) do
    for %{name: name, type: :belongs_to, opts: %{required: true} = rel_opts} <- Relations.__relations__(schema),
        name not in [:creator, :updated_by],
        key = :"#{name}_id",
        not Map.has_key?(given, key) and not Map.has_key?(given, name),
        do: {key, related(rel_opts.module, schema, opts).id}
  end

  defp related(module, module, _opts), do: raise(ArgumentError, "#{inspect(module)} requires an entry of itself; pass it")
  defp related(module, _schema, opts), do: insert_entry(module, %{}, user: opts[:user])

  ## Assets

  # A required image, file or video gets a record without a file on disk:
  # enough to be valid. Pass a real one when the test renders or reads it.
  defp asset_defaults(schema, given, opts) do
    for %{name: name, type: type, opts: %{required: true}} <- Assets.__assets__(schema),
        key = :"#{name}_id",
        not Map.has_key?(given, key) and not Map.has_key?(given, name),
        do: {key, asset(type, opts).id}
  end

  defp asset(:image, opts) do
    Brando.Repo.repo().insert!(%Brando.Images.Image{
      path: "images/test/#{System.unique_integer([:positive])}.jpg",
      width: 1200,
      height: 800,
      formats: [:jpg],
      sizes: %{},
      status: :processed,
      config_target: "default",
      creator_id: user_id(opts[:user])
    })
  end

  defp asset(:video, _opts) do
    Brando.Repo.repo().insert!(%Brando.Videos.Video{
      type: :youtube,
      source_url: "https://www.youtube.com/watch?v=dQw4w9WgXcQ",
      remote_id: "dQw4w9WgXcQ",
      width: 1920,
      height: 1080
    })
  end

  defp asset(:file, opts) do
    Brando.Repo.repo().insert!(%Brando.Files.File{
      filename: "test.pdf",
      mime_type: "application/pdf",
      filesize: 1,
      config_target: "default",
      creator_id: user_id(opts[:user])
    })
  end

  defp asset(type, _opts), do: raise(ArgumentError, "a required #{type} asset has no default; pass it")

  defp user_id(%{id: id}), do: id
  defp user_id(_), do: nil
end
