defmodule Brando.LivePreview do
  @moduledoc """

  Create a `MyAppWeb.LivePreview` module if it does not already exist

  ```
  use Brando.LivePreview

  preview_target Brando.Pages.Page do
    mutate_data fn entry -> %{entry | title: "custom"} end

    layout {MyAppWeb.Layouts, :app}
    template {MyAppWeb.PageHTML, "index.html"}
    template_section fn e -> e.key end

    assign :navigation, fn _ -> Brando.Navigation.get_menu("main", "en") |> elem(1) end
    assign :partials, fn _ -> Brando.Pages.get_fragments("partials") |> elem(1) end
  end
  ```
  """
  require Logger
  alias Brando.Exception.LivePreviewError
  alias Brando.Worker
  alias Brando.Utils

  @preview_coder Hashids.new(
                   alphabet: "ABCDEFGHIJKLMNOPQRSTUVWXYZ1234567890",
                   salt: "bxqStiFpm5to0gsRHyC0afyIaTOH5jjD/T+kOMU5Z9UHCLJuPVnM6ESNaMC8rkzR",
                   min_len: 32
                 )

  defstruct layout: nil,
            template: nil,
            mutate_data: nil,
            schema_preloads: [],
            template_prop: nil,
            template_section: nil,
            template_css_classes: nil

  defmacro __using__(_) do
    quote do
      import unquote(__MODULE__)
      @before_compile unquote(__MODULE__)
    end
  end

  defmacro __before_compile__(_) do
    quote generated: true do
      def has_preview_target(_), do: false
      defoverridable has_preview_target: 1
    end
  end

  @doc """
  Generates a render function for live previewing

  Set `template_prop` if your template uses another way to reference the entry than what
  is used in Vue. For instance, if in Vue it is a `project`, but you want `entry`, then
  set `template_prop :entry`

    - `schema_preloads` - List of atoms to preload on `entry``
    - `mutate_data` - function to mutate entry data `entry`
          mutate_data fn entry -> %{entry | title: "custom"} end
    - `layout` - The layout template we want to use for rendering
    - `template` - The template we want to use for rendering
    - `template_prop` - What we are refering to entry as
    - `template_section` - Run this with `put_section` on conn
    - `template_css_classes` - Run this with `put_css_classes` on conn

  """
  defmacro preview_target(schema_module, do: block) do
    quote location: :keep do
      @doc """
      `prop` - the variable name we store the entry under
      `cache_key` - unique key for this live preview
      """
      def render(unquote(schema_module), entry, cache_key) do
        var!(cache_key) = cache_key
        _ = var!(cache_key)

        var!(opts) = %Brando.LivePreview{
          mutate_data: fn e -> e end
        }

        var!(entry) = entry
        var!(extra_vars) = []

        var!(language) = Map.get(var!(entry), :language, Brando.config(:default_language))

        unquote(block)
        processed_opts = var!(opts)

        {tpl_module, template} =
          if is_function(processed_opts.template) do
            processed_opts.template.(var!(entry))
          else
            processed_opts.template
          end

        {layout_module, layout_template} = processed_opts.layout

        tpl_type = ({:__templates__, 0} in tpl_module.__info__(:functions) && :view) || :html

        layout_type =
          ({:__templates__, 0} in layout_module.__info__(:functions) && :view) || :html

        section =
          if is_function(processed_opts.template_section) do
            processed_opts.template_section.(var!(entry))
          else
            processed_opts.template_section
          end

        css_classes =
          if is_function(processed_opts.template_css_classes) do
            processed_opts.template_css_classes.(var!(entry))
          else
            processed_opts.template_css_classes
          end

        # preloads
        var!(entry) =
          var!(entry)
          |> Brando.repo().preload(processed_opts.schema_preloads)
          |> processed_opts.mutate_data.()

        atom_prop =
          if processed_opts.template_prop !== nil,
            do: processed_opts.template_prop,
            else: :entry

        villain_fields = unquote(schema_module).__villain_fields__

        var!(entry) =
          Enum.reduce(villain_fields, var!(entry), fn attr, updated_entry ->
            html_attr = Brando.Villain.get_html_field(unquote(schema_module), attr)
            atom_key = attr.name

            parsed_villain =
              Brando.Villain.parse(Map.get(var!(entry), atom_key), var!(entry),
                cache_modules: true,
                data_field: atom_key,
                html_field: html_attr.name
              )

            Map.put(updated_entry, html_attr.name, parsed_villain)
          end)

        session_opts =
          Plug.Session.init(
            store: :cookie,
            key: "_live_preview_key",
            signing_salt: "0f0f0f0"
          )

        # build conn
        conn =
          Phoenix.ConnTest.build_conn(:get, "/#{var!(language)}/__LIVE_PREVIEW")
          |> Plug.Session.call(session_opts)
          |> Plug.Conn.assign(:language, to_string(var!(language)))
          |> Plug.Conn.put_private(:brando_live_preview, true)
          |> Brando.router().browser([])
          |> Brando.Plug.HTML.put_section(section)
          |> Brando.Plug.HTML.put_css_classes(css_classes)

        render_assigns =
          (Map.to_list(conn.assigns) ++
             [
               {:conn, conn},
               {:section, section},
               {:LIVE_PREVIEW, true},
               {:language, to_string(var!(language))},
               {atom_prop, var!(entry)}
             ] ++ unquote(Macro.var(:extra_vars, nil)))
          |> Enum.into(%{})

        inner_content =
          Brando.LivePreview.render_inner_content(
            tpl_type,
            tpl_module,
            template,
            render_assigns
          )

        root_assigns =
          render_assigns
          |> Map.put(:inner_content, inner_content)
          |> Map.delete(:layout)

        Brando.LivePreview.render_layout(
          layout_type,
          layout_module,
          layout_template,
          root_assigns
        )
      end

      def has_preview_target(unquote(schema_module)), do: true
    end
  end

  def render_layout(:html, layout_module, layout_tpl, root_assigns) do
    layout_tpl = (is_binary(layout_tpl) && layout_tpl) || to_string(layout_tpl)

    Phoenix.Template.render_to_string(
      layout_module,
      layout_tpl,
      "html",
      root_assigns
    )
  end

  @deprecated "Use Phoenix.Template / html instead"
  def render_layout(:view, layout_module, layout_template, root_assigns) do
    if Code.ensure_loaded?(Phoenix.View) do
      Phoenix.View.render_to_string(
        layout_module,
        layout_template,
        root_assigns
      )
    else
      raise "live preview is using :view without Phoenix.View installed. Add `:phoenix_view` to your deps"
    end
  end

  def render_inner_content(:html, tpl_module, tpl, render_assigns) do
    tpl = (is_binary(tpl) && tpl) || to_string(tpl)
    tpl_with_type = String.replace(tpl, ".html", "")
    Phoenix.Template.render(tpl_module, tpl_with_type, "html", render_assigns)
  end

  @deprecated "Use Phoenix.Template / html instead"
  def render_inner_content(:view, tpl_module, tpl, render_assigns) do
    if Code.ensure_loaded?(Phoenix.View) do
      tpl = (is_binary(tpl) && tpl) || to_string(tpl)
      Phoenix.View.render(tpl_module, tpl, render_assigns)
    else
      raise "live preview is using :view without Phoenix.View installed. Add `:phoenix_view` to your deps"
    end
  end

  defmacro schema_preloads(schema_preloads) do
    quote do
      var!(opts) = Map.put(var!(opts), :schema_preloads, unquote(schema_preloads))
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
      var!(opts) = Map.put(var!(opts), :mutate_data, unquote(mutate_data))
    end
  end

  defmacro layout(layout) do
    quote do
      var!(opts) = Map.put(var!(opts), :layout, unquote(layout))
    end
  end

  defmacro layout_module(layout_module) do
    raise "deprecated. Use `layout {MyApp.Layouts, :app}` instead"

    quote do
      var!(opts) = Map.put(var!(opts), :layout_module, unquote(layout_module))
    end
  end

  defmacro layout_template(layout_template) do
    raise "deprecated. Use `layout {MyApp.Layouts, :app}` instead"

    quote do
      var!(opts) = Map.put(var!(opts), :layout_template, unquote(layout_template))
    end
  end

  defmacro template(template) do
    quote do
      var!(opts) = Map.put(var!(opts), :template, unquote(template))
    end
  end

  defmacro view_module(view_module) do
    raise """
    deprecated.

    Use

        template {MyApp.ProjectHTML, \"list\"}

    or

        template {MyApp.ProjectView, \"list.html\"}

    instead
    """

    quote do
      var!(opts) = Map.put(var!(opts), :view_module, unquote(view_module))
    end
  end

  defmacro view_template(view_template) do
    raise """
    deprecated.

    Use

        template {MyApp.ProjectHTML, \"list\"}

    or

        template {MyApp.ProjectView, \"list.html\"}

    instead
    """

    quote do
      var!(opts) = Map.put(var!(opts), :view_template, unquote(view_template))
    end
  end

  defmacro template_section(template_section) do
    quote do
      var!(opts) = Map.put(var!(opts), :template_section, unquote(template_section))
    end
  end

  defmacro template_css_classes(template_css_classes) do
    quote do
      var!(opts) = Map.put(var!(opts), :template_css_classes, unquote(template_css_classes))
    end
  end

  defmacro template_prop(template_prop) do
    quote do
      var!(opts) = Map.put(var!(opts), :template_prop, unquote(template_prop))
    end
  end

  @doc """
  Assign variables to be used in the live preview.

  Normally you would set the same assigns you do in your controller.

  ## Example

      assign :latest_articles, fn _entry, language ->
        # language is either the language found in the `entry` or the default site language
        MyApp.Articles.list_articles!(%{
          filter: %{featured: false, language: language},
          preload: [:category],
          order: "asc sequence,
          limit: 4
        })
      end
  """
  defmacro assign(var_name, var_value) do
    quote do
      cached_var =
        Brando.LivePreview.get_var(unquote(Macro.var(:cache_key, nil)), unquote(var_name), fn ->
          case :erlang.fun_info(unquote(var_value))[:arity] do
            0 ->
              raise LivePreviewError,
                message: """
                assign for #{inspect(unquote(var_name))} was set with a 0 arity function.

                It needs to be a 1 or 2 arity function, e.g:

                    assign :f, fn _entry, _language ->
                      # ...

                """

            1 ->
              unquote(var_value).(var!(entry))

            2 ->
              unquote(var_value).(var!(entry), var!(language))
          end
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

  def initialize(schema, changeset) do
    preview_module = Brando.live_preview()

    if function_exported?(preview_module, :render, 3) do
      cache_key = build_cache_key(:erlang.system_time())
      schema_module = Module.concat([schema])
      entry_struct = Ecto.Changeset.apply_changes(changeset)

      try do
        wrapper_html = preview_module.render(schema_module, entry_struct, cache_key)

        if Cachex.get(:cache, cache_key) == {:ok, nil} do
          Brando.LivePreview.store_cache(cache_key, wrapper_html)
        end

        Brando.endpoint().broadcast("live_preview:#{cache_key}", "update", %{html: wrapper_html})

        {:ok, cache_key}
      rescue
        err in [KeyError] ->
          Logger.error("""

          Stacktrace:

          #{Exception.format(:error, err, __STACKTRACE__)}

          """)

          if err.term[:__struct__] && err.term[:__struct__] == Ecto.Association.NotLoaded do
            {:error,
             "LivePreview is missing preload for #{inspect(err.term.__field__)}<br><br>Add `schema_preloads [#{inspect(err.term.__field__)}]` to your `preview_target`"}
          else
            {:error, "#{inspect(err, pretty: true)}"}
          end

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

          #{Exception.format(:error, err, __STACKTRACE__)}

          """)

          error_message = Map.get(err, :message, inspect(err))
          {:error, "Initialization failed.\r\n\r\n#{error_message}"}
      end
    else
      {:error, "No render/3 function found in LivePreview module"}
    end
  end

  def update(schema, changeset, cache_key) do
    # TODO: consider if it's worth trying to diff
    preview_module = Brando.live_preview()
    schema_module = Module.concat([schema])
    entry = Ecto.Changeset.apply_changes(changeset)

    wrapper_html = preview_module.render(schema_module, entry, cache_key)
    Brando.endpoint().broadcast("live_preview:#{cache_key}", "update", %{html: wrapper_html})
    cache_key
  end

  @doc """
  Renders the entry, stores in DB and returns URL
  """
  def share(schema_module, changeset, user) do
    preview_module = Brando.live_preview()

    if function_exported?(preview_module, :render, 3) do
      cache_key = build_cache_key(:erlang.system_time())
      entry_struct = Ecto.Changeset.apply_changes(changeset)

      html =
        schema_module
        |> preview_module.render(entry_struct, cache_key)
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
end
