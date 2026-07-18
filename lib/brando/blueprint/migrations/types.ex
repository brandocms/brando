defmodule Brando.Blueprint.Migrations.Types do
  @moduledoc false

  alias Brando.Blueprint.Utils
  alias Brando.Exception.BlueprintError

  @column_opts [:default, :null, :precision, :scale]

  @doc """
  Returns the database type represented by a Blueprint attribute type.

  Parameterized enums and custom `Ecto.Type` modules are reduced to the
  primitive type that Ecto actually dumps.
  """
  @spec migration_type(term(), map(), keyword()) :: term()
  def migration_type(type, opts \\ %{}, context \\ [])

  def migration_type(:string, _opts, _context), do: :text
  def migration_type(:text, _opts, _context), do: :text
  def migration_type(:villain, _opts, _context), do: :jsonb
  def migration_type(:image, _opts, _context), do: :jsonb
  def migration_type(:file, _opts, _context), do: :jsonb
  def migration_type(:video, _opts, _context), do: :jsonb
  def migration_type(:language, _opts, _context), do: :text
  def migration_type(:slug, _opts, _context), do: :text
  def migration_type(:status, _opts, _context), do: :integer
  def migration_type(:datetime, _opts, _context), do: :utc_datetime
  def migration_type(:timestamp, _opts, _context), do: :timestamp
  def migration_type(:enum, opts, context), do: enum_migration_type(opts, context)
  def migration_type(Ecto.Enum, opts, context), do: enum_migration_type(opts, context)
  def migration_type({:array, :enum}, opts, context), do: {:array, enum_migration_type(opts, context)}
  def migration_type({:array, Ecto.Enum}, opts, context), do: {:array, enum_migration_type(opts, context)}
  def migration_type(:i18n_string, _opts, _context), do: :jsonb

  def migration_type(type, opts, context) do
    type
    |> runtime_type(opts, context)
    |> Ecto.Type.type()
  end

  @doc """
  Returns migration column options with defaults dumped to database literals.

  Blueprint defaults are application values. Ecto enums and custom types may
  dump those values to a different representation, which is the value an Ecto
  migration must use as the database default.
  """
  @spec migration_opts(term(), map(), keyword()) :: map()
  def migration_opts(type, opts, context \\ []) do
    migration_opts = Map.take(opts, @column_opts)

    if Map.has_key?(migration_opts, :default) do
      Map.update!(migration_opts, :default, &migration_default(type, opts, context, &1))
    else
      migration_opts
    end
  end

  defp enum_migration_type(opts, context) do
    case runtime_type(:enum, opts, context) |> Ecto.Type.type() do
      :string -> :text
      type -> type
    end
  end

  defp migration_default(type, opts, context, value) do
    runtime_type = runtime_type(type, opts, context)
    migration_type = migration_type(type, opts, context)

    case Ecto.Type.dump(runtime_type, value) do
      {:ok, dumped_value} ->
        normalize_dumped_default(dumped_value, migration_type)

      :error ->
        raise BlueprintError,
          message: "Cannot use #{inspect(value)} as a database default for Blueprint type #{inspect(type)}"
    end
  end

  defp normalize_dumped_default(%Decimal{} = value, _type), do: Decimal.to_string(value, :normal)
  defp normalize_dumped_default(%Date{} = value, _type), do: Date.to_iso8601(value)
  defp normalize_dumped_default(%Time{} = value, _type), do: Time.to_iso8601(value)
  defp normalize_dumped_default(%NaiveDateTime{} = value, _type), do: NaiveDateTime.to_iso8601(value)
  defp normalize_dumped_default(%DateTime{} = value, _type), do: DateTime.to_iso8601(value)

  defp normalize_dumped_default(values, {:array, type}) when is_list(values) do
    Enum.map(values, &normalize_dumped_default(&1, type))
  end

  defp normalize_dumped_default(value, :jsonb) when is_map(value) do
    encoded_value = value |> Jason.encode!() |> String.replace("'", "''")
    {:fragment, "'#{encoded_value}'::jsonb"}
  end

  defp normalize_dumped_default(value, _type), do: value

  defp runtime_type(type, opts, context) do
    ecto_opts = type |> Utils.to_ecto_opts(opts) |> Keyword.merge(context)

    type
    |> Utils.to_ecto_type()
    |> initialize_parameterized_type(ecto_opts)
  end

  defp initialize_parameterized_type({:array, type}, opts) do
    {:array, initialize_parameterized_type(type, opts)}
  end

  defp initialize_parameterized_type(type, opts) when is_atom(type) do
    if Code.ensure_loaded?(type) and function_exported?(type, :type, 1) do
      Ecto.ParameterizedType.init(type, opts)
    else
      type
    end
  end

  defp initialize_parameterized_type(type, _opts), do: type
end
