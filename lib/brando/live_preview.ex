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
  Set `template_prop` to the assign name your template uses for the edited entry
  (`:entry` by default).

  Declare multiple targets for a schema with distinct `name` atoms. `label` and
  optional `description` identify each view in the editor's preview chooser.
  Unnamed targets use `:default`; existing single-target configurations are unchanged.
  See the [Live preview guide](live_preview.html) for a detail/listing example.

    - `schema_preloads` - List of atoms to preload on `entry`
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
          order: "asc sequence",
          limit: 4
        })
      end

  """

  use Spark.Dsl,
    default_extensions: [extensions: [Brando.LivePreview.Dsl]],
    opts_to_document: []

  require Logger
  alias Brando.Exception.LivePreviewError
  alias Brando.Utils
  alias Brando.Worker

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
    opts = get_target_config(schema_module, Keyword.get(render_opts, :target, target_name(cache_key)))
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
      |> Map.put(:secret_key_base, Brando.endpoint().config(:secret_key_base))
      |> Plug.Session.call(session_opts)
      |> Plug.Conn.assign(:language, to_string(language))
      |> Plug.Conn.put_private(:brando_live_preview, true)
      |> Plug.Conn.put_private(:brando_preview_context, preview_context())
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

  defp preview_context do
    case Brando.Authorization.Scope.current(nil) do
      %{kind: :site, site_id: site_id, environment_id: environment_id} ->
        {Brando.Tenant.Registry.get_site(site_id), Brando.Tenant.Registry.get_environment(environment_id)}

      _ ->
        nil
    end
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
    Enum.map(assigns, &process_assign(&1, entry, language, cache_key))
  end

  defp process_assign(%{key: key, value_fn: value_fn}, entry, language, cache_key) do
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

  defp build_cache_key(_seed), do: "PREVIEW-" <> Base.url_encode64(:crypto.strong_rand_bytes(24), padding: false)

  def store_cache(key, html),
    do: Cachex.put(:cache, "__live_preview__" <> key, html, expire: :timer.hours(1))

  def get_cache(key) when is_binary(key), do: Cachex.get(:cache, "__live_preview__" <> key)
  def get_cache(_), do: {:ok, nil}

  @doc """
  Clean up all Cachex entries for a live preview session.
  Runs asynchronously to avoid blocking the calling process.
  """
  def cleanup_cache(nil), do: :ok

  def cleanup_cache(cache_key) do
    Task.start(fn ->
      Cachex.del(:cache, "__live_preview__" <> cache_key)
      Brando.Authorization.Preview.cleanup(cache_key)
      Cachex.del(:cache, "#{cache_key}__TARGET__")
      invalidate_assigns(cache_key)
    end)
  end

  def initialize(schema, changeset, updated_entry_assocs \\ %{}, target \\ nil) do
    cache_key = build_cache_key(:erlang.system_time())
    schema_module = Module.concat([schema])
    entry_struct = prepare_entry_struct(changeset, updated_entry_assocs)

    try do
      with :ok <- Brando.Authorization.Preview.register(cache_key, changeset) do
        target_config = get_target_config(schema_module, target)
        wrapper_html = render(schema_module, entry_struct, cache_key, target: target_config.name)
        store_target(cache_key, target_config.name)
        store_cache(cache_key, wrapper_html)
        broadcast(cache_key, "update", %{html: wrapper_html})
        {:ok, cache_key}
      else
        _ -> {:error, "You no longer have permission to preview this entry."}
      end
    rescue
      err in [KeyError] ->
        cleanup_cache(cache_key)

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
        cleanup_cache(cache_key)
        error_message = Map.get(err, :message, inspect(err))
        {:error, "Initialization failed.\r\n\r\n#{error_message}"}
    end
  end

  def update_cache(cache_key, schema, changeset, updated_entry_assocs \\ %{}),
    do: render_update(schema, changeset, cache_key, updated_entry_assocs, nil)

  def update(_schema, _changeset, nil), do: nil

  def update(schema, changeset, cache_key, updated_entry_assocs \\ %{}),
    do: render_update(schema, changeset, cache_key, updated_entry_assocs, "update")

  def rerender(schema, changeset, cache_key, updated_entry_assocs \\ %{}),
    do: render_update(schema, changeset, cache_key, updated_entry_assocs, "rerender")

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

  def reload(schema, changeset, cache_key, updated_entry_assocs \\ %{}),
    do: render_update(schema, changeset, cache_key, updated_entry_assocs, "reload")

  defp render_update(schema, changeset, cache_key, updated_entry_assocs, event) do
    with :ok <- Brando.Authorization.Preview.authorize_write(cache_key, changeset),
         :ok <- Brando.Authorization.Preview.register(cache_key, changeset) do
      entry_struct = prepare_entry_struct(changeset, updated_entry_assocs)
      target = get_target_config(Module.concat([schema]), target_name(cache_key))
      wrapper_html = render(Module.concat([schema]), entry_struct, cache_key, target: target.name)
      store_target(cache_key, target.name)
      store_cache(cache_key, wrapper_html)
      if event, do: broadcast(cache_key, event, if(event == "reload", do: %{}, else: %{html: wrapper_html}))
      cache_key
    end
  end

  @doc "Switch the view without changing the preview session or its block subscriptions."
  def switch_target(schema, changeset, cache_key, target_name, updated_entry_assocs \\ %{}) do
    with :ok <- Brando.Authorization.Preview.authorize_write(cache_key, changeset) do
      schema_module = Module.concat([schema])
      target = get_target_config(schema_module, target_name)
      entry = prepare_entry_struct(changeset, updated_entry_assocs)
      invalidate_assigns(cache_key)
      html = render(schema_module, entry, cache_key, target: target.name)

      with :ok <- Brando.Authorization.Preview.register(cache_key, changeset) do
        store_target(cache_key, target.name)
        store_cache(cache_key, html)
        broadcast(cache_key, "reload", %{})
        {:ok, cache_key}
      end
    end
  rescue
    err ->
      Logger.error(Exception.format(:error, err, __STACKTRACE__))
      # Preserve the previous view if the new template fails. Its assigns must
      # also be recomputed after a partially rendered alternative.
      invalidate_assigns(cache_key)
      {:error, "Could not switch preview: #{Exception.message(err)}"}
  end

  @doc "The server-owned target selected for a preview session (nil for legacy sessions)."
  def target_name(cache_key) when is_binary(cache_key) do
    {:ok, name} = Cachex.get(:cache, "#{cache_key}__TARGET__")
    name
  end

  def target_name(_cache_key), do: nil

  defp store_target(cache_key, name),
    do: Cachex.put(:cache, "#{cache_key}__TARGET__", name, expire: :timer.hours(1))

  defp invalidate_assigns(cache_key) do
    {:ok, keys} = Cachex.keys(:cache)

    keys
    |> Enum.filter(&(is_binary(&1) and String.starts_with?(&1, "#{cache_key}__VAR__")))
    |> Enum.each(&Cachex.del(:cache, &1))
  end

  @doc false
  def broadcast(cache_key, event, payload) do
    with :ok <- Brando.Authorization.Preview.authorize_broadcast(cache_key) do
      Brando.endpoint().broadcast("live_preview:#{cache_key}", event, payload)
    end
  end

  @doc """
  Renders the entry, stores in DB and returns URL
  """
  def share(schema_module, changeset, user, updated_entry_assocs \\ %{}, target \\ nil) do
    with :ok <- Brando.Authorization.Preview.authorize_share(user, changeset) do
      cache_key = build_cache_key(:erlang.system_time())
      entry_struct = prepare_entry_struct(changeset, updated_entry_assocs)

      expiry_days = Brando.config(:preview_expiry_days) || 2

      html =
        schema_module
        |> render(entry_struct, cache_key, include_meta: true, target: target)
        |> Utils.term_to_binary()

      preview_key = Utils.random_string(12)
      expires_at = DateTime.add(DateTime.utc_now(), expiry_days, :day)

      preview = %{
        html: html,
        preview_key: preview_key,
        expires_at: expires_at,
        creator_id: user.id
      }

      with :ok <- Brando.Authorization.Preview.authorize_share(user, changeset),
           {:ok, preview} <- Brando.Sites.create_preview(preview, :system) do
        %{id: preview.id}
        |> Brando.Tenant.Job.attach()
        |> Worker.PreviewPurger.new(scheduled_at: expires_at, tags: [:preview_purger])
        |> Oban.insert()

        {:ok, Brando.Sites.Preview.__absolute_url__(preview), expiry_days}
      end
    end
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

  @doc "All configured views for a schema, in declaration order."
  def get_targets(schema_module) do
    Brando.live_preview()
    |> Spark.Dsl.Extension.get_entities([:live_preview])
    |> Enum.filter(&(&1.schema == schema_module))
  end

  @doc "Resolve a declared target safely from its atom or browser string name."
  def get_target_config(schema_module, name \\ nil) do
    targets = get_targets(schema_module)

    target =
      if is_nil(name) do
        Enum.find(targets, &(&1.name == :default)) || List.first(targets)
      else
        Enum.find(targets, &(to_string(&1.name) == to_string(name)))
      end

    target ||
      raise LivePreviewError,
        message: "No preview target #{inspect(name)} found for #{inspect(schema_module)}"
  end

  def has_live_preview_target(schema_module), do: get_targets(schema_module) != []

  defp prepare_entry_struct(changeset, updated_entry_assocs) do
    changeset
    |> Brando.Utils.apply_changes_recursively()
    |> Map.merge(updated_entry_assocs)
  end
end
