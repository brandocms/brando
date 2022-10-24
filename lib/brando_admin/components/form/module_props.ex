defmodule BrandoAdmin.Components.Form.ModuleProps do
  use BrandoAdmin, :live_component
  use Phoenix.HTML
  import Brando.Gettext
  import BrandoAdmin.Components.Form.Input.Blocks.Utils
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

  # prop add_table_template, :event, required: true
  # prop add_table_row, :event, required: true
  # prop add_table_col, :event, required: true

  # data open_col_vars, :list

  def mount(socket) do
    {:ok,
     socket
     |> assign(open_col_vars: [], datasource: false)
     |> assign_new(:entry_form, fn -> false end)
     |> assign_new(:key, fn -> "default" end)
     |> assign_available_sources()}
  end

  def update(assigns, socket) do
    datasource = input_value(assigns.form, :datasource)

    {:ok,
     socket
     |> assign(assigns)
     |> assign(:datasource, datasource)
     |> assign_available_queries()}
  end

  def render(assigns) do
    ~H"""
    <div class="properties shaded">
      <div class="inner">
        <Input.text form={@form} field={:name} label={gettext "Name"} />
        <Input.text form={@form} field={:namespace} label={gettext "Namespace"} />
        <Input.textarea form={@form} field={:help_text} label={gettext "Help text"} />
        <Input.text form={@form} field={:class} label={gettext "Class"} />
        <Input.toggle form={@form} field={:wrapper} label={gettext "Wrapper"} />

        <%= if !@entry_form do %>
          <div class="button-group">
            <button
              phx-click={show_modal("##{@form.id}-#{@key}-icon")}
              class="secondary"
              type="button">
              Edit icon
            </button>
          </div>
        <% end %>

        <Content.modal title="Edit icon" id={"#{@form.id}-#{@key}-icon"}>
          <Input.code id={"#{@form.id}-svg"} form={@form} field={:svg} label={gettext "SVG"} />
        </Content.modal>

        <Content.modal title="Create ref" id={"#{@form.id}-#{@key}-create-ref"} narrow>
          <div class="button-group">
            <button
              type="button"
              phx-click={@create_ref |> hide_modal("##{@form.id}-#{@key}-create-ref") |> show_modal("##{@form.id}-#{@key}-ref-0")}
              phx-value-type="text"
              class="secondary">
              Text
            </button>
            <button
              type="button"
              phx-click={@create_ref |> hide_modal("##{@form.id}-#{@key}-create-ref") |> show_modal("##{@form.id}-#{@key}-ref-0")}
              phx-value-type="header"
              class="secondary">
              Header
            </button>
            <button
              type="button"
              phx-click={@create_ref |> hide_modal("##{@form.id}-#{@key}-create-ref") |> show_modal("##{@form.id}-#{@key}-ref-0")}
              phx-value-type="picture"
              class="secondary">
              Picture
            </button>
            <button
              type="button"
              phx-click={@create_ref |> hide_modal("##{@form.id}-#{@key}-create-ref") |> show_modal("##{@form.id}-#{@key}-ref-0")}
              phx-value-type="gallery"
              class="secondary">
              Gallery
            </button>
            <button
              type="button"
              phx-click={@create_ref |> hide_modal("##{@form.id}-#{@key}-create-ref") |> show_modal("##{@form.id}-#{@key}-ref-0")}
              phx-value-type="video"
              class="secondary">
              Video
            </button>
            <button
              type="button"
              phx-click={@create_ref |> hide_modal("##{@form.id}-#{@key}-create-ref") |> show_modal("##{@form.id}-#{@key}-ref-0")}
              phx-value-type="media"
              class="secondary">
              Media
            </button>

            <button
              type="button"
              phx-click={@create_ref |> hide_modal("##{@form.id}-#{@key}-create-ref") |> show_modal("##{@form.id}-#{@key}-ref-0")}
              phx-value-type="table"
              class="secondary">
              Table
            </button>

            <button
              type="button"
              phx-click={@create_ref |> hide_modal("##{@form.id}-#{@key}-create-ref") |> show_modal("##{@form.id}-#{@key}-ref-0")}
              phx-value-type="html"
              class="secondary">
              HTML
            </button>

            <button
              type="button"
              phx-click={@create_ref |> hide_modal("##{@form.id}-#{@key}-create-ref") |> show_modal("##{@form.id}-#{@key}-ref-0")}
              phx-value-type="svg"
              class="secondary">
              SVG
            </button>

            <button
              type="button"
              phx-click={@create_ref |> hide_modal("##{@form.id}-#{@key}-create-ref") |> show_modal("##{@form.id}-#{@key}-ref-0")}
              phx-value-type="markdown"
              class="secondary">
              Markdown
            </button>

            <button
              type="button"
              phx-click={@create_ref |> hide_modal("##{@form.id}-#{@key}-create-ref") |> show_modal("##{@form.id}-#{@key}-ref-0")}
              phx-value-type="map"
              class="secondary">
              Map
            </button>

            <button
              type="button"
              phx-click={@create_ref |> hide_modal("##{@form.id}-#{@key}-create-ref") |> show_modal("##{@form.id}-#{@key}-ref-0")}
              phx-value-type="comment"
              class="secondary">
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
              class="circle">
              <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="18" height="18"><path fill="none" d="M0 0h24v24H0z" /><path d="M11 11V5h2v6h6v2h-6v6h-2v-6H5v-2z" /></svg>
            </button>
          </h2>

          <ul>
            <Form.inputs form={@form} for={:refs} let={%{form: ref, index: idx}}>
              <li class="padded">
                <%= for ref_data <- inputs_for_block(ref, :data) do %>
                  <div>
                    <span class="text-mono"><%= input_value(ref_data, :type) %></span>
                    <span class="text-mono">- %&lcub;<%= input_value(ref, :name) %>&rcub;</span>
                  </div>
                  <div class="actions">
                    <button
                      class="tiny"
                      type="button"
                      phx-click={show_modal("##{@form.id}-#{@key}-ref-#{idx}")}>
                      <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="12" height="12"><path fill="none" d="M0 0h24v24H0z" /><path d="M6.414 16L16.556 5.858l-1.414-1.414L5 14.586V16h1.414zm.829 2H3v-4.243L14.435 2.322a1 1 0 0 1 1.414 0l2.829 2.829a1 1 0 0 1 0 1.414L7.243 18zM3 20h18v2H3v-2z" /></svg>
                    </button>
                    <button class="tiny" type="button" phx-click={@delete_ref} phx-value-id={input_value(ref, :name)}>
                      <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="12" height="12"><path fill="none" d="M0 0h24v24H0z" /><path d="M17 6h5v2h-2v13a1 1 0 0 1-1 1H5a1 1 0 0 1-1-1V8H2V6h5V3a1 1 0 0 1 1-1h8a1 1 0 0 1 1 1v3zm1 2H6v12h12V8zm-4.586 6l1.768 1.768-1.414 1.414L12 15.414l-1.768 1.768-1.414-1.414L10.586 14l-1.768-1.768 1.414-1.414L12 12.586l1.768-1.768 1.414 1.414L13.414 14zM9 4v2h6V4H9z" /></svg>
                    </button>
                  </div>
                <% end %>

                <Content.modal title="Edit ref" id={"#{@form.id}-#{@key}-ref-#{idx}"} wide>
                  <div class="panels">
                    <%= for ref_data <- inputs_for_block(ref, :data) do %>
                      <Input.input type={:hidden} form={ref_data} field={:type} value={input_value(ref_data, :type)} />
                      <div class="panel">
                        <h2 class="titlecase">Block template</h2>
                        <%= case input_value(ref_data, :type) do %>
                          <% "header" -> %>
                            <%= for block_data <- inputs_for_block(ref_data, :data) do %>
                              <Input.text form={block_data} field={:level} label={gettext "Level"} />
                              <Input.text form={block_data} field={:text} label={gettext "Text"} />
                              <Input.text form={block_data} field={:id} label={gettext "ID"} />
                              <Input.text form={block_data} field={:link} label={gettext "Link"} />

                            <% end %>

                          <% "svg" -> %>
                            <%= for block_data <- inputs_for_block(ref_data, :data) do %>
                              <Input.text form={block_data} field={:class} label={gettext "Class"} />
                              <Input.code
                                id={"#{@form.id}-ref-#{@key}-#{input_value(ref, :name)}-svg-code"}
                                form={block_data}
                                field={:code}
                                label={gettext "Code"}
                              />
                            <% end %>

                          <% "text" -> %>
                            <%= for block_data <- inputs_for_block(ref_data, :data) do %>
                              <Input.text form={block_data} field={:text} label={gettext "Text"} />
                              <Input.text form={block_data} field={:type} label={gettext "Type"} />
                              <.live_component module={Input.MultiSelect}
                                id={"#{@form.id}-ref-#{@key}-#{input_value(ref, :name)}-extensions"}
                                form={block_data}
                                label={gettext "Extensions"}
                                field={:extensions}
                                opts={[options: [
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
                                ]]}
                              />
                              <br>

                              <%= input_value(block_data, :extensions) %>
                            <% end %>

                          <% "picture" -> %>
                            <%= for block_data <- inputs_for_block(ref_data, :data) do %>
                              <Input.input type={:hidden} form={block_data} field={:cdn} />
                              <Input.toggle form={block_data} field={:lazyload} label={gettext "Lazyload"} />
                              <Input.toggle form={block_data} field={:moonwalk} label={gettext "Moonwalk"} />
                              <Input.text form={block_data} field={:title} label={gettext "Title/Caption"} />
                              <Input.text form={block_data} field={:alt} label={gettext "Alt. text"} />
                              <Input.text form={block_data} field={:credits} label={gettext "Credits"} />
                              <Input.text form={block_data} field={:link} label={gettext "Link"} />
                              <Input.text form={block_data} field={:picture_class} label={gettext "Picture class(es)"} />
                              <Input.text form={block_data} field={:img_class} label={gettext "Img class(es)"} />
                              <.live_component module={Input.Select}
                                id={"#{@form.id}-ref-#{@key}-#{input_value(ref, :name)}-placeholder"}
                                form={block_data}
                                field={:placeholder}
                                opts={[options: [
                                  %{label: "SVG", value: :svg},
                                  %{label: "Dominant Color", value: :dominant_color},
                                  %{label: "Micro", value: :micro},
                                  %{label: "None", value: :none}
                                ]]}
                              />
                              <Form.array_inputs_from_data
                                let={%{
                                  id: array_id,
                                  value: array_value,
                                  label: array_label,
                                  name: array_name,
                                  checked: checked
                                }}
                                form={block_data}
                                for={:formats}
                                options={[
                                  %{label: "Original", value: "original"},
                                  %{label: "jpg", value: "jpg"},
                                  %{label: "png", value: "png"},
                                  %{label: "webp", value: "webp"},
                                  %{label: "avif", value: "avif"},
                                ]}>
                                <div class="field-wrapper compact">
                                  <div class="check-wrapper small">
                                    <input type="checkbox" id={array_id} name={array_name} value={array_value} checked={checked} />
                                    <label class="control-label small" for={array_id}>
                                      <%= array_label %>
                                    </label>
                                  </div>
                                </div>
                              </Form.array_inputs_from_data>
                            <% end %>

                          <% "gallery" -> %>
                            <%= for block_data <- inputs_for_block(ref_data, :data) do %>
                              <Input.radios
                                form={block_data}
                                field={:type}
                                label={gettext "Type"}
                                opts={[options: [
                                  %{label: gettext("Gallery"), value: :gallery},
                                  %{label: gettext("Slider"), value: :slider},
                                  %{label: gettext("Slideshow"), value: :slideshow},
                                ]]} />
                              <Input.radios
                                form={block_data}
                                field={:display}
                                label={gettext "Display"}
                                opts={[options: [
                                  %{label: gettext("Grid"), value: :grid},
                                  %{label: gettext("List"), value: :list},
                                ]]} />
                              <Input.text form={block_data} field={:class} label={gettext "Class"} />
                              <Input.text form={block_data} field={:series_slug} label={gettext "Series slug"} />
                              <Input.toggle form={block_data} field={:lightbox} label={gettext "Lightbox"} />
                              <Input.radios
                                form={block_data}
                                field={:placeholder}
                                label={gettext "Placeholder"}
                                opts={[options: [
                                  %{label: gettext("Dominant color"), value: "dominant_color"},
                                  %{label: gettext("SVG"), value: "svg"},
                                  %{label: gettext("Micro"), value: "micro"},
                                  %{label: gettext("None"), value: "none"}
                                ]]}
                              />

                              <Form.array_inputs_from_data
                                let={%{
                                  id: array_id,
                                  value: array_value,
                                  label: array_label,
                                  name: array_name,
                                  checked: checked
                                }}
                                form={block_data}
                                for={:formats}
                                options={[
                                  %{label: "Original", value: "original"},
                                  %{label: "jpg", value: "jpg"},
                                  %{label: "png", value: "png"},
                                  %{label: "webp", value: "webp"},
                                  %{label: "avif", value: "avif"},
                                ]}>
                                <div class="field-wrapper compact">
                                  <div class="check-wrapper small">
                                    <input type="checkbox" id={array_id} name={array_name} value={array_value} checked={checked} />
                                    <label class="control-label small" for={array_id}><%= array_label %></label>
                                  </div>
                                </div>
                              </Form.array_inputs_from_data>
                            <% end %>

                          <% "video" -> %>
                            <%= for block_data <- inputs_for_block(ref_data, :data) do %>
                              <Input.text form={block_data} field={:url} label={gettext "URL"} />
                              <Input.radios
                                form={block_data}
                                field={:source}
                                label={gettext "Source"}
                                opts={[options: [
                                  %{label: "YouTube", value: "youtube"},
                                  %{label: "Vimeo", value: "vimeo"},
                                  %{label: "File", value: "file"}
                                ]]}
                              />
                              <Input.input type={:hidden} form={block_data} field={:width} />
                              <Input.input type={:hidden} form={block_data} field={:height} />
                              <Input.text form={block_data} field={:remote_id} label={gettext "Remote ID"} />
                              <Input.text form={block_data} field={:poster} label={gettext "Poster"} />
                              <Input.text form={block_data} field={:cover} label={gettext "Cover"} />
                              <Input.number form={block_data} field={:opacity} label={gettext "Opacity"} />
                              <Input.toggle form={block_data} field={:autoplay} label={gettext "Autoplay"} />
                              <Input.toggle form={block_data} field={:preload} label={gettext "Preload"} />
                              <Input.toggle form={block_data} field={:play_button} label={gettext "Play button"} />
                            <% end %>

                          <% "media" -> %>
                            <%= for block_data <- inputs_for_block(ref_data, :data) do %>
                              <Form.array_inputs_from_data
                                let={%{
                                  id: array_id,
                                  value: array_value,
                                  label: array_label,
                                  name: array_name,
                                  checked: checked
                                }}
                                form={block_data}
                                for={:available_blocks}
                                options={[
                                  %{label: gettext("Picture"), value: "picture"},
                                  %{label: gettext("Video"), value: "video"},
                                  %{label: gettext("Gallery"), value: "gallery"},
                                  %{label: gettext("SVG"), value: "svg"}
                                ]}>
                                <div class="field-wrapper compact">
                                  <div class="check-wrapper small">
                                    <input type="checkbox" id={array_id} name={array_name} value={array_value} checked={checked} />
                                    <label class="control-label small" for={array_id}>
                                      <%= array_label %>
                                    </label>
                                  </div>
                                </div>
                              </Form.array_inputs_from_data>

                              <%= if "picture" in input_value(block_data, :available_blocks) do %>
                                <h2>Picture block template</h2>
                                <%= for tpl_data <- inputs_for(block_data, :template_picture) do %>
                                  <Input.toggle form={tpl_data} field={:lazyload} label={gettext "Lazyload"} />
                                  <Input.toggle form={tpl_data} field={:moonwalk} label={gettext "Moonwalk"} />
                                  <Input.text form={tpl_data} field={:picture_class} label={gettext "Picture class"} />
                                  <Input.text form={tpl_data} field={:img_class} label={gettext "Image class"} />
                                  <.live_component module={Input.Select}
                                    id={"#{@form.id}-ref-#{@key}-#{input_value(ref, :name)}-tpl-placeholder"}
                                    form={tpl_data}
                                    field={:placeholder}
                                    label={gettext "Placeholder"}
                                    opts={[options: [
                                      %{label: "SVG", value: :svg},
                                      %{label: "Dominant Color", value: :dominant_color},
                                      %{label: "Micro", value: :micro},
                                      %{label: "None", value: :none}
                                    ]]}
                                  />

                                  <Form.array_inputs_from_data
                                    let={%{id: array_id, value: array_value, label: array_label, name: array_name, checked: checked}}
                                    form={tpl_data}
                                    for={:formats}
                                    options={[
                                      %{label: "Original", value: "original"},
                                      %{label: "jpg", value: "jpg"},
                                      %{label: "png", value: "png"},
                                      %{label: "webp", value: "webp"},
                                      %{label: "avif", value: "avif"},
                                    ]}>
                                    <div class="field-wrapper compact">
                                      <div class="check-wrapper small">
                                        <input type="checkbox" id={array_id} name={array_name} value={array_value} checked={checked} />
                                        <label class="control-label small" for={array_id}><%= array_label %></label>
                                      </div>
                                    </div>
                                  </Form.array_inputs_from_data>
                                <% end %>
                              <% end %>

                              <%= if "video" in input_value(block_data, :available_blocks) do %>
                                <h2>Video block template</h2>
                                <%= for tpl_data <- inputs_for(block_data, :template_video) do %>
                                  <Input.number form={tpl_data} field={:opacity} label={gettext "Opacity"} />
                                  <Input.toggle form={tpl_data} field={:autoplay} label={gettext "Autoplay"} />
                                  <Input.toggle form={tpl_data} field={:preload} label={gettext "Preload"} />
                                  <Input.toggle form={tpl_data} field={:play_button} label={gettext "Play button"} />
                                <% end %>
                              <% end %>

                              <%= if "gallery" in input_value(block_data, :available_blocks) do %>
                                <h2>Gallery block template</h2>
                                <%= for tpl_data <- inputs_for(block_data, :template_gallery) do %>
                                  <Input.radios
                                    form={tpl_data}
                                    field={:type}
                                    label={gettext "Type"}
                                    opts={[options: [
                                      %{label: "Gallery", value: :gallery},
                                      %{label: "Slider", value: :slider},
                                      %{label: "Slideshow", value: :slideshow},
                                    ]]} />
                                  <Input.radios
                                    form={tpl_data}
                                    field={:display}
                                    label={gettext "Display"}
                                    opts={[options: [
                                      %{label: "Grid", value: :grid},
                                      %{label: "List", value: :list},
                                    ]]} />
                                  <Input.text form={tpl_data} field={:class} label={gettext "Class"} />
                                  <Input.text form={tpl_data} field={:series_slug} label={gettext "Series slug"} />
                                  <Input.toggle form={tpl_data} field={:lightbox} label={gettext "Lightbox"} />
                                  <Input.radios
                                    form={tpl_data}
                                    field={:placeholder}
                                    opts={[options: [
                                      %{label: "Dominant color", value: "dominant_color"},
                                      %{label: "SVG", value: "svg"},
                                      %{label: "Micro", value: "micro"},
                                      %{label: "None", value: "none"}
                                    ]]}
                                  />

                                  <Form.array_inputs_from_data
                                    let={%{id: array_id, value: array_value, label: array_label, name: array_name, checked: checked}}
                                    form={tpl_data}
                                    for={:formats}
                                    options={[
                                      %{label: "Original", value: "original"},
                                      %{label: "jpg", value: "jpg"},
                                      %{label: "png", value: "png"},
                                      %{label: "webp", value: "webp"},
                                      %{label: "avif", value: "avif"},
                                    ]}>
                                    <div class="field-wrapper compact">
                                      <div class="check-wrapper small">
                                        <input type="checkbox" id={array_id} name={array_name} value={array_value} checked={checked} />
                                        <label class="control-label small" for={array_id}><%= array_label %></label>
                                      </div>
                                    </div>
                                  </Form.array_inputs_from_data>
                                <% end %>
                              <% end %>

                              <%= if "svg" in input_value(block_data, :available_blocks) do %>
                                <h2>SVG block template</h2>
                                <%= for tpl_data <- inputs_for(block_data, :template_svg) do %>
                                  <Input.text form={tpl_data} field={:class} label={gettext "Class"} />
                                <% end %>
                              <% end %>

                            <% end %>

                          <% "datasource" -> %>
                            <%= for block_data <- inputs_for_block(ref_data, :data) do %>
                              <Input.text form={block_data} field={:description} label={gettext "Description"} />
                              <Input.text form={block_data} field={:arg} label={gettext "Arg"} />
                              <Input.text form={block_data} field={:limit} label={gettext "Limit"} />
                            <% end %>

                          <% "table" -> %>
                            <%= for block_data <- inputs_for_block(ref_data, :data) do %>
                              <Input.text form={block_data} field={:key} label={gettext "Key"} />
                              <Input.textarea form={block_data} field={:instructions} label={gettext "Instructions"} />

                              <%= for tpl_row <- inputs_for(block_data, :template_row) do %>
                                <%= if !input_value(tpl_row, :cols) do %>
                                  <button type="button" phx-click={@add_table_template} phx-value-id={input_value(ref, :name)}>Create table row template</button>
                                <% else %>
                                  <div
                                    id={"#{@form.id}-refs-#{@key}-table-cols"}
                                    class="col-vars"
                                    phx-hook="Brando.Sortable"
                                    data-sortable-id="sortable-table-cols"
                                    data-sortable-selector=".col-var"
                                    data-sortable-handle=".sort-handle"
                                    data-sortable-params={input_value(ref, :name)}>
                                    <Form.poly_inputs form={tpl_row} for={:cols} let={%{form: var, index: var_idx}}>
                                      <div class="col-var draggable" data-id={var_idx}>
                                        <div
                                          class="col-var-toggle"
                                          phx-click={JS.push("toggle_col_var", target: @myself)}
                                          phx-value-id={input_value(var, :key)}>
                                          <%= input_value(var, :type) %> — <%= input_value(var, :label) %>
                                          <div class="sort-handle">
                                            <svg width="15" height="15" viewBox="0 0 15 15" fill="none" xmlns="http://www.w3.org/2000/svg"><circle cx="1.5" cy="1.5" r="1.5"></circle><circle cx="7.5" cy="1.5" r="1.5"></circle><circle cx="13.5" cy="1.5" r="1.5"></circle><circle cx="1.5" cy="7.5" r="1.5"></circle><circle cx="7.5" cy="7.5" r="1.5"></circle><circle cx="13.5" cy="7.5" r="1.5"></circle><circle cx="1.5" cy="13.5" r="1.5"></circle><circle cx="7.5" cy="13.5" r="1.5"></circle><circle cx="13.5" cy="13.5" r="1.5"></circle></svg>
                                          </div>
                                        </div>
                                        <div class={render_classes([
                                          "col-var-form": true,
                                          hidden: input_value(var, :key) not in @open_col_vars
                                        ])}>
                                          <Input.input type={:hidden} form={var} field={:key} />
                                          <Input.input type={:hidden} form={var} field={:type} />
                                          <Input.input type={:hidden} form={var} field={:important} />
                                          <Input.text form={var} field={:label} label={gettext "Label"} />
                                          <Input.text form={var} field={:instructions} label={gettext "Instructions"} />
                                          <Input.text form={var} field={:placeholder} label={gettext "Placeholder"} />
                                          <%= case input_value(var, :type) do %>
                                            <% "text" -> %>
                                              <Input.text form={var} field={:value} label={gettext "Value"} />
                                            <% "string" -> %>
                                              <Input.text form={var} field={:value} label={gettext "Value"} />
                                            <% "boolean" -> %>
                                              <Input.toggle form={var} field={:value} label={gettext "Value"} />
                                            <% "datetime" -> %>
                                              <Input.datetime form={var} field={:value} label={gettext "Value"} />
                                            <% "html" -> %>
                                              <Input.rich_text form={var} field={:value} label={gettext "Value"} />
                                            <% "color" -> %>
                                              <!-- #TODO: Input.color -->
                                              <Input.text form={var} field={:value} label={gettext "Value"} />
                                            <% _ -> %>
                                              <Input.text form={var} field={:value} label={gettext "Value"} />
                                          <% end %>
                                        </div>
                                      </div>
                                    </Form.poly_inputs>
                                  </div>

                                  <%= for type <- ["string", "text", "html", "boolean", "datetime", "color"] do %>
                                    <button
                                      type="button"
                                      class="tiny"
                                      phx-click={@add_table_col}
                                      phx-value-id={input_value(ref, :name)}
                                      phx-value-type={type}>
                                      <%= type %>
                                    </button>
                                  <% end %>
                                <% end %>
                              <% end %>
                            <% end %>

                          <% type -> %>
                            No matching block <%= type %> found
                        <% end %>
                      </div>

                      <div class="panel">
                        <h2 class="titlecase">Ref config — <%= input_value(ref_data, :type) %></h2>
                        <Input.text form={ref} field={:name} label={gettext "Name"} />
                        <Input.text form={ref} field={:description} label={gettext "Description"} />
                        <Input.input type={:hidden} form={ref_data} field={:uid} value={input_value(ref_data, :uid) || Brando.Utils.generate_uid()} />
                      </div>
                    <% end %>
                  </div>
                </Content.modal>
              </li>
            </Form.inputs>
          </ul>
        </div>

        <Content.modal title={gettext "Create var"} id={"#{@form.id}-#{@key}-create-var"} narrow>
          <div class="button-group">
            <button
              type="button"
              phx-click={@create_var |> hide_modal("##{@form.id}-#{@key}-create-var")}
              phx-value-type="text"
              class="secondary">
              Text
            </button>
            <button
              type="button"
              phx-click={@create_var |> hide_modal("##{@form.id}-#{@key}-create-var")}
              phx-value-type="string"
              class="secondary">
              String
            </button>
            <button
              type="button"
              phx-click={@create_var |> hide_modal("##{@form.id}-#{@key}-create-var")}
              phx-value-type="html"
              class="secondary">
              Html
            </button>
            <button
              type="button"
              phx-click={@create_var |> hide_modal("##{@form.id}-#{@key}-create-var")}
              phx-value-type="datetime"
              class="secondary">
              Datetime
            </button>
            <button
              type="button"
              phx-click={@create_var |> hide_modal("##{@form.id}-#{@key}-create-var")}
              phx-value-type="boolean"
              class="secondary">
              Boolean
            </button>
            <button
              type="button"
              phx-click={@create_var |> hide_modal("##{@form.id}-#{@key}-create-var")}
              phx-value-type="select"
              class="secondary">
              Select
            </button>
            <button
              type="button"
              phx-click={@create_var |> hide_modal("##{@form.id}-#{@key}-create-var")}
              phx-value-type="color"
              class="secondary">
              Color
            </button>
            <button
              type="button"
              phx-click={@create_var |> hide_modal("##{@form.id}-#{@key}-create-var")}
              phx-value-type="image"
              class="secondary">
              Image
            </button>
          </div>
        </Content.modal>

        <div class="vars">
          <h2>
            <div class="header-spread">Vars</div>
            <button
              phx-click={show_modal("##{@form.id}-#{@key}-create-var")}
              type="button"
              class="circle">
              <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="18" height="18"><path fill="none" d="M0 0h24v24H0z" /><path d="M11 11V5h2v6h6v2h-6v6h-2v-6H5v-2z" /></svg>
            </button>
          </h2>
          <ul
            id={"#{@form.id}-vars-#{@key}-list"}
            phx-hook="Brando.Sortable"
            data-sortable-id={"sortable-vars#{@entry_form && "-entry-form" || ""}"}
            data-sortable-selector=".var"
            data-sortable-handle=".sort-handle">
            <Form.poly_inputs form={@form} for={:vars} let={%{form: var, index: idx}}>
              <li class="var padded sort-handle draggable" data-id={idx}>
                <Content.modal title={gettext("Edit var")} id={"#{@form.id}-#{@key}-var-#{idx}"}>
                  <.live_component module={RenderVar}
                    id={"#{@form.id}-#{@key}-render-var-#{idx}"}
                    var={var}
                    render={:all}
                    target={@myself}
                    edit />
                </Content.modal>
                <span class="text-mono"><%= input_value(var, :type) %> - &lcub;&lcub; <%= input_value(var, :key) %> &rcub;&rcub;</span>
                <div class="actions">
                  <button
                    class="tiny"
                    type="button"
                    phx-click={show_modal("##{@form.id}-#{@key}-var-#{idx}")}>
                    <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="12" height="12"><path fill="none" d="M0 0h24v24H0z" /><path d="M6.414 16L16.556 5.858l-1.414-1.414L5 14.586V16h1.414zm.829 2H3v-4.243L14.435 2.322a1 1 0 0 1 1.414 0l2.829 2.829a1 1 0 0 1 0 1.414L7.243 18zM3 20h18v2H3v-2z" /></svg>
                  </button>
                  <button class="tiny" type="button" phx-click={@delete_var} phx-value-id={input_value(var, :key)}>
                    <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="12" height="12"><path fill="none" d="M0 0h24v24H0z" /><path d="M17 6h5v2h-2v13a1 1 0 0 1-1 1H5a1 1 0 0 1-1-1V8H2V6h5V3a1 1 0 0 1 1-1h8a1 1 0 0 1 1 1v3zm1 2H6v12h12V8zm-4.586 6l1.768 1.768-1.414 1.414L12 15.414l-1.768 1.768-1.414-1.414L10.586 14l-1.768-1.768 1.414-1.414L12 12.586l1.768-1.768 1.414 1.414L13.414 14zM9 4v2h6V4H9z" /></svg>
                  </button>
                </div>
              </li>
            </Form.poly_inputs>
          </ul>
        </div>

        <div class="datasource">
          <Input.toggle form={@form} field={:datasource} label={gettext "Datasource"} />

          <%= if @datasource in [true, "true"] do %>
            <.live_component module={Input.Select}
              id={"#{@form.id}-datasource-module"}
              form={@form}
              field={:datasource_module}
              opts={[options: @available_sources]}
            />

            <Input.radios form={@form} field={:datasource_type} label={gettext "Type"} opts={[options: [
              %{label: gettext("List"), value: :list},
              %{label: gettext("Single"), value: :single},
              %{label: gettext("Selection"), value: :selection},
            ]]} />

            <.live_component module={Input.Select}
              id={"#{@form.id}-datasource-query"}
              form={@form}
              field={:datasource_query}
              opts={[options: @available_queries]}
            />
          <% end %>
        </div>
      </div>
    </div>
    """
  end

  def assign_available_sources(socket) do
    {:ok, available_sources} = Datasource.list_datasources()

    available_sources =
      Enum.map(
        available_sources,
        fn module_bin ->
          module = Module.concat(List.wrap(module_bin))
          domain = module.__naming__().domain
          schema = module.__naming__().schema

          gettext_module = module.__modules__().gettext
          gettext_domain = String.downcase("#{domain}_#{schema}_naming")
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
    module = input_value(form, :datasource_module)
    type = input_value(form, :datasource_type)
    type = (is_binary(type) && String.to_existing_atom(type)) || type

    if module && type do
      {:ok, all_available_queries} = Datasource.list_datasource_keys(module)

      all_available_queries_by_type = Map.get(all_available_queries, type, [])

      available_queries_as_options =
        Enum.map(all_available_queries_by_type, &%{label: to_string(&1), value: &1})

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
