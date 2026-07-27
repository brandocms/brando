defmodule BrandoAdmin.Components.Form.Input.RenderVar do
  @moduledoc false
  use BrandoAdmin, :live_component
  use Gettext, backend: Brando.Gettext

  import BrandoAdmin.Components.Content.List.Row, only: [status_circle: 1]
  import Ecto.Changeset

  alias Brando.Utils
  alias BrandoAdmin.Components.Content
  alias BrandoAdmin.Components.Form
  alias BrandoAdmin.Components.Form.Input

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
        case assigns.asset_type do
          :image ->
            socket
            |> assign(:image, assigns.asset)
            |> assign(:image_id, assigns.asset.id)
            |> on_change(%{image: assigns.asset, image_id: assigns.asset.id})

          :file ->
            socket
            |> assign(:file, assigns.asset)
            |> assign(:file_id, assigns.asset.id)
            |> on_change(%{file: assigns.asset, file_id: assigns.asset.id})

          :video ->
            socket
            |> assign(:video, assigns.asset)
            |> assign(:video_id, assigns.asset.id)
            |> on_change(%{video: assigns.asset, video_id: assigns.asset.id})
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

    upload_results ++ var_change_results ++ video_created_results ++ var_results
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
    |> assign(:upload_kind, if(Map.get(assigns, :on_change), do: "block_var", else: "entry_var"))
    |> assign(:target, Map.get(assigns, :target, nil))
    |> assign(:should_render?, should_render?(Map.get(assigns, :render, :all), placement))
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
    |> assign_new(:value_id, fn -> value end)
    |> assign_new(:image_id, fn -> if type == :image, do: value end)
    |> assign_new(:file_id, fn -> if type == :file, do: value end)
    |> assign_new(:video_id, fn -> if type == :video, do: value end)
    |> assign_new(:gallery_id, fn -> if type == :gallery, do: value end)
    |> assign(:identifier_id, get_field(changeset, :identifier_id))
    |> assign(:instructions, get_field(changeset, :instructions))
    |> assign(:placeholder, get_field(changeset, :placeholder))
    |> assign(:var, var)
  end

  defp type_settings_heading(:color), do: gettext("Color settings")
  defp type_settings_heading(:link), do: gettext("Link settings")
  defp type_settings_heading(:select), do: gettext("Choices")
  defp type_settings_heading(_type), do: gettext("Settings")

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
                        %{label: "Boolean", value: "boolean"},
                        %{label: "Color", value: "color"},
                        %{label: "Datetime", value: "datetime"},
                        %{label: "File", value: "file"},
                        %{label: "Gallery", value: "gallery"},
                        %{label: "Html", value: "html"},
                        %{label: "Image", value: "image"},
                        %{label: "Link", value: "link"},
                        %{label: "String", value: "string"},
                        %{label: "Select", value: "select"},
                        %{label: "Text", value: "text"},
                        %{label: "Video", value: "video"}
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

              <section class="variable-section">
                <h3>{gettext("Default value")}</h3>

                <.render_value_inputs
                  edit
                  id={@id}
                  type={@type}
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

              <section :if={@type in [:color, :link, :select]} class="variable-section">
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
                      <Form.field_base field={@var[:options]} label={gettext("Options")} left_justify_meta skip_presence>
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
                      </Form.field_base>
                    </div>
                  <% _ -> %>
                <% end %>
              </section>
            </div>
          </div>
        <% else %>
          <div id={"#{@var.id}-value"}>
            <Input.input type={:hidden} field={@var[:id]} />
            <Input.input type={:hidden} field={@var[:_persistent_id]} value={@var.index} />
            <Input.input type={:hidden} field={@var[:key]} />
            <Input.input type={:hidden} field={@var[:label]} />
            <Input.input type={:hidden} field={@var[:type]} />
            <Input.input type={:hidden} field={@var[:placement]} />
            <Input.input type={:hidden} field={@var[:new_row]} />
            <Input.input type={:hidden} field={@var[:instructions]} />
            <Input.input type={:hidden} field={@var[:placeholder]} />
            <Input.input type={:hidden} field={@var[:width]} />

            <.render_value_inputs
              type={@type}
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
      <Form.field_base field={@var[:value_boolean]} label={@label} left_justify_meta>
        <div class="boolean-control">
          <Form.label field={@var[:value_boolean]} class="switch small" skip_presence>
            <Input.input type={:checkbox} field={@var[:value_boolean]} />
            <div class="slider round"></div>
          </Form.label>
          <span :if={@instructions} class="boolean-instructions" title={@instructions}>
            <.icon name="hero-information-circle" />
          </span>
        </div>
      </Form.field_base>
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
      <Form.field_base field={@var[:image_id]} label={@label} instructions={@instructions} skip_presence>
        <div class="input-image">
          <Input.Image.image_preview
            image={@image}
            field={@var[:image_id]}
            value={@image_id || ""}
            relation_field={@var[:image_id]}
            click={show_modal("#var-#{@var.id}-image-config")}
            file_name={@image && @image.path && Path.basename(@image.path)}
            publish
          />
          <.image_modal
            field={@var}
            image={@image}
            target={@target}
            component_id={@component_id}
            var_key={@var_key}
            upload_kind={@upload_kind}
          />
        </div>
      </Form.field_base>
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
      <Form.field_base field={@var[:file_id]} label={@label} instructions={@instructions} skip_presence>
        <div class="input-file">
          <Input.File.file_preview
            publish
            file={@file}
            field={@var[:file_id]}
            value={@file_id || ""}
            relation_field={@var[:file_id]}
            click={show_modal("#var-#{@var.id}-file-config")}
            file_name={@file && @file.filename && Path.basename(@file.filename)}
          />
          <.file_modal
            field={@var}
            file={@file}
            target={@target}
            component_id={@component_id}
            var_key={@var_key}
            upload_kind={@upload_kind}
          />
        </div>
      </Form.field_base>
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
      <Form.field_base field={@var[:video_id]} label={@label} instructions={@instructions} skip_presence>
        <Input.hidden field={@var[:video_id]} value={@video_id || ""} />
        <button
          type="button"
          class="file-card"
          phx-click={show_modal("#var-#{@var.id}-video-config")}
        >
          <div class="file-card__icon"><.icon name="hero-play-circle" /></div>
          <div class="file-card__meta">
            <div class="file-card__name">
              {(@video && (@video.title || @video.remote_id || @video.source_url)) || gettext("Select video")}
            </div>
            <div :if={@video} class="file-card__sub">{@video.type}</div>
          </div>
        </button>
        <.video_modal field={@var} video={@video} target={@target} />
      </Form.field_base>
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
      <Form.field_base field={@var[:gallery_id]} label={@label} instructions={@instructions} skip_presence>
        <Input.hidden field={@var[:gallery_id]} value={@gallery_id || ""} />
        <button
          type="button"
          class="file-card"
          phx-click={show_modal("#var-#{@var.id}-gallery-config")}
        >
          <div class="file-card__icon"><.icon name="hero-photo" /></div>
          <div class="file-card__meta">
            <div class="file-card__name">{gettext("Gallery")}</div>
            <div class="file-card__sub">
              {ngettext("%{count} asset", "%{count} assets", length(@gallery_objects))}
            </div>
          </div>
        </button>
        <.gallery_modal field={@var} gallery={@gallery} target={@target} />
      </Form.field_base>
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
      <Form.field_base field={@var[:identifier_id]} label={@label} instructions={@instructions} skip_presence>
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
      </Form.field_base>
    </div>
    """
  end

  def link_preview(assigns) do
    var = assigns.var
    changeset = var.source
    value = get_field(changeset, :value)
    link_type = get_field(changeset, :link_type, :url)
    link_text = get_field(changeset, :link_text)
    external? = link_type == :url && is_binary(value) && String.starts_with?(value, "http")

    assigns =
      assigns
      |> assign(:link_type, link_type)
      |> assign(:link_text, link_text)
      |> assign(:value, split_url_with_wbr(value))
      |> assign(:external?, external?)

    ~H"""
    <div class="link-preview" phx-click={@click}>
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
    </div>
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
      escaped = segment |> Phoenix.HTML.html_escape() |> Phoenix.HTML.safe_to_string()
      "#{escaped}<wbr />"
    end)
    |> Phoenix.HTML.raw()
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
    link_type = get_field(changeset, :link_type, :url)
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
    <Content.modal title={gettext("Link")} id={"var-#{@field.id}-link-config"}>
      <div class="panels">
        <div class="panel">
          <Input.radios
            field={@field[:link_type]}
            label={gettext("Type")}
            opts={[
              options: [
                %{label: gettext("URL"), value: :url},
                %{label: gettext("Identifier"), value: :identifier}
              ]
            ]}
          />
        </div>
        <div class="panel">
          <div :if={@link_type == :url}>
            <Input.text
              field={@field[:value]}
              label={gettext("URL")}
              instructions={gettext("i.e: `https://example.com`")}
              monospace
            />
            <Input.text :if={@allow_text?} field={@field[:link_text]} label={gettext("Link text")} />
            <Input.toggle field={@field[:link_target_blank]} label={gettext("Open link in new window/tab")} />
          </div>
          <div :if={@link_type == :identifier}>
            <Input.text
              :if={@allow_text?}
              field={@field[:link_text]}
              label={gettext("Link text")}
              instructions={gettext("Overrides identifier title")}
            />
            <Input.toggle field={@field[:link_target_blank]} label={gettext("Open link in new window/tab")} />

            <.live_component
              module={Content.SelectIdentifier}
              id={"#{@field.id}-identifier-select"}
              field={@field[:identifier_id]}
              var_key={@var_key}
              var_type={@var_type}
              wanted_schemas={@wanted_schemas}
              on_change={@on_change}
              target={@target}
            />
          </div>
        </div>
      </div>
    </Content.modal>
    """
  end

  def image_modal(assigns) do
    ~H"""
    <Content.modal title={gettext("Image")} id={"var-#{@field.id}-image-config"}>
      <div class="panels">
        <div class="panel">
          <%= if @image && @image.path do %>
            <img
              width={"#{@image.width}"}
              height={"#{@image.height}"}
              src={"#{Utils.img_url(@image, :original, prefix: Utils.media_url())}"}
            />

            <div class="image-info">
              Path: {@image.path}<br /> Dimensions: {@image.width}&times;{@image.height}<br />
            </div>
          <% end %>
          <%= if !@image do %>
            <div
              id={"#{@field.id}-var-uploader"}
              class="input-image"
              phx-hook="Brando.UploadTrigger"
              data-kind={@upload_kind}
              data-component-id={@component_id}
              data-var-key={@var_key}
              data-asset-type="image"
              data-config-target={@field[:config_target].value || "default"}
              data-folder-browser="true"
              data-accept=".jpg,.jpeg,.png,.gif,.webp,.svg"
            >
              <input type="file" class="file-input" accept=".jpg,.jpeg,.png,.gif,.webp,.svg" />
              <div class="img-placeholder empty upload-canvas">
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
                <div class="instructions">
                  <span>{gettext("Click or drag an image &uarr; to upload") |> raw()}</span>
                </div>
              </div>
            </div>
          <% end %>
        </div>
        <div class="panel">
          <div class="button-group-vertical">
            <button
              type="button"
              class="secondary"
              phx-click={JS.push("set_target", target: @target) |> toggle_drawer("#image-picker")}
            >
              {gettext("Select image")}
            </button>

            <button type="button" class="danger" phx-click={JS.push("reset_image", target: @target)}>
              {gettext("Reset image")}
            </button>
          </div>
        </div>
      </div>
    </Content.modal>
    """
  end

  def file_modal(assigns) do
    ~H"""
    <Content.modal title={gettext("File")} id={"var-#{@field.id}-file-config"}>
      <div class="panels">
        <div class="panel">
          <%= if @file && @file.filename do %>
            <a
              class="file-card"
              href={Utils.file_url(@file, prefix: Utils.media_url())}
              target="_blank"
              rel="noopener"
            >
              <div class="file-card__icon">
                <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" aria-hidden="true">
                  <path fill="none" d="M0 0h24v24H0z" />
                  <path d="M21 8v12.993A1 1 0 0 1 20.007 22H3.993A.993.993 0 0 1 3 21.008V2.992C3 2.444 3.445 2 3.993 2H15l6 6zm-2 1h-5V4H5v16h14V9z" />
                </svg>
              </div>
              <div class="file-card__meta">
                <div class="file-card__name">{Path.basename(@file.filename)}</div>
                <div class="file-card__sub">
                  <span class="file-card__type">{@file.mime_type}</span>
                  <span class="file-card__size">{Utils.human_size(@file.filesize)}</span>
                </div>
              </div>
            </a>
          <% end %>
          <%= if !@file do %>
            <div
              id={"#{@field.id}-var-uploader"}
              class="input-image"
              phx-hook="Brando.UploadTrigger"
              data-kind={@upload_kind}
              data-component-id={@component_id}
              data-var-key={@var_key}
              data-asset-type="file"
              data-config-target={@field[:config_target].value || "default"}
            >
              <input type="file" class="file-input" />
              <div class="img-placeholder empty upload-canvas">
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
                <div class="instructions">
                  <span>{gettext("Click or drag a file &uarr; to upload") |> raw()}</span>
                </div>
              </div>
            </div>
          <% end %>
        </div>
        <div class="panel">
          <div class="button-group-vertical">
            <button
              type="button"
              class="secondary"
              phx-click={JS.push("set_file_target", target: @target) |> toggle_drawer("#file-picker")}
            >
              {gettext("Select file")}
            </button>

            <button type="button" class="danger" phx-click={JS.push("reset_file", target: @target)}>
              {gettext("Reset file")}
            </button>
          </div>
        </div>
      </div>
    </Content.modal>
    """
  end

  def video_modal(assigns) do
    ~H"""
    <Content.modal title={gettext("Video")} id={"var-#{@field.id}-video-config"}>
      <div class="panels">
        <div class="panel">
          <%= if @video do %>
            <img
              :if={@video.thumbnail}
              src={Utils.img_url(@video.thumbnail, :small, prefix: Utils.media_url())}
              alt=""
            />
            <div class="image-info">
              {@video.title || gettext("Untitled video")}<br />
              <span :if={@video.caption}>{@video.caption}</span>
            </div>
          <% else %>
            <p>{gettext("No video selected.")}</p>
          <% end %>
        </div>
        <div class="panel">
          <div class="button-group-vertical">
            <button
              type="button"
              class="secondary"
              phx-click={JS.push("set_video_target", target: @target) |> toggle_drawer("#video-picker")}
            >
              {if @video, do: gettext("Replace video"), else: gettext("Select video")}
            </button>
            <button :if={@video} type="button" class="danger" phx-click={JS.push("reset_video", target: @target)}>
              {gettext("Reset video")}
            </button>
          </div>
        </div>
      </div>
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
    <Content.modal title={gettext("Gallery")} id={"var-#{@field.id}-gallery-config"} wide>
      <div class="gallery-input">
        <div :if={@objects == []} class="empty">{gettext("No assets in this gallery.")}</div>
        <div :if={@objects != []} class="gallery-objects gallery-objects--grid">
          <div :for={object <- @objects} class="gallery-object">
            <img
              :if={object.image}
              src={Utils.img_url(object.image, :small, prefix: Utils.media_url())}
              alt=""
            />
            <div :if={object.video} class="file-card">
              <div class="file-card__icon"><.icon name="hero-play-circle" /></div>
              <div class="file-card__meta">{object.video.title || gettext("Untitled video")}</div>
            </div>
            <button
              type="button"
              class="tiny danger"
              phx-click={JS.push("remove_gallery_object", target: @target, value: %{id: object.id})}
            >
              {gettext("Remove")}
            </button>
          </div>
        </div>
        <div class="actions">
          <button
            :if={:image in @allowed_types}
            type="button"
            class="secondary"
            phx-click={JS.push("set_gallery_image_target", target: @target) |> toggle_drawer("#image-picker")}
          >
            {gettext("Add images")}
          </button>
          <button
            :if={:video in @allowed_types}
            type="button"
            class="secondary"
            phx-click={JS.push("set_gallery_video_target", target: @target) |> toggle_drawer("#video-picker")}
          >
            {gettext("Add videos")}
          </button>
          <button
            :if={@gallery}
            type="button"
            class="danger"
            phx-click={JS.push("reset_gallery", target: @target)}
          >
            {gettext("Reset gallery")}
          </button>
        </div>
      </div>
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
      selected_images: []
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
    current_user_id = socket.assigns.current_user_id

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
          |> Map.update(:creator_id, current_user_id, &(&1 || current_user_id))
        end)
    }

    result =
      (gallery || %Brando.Galleries.Gallery{})
      |> Brando.Galleries.Gallery.changeset(params, current_user_id)
      |> then(fn changeset ->
        if gallery, do: Brando.Repo.update(changeset), else: Brando.Repo.insert(changeset)
      end)

    case result do
      {:ok, saved_gallery} ->
        saved_gallery =
          Brando.Repo.preload(
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
  defp current_user(user_id), do: Brando.Repo.get(Brando.Users.User, user_id)

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
