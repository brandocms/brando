defmodule Brando.LivePreview do
  @moduledoc """

  Create a `MyAppWeb.LivePreview` module if it does not already exist

  ```
  use Brando.LivePreview

  preview_target Brando.Pages.Page do
    mutate_data fn entry -> %{entry | title: "custom"} end

    layout_module MyAppWeb.LayoutView
    view_module MyAppWeb.PageView
    view_template fn e -> e.template end
    template_section fn e -> e.key end

    assign :navigation, fn _ -> Brando.Navigation.get_menu("main", "en") |> elem(1) end
    assign :partials, fn _ -> Brando.Pages.get_fragments("partials") |> elem(1) end
  end
  ```
  """
  require Logger
  alias Brando.Utils
  alias Brando.Worker

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

  defmacro target(_, _) do
    raise """
    Brando.LivePreview.target/2 is deprecated, use preview_target/2 instead:

        preview_target Brando.Pages.Page do
          mutate_data fn entry -> %{entry | title: "custom"} end

          layout_module MyAppWeb.LayoutView
          view_module MyAppWeb.PageView
          view_template fn e -> e.template end
          template_section fn e -> e.key end

          assign :navigation, fn _ -> Brando.Navigation.get_menu("main", "en") |> elem(1) end
          assign :partials, fn _ -> Brando.Pages.get_fragments("partials") |> elem(1) end
        end
    """
  end

  @doc """
  Generates a render function for live previewing

  Set `template_prop` if your template uses another way to reference the entry than what
  is used in Vue. For instance, if in Vue it is a `project`, but you want `entry`, then
  set `template_prop :entry`

    - `schema_preloads` - List of atoms to preload on `entry``
    - `mutate_data` - function to mutate entry data `entry`
        mutate_data fn entry -> %{entry | title: "custom"} end
    - `layout_module` - The layout view module we want to use for rendering
    - `layout_template` - The layout template we want to use for rendering
    - `view_module` - The view module we want to use for rendering
    - `view_template` - The template we want to use for rendering
    - `template_prop` - What we are refering to entry as
    - `template_section` - Run this with `put_section` on conn

  """
  defmacro preview_target(schema_module, do: block) do
    quote location: :keep do
      @doc """
      `entry` - data structure of our entry
      `key` - refers to the Villain `data` key. If nil, then ignore
      `prop` - the variable name we store the entry under
      `cache_key` - unique key for this live preview
      """
      def render(unquote(schema_module), entry, key, prop, cache_key) do
        var!(cache_key) = cache_key

        var!(opts) = [
          layout_template: "app.html",
          mutate_data: fn e -> e end,
          schema_preloads: []
        ]

        var!(entry) = entry
        var!(extra_vars) = []

        unquote(block)
        processed_opts = var!(opts)

        template = processed_opts[:view_template].(var!(entry))
        section = processed_opts[:template_section].(var!(entry))

        # preloads
        var!(entry) =
          var!(entry)
          |> Brando.repo().preload(processed_opts[:schema_preloads])
          |> processed_opts[:mutate_data].()

        atom_prop =
          if processed_opts[:template_prop] !== nil,
            do: processed_opts[:template_prop],
            else: String.to_existing_atom(prop)

        # if key, then parse villain
        var!(entry) =
          Enum.reduce(List.wrap(key), var!(entry), fn k, updated_entry ->
            html_key =
              k
              |> Recase.to_snake()
              |> String.replace("data", "html")
              |> String.to_existing_atom()

            atom_key =
              k
              |> Recase.to_snake()
              |> String.to_existing_atom()

            html =
              Brando.Villain.parse(Map.get(var!(entry), atom_key), var!(entry),
                cache_modules: true,
                data_field: atom_key,
                html_field: html_key
              )

            Map.put(updated_entry, html_key, html)
          end)

        # build conn
        conn = Phoenix.ConnTest.build_conn()
        conn = Brando.Plug.HTML.put_section(conn, section)

        render_assigns =
          ([
             {:conn, conn},
             {:section, section},
             {:LIVE_PREVIEW, true},
             {atom_prop, var!(entry)}
           ] ++ unquote(Macro.var(:extra_vars, nil)))
          |> Enum.into(%{})

        inner = Phoenix.View.render(processed_opts[:view_module], template, render_assigns)
        root_assigns = render_assigns |> Map.put(:inner_content, inner) |> Map.delete(:layout)

        Phoenix.View.render_to_string(
          processed_opts[:layout_module],
          processed_opts[:layout_template],
          root_assigns
        )
      end
    end
  end

  defmacro schema_preloads(schema_preloads) do
    quote do
      var!(opts) = Keyword.put(var!(opts), :schema_preloads, unquote(schema_preloads))
    end
  end

  @doc """
  Mutate the entry available for rendering

  ### Example

      mutate_data fn entry -> %{entry | title: "custom"} end

  Will add `title` with value `custom` to the `entry`
  """
  defmacro mutate_data(mutate_data) do
    quote do
      var!(opts) = Keyword.put(var!(opts), :mutate_data, unquote(mutate_data))
    end
  end

  defmacro layout_module(layout_module) do
    quote do
      var!(opts) = Keyword.put(var!(opts), :layout_module, unquote(layout_module))
    end
  end

  defmacro layout_template(layout_template) do
    quote do
      var!(opts) = Keyword.put(var!(opts), :layout_template, unquote(layout_template))
    end
  end

  defmacro view_module(view_module) do
    quote do
      var!(opts) = Keyword.put(var!(opts), :view_module, unquote(view_module))
    end
  end

  defmacro view_template(view_template) do
    quote do
      var!(opts) = Keyword.put(var!(opts), :view_template, unquote(view_template))
    end
  end

  defmacro template_section(template_section) do
    quote do
      var!(opts) = Keyword.put(var!(opts), :template_section, unquote(template_section))
    end
  end

  defmacro template_prop(template_prop) do
    quote do
      var!(opts) = Keyword.put(var!(opts), :template_prop, unquote(template_prop))
    end
  end

  defmacro assign(var_name, var_value) do
    quote do
      cached_var =
        Brando.LivePreview.get_var(unquote(Macro.var(:cache_key, nil)), unquote(var_name), fn ->
          unquote(var_value).(var!(entry))
        end)

      var!(extra_vars) = [{unquote(var_name), cached_var} | unquote(Macro.var(:extra_vars, nil))]
    end
  end

  @spec build_cache_key(integer) :: binary
  def build_cache_key(seed), do: "PREVIEW-" <> Hashids.encode(@preview_coder, seed)

  @spec build_share_key(integer) :: binary
  def build_share_key(seed), do: "__SHAREPREVIEW__" <> Hashids.encode(@preview_coder, seed)
  def store_cache(key, html), do: Cachex.put(:cache, "__live_preview__" <> key, html)
  def get_cache(key), do: Cachex.get(:cache, "__live_preview__" <> key)

  @spec initialize(any, any, any, any) :: {:error, <<_::384>>} | {:ok, <<_::64, _::_*8>>}
  def initialize(schema, entry, key, prop) do
    preview_module = get_preview_module()

    if function_exported?(preview_module, :render, 5) do
      cache_key = build_cache_key(:erlang.system_time())
      schema_module = Module.concat([schema])
      entry_struct = Utils.coerce_struct(entry, schema_module)
      set_entry(cache_key, entry_struct)

      try do
        wrapper_html = preview_module.render(schema_module, entry_struct, key, prop, cache_key)

        if Cachex.get(:cache, cache_key) == {:ok, nil} do
          Brando.LivePreview.store_cache(cache_key, wrapper_html)
        end

        Brando.endpoint().broadcast("live_preview:#{cache_key}", "update", %{html: wrapper_html})

        {:ok, cache_key}
      rescue
        err ->
          Logger.error("""
          Livepreview Initialization failed.
          """)

          Logger.error("""
          Error:

          #{inspect(err, pretty: true)}
          """)

          Logger.error("""

          Stacktrace:

          #{inspect(__STACKTRACE__, pretty: true)}

          """)

          {:error, "Initialization failed. #{inspect(err)}"}
      end
    else
      {:error, "No render/5 function found in LivePreview module"}
    end
  end

  def update(schema, entry_diff, key, prop, cache_key) do
    preview_module = get_preview_module()
    schema_module = Module.concat([schema])
    coerced_diff = Utils.coerce_struct(entry_diff, schema_module, :take_keys)

    entry = get_entry(cache_key)
    diffed_entry = Map.merge(entry, coerced_diff)
    set_entry(cache_key, diffed_entry)

    wrapper_html = preview_module.render(schema_module, diffed_entry, key, prop, cache_key)
    Brando.endpoint().broadcast("live_preview:#{cache_key}", "update", %{html: wrapper_html})
    cache_key
  end

  @doc """
  Renders the entry, stores in DB and returns URL
  """
  def share(schema, id, revision, key, prop, user) do
    preview_module = get_preview_module()

    if function_exported?(preview_module, :render, 5) do
      schema_module = Module.concat([schema])
      context = schema.module.__modules__().context

      singular =
        schema_module
        |> Module.split()
        |> List.last()
        |> Inflex.underscore()

      get_opts =
        if revision do
          %{matches: %{id: id}, revision: revision}
        else
          %{matches: %{id: id}}
        end

      {:ok, entry} = apply(context, :"get_#{singular}", [get_opts])

      html =
        schema_module
        |> preview_module.render(entry, key, prop, nil)
        |> Utils.term_to_binary()

      preview_key = Utils.random_string(12)
      expires_at = DateTime.add(DateTime.utc_now(), 24 * 60 * 60, :second)

      preview = %{
        html: html,
        preview_key: preview_key,
        expires_at: expires_at
      }

      {:ok, preview} = Brando.Sites.create_preview(preview, user)

      %{id: preview.id}
      |> Worker.PreviewPurger.new(
        scheduled_at: expires_at,
        tags: [:preview_purger]
      )
      |> Oban.insert()

      {:ok, Brando.Sites.Preview.__absolute_url__(preview)}
    end
  end

  def get_entry(cache_key) do
    case Cachex.get(:cache, "#{cache_key}__ENTRY") do
      {:ok, val} ->
        :erlang.binary_to_term(val)
    end
  end

  def set_entry(cache_key, entry) do
    Cachex.put(
      :cache,
      "#{cache_key}__ENTRY",
      :erlang.term_to_binary(entry),
      ttl: :timer.minutes(60)
    )

    entry
  end

  def get_var(cache_key, key, fallback_fn) do
    case Cachex.get(:cache, "#{cache_key}__VAR__#{key}") do
      {:ok, nil} ->
        val = fallback_fn.()
        Cachex.put(:cache, "#{cache_key}__VAR__#{key}", val, ttl: :timer.seconds(120))
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
