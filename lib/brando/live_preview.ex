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

    quote location: :keep do
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
            html_key = key |> String.replace("data", "html") |> String.to_existing_atom()
            atom_key = String.to_existing_atom(key)

            html =
              Brando.Villain.parse(Map.get(entry, atom_key), entry,
                cache_templates: true,
                data_field: atom_key,
                html_field: html_key
              )

            entry = Map.put(entry, :html, html)
          else
            entry
          end

        # build conn
        conn = %Plug.Conn{host: "localhost", private: %{phoenix_endpoint: Brando.endpoint()}}
        conn = Brando.Plug.HTML.put_section(conn, section)

        render_assigns =
          ([
             {:conn, conn},
             {:section, section},
             {atom_prop, entry}
           ] ++ unquote(Macro.var(:extra_vars, nil)))
          |> Enum.into(%{})

        inner = Phoenix.View.render(unquote(view_module), template, render_assigns)

        root_assigns = render_assigns |> Map.put(:inner_content, inner) |> Map.delete(:layout)

        Phoenix.View.render_to_string(
          unquote(layout_module),
          unquote(layout_template),
          root_assigns
        )
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
  def build_cache_key(seed), do: "PREVIEW-" <> Hashids.encode(@preview_coder, seed)

  def store_cache(key, html), do: Cachex.put(:cache, "__live_preview__" <> key, html)
  def get_cache(key), do: Cachex.get(:cache, "__live_preview__" <> key)

  def initialize(schema, entry, key, prop) do
    preview_module = get_preview_module()

    if function_exported?(preview_module, :render, 5) do
      cache_key = build_cache_key(:erlang.system_time())
      schema_module = Module.concat([schema])
      entry_struct = Brando.Utils.stringy_struct(schema_module, entry)

      try do
        wrapper_html = preview_module.render(schema_module, entry_struct, key, prop, cache_key)

        if Cachex.get(:cache, cache_key) == {:ok, nil} do
          Brando.LivePreview.store_cache(cache_key, wrapper_html)
        end

        Brando.endpoint().broadcast("live_preview:#{cache_key}", "update", %{html: wrapper_html})

        {:ok, cache_key}
      rescue
        _err ->
          {:error, "Initialization failed."}
      end
    else
      {:error, "No render/5 function found in LivePreview module"}
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
