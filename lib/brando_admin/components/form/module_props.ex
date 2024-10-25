defmodule BrandoAdmin.Components.Form.ModuleProps do
  use BrandoAdmin, :live_component
  # use Phoenix.HTML
  use Gettext, backend: Brando.Gettext
  alias Brando.Datasource
  alias BrandoAdmin.Components.Content
  alias BrandoAdmin.Components.Form
  alias BrandoAdmin.Components.Form.Input
  alias BrandoAdmin.Components.Form.Input.RenderVar

  # prop form, :form, required: true
  # prop key, :string, default: "default"
  # prop entry_form, :boolean, default: false

  # prop create_ref, :event, required: true
  # prop delete_ref, :event, required: true
  # prop create_var, :event, required: true
  # prop delete_var, :event, required: true
  # data open_col_vars, :list

  def mount(socket) do
    {:ok,
     socket
     |> assign(open_col_vars: [], datasource: false)
     |> assign_new(:entry_form, fn -> false end)
     |> assign_new(:key, fn -> "default" end)
     |> assign_available_datasources()
     |> assign_available_parents()
     |> assign_available_table_templates()}
  end

  def update(assigns, socket) do
    datasource = Phoenix.HTML.Form.normalize_value("checkbox", assigns.form[:datasource].value)

    {:ok,
     socket
     |> assign(assigns)
     |> assign(:datasource, datasource)
     |> assign_available_queries()}
  end

  def assign_available_parents(socket) do
    {:ok, available_parents} = Brando.Content.list_modules(%{filter: %{parent_id: nil}})
    assign(socket, :available_parents, available_parents)
  end

  def assign_available_table_templates(socket) do
    {:ok, available_table_templates} = Brando.Content.list_table_templates(%{order: "asc name"})

    available_table_templates =
      Enum.map(available_table_templates, &%{label: &1.name, value: &1.id})

    assign_new(socket, :available_table_templates, fn -> available_table_templates end)
  end

  def render(assigns) do
    ~H"""
    <div class="properties shaded">
      <div class="inner">
        <Input.radios
          field={@form[:type]}
          label={gettext("Type")}
          opts={[
            options: [
              %{label: gettext("Liquid"), value: :liquid},
              %{label: gettext("Heex"), value: :heex}
            ]
          ]}
        />
        <Input.text field={@form[:name]} label={gettext("Name")} />
        <Input.text field={@form[:namespace]} label={gettext("Namespace")} />
        <Input.textarea field={@form[:help_text]} label={gettext("Help text")} />
        <Input.text field={@form[:class]} label={gettext("Class")} />
        <Input.toggle field={@form[:multi]} label={gettext("Multi")} />

        <.live_component
          module={Input.Select}
          id={"#{@form.id}-parent_id"}
          field={@form[:parent_id]}
          opts={[options: @available_parents]}
        />

        <.live_component
          module={Input.Select}
          id={"#{@form.id}-table_template_id"}
          field={@form[:table_template_id]}
          opts={[options: @available_table_templates]}
        />

        <%= if !@entry_form do %>
          <div class="button-group">
            <button
              phx-click={show_modal("##{@form.id}-#{@key}-icon")}
              class="secondary"
              type="button"
            >
              Edit icon
            </button>
          </div>
        <% end %>

        <Content.modal title="Edit icon" id={"#{@form.id}-#{@key}-icon"}>
          <Input.code id={"#{@form.id}-svg"} field={@form[:svg]} label={gettext("SVG")} />
        </Content.modal>

        <Content.modal title="Create ref" id={"#{@form.id}-#{@key}-create-ref"} narrow>
          <div class="button-group">
            <button
              type="button"
              phx-click={
                @create_ref
                |> hide_modal("##{@form.id}-#{@key}-create-ref")
                |> show_modal("##{@form.id}-#{@key}-ref-0")
              }
              phx-value-type="text"
              class="secondary"
            >
              Text
            </button>
            <button
              type="button"
              phx-click={
                @create_ref
                |> hide_modal("##{@form.id}-#{@key}-create-ref")
                |> show_modal("##{@form.id}-#{@key}-ref-0")
              }
              phx-value-type="header"
              class="secondary"
            >
              Header
            </button>
            <button
              type="button"
              phx-click={
                @create_ref
                |> hide_modal("##{@form.id}-#{@key}-create-ref")
                |> show_modal("##{@form.id}-#{@key}-ref-0")
              }
              phx-value-type="picture"
              class="secondary"
            >
              Picture
            </button>
            <button
              type="button"
              phx-click={
                @create_ref
                |> hide_modal("##{@form.id}-#{@key}-create-ref")
                |> show_modal("##{@form.id}-#{@key}-ref-0")
              }
              phx-value-type="gallery"
              class="secondary"
            >
              Gallery
            </button>
            <button
              type="button"
              phx-click={
                @create_ref
                |> hide_modal("##{@form.id}-#{@key}-create-ref")
                |> show_modal("##{@form.id}-#{@key}-ref-0")
              }
              phx-value-type="video"
              class="secondary"
            >
              Video
            </button>
            <button
              type="button"
              phx-click={
                @create_ref
                |> hide_modal("##{@form.id}-#{@key}-create-ref")
                |> show_modal("##{@form.id}-#{@key}-ref-0")
              }
              phx-value-type="media"
              class="secondary"
            >
              Media
            </button>

            <button
              type="button"
              phx-click={
                @create_ref
                |> hide_modal("##{@form.id}-#{@key}-create-ref")
                |> show_modal("##{@form.id}-#{@key}-ref-0")
              }
              phx-value-type="html"
              class="secondary"
            >
              HTML
            </button>

            <button
              type="button"
              phx-click={
                @create_ref
                |> hide_modal("##{@form.id}-#{@key}-create-ref")
                |> show_modal("##{@form.id}-#{@key}-ref-0")
              }
              phx-value-type="svg"
              class="secondary"
            >
              SVG
            </button>

            <button
              type="button"
              phx-click={
                @create_ref
                |> hide_modal("##{@form.id}-#{@key}-create-ref")
                |> show_modal("##{@form.id}-#{@key}-ref-0")
              }
              phx-value-type="markdown"
              class="secondary"
            >
              Markdown
            </button>

            <button
              type="button"
              phx-click={
                @create_ref
                |> hide_modal("##{@form.id}-#{@key}-create-ref")
                |> show_modal("##{@form.id}-#{@key}-ref-0")
              }
              phx-value-type="map"
              class="secondary"
            >
              Map
            </button>

            <button
              type="button"
              phx-click={
                @create_ref
                |> hide_modal("##{@form.id}-#{@key}-create-ref")
                |> show_modal("##{@form.id}-#{@key}-ref-0")
              }
              phx-value-type="comment"
              class="secondary"
            >
              Comment
            </button>
          </div>
        </Content.modal>

        <div class="refs">
          <h2>
            <div class="header-spread">REFs</div>
            <button
              phx-click={show_modal("##{@form.id}-#{@key}-create-ref")}
              type="button"
              class="circle"
            >
              <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="18" height="18">
                <path fill="none" d="M0 0h24v24H0z" /><path d="M11 11V5h2v6h6v2h-6v6h-2v-6H5v-2z" />
              </svg>
            </button>
          </h2>

          <ul>
            <input type="hidden" name={@form[:refs].name} value="" />
            <.inputs_for :let={ref} field={@form[:refs]}>
              <li class="padded">
                <Form.inputs_for_block :let={ref_data} field={ref[:data]}>
                  <div>
                    <span class="text-mono"><%= ref_data[:type].value %></span>
                    <span class="text-mono">- %&lcub;<%= ref[:name].value %>&rcub;</span>
                  </div>

                  <div class="actions">
                    <button
                      class="tiny"
                      type="button"
                      phx-click={show_modal("##{@form.id}-#{@key}-ref-#{ref.index}")}
                    >
                      <.icon name="hero-pencil" />
                    </button>
                    <button
                      class="tiny"
                      type="button"
                      phx-click={@duplicate_ref}
                      phx-value-id={ref[:name].value}
                    >
                      <.icon name="hero-document-duplicate" />
                    </button>
                    <button
                      class="tiny"
                      type="button"
                      phx-click={@delete_ref}
                      phx-value-id={ref[:name].value}
                    >
                      <.icon name="hero-x-mark" />
                    </button>
                  </div>
                </Form.inputs_for_block>

                <Content.modal title="Edit ref" id={"#{@form.id}-#{@key}-ref-#{ref.index}"} wide>
                  <div class="panels">
                    <Form.inputs_for_block :let={ref_data} field={ref[:data]}>
                      <Input.input type={:hidden} field={ref_data[:type]} />
                      <div class="panel">
                        <h2 class="titlecase">Block template</h2>
                        <%= case ref_data[:type].value do %>
                          <% "header" -> %>
                            <Form.inputs_for_block :let={block_data} field={ref_data[:data]}>
                              <Input.text field={block_data[:level]} label={gettext("Level")} />
                              <Input.text field={block_data[:text]} label={gettext("Text")} />
                              <Input.text field={block_data[:id]} label={gettext("ID")} />
                              <Input.text field={block_data[:link]} label={gettext("Link")} />
                            </Form.inputs_for_block>
                          <% "comment" -> %>
                            <Form.inputs_for_block :let={block_data} field={ref_data[:data]}>
                              <Input.code
                                id={"#{@form.id}-ref-#{@key}-#{ref[:name].value}-comment-text"}
                                field={block_data[:text]}
                                label={gettext("Text")}
                              />
                            </Form.inputs_for_block>
                          <% "html" -> %>
                            <Form.inputs_for_block :let={block_data} field={ref_data[:data]}>
                              <Input.code
                                id={"#{@form.id}-ref-#{@key}-#{ref[:name].value}-html-code"}
                                field={block_data[:text]}
                                label={gettext("HTML")}
                              />
                            </Form.inputs_for_block>
                          <% "markdown" -> %>
                            <Form.inputs_for_block :let={block_data} field={ref_data[:data]}>
                              <Input.code
                                id={"#{@form.id}-ref-#{@key}-#{ref[:name].value}-markdown-code"}
                                field={block_data[:text]}
                                label={gettext("Markdown")}
                              />
                            </Form.inputs_for_block>
                          <% "map" -> %>
                            <Form.inputs_for_block :let={block_data} field={ref_data[:data]}>
                              <Input.radios
                                field={block_data[:source]}
                                opts={[
                                  options: [
                                    %{label: gettext("GMaps"), value: :gmaps}
                                  ]
                                ]}
                                label={gettext("Source")}
                              />
                              <Input.text field={block_data[:embed_url]} label={gettext("Embed URL")} />
                            </Form.inputs_for_block>
                          <% "svg" -> %>
                            <Form.inputs_for_block :let={block_data} field={ref_data[:data]}>
                              <Input.text field={block_data[:class]} label={gettext("Class")} />
                              <Input.code
                                id={"#{@form.id}-ref-#{@key}-#{ref[:name].value}-svg-code"}
                                field={block_data[:code]}
                                label={gettext("Code")}
                              />
                            </Form.inputs_for_block>
                          <% "text" -> %>
                            <Form.inputs_for_block :let={block_data} field={ref_data[:data]}>
                              <Input.text field={block_data[:text]} label={gettext("Text")} />
                              <Input.text field={block_data[:type]} label={gettext("Type")} />
                              <.live_component
                                module={Input.MultiSelect}
                                id={"#{@form.id}-ref-#{@key}-#{ref[:name].value}-extensions"}
                                label={gettext("Extensions")}
                                field={block_data[:extensions]}
                                opts={[
                                  options: [
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
                                    %{label: "Superscript", value: "sup"}
                                  ]
                                ]}
                              />
                              <br />

                              <%= block_data[:extensions].value %>
                            </Form.inputs_for_block>
                          <% "picture" -> %>
                            <Form.inputs_for_block :let={block_data} field={ref_data[:data]}>
                              <Input.input type={:hidden} field={block_data[:cdn]} />
                              <Input.toggle field={block_data[:lazyload]} label={gettext("Lazyload")} />
                              <Input.toggle field={block_data[:moonwalk]} label={gettext("Moonwalk")} />
                              <Input.text field={block_data[:title]} label={gettext("Title/Caption")} />
                              <Input.text field={block_data[:alt]} label={gettext("Alt. text")} />
                              <Input.text field={block_data[:credits]} label={gettext("Credits")} />
                              <Input.text field={block_data[:link]} label={gettext("Link")} />
                              <Input.text
                                field={block_data[:picture_class]}
                                label={gettext("Picture class(es)")}
                              />
                              <Input.text
                                field={block_data[:img_class]}
                                label={gettext("Img class(es)")}
                              />
                              <.live_component
                                module={Input.Select}
                                id={"#{@form.id}-ref-#{@key}-#{ref[:name].value}-placeholder"}
                                field={block_data[:placeholder]}
                                opts={[
                                  options: [
                                    %{label: "SVG", value: :svg},
                                    %{label: "Dominant Color", value: :dominant_color},
                                    %{label: "Dominant Color Faded", value: :dominant_color_faded},
                                    %{label: "Micro", value: :micro},
                                    %{label: "None", value: :none}
                                  ]
                                ]}
                              />
                              <Form.array_inputs_from_data
                                :let={
                                  %{
                                    id: array_id,
                                    value: array_value,
                                    label: array_label,
                                    name: array_name,
                                    checked: checked
                                  }
                                }
                                field={block_data[:formats]}
                                options={[
                                  %{label: "Original", value: "original"},
                                  %{label: "jpg", value: "jpg"},
                                  %{label: "png", value: "png"},
                                  %{label: "webp", value: "webp"},
                                  %{label: "avif", value: "avif"}
                                ]}
                              >
                                <div class="field-wrapper compact">
                                  <div class="check-wrapper small">
                                    <input
                                      type="checkbox"
                                      id={array_id}
                                      name={array_name}
                                      value={array_value}
                                      checked={checked}
                                    />
                                    <label class="control-label small" for={array_id}>
                                      <%= array_label %>
                                    </label>
                                  </div>
                                </div>
                              </Form.array_inputs_from_data>
                              <Input.text
                                field={block_data[:config_target]}
                                label={gettext("Config target")}
                                instructions={
                                  gettext("i.e: `image:Elixir.MyApp.Schema:function:fn_name`")
                                }
                                monospace
                              />
                            </Form.inputs_for_block>
                          <% "gallery" -> %>
                            <Form.inputs_for_block :let={block_data} field={ref_data[:data]}>
                              <Input.radios
                                field={block_data[:type]}
                                label={gettext("Type")}
                                opts={[
                                  options: [
                                    %{label: gettext("Gallery"), value: :gallery},
                                    %{label: gettext("Slider"), value: :slider},
                                    %{label: gettext("Slideshow"), value: :slideshow}
                                  ]
                                ]}
                              />
                              <Input.radios
                                field={block_data[:display]}
                                label={gettext("Display")}
                                opts={[
                                  options: [
                                    %{label: gettext("Grid"), value: :grid},
                                    %{label: gettext("List"), value: :list}
                                  ]
                                ]}
                              />
                              <Input.text field={block_data[:class]} label={gettext("Class")} />
                              <Input.text
                                field={block_data[:series_slug]}
                                label={gettext("Series slug")}
                              />
                              <Input.toggle field={block_data[:lightbox]} label={gettext("Lightbox")} />
                              <Input.radios
                                field={block_data[:placeholder]}
                                label={gettext("Placeholder")}
                                opts={[
                                  options: [
                                    %{label: gettext("Dominant color"), value: "dominant_color"},
                                    %{
                                      label: gettext("Dominant color faded"),
                                      value: "dominant_color_faded"
                                    },
                                    %{label: gettext("SVG"), value: "svg"},
                                    %{label: gettext("Micro"), value: "micro"},
                                    %{label: gettext("None"), value: "none"}
                                  ]
                                ]}
                              />

                              <Form.array_inputs_from_data
                                :let={
                                  %{
                                    id: array_id,
                                    value: array_value,
                                    label: array_label,
                                    name: array_name,
                                    checked: checked
                                  }
                                }
                                field={block_data[:formats]}
                                options={[
                                  %{label: "Original", value: "original"},
                                  %{label: "jpg", value: "jpg"},
                                  %{label: "png", value: "png"},
                                  %{label: "webp", value: "webp"},
                                  %{label: "avif", value: "avif"}
                                ]}
                              >
                                <div class="field-wrapper compact">
                                  <div class="check-wrapper small">
                                    <input
                                      type="checkbox"
                                      id={array_id}
                                      name={array_name}
                                      value={array_value}
                                      checked={checked}
                                    />
                                    <label class="control-label small" for={array_id}>
                                      <%= array_label %>
                                    </label>
                                  </div>
                                </div>
                              </Form.array_inputs_from_data>
                            </Form.inputs_for_block>
                          <% "video" -> %>
                            <Form.inputs_for_block :let={block_data} field={ref_data[:data]}>
                              <Input.text field={block_data[:url]} label={gettext("URL")} />
                              <Input.radios
                                field={block_data[:source]}
                                label={gettext("Source")}
                                opts={[
                                  options: [
                                    %{label: "YouTube", value: "youtube"},
                                    %{label: "Vimeo", value: "vimeo"},
                                    %{label: "File", value: "file"}
                                  ]
                                ]}
                              />
                              <Input.input type={:hidden} field={block_data[:width]} />
                              <Input.input type={:hidden} field={block_data[:height]} />
                              <Input.text field={block_data[:remote_id]} label={gettext("Remote ID")} />
                              <Input.text field={block_data[:poster]} label={gettext("Poster")} />
                              <Input.text field={block_data[:cover]} label={gettext("Cover")} />
                              <Input.number field={block_data[:opacity]} label={gettext("Opacity")} />
                              <Input.toggle field={block_data[:autoplay]} label={gettext("Autoplay")} />
                              <Input.toggle field={block_data[:preload]} label={gettext("Preload")} />
                              <Input.toggle
                                field={block_data[:play_button]}
                                label={gettext("Play button")}
                              />
                            </Form.inputs_for_block>
                          <% "media" -> %>
                            <Form.inputs_for_block :let={block_data} field={ref_data[:data]}>
                              <Form.array_inputs_from_data
                                :let={
                                  %{
                                    id: array_id,
                                    value: array_value,
                                    label: array_label,
                                    name: array_name,
                                    checked: checked
                                  }
                                }
                                field={block_data[:available_blocks]}
                                options={[
                                  %{label: gettext("Picture"), value: "picture"},
                                  %{label: gettext("Video"), value: "video"},
                                  %{label: gettext("Gallery"), value: "gallery"},
                                  %{label: gettext("SVG"), value: "svg"}
                                ]}
                              >
                                <div class="field-wrapper compact">
                                  <div class="check-wrapper small">
                                    <input
                                      type="checkbox"
                                      id={array_id}
                                      name={array_name}
                                      value={array_value}
                                      checked={checked}
                                    />
                                    <label class="control-label small" for={array_id}>
                                      <%= array_label %>
                                    </label>
                                  </div>
                                </div>
                              </Form.array_inputs_from_data>

                              <%= if "picture" in block_data[:available_blocks].value do %>
                                <h2>Picture block template</h2>
                                <.inputs_for :let={tpl_data} field={block_data[:template_picture]}>
                                  <Input.toggle
                                    field={tpl_data[:lazyload]}
                                    label={gettext("Lazyload")}
                                  />
                                  <Input.toggle
                                    field={tpl_data[:moonwalk]}
                                    label={gettext("Moonwalk")}
                                  />
                                  <Input.text
                                    field={tpl_data[:picture_class]}
                                    label={gettext("Picture class")}
                                  />
                                  <Input.text
                                    field={tpl_data[:img_class]}
                                    label={gettext("Image class")}
                                  />
                                  <.live_component
                                    module={Input.Select}
                                    id={"#{@form.id}-ref-#{@key}-#{ref[:name].value}-tpl-placeholder"}
                                    field={tpl_data[:placeholder]}
                                    label={gettext("Placeholder")}
                                    opts={[
                                      options: [
                                        %{label: "SVG", value: :svg},
                                        %{label: "Dominant Color", value: :dominant_color},
                                        %{
                                          label: "Dominant Color faded",
                                          value: :dominant_color_faded
                                        },
                                        %{label: "Micro", value: :micro},
                                        %{label: "None", value: :none}
                                      ]
                                    ]}
                                  />

                                  <Form.array_inputs_from_data
                                    :let={
                                      %{
                                        id: array_id,
                                        value: array_value,
                                        label: array_label,
                                        name: array_name,
                                        checked: checked
                                      }
                                    }
                                    field={tpl_data[:formats]}
                                    options={[
                                      %{label: "Original", value: "original"},
                                      %{label: "jpg", value: "jpg"},
                                      %{label: "png", value: "png"},
                                      %{label: "webp", value: "webp"},
                                      %{label: "avif", value: "avif"}
                                    ]}
                                  >
                                    <div class="field-wrapper compact">
                                      <div class="check-wrapper small">
                                        <input
                                          type="checkbox"
                                          id={array_id}
                                          name={array_name}
                                          value={array_value}
                                          checked={checked}
                                        />
                                        <label class="control-label small" for={array_id}>
                                          <%= array_label %>
                                        </label>
                                      </div>
                                    </div>
                                  </Form.array_inputs_from_data>
                                  <Input.text
                                    field={tpl_data[:config_target]}
                                    label={gettext("Config target")}
                                    instructions={
                                      gettext("i.e: `image:Elixir.MyApp.Schema:function:fn_name`")
                                    }
                                    monospace
                                  />
                                </.inputs_for>
                              <% end %>

                              <%= if "video" in block_data[:available_blocks].value do %>
                                <h2>Video block template</h2>
                                <.inputs_for :let={tpl_data} field={block_data[:template_video]}>
                                  <Input.number field={tpl_data[:opacity]} label={gettext("Opacity")} />
                                  <Input.toggle
                                    field={tpl_data[:autoplay]}
                                    label={gettext("Autoplay")}
                                  />
                                  <Input.toggle field={tpl_data[:preload]} label={gettext("Preload")} />
                                  <Input.toggle
                                    field={tpl_data[:play_button]}
                                    label={gettext("Play button")}
                                  />
                                </.inputs_for>
                              <% end %>

                              <%= if "gallery" in block_data[:available_blocks].value do %>
                                <h2>Gallery block template</h2>
                                <.inputs_for :let={tpl_data} field={block_data[:template_gallery]}>
                                  <Input.radios
                                    field={tpl_data[:type]}
                                    label={gettext("Type")}
                                    opts={[
                                      options: [
                                        %{label: "Gallery", value: :gallery},
                                        %{label: "Slider", value: :slider},
                                        %{label: "Slideshow", value: :slideshow}
                                      ]
                                    ]}
                                  />
                                  <Input.radios
                                    field={tpl_data[:display]}
                                    label={gettext("Display")}
                                    opts={[
                                      options: [
                                        %{label: "Grid", value: :grid},
                                        %{label: "List", value: :list}
                                      ]
                                    ]}
                                  />
                                  <Input.text field={tpl_data[:class]} label={gettext("Class")} />
                                  <Input.text
                                    field={tpl_data[:series_slug]}
                                    label={gettext("Series slug")}
                                  />
                                  <Input.toggle
                                    field={tpl_data[:lightbox]}
                                    label={gettext("Lightbox")}
                                  />
                                  <Input.radios
                                    field={tpl_data[:placeholder]}
                                    opts={[
                                      options: [
                                        %{label: "Dominant color", value: "dominant_color"},
                                        %{
                                          label: "Dominant color faded",
                                          value: "dominant_color_faded"
                                        },
                                        %{label: "SVG", value: "svg"},
                                        %{label: "Micro", value: "micro"},
                                        %{label: "None", value: "none"}
                                      ]
                                    ]}
                                  />

                                  <Form.array_inputs_from_data
                                    :let={
                                      %{
                                        id: array_id,
                                        value: array_value,
                                        label: array_label,
                                        name: array_name,
                                        checked: checked
                                      }
                                    }
                                    field={tpl_data[:formats]}
                                    options={[
                                      %{label: "Original", value: "original"},
                                      %{label: "jpg", value: "jpg"},
                                      %{label: "png", value: "png"},
                                      %{label: "webp", value: "webp"},
                                      %{label: "avif", value: "avif"}
                                    ]}
                                  >
                                    <div class="field-wrapper compact">
                                      <div class="check-wrapper small">
                                        <input
                                          type="checkbox"
                                          id={array_id}
                                          name={array_name}
                                          value={array_value}
                                          checked={checked}
                                        />
                                        <label class="control-label small" for={array_id}>
                                          <%= array_label %>
                                        </label>
                                      </div>
                                    </div>
                                  </Form.array_inputs_from_data>
                                </.inputs_for>
                              <% end %>

                              <%= if "svg" in block_data[:available_blocks].value do %>
                                <h2>SVG block template</h2>
                                <.inputs_for :let={tpl_data} field={block_data[:template_svg]}>
                                  <Input.text field={tpl_data[:class]} label={gettext("Class")} />
                                </.inputs_for>
                              <% end %>
                            </Form.inputs_for_block>
                          <% "datasource" -> %>
                            <Form.inputs_for_block :let={block_data} field={ref_data[:data]}>
                              <Input.text
                                field={block_data[:description]}
                                label={gettext("Description")}
                              />
                              <Input.text field={block_data[:arg]} label={gettext("Arg")} />
                              <Input.text field={block_data[:limit]} label={gettext("Limit")} />
                            </Form.inputs_for_block>
                          <% type -> %>
                            No matching block <%= type %> found
                        <% end %>
                      </div>

                      <div class="panel">
                        <h2 class="titlecase">Ref config — <%= ref_data[:type].value %></h2>
                        <Input.text field={ref[:name]} label={gettext("Name")} />
                        <Input.text field={ref[:description]} label={gettext("Description")} />
                        <Input.input
                          type={:hidden}
                          field={ref_data[:uid]}
                          value={ref_data[:uid].value || Brando.Utils.generate_uid()}
                        />
                      </div>
                    </Form.inputs_for_block>
                  </div>
                </Content.modal>
              </li>
            </.inputs_for>
          </ul>
        </div>

        <Content.modal title={gettext("Create var")} id={"#{@form.id}-#{@key}-create-var"} narrow>
          <div class="button-group">
            <button
              type="button"
              phx-click={@create_var |> hide_modal("##{@form.id}-#{@key}-create-var")}
              phx-value-type="text"
              class="secondary"
            >
              Rich text
            </button>
            <button
              type="button"
              phx-click={@create_var |> hide_modal("##{@form.id}-#{@key}-create-var")}
              phx-value-type="string"
              class="secondary"
            >
              String
            </button>
            <button
              type="button"
              phx-click={@create_var |> hide_modal("##{@form.id}-#{@key}-create-var")}
              phx-value-type="image"
              class="secondary"
            >
              Image
            </button>
            <button
              type="button"
              phx-click={@create_var |> hide_modal("##{@form.id}-#{@key}-create-var")}
              phx-value-type="file"
              class="secondary"
            >
              File
            </button>

            <button
              type="button"
              phx-click={@create_var |> hide_modal("##{@form.id}-#{@key}-create-var")}
              phx-value-type="boolean"
              class="secondary"
            >
              Boolean
            </button>
            <button
              type="button"
              phx-click={@create_var |> hide_modal("##{@form.id}-#{@key}-create-var")}
              phx-value-type="select"
              class="secondary"
            >
              Select
            </button>
            <button
              type="button"
              phx-click={@create_var |> hide_modal("##{@form.id}-#{@key}-create-var")}
              phx-value-type="link"
              class="secondary"
            >
              Link
            </button>
            <button
              type="button"
              phx-click={@create_var |> hide_modal("##{@form.id}-#{@key}-create-var")}
              phx-value-type="datetime"
              class="secondary"
            >
              Datetime
            </button>
            <button
              type="button"
              phx-click={@create_var |> hide_modal("##{@form.id}-#{@key}-create-var")}
              phx-value-type="color"
              class="secondary"
            >
              Color
            </button>
            <button
              type="button"
              phx-click={@create_var |> hide_modal("##{@form.id}-#{@key}-create-var")}
              phx-value-type="html"
              class="secondary"
            >
              Html
            </button>
          </div>
        </Content.modal>

        <div class="vars">
          <h2>
            <div class="header-spread">Vars</div>
            <button
              phx-click={show_modal("##{@form.id}-#{@key}-create-var")}
              type="button"
              class="circle"
            >
              <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="18" height="18">
                <path fill="none" d="M0 0h24v24H0z" /><path d="M11 11V5h2v6h6v2h-6v6h-2v-6H5v-2z" />
              </svg>
            </button>
          </h2>
          <ul
            id={"#{@form.id}-vars-#{@key}-list"}
            phx-hook="Brando.SortableAssocs"
            data-sortable-id={"sortable-vars#{@entry_form && "-entry-form" || ""}"}
            data-sortable-selector=".var"
            data-sortable-handle=".sort-handle"
            data-sortable-dispatch-event="true"
          >
            <.inputs_for :let={var} field={@form[:vars]} skip_hidden>
              <Content.modal title={gettext("Edit var")} id={"#{@form.id}-#{@key}-var-#{var.index}"}>
                <.live_component
                  module={RenderVar}
                  id={"#{@form.id}-#{@key}-render-var-#{var.index}"}
                  var={var}
                  render={:all}
                  target={@myself}
                  edit
                />
                <!-- ^- had publish -->
              </Content.modal>
              <li class="var padded sort-handle draggable" data-id={var.index}>
                <input type="hidden" name={var[:id].name} value={var[:id].value} />
                <input type="hidden" name={var[:_persistent_id].name} value={var.index} />
                <input type="hidden" name={"#{@form.name}[sort_var_ids][]"} value={var.index} />

                <span class="text-mono">
                  <%= var[:type].value %> - &lcub;&lcub; <%= var[:key].value %> &rcub;&rcub;
                </span>
                <div class="actions">
                  <button
                    class="tiny"
                    type="button"
                    phx-click={show_modal("##{@form.id}-#{@key}-var-#{var.index}")}
                  >
                    <.icon name="hero-pencil" />
                  </button>
                  <button
                    class="tiny"
                    type="button"
                    phx-click={@duplicate_var}
                    phx-value-id={var[:key].value}
                  >
                    <.icon name="hero-document-duplicate" />
                  </button>
                  <button
                    class="tiny"
                    type="button"
                    phx-click={JS.dispatch("change")}
                    name={"#{@form.name}[drop_var_ids][]"}
                    value={var.index}
                  >
                    <.icon name="hero-x-mark" />
                  </button>
                </div>
              </li>
            </.inputs_for>
            <input type="hidden" name={"#{@form.name}[drop_var_ids][]"} />
          </ul>
        </div>

        <div class="datasource">
          <Input.toggle field={@form[:datasource]} label={gettext("Datasource")} />

          <%= if @datasource do %>
            <.live_component
              module={Input.Select}
              id={"#{@form.id}-datasource-module"}
              field={@form[:datasource_module]}
              opts={[options: @available_sources]}
            />

            <Input.radios
              field={@form[:datasource_type]}
              label={gettext("Type")}
              opts={[
                options: [
                  %{label: gettext("List"), value: :list},
                  %{label: gettext("Single"), value: :single},
                  %{label: gettext("Selection"), value: :selection}
                ]
              ]}
            />

            <.live_component
              if={@form[:datasource_module].value}
              module={Input.Select}
              id={"#{@form.id}-datasource-query"}
              field={@form[:datasource_query]}
              opts={[options: @available_queries]}
            />
          <% end %>
        </div>
      </div>
    </div>
    """
  end

  def assign_available_datasources(socket) do
    {:ok, available_sources} = Datasource.list_datasources()

    available_sources =
      Enum.map(
        available_sources,
        fn module_bin ->
          module = Module.concat(List.wrap(module_bin))
          domain = module.__naming__().domain
          schema = module.__naming__().schema

          gettext_module = module.__modules__().gettext
          gettext_domain = String.downcase("#{domain}_#{schema}")
          msgid = Brando.Utils.humanize(module.__naming__().singular, :downcase)

          %{
            label: String.capitalize(Gettext.dgettext(gettext_module, gettext_domain, msgid)),
            value: module_bin
          }
        end
      )

    assign(socket, :available_sources, available_sources)
  end

  def assign_available_queries(%{assigns: %{form: form}} = socket) do
    module = form[:datasource_module].value
    type = form[:datasource_type].value
    type = (is_binary(type) && String.to_existing_atom(type)) || type

    if module && type do
      {:ok, all_available_queries} = Datasource.list_datasource_keys(module)

      all_available_queries_by_type = Map.get(all_available_queries, type, [])

      available_queries_as_options =
        Enum.map(
          all_available_queries_by_type,
          &%{label: to_string(&1), value: &1}
        )

      assign(socket, :available_queries, available_queries_as_options)
    else
      assign(socket, :available_queries, [])
    end
  end

  def handle_event(
        "toggle_col_var",
        %{"id" => col_name},
        %{assigns: %{open_col_vars: open_col_vars}} = socket
      ) do
    updated_open_col_vars =
      if col_name in open_col_vars do
        Enum.reject(open_col_vars, &(&1 == col_name))
      else
        [col_name | open_col_vars]
      end

    {:noreply, assign(socket, :open_col_vars, updated_open_col_vars)}
  end

  def handle_event("add_select_var_option", %{"var_key" => var_key}, socket) do
    send(self(), {:add_select_var_option, var_key})
    {:noreply, socket}
  end
end
