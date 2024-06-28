defmodule BrandoAdmin.Components.Form.Input.RenderVar do
  use BrandoAdmin, :live_component
  # use Phoenix.HTML
  import Brando.Gettext
  import Ecto.Changeset
  import BrandoAdmin.Components.Content.List.Row, only: [status_circle: 1]

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
    {image_ids, cmp_imgs, file_ids, cmp_files, identifier_ids, cmp_identifiers} =
      Enum.reduce(assigns_sockets, {[], [], [], [], [], []}, fn
        {%{id: id, var: %{source: changeset}}, _socket},
        {image_ids, cmp_imgs, file_ids, cmp_files, identifier_ids, cmp_identifiers} = acc ->
          case get_field(changeset, :type) do
            :image ->
              image_id = get_field(changeset, :image_id)

              {[image_id | image_ids], [{id, image_id} | cmp_imgs], file_ids, cmp_files,
               identifier_ids, cmp_identifiers}

            :file ->
              file_id = get_field(changeset, :file_id)

              {image_ids, cmp_imgs, [file_id | file_ids], [{id, file_id} | cmp_files],
               identifier_ids, cmp_identifiers}

            :link ->
              case get_field(changeset, :identifier_id) do
                nil ->
                  acc

                identifier_id ->
                  {image_ids, cmp_imgs, file_ids, cmp_files, [identifier_id | identifier_ids],
                   [{id, identifier_id} | cmp_identifiers]}
              end

            _ ->
              acc
          end
      end)

    {:ok, images} =
      if image_ids == [] do
        {:ok, []}
      else
        Brando.Images.list_images(%{filter: %{ids: image_ids}, cache: {:ttl, :timer.minutes(2)}})
      end

    mapped_imgs = images |> Enum.map(&{&1.id, &1}) |> Map.new()
    mapped_img_ids = Map.new(cmp_imgs)

    {:ok, files} =
      if file_ids == [] do
        {:ok, []}
      else
        Brando.Files.list_files(%{filter: %{ids: file_ids}, cache: {:ttl, :timer.minutes(2)}})
      end

    mapped_files = files |> Enum.map(&{&1.id, &1}) |> Map.new()
    mapped_file_ids = Map.new(cmp_files)

    {:ok, identifiers} =
      if identifier_ids == [] do
        {:ok, []}
      else
        # TODO: , cache: {:ttl, :timer.minutes(2)}}
        Brando.Content.list_identifiers(identifier_ids)
      end

    mapped_identifiers = identifiers |> Enum.map(&{&1.id, &1}) |> Map.new()
    mapped_identifier_ids = Map.new(cmp_identifiers)

    Enum.map(assigns_sockets, fn {assigns, socket} ->
      socket_i =
        case Map.get(mapped_img_ids, assigns.id) do
          nil -> assign_new(socket, :image, fn -> nil end)
          key -> assign_new(socket, :image, fn -> Map.get(mapped_imgs, key) end)
        end

      socket_if =
        case Map.get(mapped_file_ids, assigns.id) do
          nil -> assign_new(socket_i, :file, fn -> nil end)
          key -> assign_new(socket_i, :file, fn -> Map.get(mapped_files, key) end)
        end

      socket_ifi =
        case Map.get(mapped_identifier_ids, assigns.id) do
          nil -> assign(socket_if, :identifier, nil)
          key -> assign(socket_if, :identifier, Map.get(mapped_identifiers, key))
        end

      var = assigns.var
      changeset = var.source
      important = get_field(changeset, :important)
      render = Map.get(assigns, :render, :all)
      edit = Map.get(assigns, :edit, false)
      target = Map.get(assigns, :target, nil)

      should_render? =
        cond do
          render == :all -> true
          render == :only_important and important -> true
          render == :only_regular and !important -> true
          true -> false
        end

      type = get_field(changeset, :type)

      value =
        case type do
          :image -> get_field(changeset, :image_id)
          :file -> get_field(changeset, :file_id)
          :boolean -> get_field(changeset, :value_boolean)
          :link -> get_field(changeset, :value)
          _ -> get_field(changeset, :value)
        end

      value = control_value(type, value)

      socket_ifi
      |> assign(assigns)
      |> assign(:id, assigns.id)
      |> assign(:edit, edit)
      |> assign(:target, target)
      |> assign(:should_render?, should_render?)
      |> assign(:important, important)
      |> assign(:label, get_field(changeset, :label))
      |> assign(:key, var[:key].value)
      |> assign(:type, type)
      |> assign(:value, value)
      |> assign_new(:blueprint_schema_opts, fn ->
        schemas = Brando.Blueprint.list_blueprints()
        Enum.map(schemas, &%{label: &1.__naming__().singular, value: &1})
      end)
      |> assign_new(:on_change, fn -> nil end)
      |> assign_new(:images, fn -> nil end)
      |> assign_new(:files, fn -> nil end)
      |> assign_new(:identifiers, fn -> nil end)
      |> assign_new(:value_id, fn -> value end)
      |> assign_new(:image_id, fn -> if type == :image, do: value end)
      |> assign_new(:file_id, fn -> if type == :file, do: value end)
      |> assign(:identifier_id, get_field(changeset, :identifier_id))
      |> assign(:instructions, get_field(changeset, :instructions))
      |> assign(:placeholder, get_field(changeset, :placeholder))
      |> assign(:var, var)
    end)
  end

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
    <div
      id={@id}
      class={["variable", @var[:type].value]}
      data-size={@var[:width].value}
      data-id={@var[:id].value}
    >
      <%= if @should_render? do %>
        <%= if @edit do %>
          <div id={"#{@var.id}-edit"}>
            <div class="variable-header" phx-click={JS.push("toggle_visible", target: @myself)}>
              <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24">
                <path fill="none" d="M0 0h24v24H0z" /><path d="M12 22C6.477 22 2 17.523 2 12S6.477 2 12 2s10 4.477 10 10-4.477 10-10 10zm-2.29-2.333A17.9 17.9 0 0 1 8.027 13H4.062a8.008 8.008 0 0 0 5.648 6.667zM10.03 13c.151 2.439.848 4.73 1.97 6.752A15.905 15.905 0 0 0 13.97 13h-3.94zm9.908 0h-3.965a17.9 17.9 0 0 1-1.683 6.667A8.008 8.008 0 0 0 19.938 13zM4.062 11h3.965A17.9 17.9 0 0 1 9.71 4.333 8.008 8.008 0 0 0 4.062 11zm5.969 0h3.938A15.905 15.905 0 0 0 12 4.248 15.905 15.905 0 0 0 10.03 11zm4.259-6.667A17.9 17.9 0 0 1 15.973 11h3.965a8.008 8.008 0 0 0-5.648-6.667z" />
              </svg>
              <div class="variable-key">
                <%= @var[:key].value %>
                <span><%= @var[:type].value %></span>
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
              />

              <%= case @type do %>
                <% :color -> %>
                  <Input.toggle
                    field={@var[:color_picker]}
                    label={gettext("Allow picking custom colors")}
                  />
                  <Input.toggle field={@var[:color_opacity]} label={gettext("Allow setting opacity")} />
                  <Input.number
                    field={@var[:palette_id]}
                    label={gettext("ID of palette to choose colors from")}
                  />
                <% :link -> %>
                  <.live_component
                    module={Input.MultiSelect}
                    id={"#{@var.id}-select-link-schemas"}
                    label={gettext("Allowed identifier schemas")}
                    field={@var[:link_identifier_schemas]}
                    opts={[options: @blueprint_schema_opts]}
                  />
                  <Input.toggle
                    field={@var[:link_allow_custom_text]}
                    label={gettext("Allow setting custom link text")}
                  />
                <% :select -> %>
                  <Form.field_base
                    field={@var[:options]}
                    label="Options"
                    instructions=""
                    left_justify_meta
                  >
                    <Form.label field={@var[:options]}>
                      <.inputs_for :let={opt} field={@var[:options]}>
                        <Input.text field={opt[:label]} label={gettext("Label")} />
                        <Input.text field={opt[:value]} label={gettext("Value")} />
                      </.inputs_for>
                    </Form.label>
                    <button
                      type="button"
                      class="secondary"
                      phx-click={
                        JS.push("add_select_var_option", value: %{var_key: @key}, target: @target)
                      }
                    >
                      <%= gettext("Add option") %>
                    </button>
                  </Form.field_base>
                <% _ -> %>
              <% end %>
            </div>
          </div>
        <% else %>
          <div id={"#{@var.id}-value"}>
            <Input.input type={:hidden} field={@var[:id]} />
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

  def render_value_inputs(%{type: nil} = assigns) do
    ~H"""
    <Input.hidden field={@var[:value]} />
    """
  end

  def render_value_inputs(%{type: :string} = assigns) do
    ~H"""
    <div class="brando-input">
      <Input.text
        field={@var[:value]}
        label={@label}
        placeholder={@placeholder}
        instructions={@instructions}
      />
    </div>
    """
  end

  def render_value_inputs(%{type: :html} = assigns) do
    ~H"""
    <div class="brando-input">
      <Input.rich_text
        field={@var[:value]}
        label={@label}
        placeholder={@placeholder}
        instructions={@instructions}
      />
    </div>
    """
  end

  def render_value_inputs(%{type: :text} = assigns) do
    ~H"""
    <div class="brando-input">
      <Input.textarea
        field={@var[:value]}
        label={@label}
        placeholder={@placeholder}
        instructions={@instructions}
      />
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
        opts={[options: @var[:options].value || []]}
        publish={@publish}
      />

      <.inputs_for :let={opt} field={@var[:options]}>
        <Input.hidden field={opt[:label]} />
        <Input.hidden field={opt[:value]} />
      </.inputs_for>
    </div>
    """
  end

  def render_value_inputs(%{type: :image} = assigns) do
    ~H"""
    <div class="brando-input">
      <Form.field_base field={@var[:image_id]} label={@label} instructions={@instructions}>
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
          <.image_modal field={@var} image={@image} target={@target} />
        </div>
      </Form.field_base>
    </div>
    """
  end

  def render_value_inputs(%{type: :file} = assigns) do
    ~H"""
    <div class="brando-input">
      <Form.field_base field={@var[:file_id]} label={@label} instructions={@instructions}>
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
          <.file_modal field={@var} file={@file} target={@target} />
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
      <Form.field_base field={@var[:identifier_id]} label={@label} instructions={@instructions}>
        <div class="input-link">
          <.link_preview
            var={@var}
            field={@var[:identifier_id]}
            click={show_modal("#var-#{@var.id}-link-config")}
            identifier={@identifier}
          />
          <.link_modal field={@var} identifier={@identifier} target={@target} />
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
      |> assign(:value, value)
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
            <div class="link-text"><%= @link_text %></div>
          <% end %>
          <dl>
            <dt><%= gettext("URL") %>=</dt>
            <dd><%= @value || gettext("<No URL>") %></dd>
          </dl>
        <% else %>
          <.link_identifier identifier={@identifier} link_text={@link_text} />
        <% end %>
      </div>
    </div>
    """
  end

  attr :link_text, :string, default: nil
  attr :identifier, :any, default: nil

  def link_identifier(assigns) do
    identifier = assigns.identifier

    translated_type =
      if identifier do
        schema = identifier.schema

        Utils.try_path(schema.__translations__(), [:naming, :singular]) ||
          schema.__naming__().singular
      end

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
      <dt><%= gettext("URL") %>=</dt>
      <dd :if={@identifier}><%= @identifier.url %></dd>
      <dd :if={!@identifier}><%= gettext("<No URL>") %></dd>
    </dl>
    """
  end

  def link_modal(assigns) do
    field = assigns.field
    changeset = field.source
    link_type = get_field(changeset, :link_type, :url)
    allow_text? = get_field(changeset, :link_allow_custom_text)
    wanted_schemas = get_field(changeset, :link_identifier_schemas, [])

    assigns =
      assigns
      |> assign(:link_type, link_type)
      |> assign(:allow_text?, allow_text?)
      |> assign(:wanted_schemas, wanted_schemas)

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
            <Input.toggle
              field={@field[:link_target_blank]}
              label={gettext("Open link in new window/tab")}
            />
          </div>
          <div :if={@link_type == :identifier}>
            <Input.text
              :if={@allow_text?}
              field={@field[:link_text]}
              label={gettext("Link text")}
              instructions={gettext("Overrides identifier title")}
            />
            <Input.toggle
              field={@field[:link_target_blank]}
              label={gettext("Open link in new window/tab")}
            />

            <.live_component
              module={Content.SelectIdentifier}
              id={"#{@field.id}-identifier-select"}
              field={@field[:identifier_id]}
              wanted_schemas={@wanted_schemas}
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
              Path: <%= @image.path %><br />
              Dimensions: <%= @image.width %>&times;<%= @image.height %><br />
            </div>
          <% end %>
          <%= if !@image do %>
            <div
              id={"#{@field.id}-legacy-uploader"}
              class="input-image"
              phx-hook="Brando.LegacyImageUpload"
              data-text-uploading={gettext("Uploading...")}
              data-block-uid={"var-#{@field.id}"}
              data-upload-event-target={@target}
            >
              <input class="file-input" type="file" />
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
                  <span><%= gettext("Click or drag an image &uarr; to upload") |> raw() %></span>
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
              <%= gettext("Select image") %>
            </button>

            <button type="button" class="danger" phx-click={JS.push("reset_image", target: @target)}>
              <%= gettext("Reset image") %>
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
              URL: <%= Utils.file_url(@file, prefix: Utils.media_url()) %><br />
              Path: <%= @file.filename %><br /> Size: <%= @file.filesize %> bytes
            </div>
          <% end %>
          <%= if !@file do %>
            <div
              id={"#{@field.id}-legacy-uploader"}
              class="input-image"
              phx-hook="Brando.LegacyFileUpload"
              data-text-uploading={gettext("Uploading...")}
              data-block-uid={"var-#{@field.id}"}
              data-upload-event-target={@target}
              data-upload-config-target={@field[:config_target].value}
            >
              <input class="file-input" type="file" />
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
                  <span><%= gettext("Click or drag a file &uarr; to upload") |> raw() %></span>
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
              <%= gettext("Select file") %>
            </button>

            <button type="button" class="danger" phx-click={JS.push("reset_file", target: @target)}>
              <%= gettext("Reset file") %>
            </button>
          </div>
        </div>
      </div>
    </Content.modal>
    """
  end

  def handle_event("set_target", _, %{assigns: %{myself: myself}} = socket) do
    send_update(
      BrandoAdmin.Components.ImagePicker,
      id: "image-picker",
      config_target: "default",
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

  def handle_event(
        "reset_image",
        _,
        socket
      ) do
    socket
    |> assign(:image, nil)
    |> assign(:image_id, nil)
    |> on_change(%{image: nil, image_id: nil})
    |> then(&{:noreply, &1})
  end

  def handle_event(
        "reset_file",
        _,
        socket
      ) do
    socket
    |> assign(:file, nil)
    |> assign(:file_id, nil)
    |> on_change(%{file: nil, file_id: nil})
    |> then(&{:noreply, &1})
  end

  def handle_event(
        "select_image",
        %{"id" => image_id},
        socket
      ) do
    image = Brando.Images.get_image!(image_id)

    socket
    |> assign(:image_id, image_id)
    |> assign(:image, image)
    |> on_change(%{image: image, image_id: image_id})
    |> then(&{:noreply, &1})
  end

  def handle_event(
        "image_uploaded",
        %{"id" => image_id},
        socket
      ) do
    image = Brando.Images.get_image!(image_id)

    socket
    |> assign(:image_id, image_id)
    |> assign(:image, image)
    |> on_change(%{image: image, image_id: image_id})
    |> then(&{:noreply, &1})
  end

  def handle_event(
        "select_file",
        %{"id" => file_id},
        socket
      ) do
    file = Brando.Files.get_file!(file_id)

    socket
    |> assign(:file_id, file_id)
    |> assign(:file, file)
    |> on_change(%{file: file, file_id: file_id})
    |> then(&{:noreply, &1})
  end

  def handle_event(
        "file_uploaded",
        %{"id" => file_id},
        socket
      ) do
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
