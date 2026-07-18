defmodule Brando.Blueprint.Config do
  @moduledoc """
  Validates the root configuration shared by Blueprint macros and verifiers.

  `use Brando.Blueprint` options must be valid before the macro can derive
  modules, Gettext backends, table names, or Spark extensions. Settings applied
  inside the Blueprint body are validated later by the semantic verifier after
  module attributes and other compile-time expressions have been evaluated.
  """

  alias Brando.Exception.BlueprintError

  @required_use_options [:application, :domain, :schema, :singular, :plural]
  @optional_use_options [:extensions, :gettext_module, :router_scope]
  @use_options @required_use_options ++ @optional_use_options
  @module_segment ~r/^[A-Z][A-Za-z0-9_]*$/
  @snake_identifier ~r/^[a-z][a-z0-9_]*$/

  @doc """
  Expands and validates options passed to `use Brando.Blueprint`.

  Raises `Brando.Exception.BlueprintError` with the caller module and invalid
  setting when required, duplicate, unknown, or malformed options are found.
  """
  @spec validate_use_options!(Macro.t(), Macro.Env.t()) :: keyword()
  def validate_use_options!(options_ast, env) do
    options = Macro.expand(options_ast, env)
    validate_keyword_options!(options, env.module)
    validate_option_keys!(options, env.module)

    options
    |> Enum.map(&expand_option(&1, env))
    |> tap(&validate_use_option_values!(&1, env.module))
  end

  @doc """
  Validates the evaluated root attributes of a Blueprint.

  Returns `:ok` or an error tuple suitable for the Blueprint semantic verifier.
  """
  @spec validate_compiled_options(keyword()) :: :ok | {:error, String.t()}
  def validate_compiled_options(options) do
    Enum.reduce_while(options, :ok, fn {name, value}, :ok ->
      case validate_compiled_option(name, value) do
        :ok -> {:cont, :ok}
        {:error, message} -> {:halt, {:error, message}}
      end
    end)
  end

  defp validate_keyword_options!(options, module) do
    unless Keyword.keyword?(options) do
      config_error!(module, "expected a keyword list, got: #{inspect(options)}")
    end
  end

  defp validate_option_keys!(options, module) do
    keys = Keyword.keys(options)
    duplicate_keys = keys |> Enum.frequencies() |> duplicate_keys() |> Enum.sort()
    unknown_keys = keys |> Kernel.--(@use_options) |> Enum.uniq() |> Enum.sort()
    missing_keys = @required_use_options -- keys

    cond do
      duplicate_keys != [] ->
        config_error!(module, "duplicate options: #{inspect(duplicate_keys)}")

      unknown_keys != [] ->
        config_error!(module, "unknown options: #{inspect(unknown_keys)}")

      missing_keys != [] ->
        config_error!(module, "missing required options: #{inspect(missing_keys)}")

      true ->
        :ok
    end
  end

  defp duplicate_keys(frequencies) do
    for {key, count} <- frequencies, count > 1, do: key
  end

  defp expand_option({:extensions, extensions_ast}, env) do
    extensions = Macro.expand(extensions_ast, env)

    expanded_extensions =
      if is_list(extensions) do
        Enum.map(extensions, &Macro.expand(&1, env))
      else
        extensions
      end

    {:extensions, expanded_extensions}
  end

  defp expand_option({name, value}, env), do: {name, Macro.expand(value, env)}

  defp validate_use_option_values!(options, module) do
    Enum.each(options, fn {name, value} ->
      case validate_use_option(name, value) do
        :ok -> :ok
        {:error, message} -> config_error!(module, message)
      end
    end)
  end

  defp validate_use_option(name, value) when name in [:application, :domain, :schema],
    do: validate_module_segment(name, value)

  defp validate_use_option(name, value) when name in [:singular, :plural],
    do: validate_snake_identifier(name, value)

  defp validate_use_option(:router_scope, value), do: validate_router_scope(value)
  defp validate_use_option(:gettext_module, value), do: validate_optional_module(:gettext_module, value)
  defp validate_use_option(:extensions, value), do: validate_extensions(value)

  defp validate_compiled_option(name, value) when name in [:application, :domain, :schema],
    do: validate_module_segment(name, value)

  defp validate_compiled_option(name, value) when name in [:singular, :plural],
    do: validate_snake_identifier(name, value)

  defp validate_compiled_option(:router_scope, value), do: validate_router_scope(value)
  defp validate_compiled_option(:gettext_module, value), do: validate_optional_module(:gettext_module, value)

  defp validate_compiled_option(:data_layer, value) when value in [:database, :embedded], do: :ok

  defp validate_compiled_option(:data_layer, value),
    do: {:error, "`:data_layer` must be `:database` or `:embedded`, got: #{inspect(value)}"}

  defp validate_compiled_option(:table_name, value), do: validate_snake_identifier(:table_name, value)

  defp validate_compiled_option(:primary_key, value) when value in [nil, false], do: :ok

  defp validate_compiled_option(:primary_key, {:id, type, opts})
       when type in [:id, :binary_id] and is_list(opts) do
    if Keyword.keyword?(opts) do
      validate_primary_key_source(opts)
    else
      invalid_primary_key({:id, type, opts})
    end
  end

  defp validate_compiled_option(:primary_key, value), do: invalid_primary_key(value)

  defp validate_compiled_option(:allow_mark_as_deleted, value) when is_boolean(value), do: :ok

  defp validate_compiled_option(:allow_mark_as_deleted, value),
    do: {:error, "`:allow_mark_as_deleted` must be a boolean, got: #{inspect(value)}"}

  defp validate_compiled_option(:factory, value) when is_map(value) and not is_struct(value), do: :ok

  defp validate_compiled_option(:factory, value),
    do: {:error, "`:factory` must be a plain map, got: #{inspect(value)}"}

  defp validate_module_segment(name, value) when is_binary(value) do
    if Regex.match?(@module_segment, value) do
      :ok
    else
      {:error, "`:#{name}` must be a PascalCase module segment, got: #{inspect(value)}"}
    end
  end

  defp validate_module_segment(name, value),
    do: {:error, "`:#{name}` must be a PascalCase module segment string, got: #{inspect(value)}"}

  defp validate_snake_identifier(name, value) when is_binary(value) do
    if Regex.match?(@snake_identifier, value) do
      :ok
    else
      {:error, "`:#{name}` must be a snake_case identifier, got: #{inspect(value)}"}
    end
  end

  defp validate_snake_identifier(name, value),
    do: {:error, "`:#{name}` must be a snake_case identifier string, got: #{inspect(value)}"}

  defp validate_router_scope(nil), do: :ok

  defp validate_router_scope(value) when is_atom(value) and value not in [false, true], do: :ok

  defp validate_router_scope(value) when is_binary(value), do: validate_snake_identifier(:router_scope, value)

  defp validate_router_scope(value),
    do: {:error, "`:router_scope` must be nil, an atom, or a snake_case string, got: #{inspect(value)}"}

  defp validate_optional_module(_name, nil), do: :ok

  defp validate_optional_module(_name, value) when is_atom(value) and value not in [false, true], do: :ok

  defp validate_optional_module(name, value),
    do: {:error, "`:#{name}` must be a module atom or nil, got: #{inspect(value)}"}

  defp validate_extensions(extensions) when is_list(extensions) do
    if Enum.all?(extensions, &(is_atom(&1) and &1 not in [nil, false, true])) do
      :ok
    else
      {:error, "`:extensions` must contain only module atoms, got: #{inspect(extensions)}"}
    end
  end

  defp validate_extensions(value),
    do: {:error, "`:extensions` must be a list of module atoms, got: #{inspect(value)}"}

  defp invalid_primary_key(value) do
    {:error, "`:primary_key` must use the default, false, `:id`, or `:uuid` representation, got: #{inspect(value)}"}
  end

  defp validate_primary_key_source(opts) do
    case Keyword.get(opts, :source) do
      source when is_nil(source) or is_atom(source) ->
        :ok

      source ->
        {:error, "`:primary_key` source must be an atom, got: #{inspect(source)}"}
    end
  end

  defp config_error!(module, message) do
    raise BlueprintError, message: "Invalid Blueprint configuration for #{inspect(module)}: #{message}"
  end
end
