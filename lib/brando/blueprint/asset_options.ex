defmodule Brando.Blueprint.AssetOptions do
  @moduledoc false

  @asset_types [:file, :gallery, :image, :video]
  @option_scopes %{
    cfg: @asset_types,
    force_update_on_change: [:gallery],
    invalid_message: [:gallery],
    module: @asset_types,
    required: @asset_types,
    required_message: [:gallery]
  }

  @doc "Returns each asset option and the asset types that accept it."
  @spec option_scopes() :: %{atom() => [atom()]}
  def option_scopes, do: @option_scopes

  @doc "Validates the options stored on a compiled Blueprint asset."
  @spec validate(map()) :: :ok | {:error, String.t()}
  def validate(%{type: type, opts: opts}) do
    with :ok <- validate_known_options(type, opts),
         :ok <- boolean_option(opts, :required) do
      validate_gallery_options(type, opts)
    end
  end

  defp validate_known_options(type, opts) do
    allowed_options =
      for {option, allowed_types} <- @option_scopes,
          type in allowed_types,
          do: option

    case opts |> Map.keys() |> Enum.sort() |> Kernel.--(allowed_options) do
      [] -> :ok
      unknown -> {:error, "contains unsupported options #{inspect(unknown)}"}
    end
  end

  defp validate_gallery_options(:gallery, opts) do
    with :ok <- boolean_option(opts, :force_update_on_change),
         :ok <- string_option(opts, :required_message) do
      string_option(opts, :invalid_message)
    end
  end

  defp validate_gallery_options(_type, _opts), do: :ok

  defp boolean_option(opts, option) do
    case Map.get(opts, option) do
      value when value in [nil, false, true] -> :ok
      value -> {:error, "`:#{option}` must be a boolean, got: #{inspect(value)}"}
    end
  end

  defp string_option(opts, option) do
    case Map.get(opts, option) do
      nil -> :ok
      value when is_binary(value) -> :ok
      value -> {:error, "`:#{option}` must be a string, got: #{inspect(value)}"}
    end
  end
end
