defmodule Brando.LivePreview do
  @moduledoc """
  Coming up
  """

  @preview_coder Hashids.new(
                   alphabet: "ABCDEFGHIJKLMNOPQRSTUVWXYZ1234567890",
                   salt: "bxqStiFpm5to0gsRHyC0afyIaTOH5jjD/T+kOMU5Z9UHCLJuPVnM6ESNaMC8rkzR",
                   min_len: 32
                 )

  @spec build_cache_key(Map.t()) :: String.t()
  def build_cache_key(seed) do
    "PREVIEW-" <> Hashids.encode(@preview_coder, seed)
  end

  def decode_entry("PREVIEW-" <> hash) do
    {:ok, val} = Hashids.decode(@preview_coder, hash)
    val
  end

  def store_cache(key, html), do: Cachex.put(:cache, "__live_preview__" <> key, html)
  def get_cache(key), do: Cachex.get(:cache, "__live_preview__" <> key)

  def initialize(schema, entry, key, prop) do
    preview_module = get_preview_module()

    if function_exported?(preview_module, :render, 5) do
      cache_key = build_cache_key(:erlang.system_time())
      schema_module = Module.concat([schema])
      entry_struct = Brando.Utils.stringy_struct(schema_module, entry)
      wrapper_html = preview_module.render(schema_module, entry_struct, key, prop, cache_key)

      if Cachex.get(:cache, cache_key) == {:ok, nil} do
        Brando.LivePreview.store_cache(cache_key, wrapper_html)
      end

      Brando.endpoint().broadcast("live_preview:#{cache_key}", "update", %{html: wrapper_html})
      cache_key
    end
  end

  def update(schema, entry, key, prop, cache_key) do
    preview_module = get_preview_module()
    schema_module = Module.concat([schema])
    entry_struct = Brando.Utils.stringy_struct(schema_module, entry)
    wrapper_html = preview_module.render(schema_module, entry_struct, key, prop, cache_key)

    Brando.endpoint().broadcast("live_preview:#{cache_key}", "update", %{html: wrapper_html})
    cache_key
  end

  def get_var(cache_key, key, fallback_fn) do
    case Cachex.get(:cache, "#{cache_key}__#{key}") do
      {:ok, nil} ->
        val = fallback_fn.()
        Cachex.put(:cache, "#{cache_key}__#{key}", val, ttl: :timer.seconds(120))
        val

      {:ok, val} ->
        val
    end
  end

  defp get_preview_module do
    Brando.endpoint()
    |> to_string
    |> String.replace("Endpoint", "LivePreview")
    |> String.to_atom()
  end
end
