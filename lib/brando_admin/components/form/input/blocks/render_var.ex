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
  # prop render, :atom, values: [:all, :only_important, :only_regular], default: :all
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
    {:ok,
     socket
     |> assign(:visible, false)
     |> assign(:publish, false)}
  end

  def update_many(assigns_sockets) do
    {upload_events, var_updates} =
      Enum.split_with(assigns_sockets, fn {assigns, _socket} ->
        Map.has_key?(assigns, :event) && assigns.event == "upload_complete"
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

    upload_results ++ var_results
  end

  defp collect_asset_ids(assigns_sockets) do
    Enum.reduce(assigns_sockets, %{images: [], files: [], identifiers: []}, fn
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

  defp fetch_identifiers(ids) do
    Brando.Content.list_identifiers(%{
      filter: %{ids: ids},
      cache: {:ttl, :timer.minutes(5)},
      order: {:array_position, ids}
    })
  end

  defp assemble_socket({assigns, socket}, lookups) do
    socket
    |> assign_new(:image, fn -> lookup_asset(lookups.images, assigns.id) end)
    |> assign_new(:file, fn -> lookup_asset(lookups.files, assigns.id) end)
    |> assign(:identifier, lookup_asset(lookups.identifiers, assigns.id))
    |> assign_var_fields(assigns)
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
    important = get_field(changeset, :important)
    value = type |> extract_value(changeset) |> then(&control_value(type, &1))

    socket
    |> assign(assigns)
    |> assign(:id, assigns.id)
    |> assign(:edit, Map.get(assigns, :edit, false))
    |> assign(:target, Map.get(assigns, :target, nil))
    |> assign(:should_render?, should_render?(Map.get(assigns, :render, :all), important))
    |> assign(:important, important)
    |> assign(:label, get_field(changeset, :label))
    |> assign(:key, var[:key].value)
    |> assign(:type, type)
    |> assign(:value, value)
    |> assign_new(:blueprint_schema_opts, fn ->
      schemas = Brando.Blueprint.list_blueprints()
      Enum.map(schemas, &%{label: &1.__naming__().singular, value: &1})
    end)
    |> assign_new(:form_cid, fn -> nil end)
    |> assign_new(:on_change, fn -> nil end)
    |> assign_new(:images, fn -> nil end)
    |> assign_new(:files, fn -> nil end)
    |> assign_new(:inner_block, fn -> nil end)
    |> assign_new(:identifiers, fn -> nil end)
    |> assign_new(:value_id, fn -> value end)
    |> assign_new(:image_id, fn -> if type == :image, do: value end)
    |> assign_new(:file_id, fn -> if type == :file, do: value end)
    |> assign(:identifier_id, get_field(changeset, :identifier_id))
    |> assign(:instructions, get_field(changeset, :instructions))
    |> assign(:placeholder, get_field(changeset, :placeholder))
    |> assign(:var, var)
    |> maybe_register_var_upload(type, assigns)
  end

  defp maybe_register_var_upload(socket, type, assigns) when type in [:image, :file] do
    form_cid = Map.get(assigns, :form_cid)

    if form_cid && !socket.assigns[:upload_registered] do
      var_id = assigns.var[:key].value || assigns.var.index
      upload_name = :"var_#{var_id}_#{type}"

      send_update(form_cid, %{
        event: "register_var_upload",
        upload_name: upload_name,
        var_type: type,
        component_id: assigns.id,
        config_target: assigns.var[:config_target].value || "default"
      })

      assign(socket, upload_registered: true, upload_name: upload_name)
    else
      socket
      |> assign_new(:upload_registered, fn -> false end)
      |> assign_new(:upload_name, fn -> nil end)
    end
  end

  defp maybe_register_var_upload(socket, _type, _assigns) do
    socket
    |> assign_new(:upload_registered, fn -> false end)
    |> assign_new(:upload_name, fn -> nil end)
  end

  defp extract_value(:image, changeset), do: get_field(changeset, :image_id)
  defp extract_value(:file, changeset), do: get_field(changeset, :file_id)
  defp extract_value(:boolean, changeset), do: get_field(changeset, :value_boolean)
  defp extract_value(_type, changeset), do: get_field(changeset, :value)

  defp should_render?(:all, _important), do: true
  defp should_render?(:only_important, true), do: true
  defp should_render?(:only_regular, false), do: true
  defp should_render?(_render, _important), do: false

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
          <div id={"#{@var.id}-edit"}>
            <div class="variable-header" phx-click={JS.push("toggle_visible", target: @myself)}>
              <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24">
                <path fill="none" d="M0 0h24v24H0z" /><path d="M12 22C6.477 22 2 17.523 2 12S6.477 2 12 2s10 4.477 10 10-4.477 10-10 10zm-2.29-2.333A17.9 17.9 0 0 1 8.027 13H4.062a8.008 8.008 0 0 0 5.648 6.667zM10.03 13c.151 2.439.848 4.73 1.97 6.752A15.905 15.905 0 0 0 13.97 13h-3.94zm9.908 0h-3.965a17.9 17.9 0 0 1-1.683 6.667A8.008 8.008 0 0 0 19.938 13zM4.062 11h3.965A17.9 17.9 0 0 1 9.71 4.333 8.008 8.008 0 0 0 4.062 11zm5.969 0h3.938A15.905 15.905 0 0 0 12 4.248 15.905 15.905 0 0 0 10.03 11zm4.259-6.667A17.9 17.9 0 0 1 15.973 11h3.965a8.008 8.008 0 0 0-5.648-6.667z" />
              </svg>
              <div class="variable-key">
                {@var[:key].value}
                <span>{@var[:type].value}</span>
              </div>
            </div>

            <div class={["variable-content", !@visible && "hidden"]}>
              <Input.toggle field={@var[:marked_as_deleted]} label={gettext("Marked as deleted")} />
              <Input.toggle field={@var[:important]} label={gettext("Important")} />
              <Input.text field={@var[:key]} label={gettext("Key")} />
              <Input.text field={@var[:label]} label={gettext("Label")} />
              <Input.text field={@var[:instructions]} label={gettext("Instructions")} />
              <Input.text field={@var[:placeholder]} label={gettext("Placeholder")} />

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
                    %{label: "Html", value: "html"},
                    %{label: "Image", value: "image"},
                    %{label: "Link", value: "link"},
                    %{label: "String", value: "string"},
                    %{label: "Select", value: "select"},
                    %{label: "Text", value: "text"}
                  ]
                ]}
                publish={@publish}
              />

              <.live_component
                module={Input.Select}
                id={"#{@var.id}-select-width"}
                label={gettext("Width")}
                field={@var[:width]}
                opts={[
                  options: [
                    %{label: "100%", value: "full"},
                    %{label: "50%", value: "half"},
                    %{label: "33%", value: "third"}
                  ]
                ]}
                publish={@publish}
              />

              <.render_value_inputs
                edit
                id={@id}
                type={@type}
                var={@var}
                image={@image}
                images={@images}
                file={@file}
                files={@files}
                label={@label}
                value_id={@value_id}
                image_id={@image_id}
                file_id={@file_id}
                identifier={@identifier}
                identifier_id={@identifier_id}
                placeholder={@placeholder}
                instructions={@instructions}
                target={@myself}
                publish={@publish}
                on_change={@on_change}
                upload_name={@upload_name}
              />

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
                  <hr />
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
                        <div class="input-group draggable drag-item mt-1">
                          <Input.text field={opt[:label]} label={gettext("Label")} />
                          <Input.text field={opt[:value]} label={gettext("Value")} />

                          <input type="hidden" name={"#{@var.name}[sort_option_ids][]"} value={opt.index} />
                          <button
                            class="tiny"
                            type="button"
                            name={"#{@var.name}[drop_option_ids][]"}
                            value={opt.index}
                            phx-click={JS.dispatch("change")}
                          >
                            {gettext("Delete")}
                          </button>
                        </div>
                      </.inputs_for>

                      <button
                        type="button"
                        class="secondary"
                        phx-click={JS.push("add_select_var_option", value: %{var_key: @key}, target: @target)}
                      >
                        {gettext("Add option")}
                      </button>
                    </Form.field_base>
                  </div>
                <% _ -> %>
              <% end %>
            </div>
          </div>
        <% else %>
          <div id={"#{@var.id}-value"}>
            <Input.input type={:hidden} field={@var[:id]} />
            <Input.input type={:hidden} field={@var[:_persistent_id]} value={@var.index} />
            <Input.input type={:hidden} field={@var[:key]} />
            <Input.input type={:hidden} field={@var[:label]} />
            <Input.input type={:hidden} field={@var[:type]} />
            <Input.input type={:hidden} field={@var[:important]} />
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
              label={@label}
              value_id={@value_id}
              image_id={@image_id}
              file_id={@file_id}
              identifier={@identifier}
              identifier_id={@identifier_id}
              placeholder={@placeholder}
              instructions={@instructions}
              target={@myself}
              publish={@publish}
              on_change={@on_change}
              upload_name={@upload_name}
            />
          </div>
        <% end %>
      <% end %>
    </div>
    """
  end

  attr :edit, :boolean, default: false
  attr :id, :any
  attr :type, :any
  attr :var, :any
  attr :identifier, :any
  attr :image, :any
  attr :images, :any
  attr :file, :any
  attr :files, :any
  attr :label, :any
  attr :value_id, :any
  attr :image_id, :any
  attr :file_id, :any
  attr :identifier_id, :any
  attr :placeholder, :any
  attr :instructions, :any
  attr :target, :any
  attr :publish, :any
  attr :on_change, :any
  attr :upload_name, :any, default: nil

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

  def render_value_inputs(%{type: :boolean} = assigns) do
    ~H"""
    <div class="brando-input">
      <Input.toggle field={@var[:value_boolean]} label={@label} instructions={@instructions} />
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
            value={@image_id}
            relation_field={@var[:image_id]}
            click={show_modal("#var-#{@var.id}-image-config")}
            file_name={@image && @image.path && Path.basename(@image.path)}
            publish
          />
          <.image_modal field={@var} image={@image} target={@target} upload_name={@upload_name} />
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
            value={@file_id}
            relation_field={@var[:file_id]}
            click={show_modal("#var-#{@var.id}-file-config")}
            file_name={@file && @file.filename && Path.basename(@file.filename)}
          />
          <.file_modal field={@var} file={@file} target={@target} upload_name={@upload_name} />
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

  def render_value_inputs(%{type: :link} = assigns) do
    ~H"""
    <div class="brando-input">
      <Form.field_base field={@var[:identifier_id]} label={@label} instructions={@instructions} skip_presence>
        <div class="input-link">
          <.link_preview
            var={@var}
            field={@var[:identifier_id]}
            click={show_modal("#var-#{@var.id}-link-config")}
            identifier={@identifier}
          />
          <.link_modal field={@var} identifier={@identifier} target={@target} on_change={@on_change} />
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
              <dd>{raw(@value) || gettext("<No URL>")}</dd>
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

  defp split_url_with_wbr(url) do
    url
    |> String.split("/")
    |> Enum.map_join("/", &"#{&1}<wbr />")
  end

  attr :link_text, :string, default: nil
  attr :identifier, :any, default: nil

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
              phx-hook="Brando.BlockUpload"
              data-upload-name={@upload_name}
              data-config-target={@field[:config_target].value || "default"}
              data-folder-browser="true"
              data-upload-mode="single"
              data-label-uploading={gettext("Uploading")}
              data-label-processing={gettext("Processing image...")}
            >
              <input type="file" class="file-input" accept=".jpg,.jpeg,.png,.gif,.webp,.svg" style="display:none" />
              <div class="upload-progress" style="display:none">
                <progress value="0" max="100">0%</progress>
                <div class="upload-progress-label"></div>
              </div>
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
            <div class="file-info">
              URL: {Utils.file_url(@file, prefix: Utils.media_url())}<br /> Path: {@file.filename}<br />
              Size: {@file.filesize} bytes
            </div>
          <% end %>
          <%= if !@file do %>
            <div
              id={"#{@field.id}-var-uploader"}
              class="input-image"
              phx-hook="Brando.BlockUpload"
              data-upload-name={@upload_name}
              data-config-target={@field[:config_target].value || "default"}
              data-folder-browser="false"
              data-upload-mode="single"
              data-label-uploading={gettext("Uploading")}
              data-label-processing={gettext("Processing...")}
            >
              <input type="file" class="file-input" style="display:none" />
              <div class="upload-progress" style="display:none">
                <progress value="0" max="100">0%</progress>
                <div class="upload-progress-label"></div>
              </div>
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
    send_update(
      BrandoAdmin.Components.FilePicker,
      id: "file-picker",
      config_target: "default",
      event_target: myself,
      multi: false,
      selected_files: []
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

  def handle_event("select_image", %{"id" => image_id}, socket) do
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

  def handle_event("toggle_visible", _, socket) do
    {:noreply, update(socket, :visible, &(!&1))}
  end

  def handle_event("update_var", %{"_target" => target} = params, socket) do
    var_key = socket.assigns.key
    var_type = socket.assigns.type
    on_change = socket.assigns.on_change
    value = get_in(params, target)

    params = %{
      event: "update_block_var",
      var_key: var_key,
      var_type: var_type,
      data: %{value: value}
    }

    on_change.(params)
    {:noreply, socket}
  end

  def on_change(%{assigns: %{on_change: nil}} = socket, _) do
    socket
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
end
