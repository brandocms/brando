defmodule Brando.LivePreview do
  @moduledoc """
  Coming up
  """

  @preview_coder Hashids.new(
                   alphabet: "ABCDEFGHIJKLMNOPQRSTUVWXYZ1234567890",
                   salt: "bxqStiFpm5to0gsRHyC0afyIaTOH5jjD/T+kOMU5Z9UHCLJuPVnM6ESNaMC8rkzR",
                   min_len: 32
                 )

  defmacro __using__(_) do
    quote do
      import unquote(__MODULE__)
    end
  end

  @doc """
  Generates a render function for live previewing

  Set `template_prop` if your template uses another way to reference the entry than what
  is used in Vue. For instance, if in Vue it is a `project`, but you want `entry`, then
  set `template_prop: :entry`
  """
  defmacro target(opts, do: block) do
    schema_module = Keyword.fetch!(opts, :schema_module) |> Macro.expand(__CALLER__)
    view_module = Keyword.fetch!(opts, :view_module) |> Macro.expand(__CALLER__)
    layout_module = Keyword.fetch!(opts, :layout_module) |> Macro.expand(__CALLER__)
    layout_template = Keyword.get(opts, :layout_template, "app.html")
    template_prop = Keyword.get(opts, :template_prop, nil)

    quote do
      @doc """
      `entry` - data structure of our entry
      `key` - refers to the Villain `data` key. If nil, then ignore
      `prop` - the variable name we store the entry under
      `cache_key` - unique key for this live preview
      """
      def render(unquote(schema_module), entry, key, prop, cache_key) do
        template = unquote(opts[:template]).(entry)
        section = unquote(opts[:section]).(entry)
        var!(cache_key) = cache_key

        # run block assigns
        var!(extra_vars) = []
        unquote(block)

        atom_prop =
          if unquote(template_prop) !== nil,
            do: unquote(template_prop),
            else: String.to_existing_atom(prop)

        # if key, then parse villain
        entry =
          if key do
            atom_key = String.to_existing_atom(key)

            parsed_html =
              Brando.Villain.parse(Map.get(entry, atom_key), entry, cache_templates: true)

            rendered_data = Brando.Villain.render_entry(entry, parsed_html)
            entry = Map.put(entry, :html, rendered_data)
          else
            entry
          end

        # build conn
        conn = %Plug.Conn{host: "localhost", private: %{phoenix_endpoint: Brando.endpoint()}}
        conn = Brando.Plug.HTML.put_section(conn, section)

        unquote(layout_module).render(
          unquote(layout_template),
          [
            {:conn, conn},
            {:view_module, unquote(view_module)},
            {:view_template, template},
            {:section, section},
            {atom_prop, entry}
          ] ++ unquote(Macro.var(:extra_vars, nil))
        )
        |> Phoenix.HTML.safe_to_string()
      end
    end
  end

  defmacro assign(var_name, var_value) do
    quote do
      cached_var =
        Brando.LivePreview.get_var(unquote(Macro.var(:cache_key, nil)), unquote(var_name), fn ->
          unquote(var_value).()
        end)

      var!(extra_vars) = [
        {unquote(var_name), cached_var} | unquote(Macro.var(:extra_vars, nil))
      ]
    end
  end

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
