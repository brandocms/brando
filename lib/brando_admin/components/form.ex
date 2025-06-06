defmodule BrandoAdmin.Components.Form do
  @moduledoc """
  Form component for BrandoAdmin

  This component is used to render forms in BrandoAdmin, and is the heart of the admin interface.

  ## Flow

  ### Entry fields

  When changing form fields for an entry that has a block field, we will signal to update
  each block's liquex splits and also the live preview.

  In the form's "change" event, we extract the "target" and if there are blocks that want
  entry updates, we will send a message to the blocks with the "path" to the field and
  its new value to update their liquex splits and live preview.

  If we change entry fields that are assocs, for instance image fields, file fields, selects
  and multi selects, we will signal to update the entry relation from the live component.

  ### Block variables


  """
  use BrandoAdmin, :live_component
  use BrandoAdmin.Translator

  use Gettext, backend: Brando.Gettext
  import Ecto.Changeset
  import Phoenix.LiveView.TagEngine

  alias Brando.Villain
  alias BrandoAdmin.Components.Button
  alias BrandoAdmin.Components.SplitDropdown
  alias BrandoAdmin.Components.Content
  alias BrandoAdmin.Components.FilePicker
  alias BrandoAdmin.Components.ImagePicker
  alias BrandoAdmin.Components.Form.Fieldset
  alias BrandoAdmin.Components.Form.Input
  alias BrandoAdmin.Components.Form.Input.Blocks.Utils
  alias BrandoAdmin.Components.Form.Input.Image.FocalPoint
  alias BrandoAdmin.Components.Form.Input.MultiSelect
  alias BrandoAdmin.Components.Form.Input.Select
  alias BrandoAdmin.Components.Form.AlternatesDrawer
  alias BrandoAdmin.Components.Form.BlockField
  alias BrandoAdmin.Components.Form.MetaDrawer
  alias BrandoAdmin.Components.Form.RevisionsDrawer
  alias BrandoAdmin.Components.Form.ScheduledPublishingDrawer

  def mount(socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(Brando.pubsub(), "brando:modules")
    end

    # TODO: maybe check oban queue for :processing_images?
    {:ok,
     socket
     |> assign(:edit_image, %{path: [], field: nil, relation_field: nil})
     |> assign(:edit_file, %{path: [], field: nil, relation_field: nil})
     |> assign(:updated_entry_assocs, %{})
     |> assign(:file_changeset, nil)
     |> assign(:image_changeset, nil)
     |> assign(:initial_update, true)
     |> assign(:dirty_fields, [])
     |> assign(:editing_image?, false)
     |> assign(:editing_file?, false)
     |> assign(:processing_images, [])
     |> assign(:presences, %{})
     |> assign(:transformer_defaults, %{})
     |> assign(:has_meta?, false)
     |> assign(:status_revisions, :closed)
     |> assign(:processing, false)
     |> assign(:save_redirect_target, :listing)
     |> assign(:live_preview_target, "desktop")
     |> assign(:live_preview_ready?, false)
     |> assign(:live_preview_active?, false)
     |> assign(:live_preview_cache_key, nil)
     |> assign(:blocks_wanting_entry, [])
     |> assign(:blocks_ready_for_sharing, false)
     |> assign(:fields_demanding_full_live_preview_rerender, [])
     |> assign(:fields_demanding_live_preview_reassign, [])}
  end

  def update(%{action: :image_processed, image_id: id}, socket) do
    {:ok, update(socket, :processing_images, &Enum.reject(&1, fn proc_id -> proc_id == id end))}
  end

  # edit_file
  def update(%{action: :update_edit_file, file: file}, %{assigns: %{edit_file: edit_file}} = socket) do
    updated_edit_file = Map.merge(edit_file, %{file: file, id: file.id})
    file_changeset = change(file)

    {:ok,
     socket
     |> assign(:edit_file, updated_edit_file)
     |> assign(:file_changeset, file_changeset)}
  end

  def update(%{action: :update_edit_file, edit_file: %{file: nil} = edit_file}, socket) do
    file_changeset = change(%Brando.Files.File{})

    {:ok,
     socket
     |> assign(:edit_file, edit_file)
     |> assign(:editing_file?, true)
     |> assign(:file_changeset, file_changeset)}
  end

  def update(%{action: :update_edit_file, edit_file: %{file: file} = edit_file}, socket) do
    file_changeset = change(file)

    {:ok,
     socket
     |> assign(:edit_file, edit_file)
     |> assign(:editing_file?, true)
     |> assign(:file_changeset, file_changeset)}
  end

  # edit_image
  def update(%{action: :update_edit_image, image: image}, %{assigns: %{edit_image: edit_image}} = socket) do
    updated_edit_image = Map.merge(edit_image, %{image: image, id: image.id})
    image_changeset = change(image)

    {:ok,
     socket
     |> assign(:edit_image, updated_edit_image)
     |> assign(:image_changeset, image_changeset)}
  end

  def update(
        %{action: :update_edit_image, edit_image: %{image: nil} = edit_image},
        socket
      ) do
    image_changeset = change(%Brando.Images.Image{})

    {:ok,
     socket
     |> assign(:edit_image, edit_image)
     |> assign(:editing_image?, true)
     |> assign(:image_changeset, image_changeset)}
  end

  def update(%{action: :update_edit_image, edit_image: %{image: image} = edit_image}, socket) do
    image_changeset = change(image)

    {:ok,
     socket
     |> assign(:edit_image, edit_image)
     |> assign(:editing_image?, true)
     |> assign(:image_changeset, image_changeset)}
  end

  def update(
        %{event: "update_live_preview_block", rendered_html: rendered_html, uid: uid, has_children?: has_children?},
        socket
      ) do
    cache_key = socket.assigns.live_preview_cache_key

    Brando.endpoint().broadcast("live_preview:#{cache_key}", "update_block", %{
      uid: uid,
      rendered_html: rendered_html,
      has_children: has_children?
    })

    {:ok, socket}
  end

  def update(%{event: "get_live_preview_status", cid: cid}, socket) do
    cache_key = socket.assigns.live_preview_cache_key
    live_preview_active = socket.assigns.live_preview_active?
    event = (live_preview_active && "enable_live_preview") || "disable_live_preview"

    send_update(cid, %{
      event: event,
      cache_key: cache_key
    })

    {:ok, socket}
  end

  def update(%{event: "update_live_preview"}, %{assigns: %{live_preview_active?: true}} = socket) do
    # update entire live preview (when deleting or inserting blocks)
    {:ok, fetch_root_blocks(socket, :live_preview_update, 0)}
  end

  def update(%{event: "update_live_preview"}, %{assigns: %{live_preview_active?: false}} = socket) do
    {:ok, socket}
  end

  def update(%{event: "register_block_wanting_entry", cid: cid}, socket) do
    {:ok, update(socket, :blocks_wanting_entry, &Enum.uniq(&1 ++ [cid]))}
  end

  # from select, image, file, etc.
  def update(%{event: "update_entry_relation", path: path, updated_relation: updated_relation} = params, socket) do
    live_preview_active? = socket.assigns.live_preview_active?

    force_live_preview_update =
      live_preview_active? && Map.get(params, :force_live_preview_update, false)

    fields_demanding_full_live_preview_rerender =
      socket.assigns.fields_demanding_full_live_preview_rerender

    access_path = Brando.Utils.build_access_path(path)

    updated_entry_assocs =
      put_in(socket.assigns.updated_entry_assocs, access_path, updated_relation)

    full_rerender? =
      live_preview_active? &&
        Enum.any?(fields_demanding_full_live_preview_rerender, &(&1 == path))

    socket
    |> assign(:updated_entry_assocs, updated_entry_assocs)
    |> maybe_invalidate_live_preview_assign(path)
    |> maybe_full_rerender_live_preview(full_rerender?)
    |> maybe_force_live_preview_update(full_rerender?, force_live_preview_update)
    |> then(&{:ok, &1})
  end

  # TODO: rewrite to event: "update_entry_relation
  def update(
        %{
          action: :update_entry_relation,
          updated_relation: updated_relation,
          path: [:transformer, relation_key, asset_key, image_id],
          force_validation: true
        },
        socket
      ) do
    schema = socket.assigns.schema
    changeset = socket.assigns.form.source
    entries = get_field(changeset, relation_key)
    assoc_type = Brando.Blueprint.Relations.__relation__(schema, relation_key).type

    case Enum.find_index(entries, &(Map.get(&1, :"#{asset_key}_id") == image_id)) do
      nil ->
        {:ok, socket}

      idx ->
        updated_entries =
          put_in(entries, [Access.at(idx), Access.key(asset_key)], updated_relation)

        updated_changeset =
          (assoc_type == :has_many && put_assoc(changeset, relation_key, updated_entries)) ||
            put_embed(changeset, relation_key, updated_entries)

        {:ok,
         socket
         |> assign(:form, to_form(updated_changeset, []))
         |> force_svelte_remounts()}
    end
  end

  def update(
        %{action: :update_entry_relation, updated_relation: updated_relation, path: path, force_validation: true},
        %{assigns: %{entry: entry, schema: schema}} = socket
      ) do
    entry_or_default = entry || struct(schema)
    access_path = Brando.Utils.build_access_path(path)

    updated_entry = put_in(entry_or_default, access_path, updated_relation)

    {:ok,
     socket
     |> assign(:entry, updated_entry)
     |> push_event("b:validate", %{})
     |> force_svelte_remounts()}
  end

  def update(
        %{action: :update_entry_relation, updated_relation: updated_relation, path: path},
        %{assigns: %{entry: entry, schema: schema}} = socket
      ) do
    entry_or_default = entry || struct(schema)
    access_path = Brando.Utils.build_access_path(path)
    updated_entry = put_in(entry_or_default, access_path, updated_relation)

    {:ok, assign(socket, entry, updated_entry)}
  end

  def update(%{action: :update_entry_hard_reset, updated_entry: updated_entry}, socket) do
    myself = socket.assigns.myself
    send_update_after(myself, %{event: "set_block_map"}, 1000)
    send(self(), {:progress_popup, "Setting new block map..."})

    socket
    |> assign(:entry, updated_entry)
    |> assign_refreshed_form()
    |> assign(:block_map, [])
    |> assign_entry_for_blocks()
    |> clear_blocks_root_changesets()
    |> reload_all_blocks()
    |> force_svelte_remounts()
    |> then(&{:ok, &1})
  end

  def update(%{action: :update_entry, updated_entry: updated_entry}, socket) do
    %{schema: schema, current_user: current_user} = socket.assigns
    new_changeset = schema.changeset(updated_entry, %{}, current_user)
    myself = socket.assigns.myself

    send_update_after(myself, %{event: "set_block_map"}, 500)

    {:ok,
     socket
     |> assign(:entry, updated_entry)
     |> assign(:form, to_form(new_changeset, []))
     |> assign(:block_map, [])
     |> force_svelte_remounts()}
  end

  def update(%{updated_entry: updated_entry}, %{assigns: %{schema: schema, current_user: current_user}} = socket) do
    raise "DEPRECATE form.ex:updated_entry —— use action: :update_entry instead"
    new_changeset = schema.changeset(updated_entry, %{}, current_user)

    {:ok,
     socket
     |> assign(:form, to_form(new_changeset, []))
     |> force_svelte_remounts()}
  end

  def update(%{event: "set_block_map"}, socket) do
    {:ok,
     socket
     |> assign_block_map()
     |> assign_entry_for_blocks()}
  end

  # got all root changesets for the block field
  def update(
        %{event: "provide_root_blocks", root_changesets: root_changesets, block_field: block_field, tag: tag},
        socket
      ) do
    block_changesets = socket.assigns.block_changesets

    list_of_changesets =
      root_changesets
      |> Enum.reduce([], fn
        {_key, nil}, acc -> acc
        {_key, cs}, acc -> [Brando.Utils.set_action(cs) | acc]
      end)
      |> Enum.reverse()

    updated_block_changesets = Map.put(block_changesets, block_field, list_of_changesets)

    {:ok,
     socket
     |> assign(:block_changesets, updated_block_changesets)
     |> event_tag_received(tag)}
  end

  def update(%{action: :update_changeset, changeset: updated_changeset, force_validation: true}, socket) do
    {:ok,
     socket
     |> assign(:form, to_form(updated_changeset, []))
     |> push_event("b:validate", %{})
     |> force_svelte_remounts()}
  end

  def update(%{action: :update_changeset, changeset: updated_changeset}, socket) do
    updated_form = to_form(updated_changeset, [])

    {:ok, assign(socket, :form, updated_form)}
  end

  def update(
        %{updated_gallery_image: %{path: path} = updated_gallery_image, key: key},
        %{assigns: %{changeset: changeset}} = socket
      ) do
    images =
      changeset
      |> get_field(key)
      |> Enum.map(fn
        %{path: ^path} -> updated_gallery_image
        img -> img
      end)

    updated_changeset = put_change(changeset, key, images)

    {:ok,
     socket
     |> assign(:form, to_form(updated_changeset, []))
     |> assign(:processing, false)}
  end

  def update(
        %{action: :refresh_entry},
        %{
          assigns: %{
            schema: schema,
            entry_id: entry_id,
            singular: singular,
            context: context,
            form_blueprint: form_blueprint,
            current_user: current_user
          }
        } = socket
      ) do
    query_params =
      entry_id
      |> maybe_query(form_blueprint)
      |> add_preloads(schema, form_blueprint)
      |> Map.put(:with_deleted, true)

    updated_entry = apply(context, :"get_#{singular}!", [query_params])

    updated_changeset =
      updated_entry
      |> schema.changeset(%{}, current_user)
      |> Map.put(:action, :validate)

    {:ok,
     socket
     |> assign(:entry, updated_entry)
     |> assign(:form, to_form(updated_changeset))
     |> force_svelte_remounts()}
  end

  # only used for allowing global sets to add "select" options.
  def update(%{action: :add_select_var_option, var_key: var_key}, socket) do
    changeset = socket.assigns.form.source
    globals = get_field(changeset, :globals) || []

    updated_globals =
      Enum.reduce(globals, [], fn
        %{key: ^var_key} = var, acc ->
          acc ++
            [
              put_in(
                var,
                [Access.key(:options)],
                (var.options || []) ++
                  [%Brando.Content.Var.Option{label: "label", value: "option"}]
              )
            ]

        var, acc ->
          acc ++ [var]
      end)

    updated_changeset = put_change(changeset, :globals, updated_globals)
    updated_form = to_form(updated_changeset, [])

    {:ok, assign(socket, :form, updated_form)}
  end

  def update(assigns, socket) do
    form_name = assigns[:name] || :default

    {:ok,
     socket
     |> assign(assigns)
     |> assign_new(:entry_id, fn -> nil end)
     |> assign_new(:singular, fn -> assigns.schema.__naming__().singular end)
     |> assign_new(:context, fn -> assigns.schema.__modules__().context end)
     |> assign_new(:form_blueprint, fn ->
       case assigns.schema.__form__(form_name) do
         nil ->
           raise Brando.Exception.BlueprintError,
             message: "Missing `#{form_name}` form declaration for `#{inspect(assigns.schema)}`"

         form ->
           form
       end
     end)
     |> assign_new(:header, fn ->
       IO.warn("""

       No <:header> slot is defined for form component with schema `#{inspect(assigns.schema)}`.

       It is recommended to use this instead of a standalone `<Content.header>` component
       for better integration with Live Previews!

       Example:

           <.live_component module={Form}
             id="page_form"
             entry_id={@entry_id}
             current_user={@current_user}
             schema={@schema}>
             <:header>
               <%= gettext("Edit page") %>
             </:header>
           </.live_component>

       """)

       nil
     end)
     |> assign_new(:instructions, fn -> [] end)
     |> assign_entry()
     |> assign_addon_statuses()
     |> assign_default_params()
     |> extract_tab_names()
     |> assign_form()
     |> maybe_assign_uploads()
     |> maybe_assign_block_map()
     |> maybe_assign_entry_for_blocks()
     |> assign(:initial_update, false)}
  end

  defp assign_entry(%{assigns: %{initial_update: false}} = socket) do
    socket
  end

  defp assign_entry(%{assigns: %{entry_id: nil}} = socket) do
    schema = socket.assigns.schema
    current_user = socket.assigns.current_user
    assign(socket, :entry, prepare_empty_entry(schema, current_user))
  end

  defp assign_entry(socket) do
    schema = socket.assigns.schema
    form_blueprint = socket.assigns.form_blueprint
    entry_id = socket.assigns.entry_id
    singular = socket.assigns.singular
    context = socket.assigns.context

    query_params =
      entry_id
      |> maybe_query(form_blueprint)
      |> add_preloads(schema, form_blueprint)
      |> Map.put(:with_deleted, true)

    entry =
      case apply(context, :"get_#{singular}", [query_params]) do
        {:ok, entry} ->
          entry

        {:error, _err} ->
          raise Brando.Exception.EntryNotFoundError
      end

    assign(socket, :entry, entry)
  end

  defp assign_refreshed_entry(
         %{
           assigns: %{
             schema: schema,
             entry_id: entry_id,
             singular: singular,
             context: context,
             form_blueprint: form_blueprint
           }
         } = socket
       ) do
    query_params =
      entry_id
      |> maybe_query(form_blueprint)
      |> add_preloads(schema, form_blueprint)
      |> Map.put(:with_deleted, true)

    assign(socket, :entry, apply(context, :"get_#{singular}!", [query_params]))
  end

  defp maybe_query(id, form_blueprint) do
    if form_blueprint.query do
      form_blueprint.query.(id)
    else
      %{matches: %{id: id}}
    end
  end

  defp maybe_assign_uploads(socket) do
    if connected?(socket) && socket.assigns[:initial_update] do
      allow_uploads(socket)
    else
      socket
    end
  end

  defp maybe_force_live_preview_update(socket, true, _) do
    socket
  end

  defp maybe_force_live_preview_update(socket, false, true) do
    fetch_root_blocks(socket, :live_preview_update, 0)
    socket
  end

  defp maybe_force_live_preview_update(socket, _, _) do
    socket
  end

  defp maybe_full_rerender_live_preview(socket, true) do
    fetch_root_blocks(socket, :live_preview_full_rerender, 1200)
    socket
  end

  defp maybe_full_rerender_live_preview(socket, false) do
    socket
  end

  defp maybe_assign_block_map(socket) do
    schema = socket.assigns.schema
    form_blueprint = socket.assigns.form_blueprint
    blocks = form_blueprint.blocks
    entry = socket.assigns.entry

    socket
    |> assign_new(:block_map, fn ->
      case socket.assigns.has_blocks? do
        true ->
          Enum.map(
            blocks,
            &{
              &1.name,
              Module.concat(schema, "Blocks"),
              Map.get(entry, :"entry_#{&1.name}"),
              &1.opts
            }
          )

        false ->
          []
      end
    end)
    |> assign_new(:block_changesets, fn ->
      Map.new(blocks, &{&1.name, nil})
    end)
  end

  defp assign_block_map(socket) do
    schema = socket.assigns.schema
    form_blueprint = socket.assigns.form_blueprint
    blocks = form_blueprint.blocks
    entry = socket.assigns.entry

    block_map =
      case socket.assigns.has_blocks? do
        true ->
          Enum.map(
            blocks,
            &{
              &1.name,
              Module.concat(schema, "Blocks"),
              Map.get(entry, :"entry_#{&1.name}"),
              &1.opts
            }
          )

        false ->
          []
      end

    block_changesets = Map.new(blocks, &{&1.name, nil})

    socket
    |> assign(:block_map, block_map)
    |> assign(:block_changesets, block_changesets)
  end

  defp add_preloads(query_params, schema, %{query: nil}) do
    default_preloads = Map.get(query_params, :preload, [])
    schema_preloads = Brando.Blueprint.preloads_for(schema)
    preloads = Enum.uniq(schema_preloads ++ default_preloads)

    Map.put(
      query_params,
      :preload,
      preloads
    )
  end

  # if we have a custom form_query, just pass it through.
  defp add_preloads(query_params, _schema, _form) do
    query_params
  end

  defp assign_addon_statuses(%{assigns: %{schema: schema, entry: entry}} = socket) do
    # TODO: turn each into an assign_new
    assign(socket,
      has_blocks?: schema.has_trait(Brando.Trait.Blocks),
      has_meta?: schema.has_trait(Brando.Trait.Meta),
      has_revisioning?: schema.has_trait(Brando.Trait.Revisioned),
      has_scheduled_publishing?: schema.has_trait(Brando.Trait.ScheduledPublishing),
      has_alternates?: (schema.has_trait(Brando.Trait.Translatable) and schema.has_alternates?()) && entry.id,
      has_live_preview?: check_live_preview(schema)
    )
  end

  defp check_live_preview(schema) do
    Code.ensure_compiled!(Brando.live_preview())
    Brando.LivePreview.has_live_preview_target(schema)
  end

  defp assign_default_params(%{assigns: %{initial_params: initial_params}} = socket)
       when not is_nil(initial_params) and map_size(initial_params) > 0 do
    assign_new(socket, :default_params, fn -> initial_params end)
  end

  defp assign_default_params(%{assigns: %{form_blueprint: %{default_params: default_params}}} = socket)
       when is_map(default_params) and map_size(default_params) > 0 do
    assign_new(socket, :default_params, fn -> default_params end)
  end

  defp assign_default_params(%{assigns: %{form_blueprint: %{default_params: %{}}}} = socket) do
    assign_new(socket, :default_params, fn -> %{} end)
  end

  defp assign_default_params(%{assigns: %{name: name, schema: schema}}) do
    raise Brando.Exception.BlueprintError,
      message: "Missing form `#{inspect(name)}` for `#{inspect(schema)}`"
  end

  defp force_svelte_remounts(socket) do
    push_event(socket, "b:component:remount", %{})
  end

  defp extract_tab_names(%{assigns: %{form_blueprint: %{tabs: tabs}}} = socket) do
    socket
    |> assign_new(:active_tab, fn ->
      first_tab = List.first(tabs)
      Map.get(first_tab, :name)
    end)
    |> assign_new(:tabs, fn -> Enum.map(tabs, & &1.name) end)
  end

  def prepare_empty_entry(schema, current_user) do
    schema
    |> struct()
    |> maybe_put_language(current_user)
    |> nil_relations(schema)
  end

  def nil_relations(entry, schema) do
    preloads = Brando.Blueprint.preloads_for(schema)
    Brando.Repo.preload(entry, preloads)
  end

  def maybe_put_language(%{language: _} = entry, current_user) do
    lang_atom = String.to_existing_atom(current_user.config.content_language)
    Map.put(entry, :language, lang_atom)
  end

  def maybe_put_language(entry, _) do
    entry
  end

  def event_tag_received(socket, :save) do
    block_changesets = socket.assigns.block_changesets

    if Enum.any?(Map.values(block_changesets), &is_nil/1) do
      socket
    else
      socket
      |> assign(:all_blocks_received?, true)
      |> push_event("b:submit", %{})
    end
  end

  def event_tag_received(socket, :share) do
    changeset = socket.assigns.form.source
    block_changesets = socket.assigns.block_changesets
    updated_entry_assocs = socket.assigns.updated_entry_assocs

    if Enum.any?(Map.values(block_changesets), &is_nil/1) do
      socket
    else
      schema = socket.assigns.schema
      changeset = assoc_all_block_fields(block_changesets, changeset)
      user = socket.assigns.current_user

      {:ok, preview_url, expiration_days} =
        Brando.LivePreview.share(
          schema,
          changeset,
          user,
          updated_entry_assocs
        )

      message =
        gettext(
          ~s(A shareable time limited URL has been created. The URL will expire %{expiration_days} days from now.<br><br><a href="%{preview_url}" target="_blank">OPEN LINK</a>),
          %{expiration_days: expiration_days, preview_url: preview_url}
        )

      socket
      |> clear_blocks_root_changesets()
      |> push_event("b:alert", %{
        title: gettext("Get shareable link"),
        message: message,
        type: "info"
      })
    end
  end

  def event_tag_received(socket, :live_preview) do
    block_changesets = socket.assigns.block_changesets
    changeset = socket.assigns.form.source
    updated_entry_assocs = socket.assigns.updated_entry_assocs

    if Enum.any?(Map.values(block_changesets), &is_nil/1) do
      socket
    else
      # initialize live preview
      schema = socket.assigns.schema
      form_blueprint = socket.assigns.form_blueprint
      changeset = assoc_all_block_fields(block_changesets, changeset)

      if changeset.errors == [] do
        # fetch all blocks' rendered_html
        case Brando.LivePreview.initialize(schema, changeset, updated_entry_assocs) do
          {:ok, cache_key} ->
            socket
            |> assign(:live_preview_active?, true)
            |> assign(:live_preview_cache_key, cache_key)
            |> enable_live_preview_in_blocks()
            |> clear_blocks_root_changesets()
            |> assign_entry_fields_demanding_live_preview_rerender(schema)
            |> assign_entry_fields_demanding_live_preview_reassign(schema)
            |> push_event("b:live_preview", %{cache_key: cache_key})

          {:error, err} ->
            require Logger

            Logger.error("""
            => Live Preview error: #{inspect(err)}
            """)

            push_event(socket, "b:alert", %{
              title: "Live Preview error",
              message: err,
              type: "error"
            })
        end
      else
        socket
        |> clear_blocks_root_changesets()
        |> push_errors(changeset, form_blueprint, schema)
      end
    end
  end

  def event_tag_received(socket, :live_preview_standalone) do
    block_changesets = socket.assigns.block_changesets
    updated_entry_assocs = socket.assigns.updated_entry_assocs

    if Enum.any?(Map.values(block_changesets), &is_nil/1) do
      socket
    else
      # initialize live preview
      schema = socket.assigns.schema
      form_blueprint = socket.assigns.form_blueprint
      changeset = assoc_all_block_fields(block_changesets, socket.assigns.form.source)

      if changeset.errors == [] do
        cache_key = socket.assigns.live_preview_cache_key
        schema = socket.assigns.schema

        Brando.LivePreview.update_cache(cache_key, schema, changeset, updated_entry_assocs)
        send(self(), {:toast, gettext("Opening standalone live preview...")})

        url = "/__livepreview?key=#{cache_key}&mode=standalone"

        socket
        |> clear_blocks_root_changesets()
        |> push_event("b:open_window", %{url: url})
      else
        socket
        |> clear_blocks_root_changesets()
        |> push_errors(changeset, form_blueprint, schema)
      end
    end
  end

  def event_tag_received(socket, :live_preview_full_rerender) do
    block_changesets = socket.assigns.block_changesets
    changeset = socket.assigns.form.source
    cache_key = socket.assigns.live_preview_cache_key
    updated_entry_assocs = socket.assigns.updated_entry_assocs

    if Enum.any?(Map.values(block_changesets), &is_nil/1) do
      socket
    else
      schema = socket.assigns.schema
      changeset = assoc_all_block_fields(block_changesets, changeset)
      Brando.LivePreview.rerender(schema, changeset, cache_key, updated_entry_assocs)
      clear_blocks_root_changesets(socket)
    end
  end

  # when inserting or deleting blocks we want a full rerender of the live preview.
  def event_tag_received(socket, :live_preview_update) do
    block_changesets = socket.assigns.block_changesets
    changeset = socket.assigns.form.source
    cache_key = socket.assigns.live_preview_cache_key
    updated_entry_assocs = socket.assigns.updated_entry_assocs

    if Enum.any?(Map.values(block_changesets), &is_nil/1) do
      socket
    else
      schema = socket.assigns.schema
      changeset = assoc_all_block_fields(block_changesets, changeset)
      Brando.LivePreview.update(schema, changeset, cache_key, updated_entry_assocs)
      clear_blocks_root_changesets(socket)
    end
  end

  def event_tag_received(socket, tag) do
    socket
    |> clear_blocks_root_changesets()
    |> push_event("b:alert", %{
      title: gettext("Received unknown event tag"),
      message: "Tag received: #{inspect(tag)}",
      type: "info"
    })
  end

  def assign_entry_fields_demanding_live_preview_rerender(socket, schema) do
    lp_opts = Brando.LivePreview.get_target_config(schema)
    assign(socket, :fields_demanding_full_live_preview_rerender, lp_opts.rerender_on_change)
  end

  def assign_entry_fields_demanding_live_preview_reassign(socket, schema) do
    lp_opts = Brando.LivePreview.get_target_config(schema)
    assign(socket, :fields_demanding_live_preview_reassign, lp_opts.reassign_on_change)
  end

  def render(assigns) do
    ~H"""
    <div>
      <div id={"#{@id}-el"} class="brando-form" phx-hook="Brando.Form">
        <div class="form-content">
          <div :if={@header} class="form-header">
            <h1>
              {render_slot(@header)}
            </h1>
          </div>

          <div :if={@instructions} class="form-instructions">
            {render_slot(@instructions)}
          </div>

          <div class="form-tabs">
            <div class="form-tab-customs">
              <button
                :for={tab <- @tabs}
                type="button"
                class={[@active_tab == tab && "active"]}
                phx-click={JS.push("select_tab", target: @myself)}
                phx-value-name={tab}
              >
                {g(@schema, tab)}
              </button>
            </div>

            <.form_presences presences={@presences} />

            <div class="form-tab-builtins">
              <button :if={@has_meta?} phx-click={toggle_drawer("##{@id}-meta-drawer")} type="button">
                <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="16" height="16">
                  <path fill="none" d="M0 0h24v24H0z" /><path d="M10.9 2.1l9.899 1.415 1.414 9.9-9.192 9.192a1 1 0 0 1-1.414 0l-9.9-9.9a1 1 0 0 1 0-1.414L10.9 2.1zm.707 2.122L3.828 12l8.486 8.485 7.778-7.778-1.06-7.425-7.425-1.06zm2.12 6.364a2 2 0 1 1 2.83-2.829 2 2 0 0 1-2.83 2.829z" />
                </svg>
                <span class="tab-text">Meta</span>
              </button>
              <button
                :if={@has_revisioning?}
                phx-click={
                  JS.push("toggle_revisions_drawer_status", target: @myself)
                  |> toggle_drawer("##{@id}-revisions-drawer")
                }
                type="button"
              >
                <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="16" height="16">
                  <path fill="none" d="M0 0h24v24H0z" /><path d="M7.105 15.21A3.001 3.001 0 1 1 5 15.17V8.83a3.001 3.001 0 1 1 2 0V12c.836-.628 1.874-1 3-1h4a3.001 3.001 0 0 0 2.895-2.21 3.001 3.001 0 1 1 2.032.064A5.001 5.001 0 0 1 14 13h-4a3.001 3.001 0 0 0-2.895 2.21zM6 17a1 1 0 1 0 0 2 1 1 0 0 0 0-2zM6 5a1 1 0 1 0 0 2 1 1 0 0 0 0-2zm12 0a1 1 0 1 0 0 2 1 1 0 0 0 0-2z" />
                </svg>
                <span class="tab-text">{gettext("Revisions")}</span>
              </button>
              <button
                :if={@has_scheduled_publishing?}
                phx-click={toggle_drawer("##{@id}-scheduled-publishing-drawer")}
                type="button"
              >
                <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="16" height="16">
                  <path fill="none" d="M0 0h24v24H0z" /><path d="M17 3h4a1 1 0 0 1 1 1v16a1 1 0 0 1-1 1H3a1 1 0 0 1-1-1V4a1 1 0 0 1 1-1h4V1h2v2h6V1h2v2zm-2 2H9v2H7V5H4v4h16V5h-3v2h-2V5zm5 6H4v8h16v-8zM6 14h2v2H6v-2zm4 0h8v2h-8v-2z" />
                </svg>
                <span class="tab-text">{gettext("Scheduled publishing")}</span>
              </button>
              <button :if={@has_alternates?} phx-click={toggle_drawer("##{@id}-alternates-drawer")} type="button">
                <svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" viewBox="0 0 20 20" fill="currentColor">
                  <path d="M7.75 2.75a.75.75 0 00-1.5 0v1.258a32.987 32.987 0 00-3.599.278.75.75 0 10.198 1.487A31.545 31.545 0 018.7 5.545 19.381 19.381 0 017 9.56a19.418 19.418 0 01-1.002-2.05.75.75 0 00-1.384.577 20.935 20.935 0 001.492 2.91 19.613 19.613 0 01-3.828 4.154.75.75 0 10.945 1.164A21.116 21.116 0 007 12.331c.095.132.192.262.29.391a.75.75 0 001.194-.91c-.204-.266-.4-.538-.59-.815a20.888 20.888 0 002.333-5.332c.31.031.618.068.924.108a.75.75 0 00.198-1.487 32.832 32.832 0 00-3.599-.278V2.75z" />
                  <path
                    fill-rule="evenodd"
                    d="M13 8a.75.75 0 01.671.415l4.25 8.5a.75.75 0 11-1.342.67L15.787 16h-5.573l-.793 1.585a.75.75 0 11-1.342-.67l4.25-8.5A.75.75 0 0113 8zm2.037 6.5L13 10.427 10.964 14.5h4.073z"
                    clip-rule="evenodd"
                  />
                </svg>
              </button>
              <button
                :if={@has_live_preview?}
                phx-click={JS.push("open_live_preview", target: @myself)}
                class={[@live_preview_active? && "active"]}
                type="button"
              >
                <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="16" height="16">
                  <path fill="none" d="M0 0h24v24H0z" /><path d="M12 3c5.392 0 9.878 3.88 10.819 9-.94 5.12-5.427 9-10.819 9-5.392 0-9.878-3.88-10.819-9C2.121 6.88 6.608 3 12 3zm0 16a9.005 9.005 0 0 0 8.777-7 9.005 9.005 0 0 0-17.554 0A9.005 9.005 0 0 0 12 19zm0-2.5a4.5 4.5 0 1 1 0-9 4.5 4.5 0 0 1 0 9zm0-2a2.5 2.5 0 1 0 0-5 2.5 2.5 0 0 0 0 5z" />
                </svg>
              </button>
              <button :if={@has_live_preview?} phx-click={JS.push("share_link", target: @myself)} type="button">
                <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="16" height="16">
                  <path fill="none" d="M0 0h24v24H0z" /><path d="M11 2.05v2.012A8.001 8.001 0 0 0 12 20a8.001 8.001 0 0 0 7.938-7h2.013c-.502 5.053-4.766 9-9.951 9-5.523 0-10-4.477-10-10 0-5.185 3.947-9.449 9-9.95zm9 3.364l-8 8L10.586 12l8-8H14V2h8v8h-2V5.414z" />
                </svg>
              </button>
              <div class="split-dropdown">
                <button phx-click={JS.push("push_submit_redirect", target: @myself)} type="button">
                  <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="16" height="16">
                    <path fill="none" d="M0 0h24v24H0z" /><path d="M7 19v-6h10v6h2V7.828L16.172 5H5v14h2zM4 3h13l4 4v13a1 1 0 0 1-1 1H4a1 1 0 0 1-1-1V4a1 1 0 0 1 1-1zm5 12v4h6v-4H9z" />
                  </svg>
                </button>
                <SplitDropdown.render id="save-dropdown">
                  <Button.dropdown value={false} event={JS.push("push_submit_redirect", target: @myself)}>
                    {gettext("Save")}<span class="shortcut">⇧⌘S</span>
                  </Button.dropdown>
                  <Button.dropdown value={false} event={JS.push("push_submit", target: @myself)}>
                    {gettext("Save and continue editing")}<span class="shortcut">⌘S</span>
                  </Button.dropdown>
                  <Button.dropdown value={false} event={JS.push("push_submit_new", target: @myself)}>
                    {gettext("Save and create new")}
                  </Button.dropdown>
                </SplitDropdown.render>
              </div>
            </div>
          </div>

          <.live_component module={FilePicker} id="file-picker" />
          <.live_component module={ImagePicker} id="image-picker" />

          <.file_drawer
            file_changeset={@file_changeset}
            myself={@myself}
            parent_uploads={@uploads}
            edit_file={@edit_file}
            processing={@processing}
          />

          <.image_drawer
            image_changeset={@image_changeset}
            myself={@myself}
            parent_uploads={@uploads}
            edit_image={@edit_image}
            processing={@processing}
          />

          <.form id={"#{@id}_form"} for={@form} phx-target={@myself} phx-submit="save" phx-change="validate">
            <input type="hidden" name={"#{@form.name}[#{:__force_change}]"} phx-debounce="0" />
            <MetaDrawer.render
              :if={@has_meta?}
              id={"#{@id}-meta-drawer"}
              form={@form}
              parent_uploads={@uploads}
              current_user={@current_user}
              close={toggle_drawer("##{@id}-meta-drawer")}
            />

            <.live_component
              :if={@has_revisioning?}
              module={RevisionsDrawer}
              id={"#{@id}-revisions-drawer"}
              current_user={@current_user}
              entry_id={@entry_id}
              form={@form}
              form_cid={@myself}
              status={@status_revisions}
              close={
                JS.push("toggle_revisions_drawer_status", target: @myself)
                |> toggle_drawer("##{@id}-revisions-drawer")
              }
            />

            <ScheduledPublishingDrawer.render
              :if={@has_scheduled_publishing?}
              id={"#{@id}-scheduled-publishing-drawer"}
              form={@form}
              close={toggle_drawer("##{@id}-scheduled-publishing-drawer")}
            />

            <.live_component
              :if={@has_alternates?}
              module={AlternatesDrawer}
              id={"#{@id}-alternates-drawer"}
              entry={@entry}
              on_close={toggle_drawer("##{@id}-alternates-drawer")}
              on_remove_link={JS.push("remove_link", target: @myself)}
            />

            <.form_tabs
              tabs={@form_blueprint.tabs}
              active_tab={@active_tab}
              current_user={@current_user}
              parent_uploads={@uploads}
              form={@form}
              form_cid={@myself}
              schema={@schema}
            />
          </.form>

          <.live_component
            :for={{block_field, block_module, entry_blocks, field_opts} <- @block_map}
            :if={@has_blocks?}
            module={BlockField}
            block_module={block_module}
            block_field={block_field}
            form_name={@form.name}
            parent_uploads={@uploads}
            opts={field_opts}
            id={"#{@id}-blocks-#{block_field}"}
            entry={@entry_for_blocks}
            entry_blocks={entry_blocks}
            current_user={@current_user}
            form_cid={@myself}
          />

          <.submit_button processing={@processing} form_id={@id} label={gettext("Save (⌘S)")} class="primary submit-button" />
        </div>

        <.live_preview
          live_preview_active?={@live_preview_active?}
          live_preview_cache_key={@live_preview_cache_key}
          live_preview_target={@live_preview_target}
          change_preview_target={JS.push("change_preview_target", target: @myself)}
          target={@myself}
        />
      </div>
    </div>
    """
  end

  attr :presences, :list

  def form_presences(assigns) do
    ~H"""
    <div class="page-presences">
      <div :for={{_, user} <- @presences} class="user-presence visible" data-presence-user-id={user.id}>
        <div class="avatar" data-popover={user.name}>
          <Content.image image={user.avatar} size={:thumb} />
        </div>
      </div>
    </div>
    """
  end

  def form_tabs(assigns) do
    ~H"""
    <div :for={tab <- @tabs} class={["form-tab", @active_tab == tab.name && "active"]} data-tab-name={tab.name}>
      <div class="row">
        <.tab_fields
          tab={tab}
          current_user={@current_user}
          parent_uploads={@parent_uploads}
          schema={@schema}
          form={@form}
          form_cid={@form_cid}
        />
      </div>
    </div>
    """
  end

  def tab_fields(assigns) do
    assigns =
      assigns
      |> assign(:indexed_fields, Enum.with_index(assigns.tab.fields))
      |> assign(:relations, Brando.Blueprint.Relations.__relations__(assigns.schema))

    ~H"""
    <%= for {fieldset, idx} <- @indexed_fields do %>
      <%= if fieldset.__struct__ == Brando.Blueprint.Forms.Alert do %>
        <.alert type={fieldset.type}>
          <:icon>
            <.icon name="hero-exclamation-triangle" />
          </:icon>
          {raw(g(@form.source.data.__struct__, fieldset.content))}
        </.alert>
      <% else %>
        <Fieldset.render
          id={"#{@form.id}-fieldset-#{@tab.name}-#{idx}"}
          relations={@relations}
          form={@form}
          fieldset={fieldset}
          parent_uploads={@parent_uploads}
          current_user={@current_user}
          form_cid={@form_cid}
        />
      <% end %>
    <% end %>
    """
  end

  def file_drawer(assigns) do
    upload_field =
      case Map.get(assigns.parent_uploads, assigns.edit_file.field) do
        nil ->
          # if we have a path with length > 1
          if Enum.count(assigns.edit_file.path) > 1 do
            [sub | _] = assigns.edit_file.path
            nested_field = :"#{to_string(sub)}|#{to_string(assigns.edit_file.field)}"
            get_in(assigns.parent_uploads, [Access.key(nested_field)])
          end

        upload ->
          upload
      end

    assigns =
      assigns
      |> assign(:upload_field, upload_field)
      |> assign(:drop_target, Brando.Utils.try_path(upload_field, [:ref]))

    ~H"""
    <Content.drawer id="file-drawer" title={gettext("File")} close={close_file()} z={1001} narrow>
      <.form
        :let={file_form}
        :if={@file_changeset}
        id="file-drawer-form"
        for={@file_changeset}
        phx-submit="save_file"
        phx-change="validate_file"
        phx-target={@myself}
      >
        <div
          id="file-drawer-form-preview"
          phx-hook="Brando.DragDrop"
          class="file-drawer-preview"
          phx-drop-target={@drop_target}
        >
          <div :if={@processing} class="processing">
            <div>
              {gettext("Uploading")}<br />
              <progress value={@processing} max="100">{@processing}%</progress>
            </div>
          </div>

          <div class="img-placeholder">
            <div class="placeholder-wrapper">
              <div class="svg-wrapper">
                <svg class="icon-add-file" xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24">
                  <path fill="none" d="M0 0h24v24H0z" /><path d="M14.997 2L21 8l.001 4.26a5.471 5.471 0 0 0-2-1.053L19 9h-5V4H5v16h5.06a4.73 4.73 0 0 0 .817 2H3.993a.993.993 0 0 1-.986-.876L3 21.008V2.992c0-.498.387-.927.885-.985L4.002 2h10.995zM17.5 13a3.5 3.5 0 0 1 3.5 3.5l-.001.103a2.75 2.75 0 0 1-.581 5.392L20.25 22h-5.5l-.168-.005a2.75 2.75 0 0 1-.579-5.392L14 16.5a3.5 3.5 0 0 1 3.5-3.5zm0 2a1.5 1.5 0 0 0-1.473 1.215l-.02.14L16 16.5v1.62l-1.444.406a.75.75 0 0 0 .08 1.466l.109.008h5.51a.75.75 0 0 0 .19-1.474l-1.013-.283L19 18.12V16.5l-.007-.144A1.5 1.5 0 0 0 17.5 15z" />
                </svg>
              </div>
            </div>
          </div>

          <%= for entry <- @upload_field.entries do %>
            <%= for err <- upload_errors(@upload_field, entry) do %>
              <div class="alert alert-danger">
                <.icon name="hero-exclamation-triangle" />
                {Brando.Upload.error_to_string(err)}
              </div>
            <% end %>
          <% end %>

          <div
            :if={
              @edit_file && @edit_file[:file] &&
                !is_struct(@edit_file[:file], Ecto.Association.NotLoaded)
            }
            class="file-info"
          >
            <div class="filename">&#x2B24; {@edit_file.file.filename}</div>
            <div class="mimetype">&#x2B24; {@edit_file.file.mime_type}</div>
            <div class="filesize">
              &#x2B24; {Brando.Utils.human_size(@edit_file.file.filesize)}
            </div>
          </div>
        </div>

        <div class="button-group vertical">
          <div class="file-input-button">
            <span class="label">
              {gettext("Upload file")}
            </span>
            <.live_file_input upload={@upload_field} />
          </div>

          <button class="secondary" type="button" phx-click={toggle_drawer("#file-picker")}>
            {gettext("Select existing file")}
          </button>

          <button class="secondary" type="button" phx-click={reset_file_field(@myself)}>
            {gettext("Reset file field")}
          </button>
        </div>

        <div :if={@edit_file.file} class="brando-input">
          <Input.text field={file_form[:title]} label={gettext("Title")} />
        </div>
      </.form>
    </Content.drawer>
    """
  end

  def image_drawer(assigns) do
    upload_field =
      case Map.get(assigns.parent_uploads, assigns.edit_image.field) do
        nil ->
          # if we have a path with length > 1
          if Enum.count(assigns.edit_image.path) > 1 do
            [sub | _] = assigns.edit_image.path
            nested_field = :"#{to_string(sub)}|#{to_string(assigns.edit_image.field)}"
            get_in(assigns.parent_uploads, [Access.key(nested_field)])
          end

        upload ->
          upload
      end

    assigns =
      assigns
      |> assign(:upload_field, upload_field)
      |> assign(:drop_target, Brando.Utils.try_path(upload_field, [:ref]))
      |> assign(:random_id, Brando.Utils.generate_uid())

    ~H"""
    <Content.drawer id="image-drawer" title={gettext("Image")} close={close_image()} z={1001} narrow>
      <.form
        :let={image_form}
        :if={@image_changeset}
        id="image-drawer-form"
        for={@image_changeset}
        phx-submit="save_image"
        phx-change="validate_image"
        phx-target={@myself}
      >
        <div
          id="image-drawer-form-preview"
          phx-hook="Brando.DragDrop"
          class="image-drawer-preview"
          phx-drop-target={@drop_target}
        >
          <div :if={@processing} class="processing">
            <div>
              {gettext("Uploading")}<br />
              <progress value={@processing} max="100">{@processing}%</progress>
            </div>
          </div>
          <%= if @edit_image.image do %>
            <figure class="grid-overlay">
              <div class="drop-indicator">
                <div>{gettext("+ Drop here to upload")}</div>
              </div>
              <.live_component
                module={FocalPoint}
                id={"image-drawer-focal-#{@random_id}"}
                image={@edit_image}
                form={image_form}
              />
              <img
                width={@edit_image.image.width}
                height={@edit_image.image.height}
                src={Brando.Utils.img_url(@edit_image.image, :original, prefix: Brando.Utils.media_url())}
              />
            </figure>
            <figcaption class="tiny">{@edit_image.image.path}</figcaption>
          <% else %>
            <div class="img-placeholder">
              <div class="placeholder-wrapper">
                <div class="svg-wrapper">
                  <svg class="icon-add-image" xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24">
                    <path d="M0,0H24V24H0Z" transform="translate(0 0)" fill="none" />
                    <polygon
                      class="plus"
                      points="21 15 21 18 24 18 24 20 21 20 21 23 19 23 19 20 16 20 16 18 19 18 19 15 21 15"
                    />
                    <path
                      d="M21,3a1,1,0,0,1,1,1v9H20V5H4V19L14,9l3,3v2.83l-3-3L6.83,19H14v2H3a1,1,0,0,1-1-1V4A1,1,0,0,1,3,3Z"
                      transform="translate(0 0)"
                    />
                    <circle cx="8" cy="9" r="2" />
                  </svg>
                </div>
              </div>
            </div>
          <% end %>

          <%= for entry <- @upload_field.entries do %>
            <%= for err <- upload_errors(@upload_field, entry) do %>
              <div class="alert alert-danger">
                <.icon name="hero-exclamation-triangle" />
                {Brando.Upload.error_to_string(err)}
              </div>
            <% end %>
          <% end %>
        </div>

        <div class="button-group vertical">
          <div class="file-input-button">
            <span class="label">
              {gettext("Upload image")}
            </span>
            <.live_file_input :if={@upload_field} upload={@upload_field} />
          </div>
          <button class="secondary" type="button" phx-click={toggle_drawer("#image-picker")}>
            {gettext("Select existing image")}
          </button>

          <button :if={@edit_image.image} class="secondary" type="button" phx-click={duplicate_image(@edit_image, @myself)}>
            {gettext("Duplicate image")}
          </button>

          <button class="secondary" type="button" phx-click={reset_image_field(@myself)}>
            {gettext("Reset image field")}
          </button>
        </div>
        <%= if @edit_image.image do %>
          <div class="brando-input">
            <Input.text field={image_form[:title]} label={gettext("Caption")} />
          </div>

          <div class="brando-input">
            <Input.text field={image_form[:credits]} label={gettext("Credits")} />
          </div>

          <div class="brando-input">
            <Input.text field={image_form[:alt]} label={gettext("Alt. text")} />
          </div>
        <% end %>
      </.form>
    </Content.drawer>
    """
  end

  def duplicate_image(js \\ %JS{}, edit_image, target) do
    JS.push(js, "duplicate_image", value: %{image_id: edit_image.image.id}, target: target)
  end

  def reset_file_field(js \\ %JS{}, target) do
    js
    |> JS.push("reset_file_field", target: target)
    |> toggle_drawer("#file-drawer")
  end

  def reset_image_field(js \\ %JS{}, target) do
    js
    |> JS.push("reset_image_field", target: target)
    |> toggle_drawer("#image-drawer")
  end

  def close_file(js \\ %JS{}) do
    js
    |> JS.dispatch("submit", to: "#file-drawer-form", detail: %{bubbles: true, cancelable: true})
    |> toggle_drawer("#file-drawer")
  end

  def close_image(js \\ %JS{}) do
    js
    |> JS.dispatch("submit", to: "#image-drawer-form", detail: %{bubbles: true, cancelable: true})
    |> toggle_drawer("#image-drawer")
  end

  defp extract_transformers(%Brando.Blueprint.Forms.Form{tabs: tabs}) do
    Enum.flat_map(tabs, &extract_from_tab/1)
  end

  defp extract_from_tab(%Brando.Blueprint.Forms.Tab{fields: fieldsets}) do
    Enum.flat_map(fieldsets, &extract_from_fieldset/1)
  end

  defp extract_from_fieldset(%Brando.Blueprint.Forms.Fieldset{fields: fields}) do
    fields
    |> Enum.filter(&match_subform_with_transformer/1)
    |> Enum.map(&extract_subform_data/1)
  end

  defp match_subform_with_transformer(%Brando.Blueprint.Forms.Subform{style: {:transformer, _}}),
    do: true

  defp match_subform_with_transformer(_), do: false

  defp extract_subform_data(%Brando.Blueprint.Forms.Subform{
         name: name,
         style: {:transformer, key},
         default: default
       }) do
    {name, key, default}
  end

  def allow_uploads(socket) do
    schema = socket.assigns.schema
    image_fields = schema.__image_fields__()
    gallery_fields = schema.__gallery_fields__()
    file_fields = schema.__file_fields__()
    transformers = extract_transformers(socket.assigns.form_blueprint)
    # since LV changed to not allow us to set the :uploads assigns to [] or nil,
    # we need to set a "fake" upload key to not error when passing @uploads to
    # child components :(
    default_socket = allow_upload(socket, :__dfu__, accept: :any)

    socket_with_image_uploads =
      Enum.reduce(image_fields, default_socket, fn img_field, updated_socket ->
        max_size = Brando.Utils.try_path(img_field, [:opts, :cfg, :size_limit]) || 4_000_000

        allow_upload(updated_socket, img_field.name,
          accept: ~w(.jpg .jpeg .png .gif .webp .svg),
          max_file_size: max_size,
          auto_upload: true,
          progress: &__MODULE__.handle_image_progress/3
        )
      end)

    socket_with_gallery_uploads =
      Enum.reduce(gallery_fields, socket_with_image_uploads, fn gallery_field, updated_socket ->
        max_size = Brando.Utils.try_path(gallery_field, [:opts, :cfg, :size_limit]) || 4_000_000
        max_entries = Brando.Utils.try_path(gallery_field, [:opts, :max_entries]) || 25

        allow_upload(updated_socket, gallery_field.name,
          max_entries: max_entries,
          max_file_size: max_size,
          accept: ~w(.jpg .jpeg .png .gif .webp .svg),
          auto_upload: true,
          progress: &__MODULE__.handle_gallery_progress/3
        )
      end)

    socket_with_file_uploads =
      Enum.reduce(file_fields, socket_with_gallery_uploads, fn file_field, updated_socket ->
        max_size = Brando.Utils.try_path(file_field, [:opts, :cfg, :size_limit]) || 4_000_000
        accept = Brando.Utils.try_path(file_field, [:opts, :cfg, :accept]) || :any
        cdn_enabled = Brando.Utils.try_path(file_field, [:opts, :cfg, :cdn, :enabled])
        cdn_direct = Brando.Utils.try_path(file_field, [:opts, :cfg, :cdn, :direct])

        upload_options = [
          accept: accept,
          max_file_size: max_size,
          auto_upload: true,
          progress: &__MODULE__.handle_file_progress/3
        ]

        cfg = Brando.Utils.try_path(file_field, [:opts, :cfg])

        upload_options =
          if cdn_enabled && cdn_direct do
            upload_options ++ [external: &presign_upload(&1, &2, cfg)]
          else
            upload_options
          end

        allow_upload(updated_socket, file_field.name, upload_options)
      end)

    socket_with_transformers =
      Enum.reduce(transformers, socket_with_file_uploads, fn
        {relation_key, field, default}, updated_socket ->
          relation = Brando.Blueprint.Relations.__relation__(schema, relation_key)
          relation_module = get_in(relation, [Access.key(:opts), Access.key(:module)])
          img_field = Brando.Blueprint.Assets.__asset__(relation_module, field)
          max_size = Brando.Utils.try_path(img_field, [:opts, :cfg, :size_limit]) || 4_000_000
          key = :"#{relation_key}|#{field}"
          transformer_key = :"#{relation_key}|#{field}|transformer"

          updated_socket
          |> update(:transformer_defaults, &Map.put(&1, key, default))
          |> allow_upload(key,
            accept: ~w(.jpg .jpeg .png .gif .webp .svg),
            max_file_size: max_size,
            auto_upload: true,
            progress: &__MODULE__.handle_image_progress/3
          )
          |> allow_upload(transformer_key,
            accept: ~w(.jpg .jpeg .png .gif .webp .svg),
            max_entries: 50,
            max_file_size: max_size,
            chunk_timeout: 60_000,
            auto_upload: true,
            progress: &__MODULE__.handle_transformer_progress/3
          )
      end)

    socket_with_transformers
  end

  defp presign_upload(entry, socket, cfg) do
    s3_config = Brando.CDN.get_s3_config(cfg, as: :struct)

    uploads = socket.assigns.uploads
    bucket = cfg.cdn.bucket

    key =
      entry.client_name
      |> Brando.Utils.build_upload_key(cfg)
      |> Brando.Utils.strip_leading_slash()

    {:ok, fields} =
      Brando.SimpleS3Upload.sign_form_upload(s3_config, bucket,
        key: key,
        content_type: entry.client_type,
        max_file_size: uploads[entry.upload_config].max_file_size,
        expires_in: :timer.hours(1)
      )

    meta = %{
      uploader: "S3",
      key: key,
      url: cfg.cdn.media_url,
      fields: fields
    }

    {:ok, meta, socket}
  end

  def handle_event("validate", params, socket) do
    schema = socket.assigns.schema
    entry = socket.assigns.entry
    current_user = socket.assigns.current_user
    singular = socket.assigns.singular
    dirty_fields = socket.assigns.dirty_fields
    has_blocks? = socket.assigns.has_blocks?

    entry_params = Map.get(params, singular)
    entry_or_default = entry || struct(schema)

    changeset = validate(schema, entry_or_default, entry_params, current_user)
    changed_fields = Map.keys(changeset.changes)

    socket =
      if changed_fields == dirty_fields do
        socket
      else
        Phoenix.PubSub.broadcast(
          Brando.pubsub(),
          "brando:dirty_fields:#{entry.id}",
          {:dirty_fields, changed_fields, current_user.id}
        )

        assign(socket, :dirty_fields, changed_fields)
      end

    case Map.get(params, "_target") do
      [^singular | rest] ->
        if has_blocks? && rest != ["__force_change"] do
          path = string_path_to_access_path(rest)
          change = get_in(params, rest)
          send_updated_entry_field_to_blocks(socket, path, change)
        end

        if rest == ["language"] do
          request_select_options_update(socket)
        end

        new_form = to_form(changeset, [])

        socket
        |> assign(:form, new_form)
        |> maybe_invalidate_live_preview_assign(rest, :string_path)
        |> maybe_fetch_root_blocks(:live_preview_update, 0)
        |> then(&{:noreply, &1})

      [_] ->
        {:noreply, socket}
    end
  end

  def handle_event("focus", %{"field" => field}, socket) do
    current_user = socket.assigns.current_user
    entry = socket.assigns.entry

    Phoenix.PubSub.broadcast(
      Brando.pubsub(),
      "brando:active_field:#{entry.id}",
      {:active_field, field, current_user.id}
    )

    {:noreply, assign(socket, :focused_field, field)}
  end

  def handle_event("focus", _, socket) do
    {:noreply, socket}
  end

  def handle_event("save", _params, %{assigns: %{editing_image?: true}} = socket) do
    {:noreply,
     push_event(socket, "b:alert", %{
       title: gettext("Error"),
       message:
         gettext(
           "You must close the image drawer before saving this form. You might have changes to an image that has not been processed, which might lead to broken image links. Close the image drawer, allow processing to finish (if any), then try to save again."
         ),
       type: "error"
     })}
  end

  def handle_event("save", _params, %{assigns: %{editing_file?: true}} = socket) do
    {:noreply,
     push_event(socket, "b:alert", %{
       title: gettext("Error"),
       message:
         gettext(
           "You must close the file drawer before saving this form. You might have changes to a file that has not been processed, which might lead to broken links. Close the file drawer, allow processing to finish (if any), then try to save again."
         ),
       type: "error"
     })}
  end

  def handle_event("save", params, %{assigns: %{has_blocks?: true, all_blocks_received?: true}} = socket) do
    schema = socket.assigns.schema
    entry = socket.assigns.entry
    current_user = socket.assigns.current_user
    singular = socket.assigns.singular
    form_blueprint = socket.assigns.form_blueprint
    save_redirect_target = socket.assigns.save_redirect_target
    block_changesets = socket.assigns.block_changesets
    block_map = socket.assigns.block_map

    entry_params = Map.get(params, singular)
    entry_or_default = entry || struct(schema)

    changeset =
      entry_or_default
      |> schema.changeset(entry_params, current_user)
      |> Brando.Utils.set_action()
      |> Brando.Trait.run_trait_before_save_callbacks(schema, current_user)

    singular = schema.__naming__().singular
    translated_singular = Brando.Blueprint.get_singular(schema)
    context = schema.__modules__().context
    mutation_type = (get_field(changeset, :id) && :update) || :create

    # if redirect_on_save is set in form, use this
    redirect_fn =
      form_blueprint.redirect_on_save ||
        fn socket, _entry, _mutation_type ->
          generated_list_view = schema.__modules__().admin_list_view
          Brando.routes().admin_live_path(socket, generated_list_view)
        end

    # redirect to "create new"
    redirect_new_fn = fn _socket, _entry, _mutation_type ->
      schema.__admin_route__(:create, [])
    end

    send(self(), {:progress_popup, "Associating block fields..."})

    new_changeset = assoc_all_block_fields(block_changesets, changeset)
    entry_for_blocks = build_entry_for_blocks(new_changeset, block_map)

    send(self(), {:progress_popup, "Rendering blocks for entry..."})

    rendered_changeset =
      render_blocks_for_entry(
        block_map,
        new_changeset,
        entry_for_blocks
      )

    send(self(), {:progress_popup, "Saving entry..."})

    case apply(context, :"#{mutation_type}_#{singular}", [rendered_changeset, current_user]) do
      {:ok, entry} ->
        send(self(), {:progress_popup, "Entry saved."})

        Brando.Trait.run_trait_after_save_callbacks(
          schema,
          entry,
          rendered_changeset,
          current_user
        )

        maybe_run_form_after_save(form_blueprint, entry, current_user)

        mutation_message =
          Brando.Gettext
          |> Gettext.dgettext("mutations", "#{mutation_type}", singular: translated_singular)
          |> String.capitalize()

        send(self(), {:toast, mutation_message})

        maybe_redirected_socket =
          case save_redirect_target do
            :self ->
              update_url = schema.__admin_route__(:update, [entry.id])

              if mutation_type == :create do
                socket
                |> assign(:processing, false)
                |> assign(:all_blocks_received?, false)
                |> assign(:entry_id, entry.id)
                |> assign_refreshed_entry()
                |> assign_refreshed_form()
                |> clear_blocks_root_changesets()
                |> assign_block_map()
                |> assign_entry_for_blocks()
                |> reload_all_blocks()
                |> push_patch(to: update_url)
              else
                if schema.has_trait(Brando.Trait.Revisioned) do
                  id = "#{socket.assigns.id}-revisions-drawer"
                  send_update(RevisionsDrawer, id: id, action: :refresh_revisions)
                end

                # update entry!
                socket
                |> assign(:processing, false)
                |> assign(:all_blocks_received?, false)
                |> assign(:entry_id, entry.id)
                |> assign_refreshed_entry()
                |> assign_refreshed_form()
                |> clear_blocks_root_changesets()
                |> assign_block_map()
                |> assign_entry_for_blocks()
                |> reload_all_blocks()
              end

            :listing ->
              push_navigate(socket, to: redirect_fn.(socket, entry, mutation_type))

            :new ->
              push_navigate(socket, to: redirect_new_fn.(socket, entry, mutation_type))
          end

        {:noreply, assign(maybe_redirected_socket, :save_redirect_target, :listing)}

      {:error, %Ecto.Changeset{} = changeset} ->
        require Logger
        Logger.error(inspect(changeset, pretty: true))
        send(self(), {:progress_popup, "Saving entry failed..."})

        {:noreply,
         socket
         |> assign(:processing, false)
         |> assign(:form, to_form(changeset, []))
         |> push_errors(changeset, form_blueprint, schema)}
    end
  end

  def handle_event("save", _params, %{assigns: %{has_blocks?: true}} = socket) do
    # has blocks, but not all blocks have been received
    fetch_root_blocks(socket, :save, 150)
    send(self(), {:progress_popup, "Saving..."})
    {:noreply, assign(socket, :processing, true)}
  end

  def handle_event("save", params, %{assigns: %{has_blocks?: false}} = socket) do
    schema = socket.assigns.schema
    entry = socket.assigns.entry
    current_user = socket.assigns.current_user
    singular = socket.assigns.singular
    form_blueprint = socket.assigns.form_blueprint
    save_redirect_target = socket.assigns.save_redirect_target

    entry_params = Map.get(params, singular)
    entry_or_default = entry || struct(schema)

    changeset =
      entry_or_default
      |> schema.changeset(entry_params, current_user)
      |> Brando.Utils.set_action()
      |> Brando.Trait.run_trait_before_save_callbacks(schema, current_user)

    singular = schema.__naming__().singular
    context = schema.__modules__().context

    mutation_type = (get_field(changeset, :id) && :update) || :create

    # if redirect_on_save is set in form, use this
    redirect_fn =
      form_blueprint.redirect_on_save ||
        fn _socket, _entry, _mutation_type ->
          schema.__admin_route__(:list, [schema.__modules__().admin_list_view])
        end

    # redirect to "create new"
    redirect_new_fn = fn _socket, _entry, _mutation_type ->
      schema.__admin_route__(:create, [])
    end

    case apply(context, :"#{mutation_type}_#{singular}", [changeset, current_user]) do
      {:ok, entry} ->
        Brando.Trait.run_trait_after_save_callbacks(schema, entry, changeset, current_user)
        maybe_run_form_after_save(form_blueprint, entry, current_user)
        send(self(), {:toast, "#{String.capitalize(singular)} #{mutation_type}d"})

        maybe_redirected_socket =
          case save_redirect_target do
            :self ->
              if mutation_type == :create do
                generated_route = schema.__admin_route__(:update, [entry.id])

                push_navigate(socket, to: generated_route)
              else
                if schema.has_trait(Brando.Trait.Revisioned) do
                  id = "#{socket.assigns.id}-revisions-drawer"
                  send_update(RevisionsDrawer, id: id, action: :refresh_revisions)
                end

                # update entry!
                socket
                |> assign(:entry_id, entry.id)
                |> assign_refreshed_entry()
                |> assign_refreshed_form()
              end

            :listing ->
              push_navigate(socket, to: redirect_fn.(socket, entry, mutation_type))

            :new ->
              push_navigate(socket, to: redirect_new_fn.(socket, entry, mutation_type))
          end

        {:noreply, assign(maybe_redirected_socket, :save_redirect_target, :listing)}

      {:error, %Ecto.Changeset{} = changeset} ->
        require Logger
        Logger.error(inspect(changeset, pretty: true))

        {:noreply,
         socket
         |> assign(:form, to_form(changeset, []))
         |> push_errors(changeset, form_blueprint, schema)}
    end
  end

  def handle_event(
        "duplicate_image",
        %{"image_id" => image_id},
        %{assigns: %{singular: singular, current_user: current_user}} = socket
      ) do
    {:ok, image} = Brando.Images.duplicate_image(image_id, current_user)

    send_update(__MODULE__,
      id: "#{singular}_form",
      action: :update_edit_image,
      image: image
    )

    send(self(), {:toast, gettext("Image duplicated")})

    {:noreply, socket}
  end

  def handle_event("cancel_upload", %{"ref" => ref, "field_name" => field_name}, socket) do
    field_name_atom = String.to_existing_atom(field_name)
    {:noreply, cancel_upload(socket, field_name_atom, ref)}
  end

  def handle_event("change_preview_target", %{"target" => target}, socket) do
    {:noreply, assign(socket, :live_preview_target, target)}
  end

  def handle_event(
        "reset_file_field",
        _,
        %{assigns: %{form: form, edit_file: edit_file, entry: entry, singular: singular}} = socket
      ) do
    changeset = form.source
    full_path = edit_file.path ++ [edit_file.relation_field.field]
    updated_changeset = EctoNestedChangeset.update_at(changeset, full_path, fn _ -> nil end)
    updated_edit_file = Map.put(edit_file, :file, nil)

    {:noreply,
     socket
     |> assign(:entry, Map.put(entry, edit_file.field, nil))
     |> assign(:file_changeset, nil)
     |> assign(:edit_file, updated_edit_file)
     |> assign(:form, to_form(updated_changeset, []))
     |> push_event("b:validate", %{
       target: "#{singular}[#{edit_file.relation_field.field}]",
       value: ""
     })}
  end

  def handle_event(
        "reset_image_field",
        _,
        %{assigns: %{form: form, edit_image: edit_image, entry: entry, singular: singular}} = socket
      ) do
    changeset = form.source
    full_path = edit_image.path ++ [edit_image.relation_field.field]
    updated_changeset = EctoNestedChangeset.update_at(changeset, full_path, fn _ -> nil end)
    updated_edit_image = Map.put(edit_image, :image, nil)

    {:noreply,
     socket
     |> assign(:entry, Map.put(entry, edit_image.field, nil))
     |> assign(:image_changeset, nil)
     |> assign(:edit_image, updated_edit_image)
     |> assign(:form, to_form(updated_changeset, []))
     |> push_event("b:validate", %{
       target: "#{singular}[#{edit_image.relation_field.field}]",
       value: ""
     })}
  end

  def handle_event("validate_file", _, socket) do
    {:noreply, socket}
  end

  def handle_event(
        "save_file",
        %{"file" => file_params},
        %{
          assigns: %{
            form: form,
            entry: entry,
            schema: schema,
            singular: singular,
            edit_file: %{file: file, path: path, field: field, relation_field: relation_field} = edit_file,
            current_user: current_user
          }
        } = socket
      ) do
    entry_or_default = entry || struct(schema)

    validated_changeset =
      file
      |> Brando.Files.File.changeset(file_params, current_user)
      |> Map.put(:action, :update)
      |> Brando.Trait.run_trait_before_save_callbacks(
        Brando.Files.File,
        current_user
      )

    {:ok, updated_file} = Brando.Files.update_file(validated_changeset, current_user)

    Brando.Trait.run_trait_after_save_callbacks(
      Brando.Images.Image,
      updated_file,
      validated_changeset,
      current_user
    )

    file_config = Brando.Utils.try_path(relation_field, [:opts, :cfg])

    if file_config && file_config.completed_callback do
      file_config.completed_callback.(updated_file, current_user)
    end

    edit_file = Map.put(edit_file, :file, updated_file)
    full_path = path ++ [relation_field.field]

    updated_changeset =
      form.source
      |> apply_changes()
      |> change()
      |> EctoNestedChangeset.update_at(full_path, fn _ -> file.id end)

    updated_entry = Map.put(entry_or_default, field, updated_file)

    # this is only for fresh uploads.
    if !updated_file.cdn && Brando.CDN.enabled?(Brando.Files) do
      # TODO __ FIGURE OUT FULL_PATH
      full_field_path = []
      Brando.CDN.queue_upload(updated_file, current_user, full_field_path)
    end

    {:noreply,
     socket
     |> assign(:entry, updated_entry)
     |> assign(:form, to_form(updated_changeset, []))
     |> assign(:file_changeset, validated_changeset)
     |> assign(:editing_file?, false)
     |> assign(:edit_file, edit_file)
     |> push_event("b:validate", %{
       target: "#{singular}[#{edit_file.relation_field.field}]",
       value: file.id
     })}
  end

  # without file in params
  def handle_event("save_file", _, socket) do
    {:noreply, socket}
  end

  def handle_event("validate_image", _, socket) do
    {:noreply, socket}
  end

  def handle_event(
        "save_image",
        %{"image" => image_params},
        %{
          assigns: %{
            form: form,
            entry: entry,
            schema: schema,
            singular: singular,
            edit_image: %{image: image, path: path, field: field, relation_field: relation_field} = edit_image,
            current_user: current_user
          }
        } = socket
      ) do
    entry_or_default = entry || struct(schema)

    validated_changeset =
      image
      |> Brando.Images.Image.changeset(image_params, current_user)
      |> Map.put(:action, :update)
      |> Brando.Trait.run_trait_before_save_callbacks(
        Brando.Images.Image,
        current_user
      )

    {:ok, updated_image} = Brando.Images.update_image(validated_changeset, current_user)

    Brando.Trait.run_trait_after_save_callbacks(
      Brando.Images.Image,
      updated_image,
      validated_changeset,
      current_user
    )

    edit_image = Map.put(edit_image, :image, updated_image)
    relation_full_path = path ++ [relation_field.field]
    field_full_path = path ++ [field]

    updated_changeset =
      form.source
      |> apply_changes()
      |> change()
      |> EctoNestedChangeset.update_at(relation_full_path, fn _ -> image.id end)

    entrys_current_image = Brando.Utils.try_path(entry_or_default, field_full_path)
    access_field_full_path = Brando.Utils.build_access_path(field_full_path)

    updated_entry =
      if loaded_image?(entrys_current_image) && entrys_current_image.id == image.id &&
           updated_image.status == :processed do
        # the image has already been marked as processed, do not
        # update the image but merge in title, credits and alt text
        merged_image =
          Map.merge(entrys_current_image, Map.take(updated_image, [:title, :credits, :alt]))

        put_in(entry_or_default, access_field_full_path, merged_image)
      else
        put_in(entry_or_default, access_field_full_path, updated_image)
      end

    # Subscribe parent live view to changes to this image
    Phoenix.PubSub.subscribe(Brando.pubsub(), "brando:image:#{image.id}")

    # this is only for fresh uploads.
    if updated_image.status !== :processed do
      Brando.Images.Processing.queue_processing(updated_image, current_user, field_full_path)
    end

    target_field_name = Enum.join([singular | Enum.map(relation_full_path, &"[#{to_string(&1)}]")], "")

    {:noreply,
     socket
     |> assign(:entry, updated_entry)
     |> assign(:form, to_form(updated_changeset, []))
     |> assign(:image_changeset, validated_changeset)
     |> assign(:edit_image, edit_image)
     |> assign(:editing_image?, false)
     |> push_event("b:validate", %{
       target: target_field_name,
       value: image.id
     })}
  end

  # without image in params
  def handle_event("save_image", _, socket) do
    {:noreply, assign(socket, :editing_image?, false)}
  end

  def handle_event("share_link", _, socket) do
    send(self(), {:toast, gettext("Gathering blocks for sharing...")})
    fetch_root_blocks(socket, :share, 500)
    {:noreply, socket}
  end

  # close live_preview
  def handle_event("open_live_preview", _, %{assigns: %{live_preview_active?: true}} = socket) do
    socket
    |> assign(:live_preview_active?, false)
    |> assign(:live_preview_cache_key, nil)
    |> disable_live_preview_in_blocks()
    |> push_event("js-exec", %{to: "#sidebar", attr: "data-js-show"})
    |> then(&{:noreply, &1})
  end

  # try to open live_preview, but blocks are not ready.
  def handle_event("open_live_preview", _, %{assigns: %{live_preview_ready?: false}} = socket) do
    send(self(), {:toast, gettext("Starting Live Preview — fetching initial render...")})
    fetch_root_blocks(socket, :live_preview, 500)
    {:noreply, push_event(socket, "js-exec", %{to: "#sidebar", attr: "data-js-hide"})}
  end

  def handle_event("open_live_preview_standalone", _, socket) do
    send(self(), {:toast, gettext("Opening stand alone live preview window...")})
    fetch_root_blocks(socket, :live_preview_standalone, 500)
    {:noreply, socket}
  end

  def handle_event("push_submit_redirect", _, socket) do
    {:noreply, push_event(socket, "b:submit", %{})}
  end

  def handle_event("push_submit", _, socket) do
    {:noreply,
     socket
     |> assign(:save_redirect_target, :self)
     |> push_event("b:submit", %{})}
  end

  def handle_event("push_submit_new", _, socket) do
    {:noreply,
     socket
     |> assign(:save_redirect_target, :new)
     |> push_event("b:submit", %{})}
  end

  def handle_event("toggle_revisions_drawer_status", _, socket) do
    if socket.assigns.entry_id do
      {:noreply, assign(socket, :status_revisions, (socket.assigns.status_revisions == :open && :closed) || :open)}
    else
      error_title = gettext("Notice")

      error_msg =
        gettext("To create and administrate revisions, the entry must be saved at least one time first.")

      {:noreply, push_event(socket, "b:alert", %{title: error_title, message: error_msg, type: "error"})}
    end
  end

  def handle_event("select_tab", %{"name" => tab_name}, socket) do
    {:noreply, assign(socket, :active_tab, tab_name)}
  end

  def handle_event("save_redirect_target", _, socket) do
    {:noreply, assign(socket, :save_redirect_target, :self)}
  end

  defp maybe_invalidate_live_preview_assign(socket, path, path_type \\ :atom_path)

  defp maybe_invalidate_live_preview_assign(
         %{assigns: %{live_preview_active?: true, fields_demanding_live_preview_reassign: fdlpr}} = socket,
         path,
         path_type
       )
       when fdlpr != [] do
    path = if path_type == :string_path, do: string_path_to_atom_path(path), else: path
    cache_key = socket.assigns.live_preview_cache_key

    case Enum.find(fdlpr, fn {_key, trigger_path} -> trigger_path == path end) do
      {key, _} -> Brando.LivePreview.invalidate_var(cache_key, key)
      nil -> nil
    end

    socket
  end

  defp maybe_invalidate_live_preview_assign(socket, _string_path, _) do
    socket
  end

  defp request_select_options_update(socket) do
    form_blueprint = socket.assigns.form_blueprint
    singular = socket.assigns.singular

    form_blueprint
    |> Brando.Blueprint.Forms.list_fields(:select)
    |> Enum.reject(&(&1 == :language))
    |> build_lc_ids(singular)
    |> send_select_options_update(Select)

    form_blueprint
    |> Brando.Blueprint.Forms.list_fields(:multi_select)
    |> build_lc_ids(singular)
    |> send_select_options_update(MultiSelect)

    socket
  end

  defp send_select_options_update(field_ids, component) do
    Enum.map(field_ids, fn field_id ->
      send_update(component, id: field_id, action: :force_refresh_options)
    end)
  end

  defp build_lc_ids(fields, singular) do
    Enum.map(fields, fn field -> "#{singular}_#{field}" end)
  end

  defp maybe_fetch_root_blocks(%{assigns: %{live_preview_active?: true}} = socket, event, delay) do
    fetch_root_blocks(socket, event, delay)
    socket
  end

  defp maybe_fetch_root_blocks(%{assigns: %{live_preview_active?: false}} = socket, _, _) do
    socket
  end

  defp fetch_root_blocks(socket, tag, delay) do
    id = socket.assigns.id
    block_map = socket.assigns.block_map

    for {block_field_name, _schema, _entry_blocks, _opts} <- block_map do
      block_field_id = "#{id}-blocks-#{block_field_name}"

      send_update_after(
        BlockField,
        [id: block_field_id, event: "fetch_root_blocks", tag: tag],
        delay
      )
    end

    socket
  end

  defp clear_blocks_root_changesets(socket) do
    block_map = socket.assigns.block_map
    id = socket.assigns.id

    for {block_field_name, _schema, _entry_blocks, _opts} <- block_map do
      block_field_id = "#{id}-blocks-#{block_field_name}"
      send_update(BlockField, id: block_field_id, event: "clear_root_changesets")
    end

    socket
  end

  defp reload_all_blocks(socket) do
    block_map = socket.assigns.block_map
    id = socket.assigns.id

    for {block_field_name, _schema, _entry_blocks, _opts} <- block_map do
      block_field_id = "#{id}-blocks-#{block_field_name}"
      send_update(BlockField, id: block_field_id, event: "reload_all_blocks")
    end

    socket
  end

  defp enable_live_preview_in_blocks(socket) do
    block_map = socket.assigns.block_map
    id = socket.assigns.id
    cache_key = socket.assigns.live_preview_cache_key

    for {block_field_name, _schema, _entry_blocks, _opts} <- block_map do
      block_field_id = "#{id}-blocks-#{block_field_name}"

      send_update(BlockField,
        id: block_field_id,
        event: "enable_live_preview",
        cache_key: cache_key
      )
    end

    socket
  end

  defp disable_live_preview_in_blocks(socket) do
    block_map = socket.assigns.block_map
    id = socket.assigns.id

    for {block_field_name, _schema, _entry_blocks, _opts} <- block_map do
      block_field_id = "#{id}-blocks-#{block_field_name}"

      send_update(BlockField,
        id: block_field_id,
        event: "disable_live_preview"
      )
    end

    socket
  end

  defp maybe_run_form_after_save(%{after_save: nil}, _, _), do: nil

  defp maybe_run_form_after_save(%{after_save: after_save}, entry, current_user) do
    after_save.(entry, current_user)
  end

  defp validate(schema, entry, params, user) do
    entry
    |> schema.changeset(params, user)
    |> Map.put(:action, :validate)
  end

  defp assoc_all_block_fields(block_changesets, changeset) do
    Enum.reduce(block_changesets, changeset, fn {field_name, block_cs}, updated_changeset ->
      updated_block_cs =
        block_cs
        |> Brando.Villain.reject_deleted(true)
        |> Brando.Utils.set_action()

      Ecto.Changeset.put_assoc(updated_changeset, :"entry_#{field_name}", updated_block_cs)
    end)
  end

  defp loaded_image?(nil), do: false
  defp loaded_image?(%Ecto.Association.NotLoaded{}), do: false
  defp loaded_image?(%Brando.Images.Image{}), do: true

  defp push_errors(socket, changeset, form, schema, env \\ :save) do
    error_title = gettext("Error")

    error_notice =
      if env == :save do
        gettext("Error while saving form. Please correct marked fields and resubmit<br><br>Fields marked invalid:")
      else
        gettext(
          "Cannot open Live Preview with errors in form. Please correct marked fields and try again<br><br>Fields marked invalid:"
        )
      end

    traversed_errors =
      traverse_errors(changeset, fn
        {msg, opts} -> String.replace(msg, "%{count}", to_string(opts[:count]))
        msg -> msg
      end)

    error_keys = Map.keys(traversed_errors)

    tab_with_first_error =
      error_keys
      |> List.first()
      |> Brando.Blueprint.Forms.get_tab_for_field(form)

    translated_error_keys = Brando.Blueprint.Utils.translate_error_keys(error_keys, form, schema)

    error_list =
      for key <- translated_error_keys do
        "<li class=\"text-mono\">#{key}</li>"
      end

    error_msg = """
    #{error_notice}<br><br>
    <ul class="error-keys">#{error_list}</ul>
    """

    require Logger

    Logger.error("""


    Changeset errors:

    #{inspect(changeset.errors, pretty: true)}

    """)

    socket
    |> assign(:active_tab, tab_with_first_error)
    |> push_event("b:alert", %{title: error_title, message: error_msg, type: "error"})
    |> push_event("b:scroll_to_first_error", %{})
  end

  def handle_image_progress(key, upload_entry, socket) do
    edit_image = socket.assigns.edit_image
    current_user = socket.assigns.current_user
    socket = assign(socket, :processing, upload_entry.progress)

    if upload_entry.done? do
      socket = assign(socket, :processing, false)

      # if we have a concat'ed key (from a subform) we split out our field and schema
      key =
        case String.split(to_string(key), "|") do
          [_, string_key] -> String.to_existing_atom(string_key)
          [_string_key] -> key
        end

      relation_key = String.to_existing_atom("#{key}_id")

      %{cfg: cfg} = Brando.Blueprint.Assets.__asset_opts__(edit_image.schema, key)
      config_target = "image:#{inspect(edit_image.schema)}:#{key}"

      case consume_uploaded_entry(
             socket,
             upload_entry,
             fn meta ->
               updated_meta =
                 Map.merge(meta, %{
                   config_target: config_target,
                   field_path: edit_image.path ++ [relation_key]
                 })

               Brando.Upload.handle_upload(updated_meta, upload_entry, cfg, current_user)
             end
           ) do
        {:error, :content_type, rejected_type, allowed_types} ->
          error_title = gettext("Error uploading")

          error_msg =
            gettext(
              "Server rejected image type [%{rejected_type}].<br><br>Allowed types are:<br>%{allowed_types}",
              %{rejected_type: rejected_type, allowed_types: inspect(allowed_types)}
            )

          {:noreply, push_event(socket, "b:alert", %{title: error_title, type: "error", message: error_msg})}

        image ->
          image_changeset = change(image)
          edit_image = Map.merge(edit_image, %{id: image.id, image: image})

          {:noreply,
           socket
           |> update_changeset(edit_image.path, relation_key, image.id)
           |> assign(:edit_image, edit_image)
           |> assign(:image_changeset, image_changeset)}
      end
    else
      {:noreply, socket}
    end
  end

  def handle_gallery_progress(
        key,
        upload_entry,
        %{assigns: %{current_user: current_user, schema: schema, form: form}} = socket
      ) do
    if upload_entry.done? do
      %{cfg: cfg} = Brando.Blueprint.Assets.__asset_opts__(schema, key)
      config_target = "gallery:#{inspect(schema)}:#{key}"

      image =
        consume_uploaded_entry(
          socket,
          upload_entry,
          fn meta ->
            Brando.Upload.handle_upload(
              Map.put(meta, :config_target, config_target),
              upload_entry,
              cfg,
              current_user
            )
          end
        )

      # Subscribe parent live view to changes to this image
      Phoenix.PubSub.subscribe(Brando.pubsub(), "brando:image:#{image.id}")
      Brando.Images.Processing.queue_processing(image, current_user)

      changeset = form.source
      gallery = get_field(changeset, key)

      current_gallery_images =
        if gallery do
          Enum.map(
            gallery.gallery_objects || [],
            &Map.take(&1, [:id, :image_id, :video_id, :gallery_id, :sequence, :creator_id])
          )
        else
          []
        end

      new_gallery_image = %{
        image_id: image.id,
        creator_id: current_user.id,
        gallery_id: gallery && gallery.id,
        image: image
      }

      new_gallery_images = current_gallery_images ++ List.wrap(new_gallery_image)

      new_gallery =
        if gallery do
          %{
            id: gallery.id,
            config_target: gallery.config_target,
            gallery_objects: sequence(new_gallery_images)
          }
        else
          %{
            config_target: "gallery:#{inspect(schema)}:#{key}",
            gallery_objects: sequence(new_gallery_images)
          }
        end

      # TODO: This sucks.
      current_gallery_images = (gallery && gallery.gallery_objects) || []

      unloaded_image_ids =
        current_gallery_images
        |> Enum.filter(&(&1.image != nil && &1.image.__struct__ == Ecto.Association.NotLoaded))
        |> Enum.map(& &1.image_id)

      loaded_image_paths =
        current_gallery_images
        |> Enum.filter(&(&1.image != nil && &1.image.__struct__ != Ecto.Association.NotLoaded))
        |> Enum.map(& &1.image.path)

      unloaded_image_paths =
        if unloaded_image_ids == [] do
          []
        else
          %{filter: %{ids: unloaded_image_ids}, select: [:path]}
          |> Brando.Images.list_images!()
          |> Enum.map(& &1.path)
        end

      selected_images = loaded_image_paths ++ unloaded_image_paths ++ [image.path]

      send_update(BrandoAdmin.Components.ImagePicker,
        id: "image-picker",
        selected_images: selected_images
      )

      updated_changeset = put_assoc(changeset, key, new_gallery)

      module = changeset.data.__struct__
      form_id = "#{module.__naming__().singular}_#{key}"

      send_update(BrandoAdmin.Components.Form.Input.Gallery,
        id: form_id,
        new_image: %{image_id: image.id, image: image},
        selected_images: selected_images
      )

      {:noreply,
       socket
       |> update(:processing_images, &[image.id | &1])
       |> assign(:form, to_form(updated_changeset, []))}
    else
      {:noreply, socket}
    end
  end

  def handle_transformer_progress(key, upload_entry, socket) do
    current_user = socket.assigns.current_user
    schema = socket.assigns.schema
    socket = assign(socket, :processing, upload_entry.progress)

    if upload_entry.done? do
      entries = get_in(socket.assigns.uploads, [key, Access.key(:entries)])
      all_done? = Enum.all?(entries, &(&1.progress == 100))

      [relation_key, asset_key, _] = String.split(to_string(key), "|")
      original_key = key
      key = [relation_key, asset_key] |> Enum.join("|") |> String.to_existing_atom()

      relation =
        Brando.Blueprint.Relations.__relation__(schema, String.to_existing_atom(relation_key))

      relation_module = get_in(relation, [Access.key(:opts), Access.key(:module)])

      %{cfg: cfg} =
        Brando.Blueprint.Assets.__asset_opts__(
          relation_module,
          String.to_existing_atom(asset_key)
        )

      config_target = "image:#{inspect(relation_module)}:#{asset_key}"

      case consume_uploaded_entry(
             socket,
             upload_entry,
             fn meta ->
               Brando.Upload.handle_upload(
                 Map.put(meta, :config_target, config_target),
                 upload_entry,
                 cfg,
                 current_user
               )
             end
           ) do
        {:error, :content_type, rejected_type, allowed_types} ->
          error_title = gettext("Error uploading")

          error_msg =
            gettext(
              "Server rejected image type [%{rejected_type}].<br><br>Allowed types are:<br>%{allowed_types}",
              %{rejected_type: rejected_type, allowed_types: inspect(allowed_types)}
            )

          {:noreply, push_event(socket, "b:alert", %{title: error_title, type: "error", message: error_msg})}

        image ->
          socket =
            case uploaded_entries(socket, original_key) do
              {[_ | _], []} ->
                assign(socket, :processing, false)

              {[_ | _], [_ | _]} ->
                assign(socket, :processing, true)

              {[], [_ | _]} ->
                assign(socket, :processing, true)
            end

          Phoenix.PubSub.subscribe(Brando.pubsub(), "brando:image:#{image.id}")

          Brando.Images.Processing.queue_processing(
            image,
            current_user,
            {:transformer, relation_key, asset_key, image.id}
          )

          # get the default struct for the transformer
          transformer_defaults = socket.assigns.transformer_defaults

          default =
            case Map.get(transformer_defaults, key) do
              fun when is_function(fun) ->
                fun.(socket.assigns.entry, image)

              default ->
                default
            end

          asset_relation_key = String.to_existing_atom("#{asset_key}_id")
          default_with_asset = Map.put(default, asset_relation_key, image.id)
          changeset = socket.assigns.form.source
          relation_atom = String.to_existing_atom(relation_key)

          updated_field =
            changeset
            |> get_change_or_field(relation_atom)
            |> Kernel.++([default_with_asset])

          updated_changeset =
            case relation.type do
              :has_many -> put_assoc(changeset, relation_atom, updated_field)
              _ -> put_embed(changeset, relation_atom, updated_field)
            end

          if all_done? do
            # hmm
          end

          {:noreply,
           socket
           |> update(:processing_images, &[image.id | &1])
           |> assign(:form, to_form(updated_changeset, []))}
      end
    else
      {:noreply, socket}
    end
  end

  defp sequence(gallery_images) do
    gallery_images
    |> Enum.with_index()
    |> Enum.map(fn {gi, idx} -> Map.put(gi, :sequence, idx) end)
  end

  defp get_change_or_field(changeset, field) do
    with nil <- get_change(changeset, field) do
      get_field(changeset, field, [])
    end
  end

  def handle_file_progress(
        key,
        upload_entry,
        %{assigns: %{schema: schema, edit_file: edit_file, current_user: current_user}} = socket
      ) do
    socket = assign(socket, :processing, upload_entry.progress)

    if upload_entry.done? do
      socket = assign(socket, :processing, false)
      relation_key = String.to_existing_atom("#{key}_id")
      %{cfg: cfg} = Brando.Blueprint.Assets.__asset_opts__(schema, key)
      config_target = "file:#{inspect(schema)}:#{key}"

      case consume_uploaded_entry(
             socket,
             upload_entry,
             fn meta ->
               Brando.Upload.handle_upload(
                 Map.put(meta, :config_target, config_target),
                 upload_entry,
                 cfg,
                 current_user
               )
             end
           ) do
        {:error, :content_type, rejected_type, allowed_types} ->
          error_title = gettext("Error uploading")

          error_msg =
            gettext(
              "Server rejected file type [%{rejected_type}].<br><br>Allowed types are:<br>%{allowed_types}",
              %{rejected_type: rejected_type, allowed_types: inspect(allowed_types)}
            )

          {:noreply, push_event(socket, "b:alert", %{title: error_title, type: "error", message: error_msg})}

        file ->
          file_changeset = change(file)
          edit_file = Map.merge(edit_file, %{id: file.id, file: file})

          {:noreply,
           socket
           |> update_changeset(relation_key, file.id)
           |> assign(:edit_file, edit_file)
           |> assign(:file_changeset, file_changeset)}
      end
    else
      {:noreply, socket}
    end
  end

  def assign_form(
        %{
          assigns: %{
            default_params: default_params,
            entry: %{id: nil} = default_entry,
            schema: schema,
            current_user: current_user
          }
        } = socket
      ) do
    assign_new(socket, :form, fn ->
      # this is the initial assignment of changeset with an empty entry,
      # so we add default_params here
      default_entry
      |> schema.changeset(default_params, current_user)
      |> Map.put(:action, :validate)
      |> to_form()
    end)
  end

  def assign_form(%{assigns: %{entry: entry, schema: schema, current_user: current_user}} = socket) do
    assign_new(socket, :form, fn ->
      entry
      |> schema.changeset(%{}, current_user)
      |> Map.put(:action, :validate)
      |> to_form()
    end)
  end

  def assign_refreshed_form(%{assigns: %{entry: entry, schema: schema, current_user: current_user}} = socket) do
    updated_changeset =
      entry
      |> schema.changeset(%{}, current_user)
      |> Map.put(:action, :validate)

    assign(socket, :form, to_form(updated_changeset, []))
  end

  @doc """
  Assigns a stripped down entry to be used in block fields
  """
  def assign_entry_for_blocks(%{assigns: %{has_blocks?: true}} = socket) do
    changeset = socket.assigns.form.source
    block_map = socket.assigns.block_map
    entry_for_blocks = build_entry_for_blocks(changeset, block_map)
    assign(socket, :entry_for_blocks, entry_for_blocks)
  end

  @doc """
  Assigns a stripped down entry to be used in block fields
  """
  def maybe_assign_entry_for_blocks(%{assigns: %{has_blocks?: true}} = socket) do
    assign_new(socket, :entry_for_blocks, fn ->
      changeset = socket.assigns.form.source
      block_map = socket.assigns.block_map
      build_entry_for_blocks(changeset, block_map)
    end)
  end

  def maybe_assign_entry_for_blocks(socket), do: socket

  defp build_entry_for_blocks(changeset, block_map) do
    blocks_field_names =
      Enum.reduce(block_map, [], fn {block_field_name, _schema, _entry_blocks, _opts}, acc ->
        entry_field_name = :"entry_#{block_field_name}"
        rendered_field_name = :"rendered_#{block_field_name}"
        rendered_at_field_name = :"rendered_#{block_field_name}_at"

        [
          entry_field_name
          | [block_field_name | [rendered_field_name | [rendered_at_field_name | acc]]]
        ]
      end)

    changeset
    |> apply_changes()
    |> Map.drop(blocks_field_names)
  end

  def render_blocks_for_entry(block_map, changeset, entry) do
    Enum.reduce(block_map, changeset, fn {block_field_name, _schema, _entry_blocks, _opts}, updated_changeset ->
      entry_field_name = :"entry_#{block_field_name}"
      rendered_field_name = :"rendered_#{block_field_name}"
      rendered_at_field_name = :"rendered_#{block_field_name}_at"
      blocks_to_parse = get_assoc(changeset, entry_field_name)
      applied_blocks = Brando.Utils.apply_changes_recursively(blocks_to_parse)
      rendered_blocks = Villain.parse(applied_blocks, entry, [])

      updated_changeset
      |> put_change(rendered_field_name, rendered_blocks)
      |> put_change(rendered_at_field_name, DateTime.truncate(DateTime.utc_now(), :second))
    end)
  end

  defp send_updated_entry_field_to_blocks(socket, path, change) do
    blocks_wanting_entry = socket.assigns.blocks_wanting_entry

    Enum.each(blocks_wanting_entry, fn cid ->
      send_update(cid, %{event: "update_entry_field", path: path, change: change})
    end)

    socket
  end

  # used for updating schema assets
  def update_changeset(socket, [], key, arg) do
    # empty path, treat as root field
    update_changeset(socket, key, arg)
  end

  def update_changeset(socket, path, key, list) when is_list(list) do
    changeset = socket.assigns.form.source

    new_changeset =
      EctoNestedChangeset.update_at(changeset, path ++ [key], fn _ ->
        Enum.map(list, &Map.from_struct/1)
      end)

    assign(socket, :form, to_form(new_changeset, []))
  end

  def update_changeset(socket, path, key, map) when is_list(path) and is_map(map) do
    changeset = socket.assigns.form.source

    new_changeset =
      EctoNestedChangeset.update_at(changeset, path ++ [key], fn _ -> Map.from_struct(map) end)

    assign(socket, :form, to_form(new_changeset, []))
  end

  def update_changeset(socket, path, key, value) when is_list(path) do
    changeset = socket.assigns.form.source
    # if we have a path, apply_changes and change the changeset before updating it(?)
    changeset =
      if path == [] do
        changeset
      else
        changeset
        |> apply_changes()
        |> change()
      end

    new_changeset = EctoNestedChangeset.update_at(changeset, path ++ [key], fn _ -> value end)

    assign(socket, :form, to_form(new_changeset, []))
  end

  def update_changeset(socket, key, list) when is_list(list) do
    changeset = socket.assigns.form.source
    new_changeset = put_change(changeset, key, Enum.map(list, &Map.from_struct/1))

    assign(socket, :form, to_form(new_changeset, []))
  end

  def update_changeset(socket, key, value) when is_map(value) do
    changeset = socket.assigns.form.source
    new_changeset = put_change(changeset, key, Map.from_struct(value))

    assign(socket, :form, to_form(new_changeset, []))
  end

  def update_changeset(socket, key, value) do
    changeset = socket.assigns.form.source
    new_changeset = put_change(changeset, key, value)

    assign(socket, :form, to_form(new_changeset, []))
  end

  defp string_path_to_atom_path(string_path) do
    Enum.map(string_path, &String.to_existing_atom/1)
  end

  defp string_path_to_access_path(string_path) do
    case string_path do
      [field] ->
        field
        |> String.to_existing_atom()
        |> Access.key()
        |> List.wrap()

      [relation, field] ->
        [
          relation |> String.to_existing_atom() |> Access.key(),
          field |> String.to_existing_atom() |> Access.key()
        ]

      [relation, index, field] ->
        [
          relation |> String.to_existing_atom() |> Access.key(),
          index |> String.to_integer() |> Access.at(),
          field |> String.to_existing_atom() |> Access.key()
        ]
    end
  end

  ##
  ## Function components

  def live_preview(assigns) do
    ~H"""
    <%= if @live_preview_active? do %>
      <div class="live-preview-wrapper" phx-update="ignore" id="live-preview" phx-hook="Brando.LivePreview">
        <div class="live-preview">
          <div class="live-preview-targets">
            <div class="live-preview-divider"></div>
            <button
              type="button"
              class="tiny live-preview-blank"
              phx-click="open_live_preview_standalone"
              phx-target={@target}
            >
              {gettext("Open preview in new window")}
            </button>
            <div class="live-preview-targets-buttons">
              <button type="button" data-live-preview-target="desktop">
                <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="24" height="24">
                  <path fill="none" d="M0 0h24v24H0z" /><path d="M4 5v11h16V5H4zm-2-.993C2 3.451 2.455 3 2.992 3h18.016c.548 0 .992.449.992 1.007V18H2V4.007zM1 19h22v2H1v-2z" />
                </svg>
                <span>1440px</span>
              </button>
              <button type="button" data-live-preview-target="tablet">
                <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="24" height="24">
                  <path fill="none" d="M0 0h24v24H0z" /><path d="M6 4v16h12V4H6zM5 2h14a1 1 0 0 1 1 1v18a1 1 0 0 1-1 1H5a1 1 0 0 1-1-1V3a1 1 0 0 1 1-1zm7 15a1 1 0 1 1 0 2 1 1 0 0 1 0-2z" />
                </svg>
                <span>768px</span>
              </button>
              <button type="button" data-live-preview-target="mobile">
                <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="24" height="24">
                  <path fill="none" d="M0 0h24v24H0z" /><path d="M7 4v16h10V4H7zM6 2h12a1 1 0 0 1 1 1v18a1 1 0 0 1-1 1H6a1 1 0 0 1-1-1V3a1 1 0 0 1 1-1zm6 15a1 1 0 1 1 0 2 1 1 0 0 1 0-2z" />
                </svg>
                <span>375px</span>
              </button>
            </div>
          </div>
          <div class="live-preview-iframe-wrapper">
            <iframe data-live-preview-device={@live_preview_target} src={"/__livepreview?key=#{@live_preview_cache_key}"}>
            </iframe>
          </div>
        </div>
      </div>
    <% end %>
    """
  end

  attr :field, Phoenix.HTML.FormField
  attr :relation, :boolean
  attr :compact, :boolean, default: false
  attr :left_justify_meta, :boolean, default: false
  attr :meta_top, :boolean, default: false
  attr :instructions, :string
  attr :label, :any
  attr :class, :any
  attr :fit_content, :boolean, default: false
  attr :uid, :string
  attr :id_prefix, :string
  attr :skip_presence, :boolean, default: false
  slot :meta
  slot :header

  def field_base(assigns) do
    relation = Map.get(assigns, :relation, false)
    failed = has_error(assigns.field, relation)
    label = get_label(assigns)
    hidden = label == :hidden

    assigns =
      assigns
      |> assign_new(:uid, fn -> nil end)
      |> assign_new(:id_prefix, fn -> "" end)
      |> assign_new(:class, fn -> nil end)
      |> assign_new(:left_justify_meta, fn -> nil end)
      |> assign(:relation, relation)
      |> assign(:failed, failed)
      |> assign(:hidden, hidden)
      |> assign(:label, label)
      |> assign(:raw_instructions, assigns[:instructions])

    f_id =
      if assigns[:uid] do
        "f-#{assigns.uid}-#{assigns.id_prefix}-#{assigns.field.id}"
      else
        "#{assigns.field.id}"
      end

    f_name = assigns[:field] && assigns[:field].name

    assigns =
      assigns
      |> assign(:f_id, f_id)
      |> assign(:f_name, f_name)

    ~H"""
    <div
      class={["field-wrapper", @class, @fit_content && "fit-content"]}
      id={"#{@f_id}-field-wrapper"}
      phx-hook="Brando.FieldBase"
    >
      <div class={["label-wrapper", @hidden && "hidden"]}>
        <label
          for={"#{@f_id}"}
          class={["control-label", @failed && "failed"]}
          data-field-presence={!@skip_presence && @f_name}
        >
          <span>{@label}</span>
          <div :if={!@skip_presence} class="field-presence" phx-update="ignore" id={"#{@f_id}-field-presence"}></div>
        </label>
        <.error_tag :if={@field} field={@field} relation={@relation} id_prefix={@id_prefix} uid={@uid} />
        <div :if={@header != []} class="field-wrapper-header">
          {render_slot(@header)}
        </div>
      </div>
      <%= if @raw_instructions || @meta do %>
        <div :if={@meta_top} class={["meta", @left_justify_meta && "left"]}>
          <%= if @raw_instructions do %>
            <div class="help-text">
              ↳ <span>{@raw_instructions}</span>
            </div>
            <div :if={@meta != []} class="extra">
              {render_slot(@meta)}
            </div>
          <% end %>
        </div>
      <% end %>
      <div class="field-base" id={"#{@f_id}-field-base"}>
        {render_slot(@inner_block)}
      </div>
      <%= if @raw_instructions || @meta do %>
        <div :if={!@meta_top} class={["meta", @left_justify_meta && "left"]}>
          <%= if @raw_instructions do %>
            <div class="help-text">
              ↳ <span>{@raw_instructions}</span>
            </div>
            <div :if={@meta != []} class="extra">
              {render_slot(@meta)}
            </div>
          <% end %>
        </div>
      <% end %>
    </div>
    """
  end

  defp get_label(%{label: nil} = assigns) do
    assigns.field.field
    |> to_string()
    |> Brando.Utils.humanize()
  end

  defp get_label(%{label: label}) do
    label
  end

  defp has_error(field, true) do
    relation_field = :"#{field.field}_id"

    case Keyword.get_values(field.form.errors, relation_field) do
      [] -> false
      _ -> true
    end
  end

  defp has_error(%{errors: []}, _), do: false
  defp has_error(%{errors: _}, _), do: true

  def input(assigns) do
    assigns =
      assigns
      |> assign_new(:path, fn -> [] end)
      |> assign_new(:component_id, fn -> assigns.field.id end)
      |> assign_new(:parent_form, fn -> nil end)
      |> assign_new(:parent_form_id, fn -> nil end)
      |> assign_new(:subform_id, fn -> nil end)
      |> assign_new(:form_cid, fn -> nil end)
      |> assign_new(:compact, fn -> Keyword.get(assigns.opts, :compact, false) end)
      |> assign_new(:size, fn -> Keyword.get(assigns.opts, :size, "full") end)
      |> assign_new(:component_target, fn ->
        case assigns.type do
          {:component, _module} ->
            raise """

            {:component, module} is deprecated. Use {:live_component, module} instead.
            If you want to pass a function component, pass it as a function capture instead:

            &Components.my_component/1

            """

          {:live_component, module} ->
            module

          fun when is_function(fun, 1) ->
            fun

          type ->
            type_module = type |> to_string() |> Macro.camelize()
            input_module = Module.concat([Input, type_module])

            # if module exists, it's a live component. if not, function component
            case Code.ensure_compiled(input_module) do
              {:module, _} -> input_module
              _ -> Function.capture(BrandoAdmin.Components.Form.Input, type, 1)
            end
        end
      end)

    ~H"""
    <%= if is_function(@component_target) do %>
      <div class="brando-input" data-component={@type} data-compact={@compact} data-size={@size}>
        {component(
          @component_target,
          assigns,
          {__ENV__.module, __ENV__.function, __ENV__.file, __ENV__.line}
        )}
      </div>
    <% else %>
      <div class="brando-input" data-component={inspect(@type)} data-compact={@compact} data-size={@size}>
        <.live_component
          module={@component_target}
          id={@component_id}
          parent_form={@parent_form}
          parent_form_id={@parent_form_id}
          subform_id={@subform_id}
          field={@field}
          label={@label}
          path={@path}
          placeholder={@placeholder}
          instructions={@instructions}
          parent_uploads={@parent_uploads}
          opts={@opts}
          current_user={@current_user}
          form_cid={@form_cid}
          on_change={fn params -> send_update(@form_cid, params) end}
        />
      </div>
    <% end %>
    """
  end

  attr :field, Phoenix.HTML.FormField
  slot :inner_block

  def map_inputs(assigns) do
    subform = Utils.form_for_map(assigns.field)

    input_value =
      if input_value = assigns.field.value do
        Enum.reduce(input_value, %{}, fn
          {"_unused_" <> _k, _v}, acc -> acc
          {k, v}, acc -> Map.put(acc, k, v)
        end)
      end

    assigns =
      assigns
      |> assign(:subform, subform)
      |> assign(:input_value, input_value)

    ~H"""
    <%= if @input_value do %>
      <%= for {map_key, map_value} <- @input_value do %>
        {render_slot(@inner_block, %{
          name: "#{@field.name}[#{map_key}]",
          key: map_key,
          value: map_value,
          subform: @subform
        })}
      <% end %>
    <% end %>
    """
  end

  attr :field, Phoenix.HTML.FormField

  def map_value_inputs(assigns) do
    subform = Utils.form_for_map_value(assigns.field)
    input_value = assigns.field.value

    assigns =
      assigns
      |> assign(:subform, subform)
      |> assign(:input_value, input_value)

    ~H"""
    <%= for {map_key, map_value} <- @input_value do %>
      {render_slot(@inner_block, %{
        name: "#{@field.name}[#{map_key}]",
        key: map_key,
        value: map_value,
        subform: @subform
      })}
    <% end %>
    """
  end

  @doc type: :component
  attr :field, Phoenix.HTML.FormField,
    required: true,
    doc: "A %Phoenix.HTML.Form{}/field name tuple, for example: {@form[:email]}."

  attr :id, :string,
    doc: """
    The id to be used in the form, defaults to the concatenation of the given
    field to the parent form id.
    """

  attr :as, :atom,
    doc: """
    The name to be used in the form, defaults to the concatenation of the given
    field to the parent form name.
    """

  attr :default, :any, doc: "The value to use if none is available."

  attr :prepend, :list,
    doc: """
    The values to prepend when rendering. This only applies if the field value
    is a list and no parameters were sent through the form.
    """

  attr :append, :list,
    doc: """
    The values to append when rendering. This only applies if the field value
    is a list and no parameters were sent through the form.
    """

  attr :skip_hidden, :boolean,
    default: false,
    doc: """
    Skip the automatic rendering of hidden fields to allow for more tight control
    over the generated markup.
    """

  slot :inner_block, required: true, doc: "The content rendered for each nested form."

  def inputs_for_block(assigns) do
    %Phoenix.HTML.FormField{form: form} = assigns.field
    options = assigns |> Map.take([:id, :as, :default, :append, :prepend]) |> Keyword.new()

    options =
      form.options
      |> Keyword.take([:multipart])
      |> Keyword.merge(options)

    forms =
      BrandoAdmin.Components.Form.Input.Blocks.Utils.to_form_single(
        form.source,
        assigns.field,
        options
      )

    assigns = assign(assigns, :forms, forms)

    ~H"""
    <%= for finner <- @forms do %>
      <%= unless @skip_hidden do %>
        <%= for {name, value_or_values} <- finner.hidden,
                name = name_for_value_or_values(finner, name, value_or_values),
                value <- List.wrap(value_or_values) do %>
          <input type="hidden" name={name} value={value} />
        <% end %>
      <% end %>
      {render_slot(@inner_block, finner)}
    <% end %>
    """
  end

  @doc type: :component
  attr :field, Phoenix.HTML.FormField,
    required: true,
    doc: "A %Phoenix.HTML.Form{}/field name tuple, for example: {@form[:email]}."

  attr :id, :string,
    doc: """
    The id to be used in the form, defaults to the concatenation of the given
    field to the parent form id.
    """

  attr :as, :atom,
    doc: """
    The name to be used in the form, defaults to the concatenation of the given
    field to the parent form name.
    """

  attr :default, :any, doc: "The value to use if none is available."

  attr :prepend, :list,
    doc: """
    The values to prepend when rendering. This only applies if the field value
    is a list and no parameters were sent through the form.
    """

  attr :append, :list,
    doc: """
    The values to append when rendering. This only applies if the field value
    is a list and no parameters were sent through the form.
    """

  attr :skip_hidden, :boolean,
    default: false,
    doc: """
    Skip the automatic rendering of hidden fields to allow for more tight control
    over the generated markup.
    """

  slot :inner_block, required: true, doc: "The content rendered for each nested form."

  def inputs_for_poly(assigns) do
    %Phoenix.HTML.FormField{form: form} = assigns.field
    options = assigns |> Map.take([:id, :as, :default, :append, :prepend]) |> Keyword.new()

    options =
      form.options
      |> Keyword.take([:multipart])
      |> Keyword.merge(options)

    forms =
      BrandoAdmin.Components.Form.Input.Blocks.Utils.to_form_multi(
        form.source,
        assigns.field,
        options
      )

    assigns = assign(assigns, :forms, forms)

    ~H"""
    <%= for finner <- @forms do %>
      <%= unless @skip_hidden do %>
        <%= for {name, value_or_values} <- finner.hidden,
                name = name_for_value_or_values(finner, name, value_or_values),
                value <- List.wrap(value_or_values) do %>
          <input type="hidden" name={name} value={value} />
        <% end %>
      <% end %>
      {render_slot(@inner_block, finner)}
    <% end %>
    """
  end

  defp name_for_value_or_values(form, field, values) when is_list(values) do
    Phoenix.HTML.Form.input_name(form, field) <> "[]"
  end

  defp name_for_value_or_values(form, field, _value) do
    Phoenix.HTML.Form.input_name(form, field)
  end

  attr :field, Phoenix.HTML.FormField
  slot :inner_block

  def array_inputs(assigns) do
    assigns =
      assigns
      |> assign(:input_value, assigns.field.value)
      |> assign(:indexed_inputs, Enum.with_index(assigns.field.value || []))

    ~H"""
    <%= if @input_value do %>
      <%= for {array_value, array_index} <- @indexed_inputs do %>
        {render_slot(@inner_block, %{
          name: "#{@field.name}[]",
          index: array_index,
          value: array_value
        })}
      <% end %>
    <% end %>
    """
  end

  attr :field, Phoenix.HTML.FormField
  attr :options, :any
  slot :inner_block

  def array_inputs_from_data(assigns) do
    checked_values = assigns.field.value || []

    assigns =
      assigns
      |> assign(:checked_values, Enum.map(checked_values, &to_string(&1)))
      |> assign(:indexed_options, Enum.with_index(assigns.options))

    ~H"""
    <%= for {option, idx} <- @indexed_options do %>
      {render_slot(@inner_block, %{
        name: "#{@field.name}[]",
        id: "#{@field.id}-#{idx}",
        index: idx,
        value: option.value,
        label: option.label,
        checked: option.value in @checked_values
      })}
    <% end %>
    """
  end

  def submit_button(assigns) do
    ~H"""
    <button
      id={"#{@form_id}-submit"}
      type="button"
      disabled={@processing}
      data-processing={@processing}
      data-form-id={@form_id}
      data-testid="submit"
      class={@class}
      phx-hook="Brando.Submit"
    >
      <%= if @processing do %>
        <div class="processing">
          <svg class="spin" xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="24" height="24">
            <path fill="none" d="M0 0h24v24H0z" /><path d="M5.463 4.433A9.961 9.961 0 0 1 12 2c5.523 0 10 4.477 10 10 0 2.136-.67 4.116-1.81 5.74L17 12h3A8 8 0 0 0 6.46 6.228l-.997-1.795zm13.074 15.134A9.961 9.961 0 0 1 12 22C6.477 22 2 17.523 2 12c0-2.136.67-4.116 1.81-5.74L7 12H4a8 8 0 0 0 13.54 5.772l.997 1.795z" />
          </svg>
          {gettext("Processing. Please wait...")}
        </div>
      <% else %>
        {@label}
      <% end %>
    </button>
    """
  end

  @doc """
  Translates an error message using gettext.
  """
  def translate_error({msg, opts}) do
    # When using gettext, we typically pass the strings we want
    # to translate as a static argument:
    #
    #     # Translate "is invalid" in the "errors" domain
    #     dgettext("errors", "is invalid")
    #
    #     # Translate the number of files with plural rules
    #     dngettext("errors", "1 file", "%{count} files", count)
    #
    # Because the error messages we show in our forms and APIs
    # are defined inside Ecto, we need to translate them dynamically.
    # This requires us to call the Gettext module passing our gettext
    # backend as first argument.
    #
    # Note we use the "errors" domain, which means translations
    # should be written to the errors.po file. The :count option is
    # set by Ecto and indicates we should also apply plural rules.
    if count = opts[:count] do
      Gettext.dngettext(Brando.web_module(Gettext), "errors", msg, msg, count, opts)
    else
      Gettext.dgettext(Brando.web_module(Gettext), "errors", msg, opts)
    end
  end

  attr :field, Phoenix.HTML.FormField
  attr :relation, :atom
  attr :id_prefix, :string
  attr :uid, :string

  def error_tag(assigns) do
    errors = if Phoenix.Component.used_input?(assigns.field), do: assigns.field.errors, else: []

    assigns =
      assigns
      |> assign(:errors, errors)
      |> assign_new(:translate_fn, fn ->
        {mod, fun} = assigns[:translator] || {__MODULE__, :translate_error}
        &apply(mod, fun, [&1])
      end)

    assigns =
      if assigns.relation do
        relation_field_atom = :"#{assigns.field.field}_id"
        assign(assigns, :field, assigns.field.form[relation_field_atom])
      else
        assigns
      end

    f_id =
      if assigns[:uid] do
        "f-#{assigns.uid}-#{assigns.id_prefix}-#{assigns.field.id}"
      else
        "#{assigns.field.id}"
      end

    assigns = assign(assigns, :f_id, f_id)

    ~H"""
    <span :for={error <- @errors} id={"#{@f_id}-error"} class="field-error">
      {@translate_fn.(error)}
    </span>
    """
  end

  attr :form, :any
  attr :field, :any
  attr :uid, :any, default: nil
  attr :id_prefix, :string, default: ""
  attr :class, :any, default: nil
  attr :click, :any, default: nil
  attr :popover, :string, default: nil
  attr :skip_presence, :boolean, default: false
  slot :inner_block

  def label(assigns) do
    f_id =
      if assigns.uid do
        "f-#{assigns.uid}-#{assigns.id_prefix}-#{assigns.field.id}"
      else
        "#{assigns.field.id}"
      end

    f_name = assigns[:field] && assigns[:field].name

    assigns =
      assigns
      |> assign(:f_id, f_id)
      |> assign(:f_name, f_name)

    ~H"""
    <label class={@class} for={@f_id} data-popover={@popover} phx-click={@click} data-field-presence={@f_name}>
      {render_slot(@inner_block)}
      <div :if={!@skip_presence} class="field-presence" phx-update="ignore" id={"#{@f_id}-field-presence"}></div>
    </label>
    """
  end
end
