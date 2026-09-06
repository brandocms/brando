defmodule BrandoAdmin.Components.Form.ModuleProps.RefBlockForm do
  @moduledoc """
  Pattern-matched function components for ref block template forms.
  """
  use BrandoAdmin, :component
  use Gettext, backend: Brando.Gettext

  alias BrandoAdmin.Components.Form.Input
  alias BrandoAdmin.Components.Form.ModuleProps
  alias BrandoAdmin.Components.Form.Primitives
  alias Phoenix.LiveView.JS

  @text_extension_options [
    %{label: "All", value: nil},
    %{label: "Paragraph", value: "p"},
    %{label: "H1", value: "h1"},
    %{label: "H2", value: "h2"},
    %{label: "H3", value: "h3"},
    %{label: "List", value: "list"},
    %{label: "Link", value: "link"},
    %{label: "Button", value: "button"},
    %{label: "Bold", value: "bold"},
    %{label: "Italic", value: "italic"},
    %{label: "Subscript", value: "sub"},
    %{label: "Superscript", value: "sup"},
    %{label: "Color", value: "color"},
    %{label: "Unset Marks", value: "unsetMarks"},
    %{label: "Jump Anchor", value: "jumpAnchor"},
    %{label: "Smart Text", value: "smartText"},
    %{label: "Align", value: "align"}
  ]

  @placeholder_options [
    %{label: "SVG", value: :svg},
    %{label: "Dominant Color", value: :dominant_color},
    %{label: "Dominant Color Faded", value: :dominant_color_faded},
    %{label: "Micro", value: :micro},
    %{label: "None", value: :none}
  ]

  @fetchpriority_options [
    %{label: "Auto", value: :auto},
    %{label: "High", value: :high},
    %{label: "Low", value: :low}
  ]

  @gallery_type_options [
    %{label: "Gallery", value: :gallery},
    %{label: "Slider", value: :slider},
    %{label: "Slideshow", value: :slideshow}
  ]

  @display_options [
    %{label: "Grid", value: :grid},
    %{label: "List", value: :list}
  ]

  @gallery_placeholder_options [
    %{label: "Dominant color", value: "dominant_color"},
    %{label: "Dominant color faded", value: "dominant_color_faded"},
    %{label: "SVG", value: "svg"},
    %{label: "Micro", value: "micro"},
    %{label: "None", value: "none"}
  ]

  @video_source_options [
    %{label: "YouTube", value: "youtube"},
    %{label: "Vimeo", value: "vimeo"},
    %{label: "File", value: "file"}
  ]

  @available_blocks_options [
    %{label: "Picture", value: "picture"},
    %{label: "Video", value: "video"},
    %{label: "Gallery", value: "gallery"},
    %{label: "SVG", value: "svg"}
  ]

  attr :type, :string, required: true
  attr :ref_data, :any, required: true
  attr :form_id, :string, required: true
  attr :key, :string, required: true
  attr :ref_name, :string, required: true

  def block_form(%{type: "header"} = assigns) do
    ~H"""
    <Primitives.inputs_for_block :let={block_data} field={@ref_data[:data]}>
      <Input.text field={block_data[:level]} label={gettext("Level")} />
      <Input.text field={block_data[:text]} label={gettext("Text")} />
      <Input.text field={block_data[:id]} label={gettext("ID")} />
      <Input.text field={block_data[:link]} label={gettext("Link")} />
    </Primitives.inputs_for_block>
    """
  end

  def block_form(%{type: "comment"} = assigns) do
    ~H"""
    <Primitives.inputs_for_block :let={block_data} field={@ref_data[:data]}>
      <Input.code
        id={"#{@form_id}-ref-#{@key}-#{@ref_name}-comment-text"}
        field={block_data[:text]}
        label={gettext("Text")}
      />
    </Primitives.inputs_for_block>
    """
  end

  def block_form(%{type: "html"} = assigns) do
    ~H"""
    <Primitives.inputs_for_block :let={block_data} field={@ref_data[:data]}>
      <Input.code
        id={"#{@form_id}-ref-#{@key}-#{@ref_name}-html-code"}
        field={block_data[:text]}
        label={gettext("HTML")}
      />
    </Primitives.inputs_for_block>
    """
  end

  def block_form(%{type: "markdown"} = assigns) do
    ~H"""
    <Primitives.inputs_for_block :let={block_data} field={@ref_data[:data]}>
      <Input.code
        id={"#{@form_id}-ref-#{@key}-#{@ref_name}-markdown-code"}
        field={block_data[:text]}
        label={gettext("Markdown")}
      />
    </Primitives.inputs_for_block>
    """
  end

  def block_form(%{type: "map"} = assigns) do
    ~H"""
    <Primitives.inputs_for_block :let={block_data} field={@ref_data[:data]}>
      <Input.radios
        field={block_data[:source]}
        opts={[options: [%{label: gettext("GMaps"), value: :gmaps}]]}
        label={gettext("Source")}
      />
      <Input.text field={block_data[:embed_url]} label={gettext("Embed URL")} />
    </Primitives.inputs_for_block>
    """
  end

  def block_form(%{type: "svg"} = assigns) do
    ~H"""
    <Primitives.inputs_for_block :let={block_data} field={@ref_data[:data]}>
      <Input.text field={block_data[:class]} label={gettext("Class")} />
      <Input.code
        id={"#{@form_id}-ref-#{@key}-#{@ref_name}-svg-code"}
        field={block_data[:code]}
        label={gettext("Code")}
      />
    </Primitives.inputs_for_block>
    """
  end

  def block_form(%{type: "blocks"} = assigns) do
    ~H"""
    <Primitives.inputs_for_block :let={block_data} field={@ref_data[:data]}>
      <Input.text
        field={block_data[:module_set]}
        label={gettext("Module set")}
        instructions={gettext("The module set available in this region. Use all for all suitable modules.")}
      />
    </Primitives.inputs_for_block>
    """
  end

  def block_form(%{type: "text"} = assigns) do
    assigns =
      assign(assigns, :text_extension_options, @text_extension_options)

    ~H"""
    <Primitives.inputs_for_block :let={block_data} field={@ref_data[:data]}>
      <Input.text field={block_data[:text]} label={gettext("Text")} />
      <.live_component
        module={Input.MultiSelect}
        id={"#{@form_id}-ref-#{@key}-#{@ref_name}-extensions"}
        label={gettext("Extensions")}
        field={block_data[:extensions]}
        opts={[options: @text_extension_options]}
      />
      <Input.hidden field={block_data[:type]} />
      <Input.toggle field={block_data[:footnotes]} label={gettext("Footnotes")} />
      <Input.text
        field={block_data[:footnote_module_set]}
        label={gettext("Footnote module set")}
        instructions={
          gettext("An ordered set of modules for notes. Put a Text module first to make new notes quick to write.")
        }
      />
      <br />
      {block_data[:extensions].value}
    </Primitives.inputs_for_block>
    """
  end

  def block_form(%{type: "picture"} = assigns) do
    assigns =
      assigns
      |> assign(:placeholder_options, @placeholder_options)
      |> assign(:fetchpriority_options, @fetchpriority_options)

    ~H"""
    <Primitives.inputs_for_block :let={block_data} field={@ref_data[:data]}>
      <Input.toggle field={block_data[:lazyload]} label={gettext("Lazyload")} />
      <Input.toggle field={block_data[:moonwalk]} label={gettext("Moonwalk")} />
      <Input.text field={block_data[:title]} label={gettext("Title/Caption")} />
      <Input.text field={block_data[:alt]} label={gettext("Alt. text")} />
      <Input.text field={block_data[:credits]} label={gettext("Credits")} />
      <Input.text field={block_data[:link]} label={gettext("Link")} />
      <Input.text field={block_data[:picture_class]} label={gettext("Picture class(es)")} />
      <Input.text field={block_data[:img_class]} label={gettext("Img class(es)")} />
      <.live_component
        module={Input.Select}
        id={"#{@form_id}-ref-#{@key}-#{@ref_name}-placeholder"}
        field={block_data[:placeholder]}
        inline={true}
        opts={[options: @placeholder_options]}
      />
      <.live_component
        module={Input.Select}
        id={"#{@form_id}-ref-#{@key}-#{@ref_name}-fetchpriority"}
        field={block_data[:fetchpriority]}
        inline={true}
        opts={[options: @fetchpriority_options]}
      />
      <ModuleProps.format_checkboxes field={block_data[:formats]} />
      <Input.text
        field={block_data[:config_target]}
        label={gettext("Config target")}
        instructions={gettext("i.e: `image:Elixir.MyApp.Schema:function:fn_name`")}
        monospace
      />
    </Primitives.inputs_for_block>
    """
  end

  def block_form(%{type: "file"} = assigns) do
    ~H"""
    <Primitives.inputs_for_block :let={block_data} field={@ref_data[:data]}>
      <Input.text field={block_data[:title]} label={gettext("Title override")} />
      <Input.text field={block_data[:label]} label={gettext("Link label")} />
      <Input.textarea field={block_data[:description]} label={gettext("Description")} />
      <Input.text field={block_data[:class]} label={gettext("CSS class(es)")} />
      <Input.toggle field={block_data[:target_blank]} label={gettext("Open in new window/tab")} />
      <Input.toggle field={block_data[:download]} label={gettext("Download instead of open")} />
      <Input.text
        field={block_data[:config_target]}
        label={gettext("Config target")}
        instructions={gettext("i.e: `file:Elixir.MyApp.Schema:function:fn_name`")}
        monospace
      />
    </Primitives.inputs_for_block>
    """
  end

  def block_form(%{type: "gallery"} = assigns) do
    assigns =
      assigns
      |> assign(:gallery_type_options, @gallery_type_options)
      |> assign(:display_options, @display_options)
      |> assign(:gallery_placeholder_options, @gallery_placeholder_options)

    ~H"""
    <Primitives.inputs_for_block :let={block_data} field={@ref_data[:data]}>
      <Input.radios
        field={block_data[:type]}
        label={gettext("Type")}
        opts={[options: @gallery_type_options]}
      />
      <Input.radios
        field={block_data[:display]}
        label={gettext("Display")}
        opts={[options: @display_options]}
      />
      <Input.text field={block_data[:class]} label={gettext("Class")} />
      <Input.toggle field={block_data[:lightbox]} label={gettext("Lightbox")} />
      <Input.radios
        field={block_data[:placeholder]}
        label={gettext("Placeholder")}
        opts={[options: @gallery_placeholder_options]}
      />
      <ModuleProps.format_checkboxes field={block_data[:formats]} />
      <.live_component
        module={Input.MultiSelect}
        id={"#{@form_id}-ref-#{@key}-#{@ref_name}-gallery-allowed-types"}
        field={block_data[:allowed_types]}
        label={gettext("Allowed media")}
        opts={[options: [%{label: gettext("Images"), value: :image}, %{label: gettext("Videos"), value: :video}]]}
      />
      <Input.text field={block_data[:image_config_target]} label={gettext("Image config target")} monospace />
      <Input.text field={block_data[:video_config_target]} label={gettext("Video config target")} monospace />
    </Primitives.inputs_for_block>
    """
  end

  def block_form(%{type: "video"} = assigns) do
    assigns = assign(assigns, :video_source_options, @video_source_options)

    ~H"""
    <Primitives.inputs_for_block :let={block_data} field={@ref_data[:data]}>
      <Input.text field={block_data[:url]} label={gettext("URL")} />
      <Input.radios
        field={block_data[:source]}
        label={gettext("Source")}
        opts={[options: @video_source_options]}
      />
      <Input.input type={:hidden} field={block_data[:width]} />
      <Input.input type={:hidden} field={block_data[:height]} />
      <Input.text field={block_data[:remote_id]} label={gettext("Remote ID")} />
      <Input.text field={block_data[:poster]} label={gettext("Poster")} />
      <Input.text field={block_data[:cover]} label={gettext("Cover")} />
      <Input.number field={block_data[:opacity]} label={gettext("Opacity")} />
      <Input.toggle field={block_data[:autoplay]} label={gettext("Autoplay")} />
      <Input.toggle field={block_data[:preload]} label={gettext("Preload")} />
      <Input.toggle field={block_data[:play_button]} label={gettext("Play button")} />
      <Input.toggle field={block_data[:progress]} label={gettext("Progress bar")} />
      <Input.text
        field={block_data[:config_target]}
        label={gettext("Config target")}
        instructions={gettext("i.e: `video:Elixir.MyApp.Schema:field_name`")}
        monospace
      />
    </Primitives.inputs_for_block>
    """
  end

  def block_form(%{type: "media"} = assigns) do
    assigns =
      assigns
      |> assign(:available_blocks_options, @available_blocks_options)
      |> assign(:placeholder_options, @placeholder_options)
      |> assign(:fetchpriority_options, @fetchpriority_options)
      |> assign(:gallery_type_options, @gallery_type_options)
      |> assign(:display_options, @display_options)
      |> assign(:gallery_placeholder_options, @gallery_placeholder_options)

    ~H"""
    <Primitives.inputs_for_block :let={block_data} field={@ref_data[:data]}>
      <.available_blocks_checkboxes field={block_data[:available_blocks]} options={@available_blocks_options} />

      <.media_picture_template
        :if={"picture" in (block_data[:available_blocks].value || [])}
        field={block_data[:template_picture]}
        form_id={@form_id}
        key={@key}
        ref_name={@ref_name}
        placeholder_options={@placeholder_options}
        fetchpriority_options={@fetchpriority_options}
      />

      <.media_video_template
        :if={"video" in (block_data[:available_blocks].value || [])}
        field={block_data[:template_video]}
      />

      <.media_gallery_template
        :if={"gallery" in (block_data[:available_blocks].value || [])}
        field={block_data[:template_gallery]}
        gallery_type_options={@gallery_type_options}
        display_options={@display_options}
        gallery_placeholder_options={@gallery_placeholder_options}
      />

      <.media_svg_template
        :if={"svg" in (block_data[:available_blocks].value || [])}
        field={block_data[:template_svg]}
      />
    </Primitives.inputs_for_block>
    """
  end

  def block_form(%{type: "datasource"} = assigns) do
    ~H"""
    <Primitives.inputs_for_block :let={block_data} field={@ref_data[:data]}>
      <Input.text field={block_data[:description]} label={gettext("Description")} />
      <Input.text field={block_data[:arg]} label={gettext("Arg")} />
      <Input.text field={block_data[:limit]} label={gettext("Limit")} />
    </Primitives.inputs_for_block>
    """
  end

  def block_form(assigns) do
    ~H"""
    <div>No matching block {@type} found</div>
    """
  end

  # --- Media block sub-templates ---

  attr :field, :any, required: true
  attr :options, :list, required: true

  defp available_blocks_checkboxes(assigns) do
    ~H"""
    <Primitives.array_inputs_from_data
      :let={%{id: array_id, value: array_value, label: array_label, name: array_name, checked: checked}}
      field={@field}
      options={@options}
    >
      <div class="field-wrapper compact">
        <div class="check-wrapper small">
          <input type="checkbox" id={array_id} name={array_name} value={array_value} checked={checked} />
          <label class="control-label small" for={array_id}>{array_label}</label>
        </div>
      </div>
    </Primitives.array_inputs_from_data>
    """
  end

  attr :field, :any, required: true
  attr :form_id, :string, required: true
  attr :key, :string, required: true
  attr :ref_name, :string, required: true
  attr :placeholder_options, :list, required: true
  attr :fetchpriority_options, :list, required: true

  defp media_picture_template(assigns) do
    ~H"""
    <h2>Picture block template</h2>
    <.inputs_for :let={tpl_data} field={@field}>
      <Input.toggle field={tpl_data[:lazyload]} label={gettext("Lazyload")} />
      <Input.toggle field={tpl_data[:moonwalk]} label={gettext("Moonwalk")} />
      <Input.text field={tpl_data[:picture_class]} label={gettext("Picture class")} />
      <Input.text field={tpl_data[:img_class]} label={gettext("Image class")} />
      <.live_component
        module={Input.Select}
        id={"#{@form_id}-ref-#{@key}-#{@ref_name}-tpl-placeholder"}
        field={tpl_data[:placeholder]}
        label={gettext("Placeholder")}
        inline={true}
        opts={[options: @placeholder_options]}
      />
      <.live_component
        module={Input.Select}
        id={"#{@form_id}-ref-#{@key}-#{@ref_name}-tpl-fetchpriority"}
        field={tpl_data[:fetchpriority]}
        label={gettext("Fetch priority")}
        inline={true}
        opts={[options: @fetchpriority_options]}
      />
      <ModuleProps.format_checkboxes field={tpl_data[:formats]} />
      <Input.text
        field={tpl_data[:config_target]}
        label={gettext("Config target")}
        instructions={gettext("i.e: `image:Elixir.MyApp.Schema:function:fn_name`")}
        monospace
      />
    </.inputs_for>
    """
  end

  attr :field, :any, required: true

  defp media_video_template(assigns) do
    ~H"""
    <h2>Video block template</h2>
    <.inputs_for :let={tpl_data} field={@field}>
      <Input.number field={tpl_data[:opacity]} label={gettext("Opacity")} />
      <Input.toggle field={tpl_data[:autoplay]} label={gettext("Autoplay")} />
      <Input.toggle field={tpl_data[:preload]} label={gettext("Preload")} />
      <Input.toggle field={tpl_data[:play_button]} label={gettext("Play button")} />
      <Input.toggle field={tpl_data[:progress]} label={gettext("Progress bar")} />
      <Input.toggle field={tpl_data[:controls]} label={gettext("Show native player controls")} />
      <Input.toggle field={tpl_data[:loop]} label={gettext("Loop")} />
      <Input.toggle field={tpl_data[:muted]} label={gettext("Muted")} />
      <Input.text
        field={tpl_data[:config_target]}
        label={gettext("Config target")}
        instructions={gettext("i.e: `video:Elixir.MyApp.Schema:field_name`")}
        monospace
      />
    </.inputs_for>
    """
  end

  attr :field, :any, required: true
  attr :gallery_type_options, :list, required: true
  attr :display_options, :list, required: true
  attr :gallery_placeholder_options, :list, required: true

  defp media_gallery_template(assigns) do
    ~H"""
    <h2>Gallery block template</h2>
    <.inputs_for :let={tpl_data} field={@field}>
      <Input.radios
        field={tpl_data[:type]}
        label={gettext("Type")}
        opts={[options: @gallery_type_options]}
      />
      <Input.radios
        field={tpl_data[:display]}
        label={gettext("Display")}
        opts={[options: @display_options]}
      />
      <Input.text field={tpl_data[:class]} label={gettext("Class")} />
      <Input.toggle field={tpl_data[:lightbox]} label={gettext("Lightbox")} />
      <Input.radios
        field={tpl_data[:placeholder]}
        opts={[options: @gallery_placeholder_options]}
      />
      <ModuleProps.format_checkboxes field={tpl_data[:formats]} />
      <.live_component
        module={Input.MultiSelect}
        id={"#{@field.id}-gallery-allowed-types"}
        field={tpl_data[:allowed_types]}
        label={gettext("Allowed media")}
        opts={[options: [%{label: gettext("Images"), value: :image}, %{label: gettext("Videos"), value: :video}]]}
      />
      <Input.text field={tpl_data[:image_config_target]} label={gettext("Image config target")} monospace />
      <Input.text field={tpl_data[:video_config_target]} label={gettext("Video config target")} monospace />
    </.inputs_for>
    """
  end

  attr :field, :any, required: true

  defp media_svg_template(assigns) do
    ~H"""
    <h2>SVG block template</h2>
    <.inputs_for :let={tpl_data} field={@field}>
      <Input.text field={tpl_data[:class]} label={gettext("Class")} />
    </.inputs_for>
    """
  end

  @style_element_options Enum.map(
                           Brando.Villain.Blocks.TextBlock.Style.style_elements(),
                           &%{label: &1, value: &1}
                         )

  def block_form_extras(%{type: "text"} = assigns) do
    assigns = assign(assigns, :style_element_options, @style_element_options)

    ~H"""
    <Primitives.inputs_for_block :let={block_data} field={@block_data[:data]}>
      <Primitives.field_base field={block_data[:styles]} label={gettext("Styles")} class="subform">
        <.inputs_for :let={style_form} field={block_data[:styles]}>
          <div class="subform-entry inline">
            <input type="hidden" name={"#{block_data.name}[sort_style_ids][]"} value={style_form.index} />
            <div class="subform-tools">
              <button
                name={"#{block_data.name}[drop_style_ids][]"}
                type="button"
                value={style_form.index}
                phx-click={JS.dispatch("change")}
                class="subform-delete"
              >
                <.icon name="hero-x-mark" />
              </button>
            </div>
            <div class="subform-fields">
              <.live_component
                module={Input.Select}
                id={"#{style_form.id}-element"}
                label={gettext("Element")}
                field={style_form[:element]}
                inline={true}
                opts={[options: @style_element_options]}
              />
              <Input.text field={style_form[:class]} label={gettext("Class")} />
              <Input.text field={style_form[:label]} label={gettext("Label")} />
              <Input.text field={style_form[:icon]} label={gettext("Icon")} />
            </div>
          </div>
        </.inputs_for>
        <input type="hidden" name={"#{block_data.name}[drop_style_ids][]"} />
        <button
          type="button"
          name={"#{block_data.name}[sort_style_ids][]"}
          value="new"
          phx-click={JS.dispatch("change")}
          class="add-entry-button"
        >
          {gettext("Add style")}
        </button>
      </Primitives.field_base>
    </Primitives.inputs_for_block>
    """
  end

  def block_form_extras(assigns) do
    ~H""
  end
end
