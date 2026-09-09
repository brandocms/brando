defmodule BrandoAdmin.Components.Form.Input.RenderVar do
  @moduledoc false
  use BrandoAdmin, :live_component
  use Gettext, backend: Brando.Gettext

  import BrandoAdmin.Components.Content.List.Row, only: [status_circle: 1]
  import Ecto.Changeset

  alias Brando.Repo
  alias Brando.Utils
  alias BrandoAdmin.Components.Assets.MediaField
  alias BrandoAdmin.Components.Content
  alias BrandoAdmin.Components.Form.Input
  alias BrandoAdmin.Components.Form.Primitives
  alias Phoenix.HTML

  # prop var, :any
  # prop render, :atom, values: [:all, :content, :config], default: :all
  # prop edit, :boolean, default: false

  # data should_render?, :boolean
  # data label, :string
  # data type, :string
  # data instructions, :string
  # data placeholder, :string
  # data value, :any
  # data visible, :boolean
  # data publish, :boolean

  def mount(socket) do
    {:ok, assign(socket, :publish, false)}
  end

  def update_many(assigns_sockets) do
    original_assigns_sockets = assigns_sockets

    {processed_events, assigns_sockets} =
      Enum.split_with(assigns_sockets, fn {assigns, _} -> assigns[:event] == "image_processed" end)

    processed_results =
      Enum.map(processed_events, fn {%{image: image}, socket} ->
        cond do
          socket.assigns[:image_id] == image.id ->
            assign(socket, :image, image)

          socket.assigns[:type] == :gallery && socket.assigns[:gallery] ->
            gallery = socket.assigns.gallery

            objects =
              Enum.map(gallery_objects(gallery), fn object ->
                if object.image_id == image.id, do: %{object | image: image}, else: object
              end)

            assign(socket, :gallery, %{gallery | gallery_objects: objects})

          true ->
            socket
        end
      end)

    {upload_events, rest} =
      Enum.split_with(assigns_sockets, fn {assigns, _socket} ->
        Map.has_key?(assigns, :event) && assigns.event == "upload_complete"
      end)

    # Entry-level link vars route SelectIdentifier picks back here (no owning
    # block to receive "update_block_var") — apply them through on_change/2 so
    # the nil-on_change clause syncs the FK into the parent form.
    {var_change_events, remaining_updates} =
      Enum.split_with(rest, fn {assigns, _socket} ->
        Map.has_key?(assigns, :event) && assigns.event == "update_block_var"
      end)

    {video_created_events, var_updates} =
      Enum.split_with(remaining_updates, fn {assigns, _socket} ->
        Map.has_key?(assigns, :event) && assigns.event == "video_created_from_url"
      end)

    var_change_results =
      Enum.map(var_change_events, fn {assigns, socket} ->
        on_change(socket, assigns.data)
      end)

    video_created_results =
      Enum.map(video_created_events, fn {assigns, socket} ->
        {:ok, video} =
          Brando.Videos.get_video(%{
            matches: %{id: assigns.video_data.id},
            preload: [:thumbnail, :file]
          })

        socket
        |> assign(:video, video)
        |> assign(:video_id, video.id)
        |> on_change(%{video: video, video_id: video.id})
      end)

    # Handle upload_complete events directly (no DB lookups needed)
    upload_results =
      Enum.map(upload_events, fn {assigns, socket} ->
        current_id = socket.assigns[assigns.asset_type] && socket.assigns[assigns.asset_type].id

        if Brando.Uploads.AssetIntent.current_selection?(assigns[:expected_asset_id], current_id) do
          case {socket.assigns.type, assigns.asset_type} do
            {:gallery, media_type} ->
              id_field = if media_type == :image, do: :image_id, else: :video_id
              objects = gallery_objects(socket.assigns.gallery)

              persist_gallery(
                socket,
                objects ++ [%{id_field => assigns.asset.id, creator_id: socket.assigns.current_user_id}]
              )

            {_, :image} ->
              socket
              |> assign(:image, assigns.asset)
              |> assign(:image_id, assigns.asset.id)
              |> on_change(%{image: assigns.asset, image_id: assigns.asset.id})

            {_, :file} ->
              socket
              |> assign(:file, assigns.asset)
              |> assign(:file_id, assigns.asset.id)
              |> on_change(%{file: assigns.asset, file_id: assigns.asset.id})

            {_, :video} ->
              socket
              |> assign(:video, assigns.asset)
              |> assign(:video_id, assigns.asset.id)
              |> on_change(%{video: assigns.asset, video_id: assigns.asset.id})
          end
        else
          socket
        end
      end)

    # Handle normal var updates with batched DB lookups
    var_results =
      if var_updates != [] do
        asset_ids = collect_asset_ids(var_updates)
        lookups = build_asset_lookups(asset_ids)
        Enum.map(var_updates, &assemble_socket(&1, lookups))
      else
        []
      end

    results =
      Map.new(
        processed_results ++ upload_results ++ var_change_results ++ video_created_results ++ var_results,
        &{&1.assigns.id, &1}
      )

    Enum.map(original_assigns_sockets, fn {assigns, socket} -> Map.fetch!(results, assigns[:id] || socket.assigns.id) end)
  end

  defp collect_asset_ids(assigns_sockets) do
    Enum.reduce(assigns_sockets, %{images: [], files: [], videos: [], galleries: [], identifiers: []}, fn
      {%{id: id, var: %{source: changeset}}, _socket}, acc ->
        collect_asset_id_for_type(get_field(changeset, :type), changeset, id, acc)
    end)
  end

  defp collect_asset_id_for_type(:image, changeset, id, acc) do
    image_id = get_field(changeset, :image_id)
    %{acc | images: [{id, image_id} | acc.images]}
  end

  defp collect_asset_id_for_type(:file, changeset, id, acc) do
    file_id = get_field(changeset, :file_id)
    %{acc | files: [{id, file_id} | acc.files]}
  end

  defp collect_asset_id_for_type(:video, changeset, id, acc) do
    video_id = get_field(changeset, :video_id)
    %{acc | videos: [{id, video_id} | acc.videos]}
  end

  defp collect_asset_id_for_type(:gallery, changeset, id, acc) do
    gallery_id = get_field(changeset, :gallery_id)
    %{acc | galleries: [{id, gallery_id} | acc.galleries]}
  end

  defp collect_asset_id_for_type(:link, changeset, id, acc) do
    case get_field(changeset, :identifier_id) do
      nil -> acc
      identifier_id -> %{acc | identifiers: [{id, identifier_id} | acc.identifiers]}
    end
  end

  defp collect_asset_id_for_type(_type, _changeset, _id, acc), do: acc

  defp build_asset_lookups(asset_ids) do
    %{
      images: fetch_and_map_assets(asset_ids.images, &fetch_images/1),
      files: fetch_and_map_assets(asset_ids.files, &fetch_files/1),
      videos: fetch_and_map_assets(asset_ids.videos, &fetch_videos/1),
      galleries: fetch_and_map_assets(asset_ids.galleries, &fetch_galleries/1),
      identifiers: fetch_and_map_assets(asset_ids.identifiers, &fetch_identifiers/1)
    }
  end

  defp fetch_and_map_assets([], _fetch_fn), do: {%{}, %{}}

  defp fetch_and_map_assets(component_id_pairs, fetch_fn) do
    ids = Enum.map(component_id_pairs, &elem(&1, 1))
    {:ok, assets} = fetch_fn.(ids)
    asset_map = Map.new(assets, &{&1.id, &1})
    component_map = Map.new(component_id_pairs)
    {asset_map, component_map}
  end

  defp fetch_images(ids) do
    Brando.Images.list_images(%{filter: %{ids: ids}, cache: {:ttl, :timer.minutes(5)}})
  end

  defp fetch_files(ids) do
    Brando.Files.list_files(%{filter: %{ids: ids}, cache: {:ttl, :timer.minutes(5)}})
  end

  defp fetch_videos(ids) do
    Brando.Videos.list_videos(%{filter: %{ids: ids}, preload: [:thumbnail, :file]})
  end

  defp fetch_galleries(ids) do
    Brando.Galleries.list_galleries(%{
      filter: %{ids: ids},
      preload: [gallery_objects: [:image, video: [:thumbnail, :file]]]
    })
  end

  defp fetch_identifiers(ids) do
    Brando.Content.list_identifiers(%{
      filter: %{ids: ids},
      cache: {:ttl, :timer.minutes(5)},
      order: {:array_position, ids}
    })
  end

  defp assemble_socket({assigns, socket}, lookups) do
    socket
    |> refresh_asset_assign(:image, :image_id, lookups.images, assigns)
    |> refresh_asset_assign(:file, :file_id, lookups.files, assigns)
    |> refresh_asset_assign(:video, :video_id, lookups.videos, assigns)
    |> refresh_asset_assign(:gallery, :gallery_id, lookups.galleries, assigns)
    |> assign(:identifier, lookup_asset(lookups.identifiers, assigns.id))
    |> assign_var_fields(assigns)
  end

  # Keep @image/@file in sync with the changeset FK. `assign_new` would strand a
  # stale nil after an upload/select changed the FK (blank card); a plain `assign`
  # would re-fetch a fresh struct every render and loop. So only (re)assign when
  # the changeset's *_id differs from the currently-displayed asset — this refreshes
  # the card on an actual change and stays stable (no re-fetch, no loop) otherwise.
  defp refresh_asset_assign(socket, key, fk_field, lookup, assigns) do
    changeset_id = get_field(assigns.var.source, fk_field)
    current = Map.get(socket.assigns, key, :unset)
    current_id = if is_struct(current), do: current.id, else: nil

    if current != :unset and changeset_id == current_id do
      socket
    else
      assign(socket, key, changeset_id && lookup_asset(lookup, assigns.id))
    end
  end

  defp lookup_asset({asset_map, component_map}, component_id) do
    with asset_id when not is_nil(asset_id) <- Map.get(component_map, component_id) do
      Map.get(asset_map, asset_id)
    end
  end

  defp assign_var_fields(socket, assigns) do
    var = assigns.var
    changeset = var.source
    type = get_field(changeset, :type)
    placement = get_field(changeset, :placement) || :content
    value = type |> extract_value(changeset) |> then(&control_value(type, &1))

    socket
    |> assign(assigns)
    |> assign_new(:visible, fn -> Map.get(assigns, :initially_open, false) end)
    |> assign(:id, assigns.id)
    |> assign(:edit, Map.get(assigns, :edit, false))
    |> assign(:modal_editor, Map.get(assigns, :modal_editor, false))
    |> assign(:upload_kind, if(Map.get(assigns, :on_change), do: "block_var", else: "entry_var"))
    |> assign(:target, Map.get(assigns, :target, nil))
    |> assign(:should_render?, should_render?(Map.get(assigns, :render, :all), placement))
    # Blank, not just nil: after a validate round trip the id comes back as the
    # "" this component's own hidden input submitted. See `Render.carried_var/1`,
    # which carries the same distinction for vars with no UI at all.
    |> assign(:unsaved_var?, var[:id].value in [nil, ""])
    |> assign(:placement, placement)
    |> assign(:label, get_field(changeset, :label))
    |> assign(:key, var[:key].value)
    |> assign(:type, type)
    |> assign(:value, value)
    |> assign_new(:width_options, fn -> width_options() end)
    |> assign_new(:blueprint_schema_opts, fn ->
      schemas = Brando.Blueprint.list_blueprints()
      Enum.map(schemas, &%{label: &1.__naming__().singular, value: &1})
    end)
    |> assign_new(:form_id, fn -> nil end)
    |> assign_new(:current_user_id, fn -> get_field(changeset, :creator_id) end)
    |> assign_new(:on_change, fn -> nil end)
    |> assign_new(:images, fn -> nil end)
    |> assign_new(:files, fn -> nil end)
    |> assign_new(:videos, fn -> nil end)
    |> assign_new(:galleries, fn -> nil end)
    |> assign_new(:inner_block, fn -> nil end)
    |> assign_new(:identifiers, fn -> nil end)
    |> assign(:value_id, value)
    |> assign(:image_id, if(type == :image, do: value))
    |> assign(:file_id, if(type == :file, do: value))
    |> assign(:video_id, if(type == :video, do: value))
    |> assign(:gallery_id, if(type == :gallery, do: value))
    |> assign(:identifier_id, get_field(changeset, :identifier_id))
    |> assign(:instructions, get_field(changeset, :instructions))
    |> assign(:placeholder, get_field(changeset, :placeholder))
    |> assign(:palette_colors, if(type == :color, do: Input.palette_colors(get_field(changeset, :palette_id))))
    |> assign(:var, var)
  end

  # Only ever called from the section guarded by `@type in [:color, :link,
  # :select]`, so there is no other type to fall back for.
  defp type_settings_heading(:color), do: gettext("Color settings")
  defp type_settings_heading(:link), do: gettext("Link settings")
  defp type_settings_heading(:select), do: gettext("Choices")

  defp width_options do
    [
      %{label: gettext("Full row"), value: "full"},
      %{label: gettext("Half — 6 units"), value: "half"},
      %{label: gettext("Third — 4 units"), value: "third"},
      %{label: gettext("Quarter — 3 units"), value: "fourth"},
      %{label: gettext("Auto — fits its content"), value: "auto"},
      %{label: gettext("Fill — takes what is left"), value: "fill"}
    ]
  end

  defp extract_value(:image, changeset), do: get_field(changeset, :image_id)
  defp extract_value(:file, changeset), do: get_field(changeset, :file_id)
  defp extract_value(:video, changeset), do: get_field(changeset, :video_id)
  defp extract_value(:gallery, changeset), do: get_field(changeset, :gallery_id)
  defp extract_value(:boolean, changeset), do: get_field(changeset, :value_boolean)
  defp extract_value(_type, changeset), do: get_field(changeset, :value)

  # `:all` is the authoring render — the module editor's edit modal — and has to
  # include `:hidden` vars: it is where placement is changed, and a var whose
  # inputs leave the form loses its params on the next submit. The surface
  # renders are the consumption side, and there `:hidden` shows nothing.
  defp should_render?(:all, _placement), do: true
  defp should_render?(_render, :hidden), do: false
  defp should_render?(placement, placement), do: true
  defp should_render?(_render, _placement), do: false

  defp control_value(nil, nil), do: ""
  defp control_value(:string, value) when is_binary(value), do: value
  defp control_value(:string, _value), do: ""

  defp control_value(:text, value) when is_binary(value), do: value
  defp control_value(:text, _value), do: ""

  defp control_value(:datetime, %DateTime{} = value), do: value
  defp control_value(:datetime, %Date{} = value), do: value
  defp control_value(:datetime, _value), do: DateTime.utc_now()

  defp control_value(:boolean, value) when is_boolean(value), do: value
  defp control_value(:boolean, _value), do: false

  defp control_value(:color, "#" <> value), do: "##{value}"
  defp control_value(:color, _value), do: "#000000"

  defp control_value(:select, value) when is_binary(value), do: value
  defp control_value(:select, _value), do: ""

  defp control_value(:html, value) when is_binary(value), do: value
  defp control_value(:html, _value), do: "<p></p>"

  defp control_value(:image, value) when is_binary(value), do: nil
  defp control_value(:image, value) when is_boolean(value), do: nil
  defp control_value(:image, value), do: value

  defp control_value(:file, value) when is_binary(value), do: nil
  defp control_value(:file, value) when is_boolean(value), do: nil
  defp control_value(:file, value), do: value

  defp control_value(:video, value) when is_binary(value), do: nil
  defp control_value(:video, value) when is_boolean(value), do: nil
  defp control_value(:video, value), do: value

  defp control_value(:gallery, value) when is_binary(value), do: nil
  defp control_value(:gallery, value) when is_boolean(value), do: nil
  defp control_value(:gallery, value), do: value

  defp control_value(:link, value) when is_binary(value), do: nil
  defp control_value(:link, value) when is_boolean(value), do: nil
  defp control_value(:link, value), do: value

  def render(assigns) do
    ~H"""
    <div id={@id} class={["variable", @var[:type].value]} data-size={@var[:width].value} data-id={@var[:id].value}>
      <%= if @inner_block do %>
        {render_slot(@inner_block)}
      <% end %>
      <%= if @should_render? do %>
        <%= if @edit do %>
          <div id={"#{@var.id}-edit"} class="variable-editor">
            <%!-- Still a disclosure: the entry-var editor (Input.Vars) stacks
                  several of these and opens them one at a time. In a modal
                  `initially_open` makes it moot. --%>
            <div class="variable-header" phx-click={JS.push("toggle_visible", target: @myself)}>
              <span class="variable-type">{@var[:type].value}</span>
              <div class="variable-key">
                <code>&lcub;&lcub; {@var[:key].value} &rcub;&rcub;</code>
                <span>{@var[:label].value || gettext("No label")}</span>
              </div>
              <span class={["variable-chevron", @visible && "is-open"]} aria-hidden="true">
                <.icon name="hero-chevron-down" />
              </span>
            </div>

            <div class={["variable-content", !@visible && "hidden"]}>
              <Content.modal_sections id={"#{@var.id}-editor-sections"} enabled={@modal_editor}>
                <:section id="definition" label={gettext("Definition")} icon="hero-code-bracket">
                  <section class="variable-section">
                    <h3>{gettext("Naming")}</h3>
                    <div class="variable-grid">
                      <Input.text
                        field={@var[:key]}
                        label={gettext("Key")}
                        instructions={gettext("How the template refers to it")}
                      />
                      <Input.text
                        field={@var[:label]}
                        label={gettext("Label")}
                        instructions={gettext("What the editor sees above the field")}
                      />
                    </div>
                    <div class="variable-grid">
                      <Input.text field={@var[:instructions]} label={gettext("Instructions")} />
                      <Input.text field={@var[:placeholder]} label={gettext("Placeholder")} />
                    </div>
                  </section>

                  <section class="variable-section">
                    <h3>{gettext("Type and placement")}</h3>
                    <div class="variable-grid">
                      <.live_component
                        module={Input.Select}
                        id={"#{@var.id}-select-type"}
                        label={gettext("Type")}
                        field={@var[:type]}
                        opts={[
                          options: [
                            %{label: gettext("Boolean"), value: "boolean"},
                            %{label: gettext("Color"), value: "color"},
                            %{label: gettext("Datetime"), value: "datetime"},
                            %{label: gettext("File"), value: "file"},
                            %{label: gettext("Gallery"), value: "gallery"},
                            %{label: gettext("Html"), value: "html"},
                            %{label: gettext("Image"), value: "image"},
                            %{label: gettext("Link"), value: "link"},
                            %{label: gettext("String"), value: "string"},
                            %{label: gettext("Select"), value: "select"},
                            %{label: gettext("Text"), value: "text"},
                            %{label: gettext("Video"), value: "video"}
                          ]
                        ]}
                        publish={@publish}
                      />

                      <.live_component
                        module={Input.Select}
                        id={"#{@var.id}-select-placement"}
                        label={gettext("Shown")}
                        field={@var[:placement]}
                        opts={[
                          options: [
                            %{label: gettext("In the block"), value: "content"},
                            %{label: gettext("Configure modal"), value: "config"},
                            %{label: gettext("Hidden from editors"), value: "hidden"}
                          ]
                        ]}
                        publish={@publish}
                      />
                    </div>

                    <div class="variable-grid">
                      <.live_component
                        module={Input.Select}
                        id={"#{@var.id}-select-width"}
                        label={gettext("Width")}
                        field={@var[:width]}
                        opts={[options: @width_options]}
                        publish={@publish}
                      />

                      <Input.toggle field={@var[:new_row]} label={gettext("Start a new row")} />
                    </div>

                    <p class="variable-note">
                      {gettext("Width and row breaks are easier to judge on the layout canvas.")}
                    </p>
                  </section>
                </:section>
                <:section id="default" label={gettext("Default value")} icon="hero-pencil-square">
                  <section class="variable-section">
                    <h3>{gettext("Default value")}</h3>

                    <.render_value_inputs
                      edit
                      id={@id}
                      type={@type}
                      palette_colors={@palette_colors}
                      var={@var}
                      image={@image}
                      images={@images}
                      file={@file}
                      files={@files}
                      video={@video}
                      videos={@videos}
                      gallery={@gallery}
                      galleries={@galleries}
                      label={@label}
                      value_id={@value_id}
                      image_id={@image_id}
                      file_id={@file_id}
                      video_id={@video_id}
                      gallery_id={@gallery_id}
                      identifier={@identifier}
                      identifier_id={@identifier_id}
                      placeholder={@placeholder}
                      instructions={@instructions}
                      target={@myself}
                      publish={@publish}
                      on_change={@on_change}
                      component_id={@id}
                      var_key={@key}
                      upload_kind={@upload_kind}
                    />
                  </section>
                </:section>
                <:section
                  :if={@type in [:color, :link, :select]}
                  id="behavior"
                  label={type_settings_heading(@type)}
                  icon="hero-adjustments-horizontal"
                >
                  <section class="variable-section">
                    <h3>{type_settings_heading(@type)}</h3>

                    <%= case @type do %>
                      <% :color -> %>
                        <Input.toggle field={@var[:color_picker]} label={gettext("Allow picking custom colors")} />
                        <Input.toggle field={@var[:color_opacity]} label={gettext("Allow setting opacity")} />
                        <Input.number field={@var[:palette_id]} label={gettext("ID of palette to choose colors from")} />
                      <% :link -> %>
                        <.live_component
                          module={Input.MultiSelect}
                          id={"#{@var.id}-select-link-schemas"}
                          label={gettext("Allowed identifier schemas")}
                          field={@var[:link_identifier_schemas]}
                          opts={[options: @blueprint_schema_opts]}
                        />
                        <Input.toggle field={@var[:link_allow_custom_text]} label={gettext("Allow setting custom link text")} />
                      <% :select -> %>
                        <div
                          phx-hook="Brando.SortableEmbeds"
                          id={"#{@var.id}-variable-options"}
                          data-target={@myself}
                          data-sortable-id={"sortable-#{@var.id}-variable-options"}
                          data-sortable-handle=".sort-handle"
                          data-sortable-selector=".input-group"
                        >
                          <Primitives.field_base
                            field={@var[:options]}
                            label={gettext("Options")}
                            left_justify_meta
                            skip_presence
                          >
                            <.inputs_for :let={opt} field={@var[:options]}>
                              <%!-- `.input-group` is the hook's sortable selector and
                                `.sort-handle` the handle it looks for — there was
                                no handle, so options could not be reordered. --%>
                              <div class="input-group variable-option draggable drag-item">
                                <button
                                  type="button"
                                  class="sort-handle"
                                  aria-label={gettext("Reorder option")}
                                  title={gettext("Drag to reorder")}
                                >
                                  <span class="drag-grip" aria-hidden="true"></span>
                                </button>

                                <Input.text field={opt[:label]} label={gettext("Label")} />
                                <Input.text field={opt[:value]} label={gettext("Value")} />

                                <input type="hidden" name={"#{@var.name}[sort_option_ids][]"} value={opt.index} />
                                <button
                                  class="module-item-action module-danger"
                                  type="button"
                                  name={"#{@var.name}[drop_option_ids][]"}
                                  value={opt.index}
                                  aria-label={gettext("Delete option")}
                                  title={gettext("Delete")}
                                  phx-click={JS.dispatch("change")}
                                >
                                  <.icon name="hero-x-mark" />
                                </button>
                              </div>
                            </.inputs_for>

                            <button
                              type="button"
                              class="module-add-button"
                              phx-click={JS.push("add_select_var_option", value: %{var_key: @key}, target: @target)}
                            >
                              <.icon name="hero-plus" />
                              {gettext("Add option")}
                            </button>
                          </Primitives.field_base>
                        </div>
                    <% end %>
                  </section>
                </:section>
              </Content.modal_sections>
            </div>
          </div>
        <% else %>
          <div id={"#{@var.id}-value"}>
            <Input.input type={:hidden} field={@var[:id]} />
            <Input.input type={:hidden} field={@var[:_persistent_id]} value={@var.index} />
            <%!-- A var's *definition* — key, label, type, placement, layout —
                  is copied from the module and never edited here; this screen
                  only edits `value`. It has to round-trip anyway while the var
                  is unsaved, because `cast_assoc` matches by primary key and
                  rebuilds a pk-less record from whatever params arrive. Once
                  the var has an id, cast matches it and leaves every field the
                  params don't mention alone — so eight inputs per var stop
                  being emitted for the entries editors actually open.
                  Measured: 227 KB of a 4 313 KB mount at 115 blocks. --%>
            <%= if @unsaved_var? do %>
              <Input.input type={:hidden} field={@var[:key]} />
              <Input.input type={:hidden} field={@var[:label]} />
              <Input.input type={:hidden} field={@var[:type]} />
              <Input.input type={:hidden} field={@var[:placement]} />
              <Input.input type={:hidden} field={@var[:new_row]} />
              <Input.input type={:hidden} field={@var[:instructions]} />
              <Input.input type={:hidden} field={@var[:placeholder]} />
              <Input.input type={:hidden} field={@var[:width]} />
            <% end %>

            <.render_value_inputs
              type={@type}
              palette_colors={@palette_colors}
              var={@var}
              image={@image}
              images={@images}
              file={@file}
              files={@files}
              video={@video}
              videos={@videos}
              gallery={@gallery}
              galleries={@galleries}
              label={@label}
              value_id={@value_id}
              image_id={@image_id}
              file_id={@file_id}
              video_id={@video_id}
              gallery_id={@gallery_id}
              identifier={@identifier}
              identifier_id={@identifier_id}
              placeholder={@placeholder}
              instructions={@instructions}
              target={@myself}
              publish={@publish}
              on_change={@on_change}
              component_id={@id}
              var_key={@key}
              upload_kind={@upload_kind}
            />
          </div>
        <% end %>
      <% end %>
    </div>
    """
  end

  attr(:edit, :boolean, default: false)
  attr(:id, :any)
  attr(:type, :any)
  attr(:palette_colors, :string, default: nil)
  attr(:var, :any)
  attr(:identifier, :any)
  attr(:image, :any)
  attr(:images, :any)
  attr(:file, :any)
  attr(:files, :any)
  attr(:video, :any)
  attr(:videos, :any)
  attr(:gallery, :any)
  attr(:galleries, :any)
  attr(:label, :any)
  attr(:value_id, :any)
  attr(:image_id, :any)
  attr(:file_id, :any)
  attr(:video_id, :any)
  attr(:gallery_id, :any)
  attr(:identifier_id, :any)
  attr(:placeholder, :any)
  attr(:instructions, :any)
  attr(:target, :any)
  attr(:publish, :any)
  attr(:on_change, :any)
  attr(:component_id, :any, default: nil)
  attr(:var_key, :any, default: nil)
  attr(:upload_kind, :string, default: "entry_var")

  def render_value_inputs(%{type: nil} = assigns) do
    ~H"""
    <Input.hidden field={@var[:value]} />
    """
  end

  def render_value_inputs(%{type: :string} = assigns) do
    ~H"""
    <div class="brando-input">
      <Input.text field={@var[:value]} label={@label} placeholder={@placeholder} instructions={@instructions} />
    </div>
    """
  end

  def render_value_inputs(%{type: :html} = assigns) do
    ~H"""
    <div class="brando-input">
      <Input.rich_text field={@var[:value]} label={@label} placeholder={@placeholder} opts={[]} instructions={@instructions} />
    </div>
    """
  end

  def render_value_inputs(%{type: :text} = assigns) do
    ~H"""
    <div class="brando-input">
      <Input.textarea field={@var[:value]} label={@label} placeholder={@placeholder} instructions={@instructions} />
    </div>
    """
  end

  # The switch sits inside a control box the same height as a text input so a
  # toggle and a text field placed on the same row share a baseline. The
  # instructions are demoted to a tooltip — that, plus narrow widths, is what
  # lets several toggles stack where one used to sit.
  def render_value_inputs(%{type: :boolean} = assigns) do
    ~H"""
    <div class="brando-input">
      <Primitives.field_base field={@var[:value_boolean]} label={@label} left_justify_meta>
        <div class="boolean-control">
          <Primitives.label field={@var[:value_boolean]} class="switch small" skip_presence>
            <Input.input type={:checkbox} field={@var[:value_boolean]} />
            <div class="slider round"></div>
          </Primitives.label>
          <span :if={@instructions} class="boolean-instructions" title={@instructions}>
            <.icon name="hero-information-circle" />
          </span>
        </div>
      </Primitives.field_base>
    </div>
    """
  end

  def render_value_inputs(%{type: :datetime} = assigns) do
    ~H"""
    <div class="brando-input">
      <Input.datetime field={@var[:value]} label={@label} instructions={@instructions} />
    </div>
    """
  end

  def render_value_inputs(%{type: :color} = assigns) do
    changeset = assigns.var.source

    assigns =
      assigns
      |> assign(:color_opacity, get_field(changeset, :color_opacity))
      |> assign(:color_picker, get_field(changeset, :color_picker))
      |> assign(:palette_id, get_field(changeset, :palette_id))

    ~H"""
    <div class="brando-input">
      <Input.color
        palette_colors={@palette_colors}
        field={@var[:value]}
        label={@label}
        placeholder={@placeholder}
        instructions={@instructions}
        opts={[
          opacity: @color_opacity,
          picker: @color_picker,
          palette_id: @palette_id
        ]}
      />
      <%= unless @edit do %>
        <Input.input type={:hidden} field={@var[:color_picker]} />
        <Input.input type={:hidden} field={@var[:color_opacity]} />
        <Input.input type={:hidden} field={@var[:palette_id]} />
      <% end %>
    </div>
    """
  end

  def render_value_inputs(%{type: :select} = assigns) do
    ~H"""
    <div class="brando-input">
      <.live_component
        module={Input.Select}
        id={"#{@var.id}-select"}
        label={@label}
        field={@var[:value]}
        inline={true}
        opts={[options: @var[:options].value || []]}
        publish={@publish}
      />

      <.inputs_for :let={opt} field={@var[:options]}>
        <Input.hidden field={opt[:label]} id_prefix="hidden_opts" />
        <Input.hidden field={opt[:value]} id_prefix="hidden_opts" />
      </.inputs_for>
    </div>
    """
  end

  def render_value_inputs(%{type: :image} = assigns) do
    ~H"""
    <div class="brando-input">
      <Primitives.field_base field={@var[:image_id]} label={@label} instructions={@instructions} skip_presence>
        <div class="input-image">
          <MediaField.field
            id={"#{@var.id}-image-media"}
            type={:image}
            asset={@image}
            kind={@upload_kind}
            component_id={@component_id}
            var_key={@var_key}
            config_target={@var[:config_target].value || "default"}
            configure={show_modal("#var-#{@var.id}-image-config")}
            browse={JS.push("set_target", target: @target) |> toggle_drawer("#image-picker")}
            remove={JS.push("reset_image", target: @target)}
            label={@label}
          >
            <Input.input type={:hidden} field={@var[:image_id]} value={@image_id || ""} publish />
          </MediaField.field>
          <.image_modal
            field={@var}
            image={@image}
            target={@target}
            component_id={@component_id}
            var_key={@var_key}
            upload_kind={@upload_kind}
          />
        </div>
      </Primitives.field_base>
      <div :if={@edit} class="brando-input">
        <Input.text
          field={@var[:config_target]}
          label={gettext("Config target")}
          instructions={gettext("i.e: `image:Elixir.MyApp.Schema:function:fn_name`")}
          monospace
        />
      </div>
    </div>
    """
  end

  def render_value_inputs(%{type: :file} = assigns) do
    ~H"""
    <div class="brando-input">
      <Primitives.field_base field={@var[:file_id]} label={@label} instructions={@instructions} skip_presence>
        <div class="input-file">
          <MediaField.field
            id={"#{@var.id}-file-media"}
            type={:file}
            asset={@file}
            kind={@upload_kind}
            component_id={@component_id}
            var_key={@var_key}
            config_target={@var[:config_target].value || "default"}
            configure={show_modal("#var-#{@var.id}-file-config")}
            browse={JS.push("set_file_target", target: @target) |> toggle_drawer("#file-picker")}
            remove={JS.push("reset_file", target: @target)}
            label={@label}
          >
            <Input.input type={:hidden} field={@var[:file_id]} value={@file_id || ""} publish />
          </MediaField.field>
          <.file_modal
            field={@var}
            file={@file}
            target={@target}
            component_id={@component_id}
            var_key={@var_key}
            upload_kind={@upload_kind}
          />
        </div>
      </Primitives.field_base>
      <div :if={@edit} class="brando-input">
        <Input.text
          field={@var[:config_target]}
          label={gettext("Config target")}
          instructions={gettext("i.e: `file:Elixir.MyApp.Schema:function:fn_name`")}
          monospace
        />
      </div>
    </div>
    """
  end

  def render_value_inputs(%{type: :video} = assigns) do
    ~H"""
    <div class="brando-input">
      <Primitives.field_base field={@var[:video_id]} label={@label} instructions={@instructions} skip_presence>
        <MediaField.field
          id={"#{@var.id}-video-media"}
          type={:video}
          asset={@video}
          kind={@upload_kind}
          component_id={@component_id}
          var_key={@var[:key].value}
          config_target={@var[:config_target].value || "default"}
          label={@label}
          configure={show_modal("#var-#{@var.id}-video-config")}
          browse={JS.push("set_video_target", target: @target) |> toggle_drawer("#video-picker")}
          remove={JS.push("reset_video", target: @target)}
        >
          <Input.input type={:hidden} field={@var[:video_id]} value={@video_id || ""} publish />
        </MediaField.field>
        <.video_modal
          field={@var}
          video={@video}
          target={@target}
          component_id={@component_id}
          var_key={@var_key}
          upload_kind={@upload_kind}
        />
      </Primitives.field_base>
      <div :if={@edit} class="brando-input">
        <Input.text
          field={@var[:config_target]}
          label={gettext("Config target")}
          instructions={gettext("i.e: `video:Elixir.MyApp.Schema:function:fn_name`")}
          monospace
        />
      </div>
    </div>
    """
  end

  def render_value_inputs(%{type: :gallery} = assigns) do
    assigns = assign(assigns, :gallery_objects, gallery_objects(assigns.gallery))

    ~H"""
    <div class="brando-input">
      <Primitives.field_base field={@var[:gallery_id]} label={@label} instructions={@instructions} skip_presence>
        <div
          id={"#{@var.id}-gallery-media"}
          class="media-gallery"
          phx-hook="Brando.UploadTrigger"
          data-kind={"#{@upload_kind}_gallery"}
          data-component-id={@component_id}
          data-var-key={@var[:key].value}
          data-upload-label={@label}
          data-asset-type="image"
          data-config-target={@var[:gallery_image_config_target].value || "default"}
          data-video-config-target={@var[:gallery_video_config_target].value || "default"}
          data-allowed-types={Enum.join(@var[:gallery_allowed_types].value || [:image, :video], ",")}
          data-folder-browser="true"
          data-click-mode="trigger"
          data-accept="image/*,video/*"
        >
          <input type="file" class="file-input" multiple accept="image/*,video/*" />
          <Input.input type={:hidden} field={@var[:gallery_id]} value={@gallery_id || ""} publish />
          <div class="media-field-copy">
            <span class="media-field-name">{gettext("Gallery")}</span>
            <span class="media-field-meta">{ngettext("%{count} item", "%{count} items", length(@gallery_objects))} · {gettext(
              "Drop media here to add"
            )}</span>
          </div>
          <div class="media-field-actions">
            <button type="button" class="media-button primary upload-trigger"><.icon name="hero-arrow-up-tray" />{gettext(
              "Upload media"
            )}</button>
            <button type="button" class="media-button" phx-click={show_modal("#var-#{@var.id}-gallery-config")}><.icon name="hero-adjustments-horizontal" />{gettext(
              "Configure"
            )}</button>
          </div>
          <div
            id={"#{@var.id}-gallery-progress"}
            class="media-field-progress"
            phx-update="ignore"
            role="status"
            aria-live="polite"
          >
          </div>
          <div class="media-field-drop" aria-hidden="true"><span>{gettext("Add to gallery")}</span></div>
        </div>
        <.gallery_modal
          field={@var}
          gallery={@gallery}
          target={@target}
          component_id={@component_id}
          var_key={@var_key}
          upload_kind={@upload_kind}
        />
      </Primitives.field_base>
      <div :if={@edit} class="brando-input">
        <.live_component
          module={Input.MultiSelect}
          id={"#{@var.id}-gallery-allowed-types"}
          field={@var[:gallery_allowed_types]}
          label={gettext("Allowed media")}
          opts={[options: [%{label: gettext("Images"), value: :image}, %{label: gettext("Videos"), value: :video}]]}
        />
        <Input.text field={@var[:gallery_image_config_target]} label={gettext("Image config target")} monospace />
        <Input.text field={@var[:gallery_video_config_target]} label={gettext("Video config target")} monospace />
      </div>
    </div>
    """
  end

  def render_value_inputs(%{type: :link} = assigns) do
    ~H"""
    <div class="brando-input">
      <Primitives.field_base field={@var[:identifier_id]} label={@label} instructions={@instructions} skip_presence>
        <div class="input-link">
          <Input.hidden field={@var[:identifier_id]} value={@identifier_id || ""} />
          <.link_preview
            var={@var}
            field={@var[:identifier_id]}
            click={show_modal("#var-#{@var.id}-link-config")}
            identifier={@identifier}
          />
          <.link_modal
            field={@var}
            identifier={@identifier}
            target={@target}
            on_change={@on_change || fn params -> send_update(@target, params) end}
          />
        </div>
      </Primitives.field_base>
    </div>
    """
  end

  def link_preview(assigns) do
    var = assigns.var
    changeset = var.source
    value = get_field(changeset, :value)
    link_type = get_field(changeset, :link_type) || :url
    link_text = get_field(changeset, :link_text)
    external? = link_type == :url && is_binary(value) && String.starts_with?(value, "http")

    assigns =
      assigns
      |> assign(:link_type, link_type)
      |> assign(:link_text, link_text)
      |> assign(:value, split_url_with_wbr(value))
      |> assign(:external?, external?)

    ~H"""
    <button type="button" class="link-preview" phx-click={@click}>
      <div class="icon">
        <.icon :if={@link_type == :url && !@external?} name="hero-link" />
        <.icon :if={@link_type == :url && @external?} name="hero-globe-alt" />
        <.icon :if={@link_type == :identifier} name="hero-link" />
      </div>
      <div class="info">
        <%= if @link_type == :url do %>
          <%= if @link_text do %>
            <div class="link-text">{@link_text}</div>
          <% end %>
          <%= if @value not in [nil, ""] do %>
            <dl>
              <dt>{gettext("URL")}=</dt>
              <dd>{@value}</dd>
            </dl>
          <% else %>
            <dl>
              <dt>{gettext("No link set")}</dt>
            </dl>
          <% end %>
        <% else %>
          <.link_identifier identifier={@identifier} link_text={@link_text} />
        <% end %>
      </div>
    </button>
    """
  end

  defp split_url_with_wbr(nil) do
    ""
  end

  # Returns a safe tuple: each URL segment is escaped, only the <wbr /> tags
  # we add here render as markup.
  defp split_url_with_wbr(url) do
    url
    |> String.split("/")
    |> Enum.map_join("/", fn segment ->
      escaped = segment |> HTML.html_escape() |> HTML.safe_to_string()
      "#{escaped}<wbr />"
    end)
    |> HTML.raw()
  end

  attr(:link_text, :string, default: nil)
  attr(:identifier, :any, default: nil)

  def link_identifier(assigns) do
    identifier = assigns.identifier
    translated_type = identifier && Brando.Blueprint.get_singular(identifier.schema)
    assigns = assign(assigns, :translated_type, translated_type)

    ~H"""
    <div class="link-text" phx-no-format>
      <%= if @link_text do %>
        <%= if @identifier do %>
          <.status_circle status={@identifier.status} />
          <%= if @identifier.language do %>
            [<%= String.upcase(to_string(@identifier.language)) %>]
          <% end %>
          <%= @link_text %>
        <% end %>
      <% else %>
        <%= if @identifier do %>
          <.status_circle status={@identifier.status} />
          [<%= @translated_type %><%= if @identifier.language do %>/<%= String.upcase(to_string(@identifier.language)) %><% end %>]
          <%= @identifier.title %>
        <% end %>
      <% end %>
    </div>
    <dl>
      <dt>{gettext("URL")}=</dt>
      <dd :if={@identifier}>{@identifier.url}</dd>
      <dd :if={!@identifier}>{gettext("<No URL>")}</dd>
    </dl>
    """
  end

  def link_modal(assigns) do
    field = assigns.field
    changeset = field.source
    link_type = get_field(changeset, :link_type) || :url
    allow_text? = get_field(changeset, :link_allow_custom_text)
    wanted_schemas = get_field(changeset, :link_identifier_schemas, [])
    var_key = get_field(changeset, :key)
    var_type = get_field(changeset, :type)

    assigns =
      assigns
      |> assign(:link_type, link_type)
      |> assign(:allow_text?, allow_text?)
      |> assign(:wanted_schemas, wanted_schemas)
      |> assign(:var_key, var_key)
      |> assign(:var_type, var_type)

    ~H"""
    <Content.modal
      title={gettext("Edit link")}
      subtitle={@field[:label].value}
      icon="hero-link"
      layout="picker"
      id={"var-#{@field.id}-link-config"}
    >
      <div class="link-var-config">
        <div class="link-picker-modes">
          <Input.radios
            field={%{@field[:link_type] | value: @link_type}}
            label={gettext("Type")}
            opts={[
              options: [
                %{label: gettext("URL"), value: :url, icon: "hero-globe-alt"},
                %{label: gettext("Content"), value: :identifier, icon: "hero-document-text"}
              ]
            ]}
          />
        </div>
        <div :if={@link_type == :url} class="link-picker-url">
          <Input.text
            field={@field[:value]}
            label={gettext("URL")}
            instructions={gettext("i.e: `https://example.com`")}
            monospace
          />
          <Input.text :if={@allow_text?} field={@field[:link_text]} label={gettext("Link text")} />
          <Input.toggle field={@field[:link_target_blank]} label={gettext("Open link in new window/tab")} />
        </div>
        <.live_component
          :if={@link_type == :identifier}
          module={Content.SelectIdentifier}
          id={"#{@field.id}-identifier-select"}
          field={@field[:identifier_id]}
          var_key={@var_key}
          var_type={@var_type}
          wanted_schemas={@wanted_schemas}
          layout={:workspace}
          require_url
          on_change={@on_change}
          target={@target}
        >
          <:details>
            <Input.text :if={@allow_text?} field={@field[:link_text]} label={gettext("Link text")} />
            <Input.toggle field={@field[:link_target_blank]} label={gettext("Open link in new window/tab")} />
          </:details>
        </.live_component>
      </div>
      <:footer>
        <span :if={@link_type == :identifier && @identifier} class="modal-footer-selection">
          <.icon name="hero-link" />
          <span>{@identifier.title}</span>
          <small :if={@identifier.language}>{String.upcase(to_string(@identifier.language))}</small>
        </span>
        <button type="button" class="primary" phx-click={hide_modal("#var-#{@field.id}-link-config")}>{gettext("Done")}</button>
      </:footer>
    </Content.modal>
    """
  end

  def image_modal(assigns) do
    ~H"""
    <Content.modal title={gettext("Image")} id={"var-#{@field.id}-image-config"}>
      <div class="media-var-config">
        <div class="panel">
          <MediaField.field
            id={"#{@field.id}-var-uploader"}
            type={:image}
            asset={@image}
            kind={@upload_kind}
            component_id={@component_id}
            var_key={@var_key}
            config_target={@field[:config_target].value || "default"}
            browse={JS.push("set_target", target: @target) |> toggle_drawer("#image-picker")}
            remove={JS.push("reset_image", target: @target)}
          />
        </div>
      </div>
      <:footer>
        <button type="button" class="primary" phx-click={hide_modal("#var-#{@field.id}-image-config")}>{gettext("Done")}</button>
      </:footer>
    </Content.modal>
    """
  end

  def file_modal(assigns) do
    ~H"""
    <Content.modal title={gettext("File")} id={"var-#{@field.id}-file-config"}>
      <div class="media-var-config">
        <div class="panel">
          <MediaField.field
            id={"#{@field.id}-var-uploader"}
            type={:file}
            asset={@file}
            kind={@upload_kind}
            component_id={@component_id}
            var_key={@var_key}
            config_target={@field[:config_target].value || "default"}
            browse={JS.push("set_file_target", target: @target) |> toggle_drawer("#file-picker")}
            remove={JS.push("reset_file", target: @target)}
          />
        </div>
      </div>
      <:footer>
        <button type="button" class="primary" phx-click={hide_modal("#var-#{@field.id}-file-config")}>{gettext("Done")}</button>
      </:footer>
    </Content.modal>
    """
  end

  def video_modal(assigns) do
    ~H"""
    <Content.modal title={gettext("Video")} icon="hero-film" id={"var-#{@field.id}-video-config"}>
      <MediaField.field
        id={"#{@field.id}-var-uploader"}
        type={:video}
        asset={@video}
        kind={@upload_kind}
        component_id={@component_id}
        var_key={@var_key}
        config_target={@field[:config_target].value || "default"}
        browse={JS.push("set_video_target", target: @target) |> toggle_drawer("#video-picker")}
        remove={JS.push("reset_video", target: @target)}
      />
      <:footer>
        <button type="button" class="primary" phx-click={hide_modal("#var-#{@field.id}-video-config")}>{gettext("Done")}</button>
      </:footer>
    </Content.modal>
    """
  end

  def gallery_modal(assigns) do
    objects = gallery_objects(assigns.gallery)
    allowed_types = assigns.field[:gallery_allowed_types].value || [:image, :video]

    assigns =
      assigns
      |> assign(:objects, objects)
      |> assign(:allowed_types, allowed_types)

    ~H"""
    <Content.modal
      title={gettext("Gallery")}
      icon="hero-squares-2x2"
      subtitle={@field[:label].value}
      id={"var-#{@field.id}-gallery-config"}
      wide
    >
      <div
        id={"#{@field.id}-gallery-uploader"}
        class="gallery-input media-gallery media-gallery--variable"
        phx-hook="Brando.UploadTrigger"
        data-kind={"#{@upload_kind}_gallery"}
        data-component-id={@component_id}
        data-var-key={@var_key}
        data-upload-label={@field[:label].value}
        data-asset-type="image"
        data-config-target={@field[:gallery_image_config_target].value || "default"}
        data-video-config-target={@field[:gallery_video_config_target].value || "default"}
        data-allowed-types={Enum.join(@allowed_types, ",")}
        data-folder-browser="true"
        data-click-mode="trigger"
        data-accept="image/*,video/*"
      >
        <input type="file" class="file-input" multiple />
        <div
          id={"#{@field.id}-gallery-modal-progress"}
          class="media-field-progress"
          phx-update="ignore"
          role="status"
          aria-live="polite"
        >
        </div>
        <div class="media-field-drop" aria-hidden="true">{gettext("Drop to add to this gallery")}</div>
        <div class="gallery-workspace-toolbar">
          <div class="gallery-workspace-context">
            <h3>{ngettext("%{count} item", "%{count} items", length(@objects))}</h3><p>
              {gettext("Drop images or videos here to add them.")}
            </p>
          </div>
          <div class="actions">
            <button type="button" class="media-button primary upload-trigger">{gettext("Upload media")}</button>
            <button
              :if={:image in @allowed_types}
              type="button"
              class="media-button"
              phx-click={JS.push("set_gallery_image_target", target: @target) |> toggle_drawer("#image-picker")}
            >
              {gettext("Browse images")}
            </button>
            <button
              :if={:video in @allowed_types}
              type="button"
              class="media-button"
              phx-click={JS.push("set_gallery_video_target", target: @target) |> toggle_drawer("#video-picker")}
            >
              {gettext("Browse videos")}
            </button>
          </div>
        </div>
        <div :if={@objects == []} class="gallery-workspace-empty">
          <.icon name="hero-photo" />
          <h3>{gettext("Build your gallery")}</h3>
          <p>{gettext("Upload media or choose from your library.")}</p>
        </div>
        <div :if={@objects != []} class="gallery-workspace-items" role="list" aria-label={gettext("Gallery items")}>
          <div
            :for={{object, index} <- Enum.with_index(@objects)}
            class="gallery-object gallery-workspace-item"
            role="listitem"
          >
            <span class="gallery-item-position">{String.pad_leading(to_string(index + 1), 2, "0")}</span>
            <div class="gallery-item-preview">
              <img :if={object.image} src={Utils.img_url(object.image, :small, prefix: Utils.media_url())} alt="" />
              <%= if object.video do %>
                <%= cond do %>
                  <% match?(%Brando.Images.Image{}, object.video.thumbnail) -> %>
                    <Content.image image={object.video.thumbnail} size={:smallest} />
                  <% match?(%Brando.Files.File{}, object.video.file) -> %>
                    <.icon name="hero-film" />
                    <video
                      class="gallery-video-preview"
                      muted
                      preload="metadata"
                      src={Utils.media_url(object.video.file) <> "#t=0.1"}
                      aria-label={gettext("Video preview")}
                    />
                  <% true -> %>
                    <.icon name="hero-film" />
                <% end %>
              <% end %>
            </div>
            <div class="gallery-item-info">
              <span class="gallery-item-name">{if object.image,
                do: Path.basename(object.image.path),
                else: object.video.title || gettext("Untitled video")}</span>
              <span class="gallery-item-meta">
                <%= if object.image do %>
                  {gettext("Image")}<span>·</span>{object.image.width} × {object.image.height}
                <% else %>
                  {gettext("Video")}
                <% end %>
              </span>
            </div>
            <button
              type="button"
              class="gallery-item-remove"
              aria-label={
                gettext("Remove %{name}",
                  name: if(object.image, do: Path.basename(object.image.path), else: object.video.title || gettext("video"))
                )
              }
              phx-click={JS.push("remove_gallery_object", target: @target, value: %{id: object.id})}
            >
              <.icon name="hero-x-mark" /><span>{gettext("Remove")}</span>
            </button>
          </div>
        </div>
      </div>
      <:footer>
        <button
          :if={@gallery}
          type="button"
          class="gallery-reset-button"
          phx-click={JS.push("reset_gallery", target: @target)}
        >{gettext("Reset gallery")}</button>
        <button type="button" class="primary" phx-click={hide_modal("#var-#{@field.id}-gallery-config")}>{gettext("Done")}</button>
      </:footer>
    </Content.modal>
    """
  end

  defp gallery_objects(nil), do: []
  defp gallery_objects(%{gallery_objects: %Ecto.Association.NotLoaded{}}), do: []
  defp gallery_objects(%{gallery_objects: objects}) when is_list(objects), do: objects
  defp gallery_objects(_), do: []

  def handle_event("focus", _, socket) do
    {:noreply, socket}
  end

  def handle_event("set_target", _, %{assigns: %{myself: myself}} = socket) do
    config_target = socket.assigns.var[:config_target].value || "default"

    send_update(
      BrandoAdmin.Components.ImagePicker,
      id: "image-picker",
      config_target: config_target,
      event_target: myself,
      multi: false,
      # "Selection means current editing state" (uploads skill) — reopening the
      # picker must mark what the var currently holds, saved or not. The sibling
      # `set_file_target` below already did this; images did not.
      selected_images: List.wrap(socket.assigns.image_id)
    )

    {:noreply, socket}
  end

  def handle_event("set_file_target", _, %{assigns: %{myself: myself}} = socket) do
    config_target = socket.assigns.var[:config_target].value || "default"

    send_update(
      BrandoAdmin.Components.FilePicker,
      id: "file-picker",
      config_target: config_target,
      event_target: myself,
      multi: false,
      selected_files: if(socket.assigns.file_id, do: [socket.assigns.file_id], else: [])
    )

    {:noreply, socket}
  end

  def handle_event("set_video_target", _, %{assigns: %{myself: myself}} = socket) do
    config_target = socket.assigns.var[:config_target].value || "default"

    send_update(BrandoAdmin.Components.VideoPicker,
      id: "video-picker",
      config_target: config_target,
      event_target: myself,
      multi: false,
      current_user: current_user(socket.assigns.current_user_id),
      selected_videos: if(socket.assigns.video_id, do: [socket.assigns.video_id], else: [])
    )

    {:noreply, socket}
  end

  def handle_event("set_gallery_image_target", _, %{assigns: %{myself: myself}} = socket) do
    gallery = socket.assigns.gallery

    send_update(BrandoAdmin.Components.ImagePicker,
      id: "image-picker",
      config_target: socket.assigns.var[:gallery_image_config_target].value || "default",
      event_target: myself,
      multi: true,
      selected_images: gallery_media_ids(gallery, :image_id)
    )

    {:noreply, socket}
  end

  def handle_event("set_gallery_video_target", _, %{assigns: %{myself: myself}} = socket) do
    gallery = socket.assigns.gallery

    send_update(BrandoAdmin.Components.VideoPicker,
      id: "video-picker",
      config_target: socket.assigns.var[:gallery_video_config_target].value || "default",
      event_target: myself,
      multi: true,
      current_user: current_user(socket.assigns.current_user_id),
      selected_videos: gallery_media_ids(gallery, :video_id)
    )

    {:noreply, socket}
  end

  def handle_event("reset_image", _, socket) do
    socket
    |> assign(:image, nil)
    |> assign(:image_id, nil)
    |> on_change(%{image: nil, image_id: nil})
    |> then(&{:noreply, &1})
  end

  def handle_event("reset_file", _, socket) do
    socket
    |> assign(:file, nil)
    |> assign(:file_id, nil)
    |> on_change(%{file: nil, file_id: nil})
    |> then(&{:noreply, &1})
  end

  def handle_event("reset_video", _, socket) do
    socket
    |> assign(:video, nil)
    |> assign(:video_id, nil)
    |> on_change(%{video: nil, video_id: nil})
    |> then(&{:noreply, &1})
  end

  def handle_event("reset_gallery", _, socket) do
    socket
    |> assign(:gallery, nil)
    |> assign(:gallery_id, nil)
    |> on_change(%{gallery: nil, gallery_id: nil})
    |> then(&{:noreply, &1})
  end

  def handle_event("select_image", %{"id" => image_id}, %{assigns: %{type: :image}} = socket) do
    image = Brando.Images.get_image!(image_id)

    socket
    |> assign(:image_id, image_id)
    |> assign(:image, image)
    |> on_change(%{image: image, image_id: image_id})
    |> then(&{:noreply, &1})
  end

  def handle_event("select_file", %{"id" => file_id}, socket) do
    file = Brando.Files.get_file!(file_id)

    socket
    |> assign(:file_id, file_id)
    |> assign(:file, file)
    |> on_change(%{file: file, file_id: file_id})
    |> then(&{:noreply, &1})
  end

  def handle_event("select_video", %{"id" => video_id}, %{assigns: %{type: :video}} = socket) do
    {:ok, video} =
      Brando.Videos.get_video(%{matches: %{id: video_id}, preload: [:thumbnail, :file]})

    socket
    |> assign(:video_id, video.id)
    |> assign(:video, video)
    |> on_change(%{video: video, video_id: video.id})
    |> then(&{:noreply, &1})
  end

  def handle_event("select_image", %{"id" => image_id}, %{assigns: %{type: :gallery}} = socket) do
    {:noreply, toggle_gallery_media(socket, :image, image_id)}
  end

  def handle_event("select_video", %{"id" => video_id}, %{assigns: %{type: :gallery}} = socket) do
    {:noreply, toggle_gallery_media(socket, :video, video_id)}
  end

  def handle_event("remove_gallery_object", %{"id" => object_id}, socket) do
    {:noreply, remove_gallery_object(socket, object_id)}
  end

  def handle_event("toggle_visible", _, socket) do
    {:noreply, update(socket, :visible, &(!&1))}
  end

  defp toggle_gallery_media(socket, media_type, media_id) do
    media_id = normalize_id(media_id)
    id_field = if media_type == :image, do: :image_id, else: :video_id
    objects = gallery_objects(socket.assigns.gallery)

    updated_objects =
      if Enum.any?(objects, &(Map.get(&1, id_field) == media_id)) do
        Enum.reject(objects, &(Map.get(&1, id_field) == media_id))
      else
        objects ++ [%{id_field => media_id, creator_id: socket.assigns.current_user_id}]
      end

    persist_gallery(socket, updated_objects)
  end

  defp remove_gallery_object(socket, object_id) do
    object_id = normalize_id(object_id)
    objects = Enum.reject(gallery_objects(socket.assigns.gallery), &(&1.id == object_id))
    persist_gallery(socket, objects)
  end

  defp persist_gallery(socket, objects) do
    gallery = socket.assigns.gallery
    current_user_id = normalize_id(socket.assigns.current_user_id)

    params = %{
      config_target:
        (gallery && gallery.config_target) ||
          Brando.Assets.ConfigTarget.serialize({"gallery", Brando.Content.Var, :gallery}),
      gallery_objects:
        objects
        |> Enum.map(&Brando.Galleries.slim_gallery_object/1)
        |> Enum.with_index()
        |> Enum.map(fn {object, sequence} ->
          object
          |> Map.put(:sequence, sequence)
          |> Map.update(:creator_id, current_user_id, &normalize_id(&1 || current_user_id))
        end)
    }

    result =
      (gallery || %Brando.Galleries.Gallery{})
      |> Brando.Galleries.Gallery.changeset(params, current_user_id)
      |> then(fn changeset ->
        if gallery, do: Repo.update(changeset), else: Repo.insert(changeset)
      end)

    case result do
      {:ok, saved_gallery} ->
        saved_gallery =
          Repo.preload(
            saved_gallery,
            [gallery_objects: [:image, video: [:thumbnail, :file]]],
            force: true
          )

        Brando.Content.Blocks.render_entries_with_gallery_id(saved_gallery.id)
        notify_gallery_pickers(saved_gallery)

        socket
        |> assign(:gallery, saved_gallery)
        |> assign(:gallery_id, saved_gallery.id)
        |> on_change(%{gallery: saved_gallery, gallery_id: saved_gallery.id})

      {:error, changeset} ->
        put_flash(socket, :error, gettext("Could not update gallery: %{error}", error: inspect(changeset.errors)))
    end
  end

  defp notify_gallery_pickers(gallery) do
    send_update(BrandoAdmin.Components.ImagePicker,
      id: "image-picker",
      selected_images: gallery_media_ids(gallery, :image_id)
    )

    send_update(BrandoAdmin.Components.VideoPicker,
      id: "video-picker",
      selected_videos: gallery_media_ids(gallery, :video_id)
    )
  end

  defp gallery_media_ids(gallery, id_field) do
    gallery
    |> gallery_objects()
    |> Enum.map(&Map.get(&1, id_field))
    |> Enum.reject(&is_nil/1)
  end

  defp normalize_id(id) when is_integer(id), do: id
  defp normalize_id(id) when is_binary(id), do: String.to_integer(id)

  defp current_user(nil), do: nil
  defp current_user(user_id), do: Repo.get(Brando.Users.User, user_id)

  # Entry-level vars have no owning block component (`on_change` unset) — their
  # FKs live in the parent entry form's changeset. Sync the picked/reset value
  # by driving the hidden FK input through the `b:validate` client contract
  # (set value + dispatch input): a silent local assign would strand resets
  # (the hidden input falls back to the stale changeset value on the next
  # patch) and defer picks until an unrelated validate happens to fire.
  def on_change(%{assigns: %{on_change: nil}} = socket, data) do
    case var_fk_change(data) do
      {field, value} ->
        push_event(socket, "b:validate", %{
          target: socket.assigns.var[field].name,
          value: value || ""
        })

      nil ->
        socket
    end
  end

  def on_change(%{assigns: %{on_change: on_change}} = socket, data) do
    var_key = socket.assigns.key
    var_type = socket.assigns.type

    params = %{
      event: "update_block_var",
      var_key: var_key,
      var_type: var_type,
      data: data
    }

    on_change.(params)
    socket
  end

  defp var_fk_change(%{image_id: image_id}), do: {:image_id, image_id}
  defp var_fk_change(%{file_id: file_id}), do: {:file_id, file_id}
  defp var_fk_change(%{video_id: video_id}), do: {:video_id, video_id}
  defp var_fk_change(%{gallery_id: gallery_id}), do: {:gallery_id, gallery_id}
  defp var_fk_change(%{identifier: identifier}), do: {:identifier_id, identifier && identifier.id}
  defp var_fk_change(_), do: nil
end
