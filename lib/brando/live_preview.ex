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
    rerender_on_change [[:palette]]

    assign :navigation, fn _ -> Brando.Navigation.get_menu("main", "en") |> elem(1) end
    assign :partials, fn _ -> Brando.Pages.get_fragments("partials") |> elem(1) end
  end
  ```
  Set `template_prop` if your template uses another way to reference the entry than what
  is used in Vue. For instance, if in Vue it is a `project`, but you want `entry`, then
  set `template_prop :entry`

    - `schema_preloads` - List of atoms to preload on `entry``
    - `mutate_data` - function to mutate entry data `entry`
          mutate_data fn entry -> %{entry | title: "custom"} end
    - `layout` - The layout template we want to use for rendering
    - `rerender_on_change` – List of key paths that will force a rerender of the entire
      page when changed, for instance `[[:palette]]` if we have code outside of the block
      fields we must rerender when the palette changes.
    - `reassign_on_change` – List of tuples of assign name and key paths that will force a
      reassign of the assign when changed, for instance `[{:navigation, [:menu]}]` if we have
      an assign that depends on the menu.
    - `template` - The template we want to use for rendering
    - `template_prop` - What we are refering to the entry as in our template
    - `template_section` - Run this with `put_section` on conn
    - `template_css_classes` - Run this with `put_css_classes` on conn

  ## Assign

  Assign variables to be used in the live preview.

  Normally you would set the same assigns you do in your controller.

  ### Example

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

  use Spark.Dsl,
    default_extensions: [extensions: [Brando.LivePreview.Dsl]],
    opts_to_document: []

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
            rerender_on_change: [],
            reassign_on_change: [],
            schema_preloads: [],
            template_prop: nil,
            template_section: nil,
            template_css_classes: nil,
            assigns: []

  def render(schema_module, entry, cache_key, render_opts \\ []) do
    opts = Brando.LivePreview.get_target_config(schema_module)
    language = Map.get(entry, :language, Brando.config(:default_language))

    # Preload before processing assigns so that both the assign value_fns and the
    # template prop receive a fully preloaded entry. `mutate_data` is still applied
    # further down, after `process_assigns`, to preserve the existing semantics where
    # value_fns see un-mutated data.
    entry = maybe_preload(entry, opts.schema_preloads)

    processed_assigns = process_assigns(opts.assigns, entry, language, cache_key)

    {tpl_module, template} =
      if is_function(opts.template) do
        opts.template.(entry)
      else
        opts.template
      end

    {layout_module, layout_template} = opts.layout

    section =
      if is_function(opts.template_section) do
        opts.template_section.(entry)
      else
        opts.template_section
      end

    css_classes =
      if is_function(opts.template_css_classes) do
        opts.template_css_classes.(entry)
      else
        opts.template_css_classes
      end

    # `schema_preloads` is applied above, before `process_assigns`.
    entry = maybe_mutate(entry, opts.mutate_data)

    atom_prop =
      if opts.template_prop !== nil,
        do: opts.template_prop,
        else: :entry

    villain_fields = schema_module.__blocks_fields__()

    entry =
      Enum.reduce(villain_fields, entry, fn attr, updated_entry ->
        entry_blocks_relation = :"entry_#{attr.name}"
        rendered_field = :"rendered_#{attr.name}"

        parsed_villain =
          Brando.Villain.parse(Map.get(entry, entry_blocks_relation), entry,
            cache_modules: true,
            annotate_blocks: true
          )

        Map.put(updated_entry, rendered_field, parsed_villain)
      end)

    session_opts =
      Plug.Session.init(
        store: :cookie,
        key: "_live_preview_key",
        signing_salt: "0f0f0f0"
      )

    # build conn
    conn =
      Phoenix.ConnTest.build_conn(:get, "/#{language}/__LIVE_PREVIEW")
      |> Plug.Session.call(session_opts)
      |> Plug.Conn.assign(:language, to_string(language))
      |> Plug.Conn.put_private(:brando_live_preview, true)
      |> Brando.router().browser([])
      |> Brando.Plug.HTML.put_section(section)
      |> Brando.Plug.HTML.put_css_classes(css_classes)
      |> maybe_put_meta(render_opts, schema_module, entry)

    render_assigns =
      (Map.to_list(conn.assigns) ++
         [
           {:conn, conn},
           {:section, section},
           {:LIVE_PREVIEW, true},
           {:language, to_string(language)},
           {atom_prop, entry}
         ] ++ processed_assigns)
      |> Enum.into(%{})

    inner_content =
      render_inner_content(
        tpl_module,
        template,
        render_assigns
      )

    root_assigns =
      render_assigns
      |> Map.put(:inner_content, inner_content)
      |> Map.delete(:layout)

    render_layout(
      layout_module,
      layout_template,
      root_assigns
    )
  end

  defp maybe_preload(entry, []), do: entry
  defp maybe_preload(entry, preloads), do: Brando.Repo.preload(entry, preloads)

  defp maybe_mutate(entry, nil), do: entry
  defp maybe_mutate(entry, mutate_fn), do: mutate_fn.(entry)

  defp maybe_put_meta(conn, render_opts, schema_module, entry) do
    if Keyword.get(render_opts, :include_meta, false) do
      conn = Brando.Plug.HTML.put_meta(conn, schema_module, entry)

      case List.keyfind(conn.private[:brando_meta] || [], "title", 0) do
        {"title", title} -> Brando.Plug.HTML.put_title(conn, title)
        nil -> conn
      end
    else
      conn
    end
  end

  defp process_assigns(assigns, entry, language, cache_key) do
    Enum.map(assigns, fn
      %{key: key, value_fn: value_fn} ->
        case :erlang.fun_info(value_fn)[:arity] do
          0 ->
            raise LivePreviewError,
              message: """
              assign for #{inspect(key)} was set with a 0 arity function.

              It needs to be a 1 or 2 arity function, e.g:

                  assign :f, fn _entry, _language ->
                    # ...

              """

          1 ->
            resolve_cached_var(cache_key, key, fn -> value_fn.(entry) end)

          2 ->
            resolve_cached_var(cache_key, key, fn -> value_fn.(entry, language) end)
        end
    end)
  end

  defp render_layout(layout_module, layout_tpl, root_assigns) do
    layout_tpl = (is_binary(layout_tpl) && layout_tpl) || to_string(layout_tpl)

    Phoenix.Template.render_to_string(
      layout_module,
      layout_tpl,
      "html",
      root_assigns
    )
  end

  defp render_inner_content(tpl_module, tpl, render_assigns) do
    tpl = (is_binary(tpl) && tpl) || to_string(tpl)
    tpl_with_type = String.replace(tpl, ".html", "")
    Phoenix.Template.render(tpl_module, tpl_with_type, "html", render_assigns)
  end

  defp build_cache_key(seed), do: "PREVIEW-" <> Hashids.encode(@preview_coder, seed)

  def store_cache(key, html),
    do: Cachex.put(:cache, "__live_preview__" <> key, html, expire: :timer.hours(1))

  def get_cache(key), do: Cachex.get(:cache, "__live_preview__" <> key)

  @doc """
  Clean up all Cachex entries for a live preview session.
  Runs asynchronously to avoid blocking the calling process.
  """
  def cleanup_cache(nil), do: :ok

  def cleanup_cache(cache_key) do
    Task.start(fn ->
      Cachex.del(:cache, "__live_preview__" <> cache_key)

      {:ok, keys} = Cachex.keys(:cache)

      keys
      |> Enum.filter(fn
        key when is_binary(key) -> String.starts_with?(key, "#{cache_key}__VAR__")
        _ -> false
      end)
      |> Enum.each(&Cachex.del(:cache, &1))
    end)
  end

  def initialize(schema, changeset, updated_entry_assocs \\ %{}) do
    cache_key = build_cache_key(:erlang.system_time())
    schema_module = Module.concat([schema])
    entry_struct = prepare_entry_struct(changeset, updated_entry_assocs)

    try do
      wrapper_html = render(schema_module, entry_struct, cache_key)
      store_cache(cache_key, wrapper_html)

      Brando.endpoint().broadcast("live_preview:#{cache_key}", "update", %{html: wrapper_html})

      {:ok, cache_key}
    rescue
      err in [KeyError] ->
        Logger.error("""

        Stacktrace:

        #{Exception.format(:error, err, __STACKTRACE__)}

        """)

        if match?(%Ecto.Association.NotLoaded{}, Map.get(err, :term)) do
          field = err.term |> Map.from_struct() |> Map.get(:__field__)

          {:error,
           "LivePreview is missing preload for #{inspect(field)}<br><br>Add `schema_preloads [#{inspect(field)}]` to your `preview_target`"}
        else
          {:error, "#{inspect(err, pretty: true)}"}
        end

      err ->
        error_message = Map.get(err, :message, inspect(err))
        {:error, "Initialization failed.\r\n\r\n#{error_message}"}
    end
  end

  def update_cache(cache_key, schema, changeset, updated_entry_assocs \\ %{}) do
    schema_module = Module.concat([schema])
    entry_struct = prepare_entry_struct(changeset, updated_entry_assocs)
    wrapper_html = render(schema_module, entry_struct, cache_key)
    store_cache(cache_key, wrapper_html)
  end

  def update(_schema, _changeset, nil), do: nil

  def update(schema, changeset, cache_key, updated_entry_assocs \\ %{}) do
    schema_module = Module.concat([schema])
    entry_struct = prepare_entry_struct(changeset, updated_entry_assocs)
    wrapper_html = render(schema_module, entry_struct, cache_key)
    store_cache(cache_key, wrapper_html)
    Brando.endpoint().broadcast("live_preview:#{cache_key}", "update", %{html: wrapper_html})
    cache_key
  end

  def rerender(schema, changeset, cache_key, updated_entry_assocs \\ %{}) do
    schema_module = Module.concat([schema])
    entry_struct = prepare_entry_struct(changeset, updated_entry_assocs)
    wrapper_html = render(schema_module, entry_struct, cache_key)
    Brando.endpoint().broadcast("live_preview:#{cache_key}", "rerender", %{html: wrapper_html})
  end

  @doc """
  Refresh the cached HTML for `cache_key` and tell the iframe to reload itself.

  Used when a change introduces new content whose frontend players must be
  JS-mounted (a newly selected video/gallery/image). A morphdom `rerender` can
  swap the DOM but can't run the host frontend's boot for new media, so it would
  leave a gray box. Reloading the iframe re-fetches the (now refreshed) cached
  HTML and lets the frontend mount the player — exactly like opening the preview.

  Critically this keeps the SAME `cache_key`: minting a new one would desync the
  key held by every block component and break subsequent morphdom updates.
  """
  def reload(_schema, _changeset, nil), do: nil

  def reload(schema, changeset, cache_key, updated_entry_assocs \\ %{}) do
    schema_module = Module.concat([schema])
    entry_struct = prepare_entry_struct(changeset, updated_entry_assocs)
    wrapper_html = render(schema_module, entry_struct, cache_key)
    store_cache(cache_key, wrapper_html)
    Brando.endpoint().broadcast("live_preview:#{cache_key}", "reload", %{})
    cache_key
  end

  @doc """
  Renders the entry, stores in DB and returns URL
  """
  def share(schema_module, changeset, user, updated_entry_assocs \\ %{}) do
    cache_key = build_cache_key(:erlang.system_time())
    entry_struct = prepare_entry_struct(changeset, updated_entry_assocs)

    expiry_days = Brando.config(:preview_expiry_days) || 2

    html =
      schema_module
      |> render(entry_struct, cache_key, include_meta: true)
      |> Utils.term_to_binary()

    preview_key = Utils.random_string(12)
    expires_at = DateTime.add(DateTime.utc_now(), expiry_days, :day)

    preview = %{
      html: html,
      preview_key: preview_key,
      expires_at: expires_at
    }

    {:ok, preview} = Brando.Sites.create_preview(preview, user)

    %{id: preview.id}
    |> Worker.PreviewPurger.new(scheduled_at: expires_at, tags: [:preview_purger])
    |> Oban.insert()

    {:ok, Brando.Sites.Preview.__absolute_url__(preview), expiry_days}
  end

  defp resolve_cached_var(cache_key, key, value_fn) do
    case get_var(cache_key, key) do
      :not_set -> {key, set_var(cache_key, key, value_fn.())}
      value -> {key, value}
    end
  end

  def get_var(cache_key, key) do
    case Cachex.get(:cache, "#{cache_key}__VAR__#{key}") do
      {:ok, nil} -> :not_set
      {:ok, val} -> val
    end
  end

  def set_var(cache_key, key, value) do
    Cachex.put(:cache, "#{cache_key}__VAR__#{key}", value, expire: :timer.seconds(120))
    value
  end

  def invalidate_var(cache_key, key) do
    Cachex.del(:cache, "#{cache_key}__VAR__#{key}")
  end

  def get_target_config(schema_module) do
    Brando.live_preview()
    |> Spark.Dsl.Extension.get_entities([:live_preview])
    |> Enum.find(&(&1.schema == schema_module))
    |> case do
      nil ->
        raise LivePreviewError, message: "No preview target found for #{inspect(schema_module)}"

      target_config ->
        target_config
    end
  end

  def has_live_preview_target(schema_module) do
    Brando.live_preview()
    |> Spark.Dsl.Extension.get_entities([:live_preview])
    |> Enum.any?(&(&1.schema == schema_module))
  end

  defp prepare_entry_struct(changeset, updated_entry_assocs) do
    changeset
    |> Brando.Utils.apply_changes_recursively()
    |> Map.merge(updated_entry_assocs)
  end

  defmodule Legacy do
    # This is here to basically support the migration script
    @deprecated "use layout/1 instead"
    defmacro layout_module(_) do
      nil
    end

    @deprecated "use template/1 instead"
    defmacro view_module(_) do
      nil
    end

    @deprecated "use template/1 instead"
    defmacro view_template(_) do
      nil
    end
  end
end
