defmodule Brando.Trait.Meta do
  @moduledoc "Adds SEO metadata fields and exposes per-field AI defaults."
  use Brando.Trait

  alias Brando.Trait.Meta.Compiler

  @meta_fields [:meta_title, :meta_description]

  @impl true
  def generate_code(module, config), do: Compiler.generate_code(module, config)

  @impl true
  def ai_field_opts(_module, _config, field_name) when field_name not in @meta_fields, do: []

  def ai_field_opts(_module, config, field_name) do
    config
    |> Map.get(:ai, %{})
    |> get_value(field_name)
    |> normalize_ai_opts()
  end

  defp get_value(config, key) when is_map(config) do
    Map.get(config, key) || Map.get(config, Atom.to_string(key))
  end

  defp get_value(config, key) when is_list(config) do
    Keyword.get(config, key)
  end

  defp get_value(_, _), do: nil

  defp normalize_ai_opts(nil), do: []
  defp normalize_ai_opts(opts) when is_list(opts), do: opts
  defp normalize_ai_opts(opts) when is_map(opts), do: Enum.into(opts, [])
  defp normalize_ai_opts(_), do: []
end
