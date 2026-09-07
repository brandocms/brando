if Code.ensure_loaded?(Igniter) do
  defmodule Mix.Brando.Igniter.Input do
    @doc false
    def __mix_recompile__?, do: not Code.ensure_loaded?(Igniter)

    @moduledoc false

    @module_name ~r/^[A-Z][A-Za-z0-9_]*(?:\.[A-Z][A-Za-z0-9_]*)*$/
    @identifier ~r/^[a-z][a-z0-9_]*$/

    def required(value, label, interactive?) do
      cond do
        is_binary(value) && String.trim(value) != "" -> {:ok, String.trim(value)}
        interactive? -> prompt(label)
        true -> {:error, "#{label} is required. Supply it as an argument or use --interactive."}
      end
    end

    def module_name(value, label) do
      if is_binary(value) && Regex.match?(@module_name, value) do
        {:ok, value}
      else
        {:error, "#{label} must be an Elixir module name, for example Catalog or Product, got: #{inspect(value)}"}
      end
    end

    def identifier(value, label) do
      if is_binary(value) && Regex.match?(@identifier, value) do
        {:ok, value}
      else
        {:error, "#{label} must use lowercase letters, digits and underscores and start with a letter."}
      end
    end

    defp prompt(label) do
      case Mix.shell().prompt("+ #{label}") do
        answer when is_binary(answer) -> required(answer, label, false)
        _ -> {:error, "Input closed while reading #{label}. Supply arguments for unattended use."}
      end
    rescue
      error in [Mix.Error, ErlangError] -> {:error, "Could not read #{label}: #{Exception.message(error)}"}
    end
  end
else
  defmodule Mix.Brando.Igniter.Input do
    @moduledoc false
    # Revisit this source when the optional dependency becomes available.
    def __mix_recompile__?, do: Code.ensure_loaded?(Igniter)
  end
end
