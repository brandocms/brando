defmodule Brando.Blueprint.AttributeOptions do
  @moduledoc false

  alias Brando.Blueprint.Attributes.Attribute

  @common_options [
    :autogenerate,
    :constraints,
    :default,
    :load_in_query,
    :null,
    :precision,
    :read_after_writes,
    :redact,
    :rename_from,
    :required,
    :scale,
    :skip_default_validation,
    :source,
    :unique,
    :virtual,
    :writable
  ]
  @timestamp_schema_options [
    :autogenerate,
    :default,
    :load_in_query,
    :null,
    :precision,
    :read_after_writes,
    :redact,
    :rename_from,
    :scale,
    :skip_default_validation,
    :virtual,
    :writable
  ]
  @virtual_storage_options [:null, :precision, :rename_from, :scale]

  @doc false
  @spec validate(Attribute.t()) :: :ok | {:error, String.t()}
  def validate(%Attribute{type: type, opts: opts} = attribute) do
    with :ok <- validate_known_options(type, opts),
         :ok <- validate_option_scopes(attribute),
         :ok <- validate_column_options(type, opts),
         :ok <- validate_ecto_options(opts) do
      validate_enum_options(type, opts)
    end
  end

  defp validate_known_options(type, opts) do
    allowed_options =
      @common_options ++
        if(enum_type?(type), do: [:embed_as, :values], else: []) ++
        if(type == :language, do: [:languages], else: [])

    unknown_options =
      if custom_parameterized_type?(type) do
        []
      else
        opts |> Map.keys() |> Enum.sort() |> Kernel.--(allowed_options)
      end

    case unknown_options do
      [] -> :ok
      unknown -> {:error, "contains unsupported options #{inspect(unknown)}"}
    end
  end

  defp validate_option_scopes(%Attribute{name: name, opts: opts})
       when name in [:inserted_at, :updated_at] do
    reject_scoped_options(opts, @timestamp_schema_options, "timestamp attributes")
  end

  defp validate_option_scopes(%Attribute{opts: %{virtual: true} = opts}) do
    reject_scoped_options(opts, @virtual_storage_options, "virtual attributes")
  end

  defp validate_option_scopes(_attribute), do: :ok

  defp reject_scoped_options(opts, scoped_options, subject) do
    unsupported = opts |> Map.keys() |> Enum.filter(&(&1 in scoped_options)) |> Enum.sort()

    case unsupported do
      [] -> :ok
      options -> {:error, "#{subject} do not support #{inspect(options)}"}
    end
  end

  defp validate_column_options(type, opts) do
    with :ok <- boolean_option(opts, :null),
         :ok <- positive_integer_option(opts, :precision),
         :ok <- non_negative_integer_option(opts, :scale),
         :ok <- decimal_options(type, opts) do
      scale_within_precision(opts)
    end
  end

  defp validate_ecto_options(opts) do
    with :ok <- boolean_option(opts, :load_in_query),
         :ok <- boolean_option(opts, :read_after_writes),
         :ok <- boolean_option(opts, :redact),
         :ok <- boolean_option(opts, :skip_default_validation) do
      writable_option(opts)
    end
  end

  defp boolean_option(opts, option) do
    case Map.get(opts, option) do
      value when value in [nil, false, true] -> :ok
      value -> {:error, "`:#{option}` must be a boolean, got: #{inspect(value)}"}
    end
  end

  defp positive_integer_option(opts, option) do
    case Map.get(opts, option) do
      nil -> :ok
      value when is_integer(value) and value > 0 -> :ok
      value -> {:error, "`:#{option}` must be a positive integer, got: #{inspect(value)}"}
    end
  end

  defp non_negative_integer_option(opts, option) do
    case Map.get(opts, option) do
      nil -> :ok
      value when is_integer(value) and value >= 0 -> :ok
      value -> {:error, "`:#{option}` must be a non-negative integer, got: #{inspect(value)}"}
    end
  end

  defp decimal_options(:decimal, _opts), do: :ok

  defp decimal_options(_type, opts) do
    if Map.has_key?(opts, :precision) or Map.has_key?(opts, :scale) do
      {:error, "`:precision` and `:scale` are only valid for decimal attributes"}
    else
      :ok
    end
  end

  defp scale_within_precision(opts) do
    case {Map.get(opts, :precision), Map.get(opts, :scale)} do
      {nil, nil} -> :ok
      {nil, _scale} -> {:error, "`:scale` requires `:precision`"}
      {precision, scale} when is_nil(scale) or scale <= precision -> :ok
      {precision, scale} -> {:error, "`:scale` #{scale} exceeds `:precision` #{precision}"}
    end
  end

  defp writable_option(opts) do
    case Map.get(opts, :writable) do
      value when value in [nil, :always, :insert, :never] -> :ok
      value -> {:error, "`:writable` must be `:always`, `:insert`, or `:never`, got: #{inspect(value)}"}
    end
  end

  defp validate_enum_options(type, opts) do
    if enum_type?(type) do
      with :ok <- enum_values(Map.get(opts, :values)) do
        enum_embed_as(Map.get(opts, :embed_as))
      end
    else
      :ok
    end
  end

  defp enum_values(values) do
    if valid_enum_values?(values) do
      :ok
    else
      {:error, "`:values` must be a non-empty unique atom list or an atom-to-string/integer keyword mapping"}
    end
  end

  defp valid_enum_values?(values) when is_list(values) and values != [] do
    if Keyword.keyword?(values) do
      keys = Keyword.keys(values)
      mapped_values = Keyword.values(values)

      Enum.all?(keys, &is_atom/1) and
        (Enum.all?(mapped_values, &is_integer/1) or Enum.all?(mapped_values, &is_binary/1)) and
        length(Enum.uniq(keys)) == length(keys) and
        length(Enum.uniq(mapped_values)) == length(mapped_values)
    else
      Enum.all?(values, &is_atom/1) and length(Enum.uniq(values)) == length(values)
    end
  end

  defp valid_enum_values?(_values), do: false

  defp enum_embed_as(value) when value in [nil, :values, :dumped], do: :ok
  defp enum_embed_as(value), do: {:error, "`:embed_as` must be `:values` or `:dumped`, got: #{inspect(value)}"}

  defp enum_type?(type), do: type in [:enum, :language, Ecto.Enum, {:array, :enum}, {:array, Ecto.Enum}]

  defp custom_parameterized_type?({:array, type}), do: custom_parameterized_type?(type)

  defp custom_parameterized_type?(type) when is_atom(type) and type != Ecto.Enum do
    Code.ensure_loaded?(type) and function_exported?(type, :type, 1)
  end

  defp custom_parameterized_type?(_type), do: false
end
