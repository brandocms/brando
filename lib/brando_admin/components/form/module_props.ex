defmodule BrandoAdmin.Components.Form.ModuleProps do
  use BrandoAdmin, :live_component
  use Phoenix.HTML
  import Brando.Gettext
  import BrandoAdmin.Components.Form.Input.Blocks.Utils
  alias BrandoAdmin.Components.Form
  alias BrandoAdmin.Components.Form.Input
  alias BrandoAdmin.Components.Form.Input.RenderVar
  alias BrandoAdmin.Components.Modal

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
     |> assign(open_col_vars: [])
     |> assign_new(:entry_form, fn -> false end)
     |> assign_new(:key, fn -> "default" end)}
  end

  def render(assigns) do
    ~H"""
    <div class="properties shaded">
      <div class="inner">
        <Input.Text.render form={@form} field={:name} label={gettext "Name"} />
        <Input.Text.render form={@form} field={:namespace} label={gettext "Namespace"} />
        <Input.Textarea.render form={@form} field={:help_text} label={gettext "Help text"} />
        <Input.Text.render form={@form} field={:class} label={gettext "Class"} />
        <Input.Toggle.render form={@form} field={:wrapper} label={gettext "Wrapper"} />

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

        <.live_component module={Modal} title="Edit icon" id={"#{@form.id}-#{@key}-icon"}>
          <Input.Code.render id={"#{@form.id}-svg"} form={@form} field={:svg} label={gettext "SVG"} />
        </.live_component>

        <.live_component module={Modal} title="Create ref" id={"#{@form.id}-#{@key}-create-ref"} narrow>
          <div class="button-group">
            <button
              type="button"
              phx-click={@create_ref |> hide_modal("##{@form.id}-#{@key}-create-ref")}
              phx-value-type="text"
              class="secondary">
              Text
            </button>
            <button
              type="button"
              phx-click={@create_ref |> hide_modal("##{@form.id}-#{@key}-create-ref")}
              phx-value-type="header"
              class="secondary">
              Header
            </button>
            <button
              type="button"
              phx-click={@create_ref |> hide_modal("##{@form.id}-#{@key}-create-ref")}
              phx-value-type="picture"
              class="secondary">
              Picture
            </button>
            <button
              type="button"
              phx-click={@create_ref |> hide_modal("##{@form.id}-#{@key}-create-ref")}
              phx-value-type="gallery"
              class="secondary">
              Gallery
            </button>
            <button
              type="button"
              phx-click={@create_ref |> hide_modal("##{@form.id}-#{@key}-create-ref")}
              phx-value-type="video"
              class="secondary">
              Video
            </button>
            <button
              type="button"
              phx-click={@create_ref |> hide_modal("##{@form.id}-#{@key}-create-ref")}
              phx-value-type="media"
              class="secondary">
              Media
            </button>

            <button
              type="button"
              phx-click={@create_ref |> hide_modal("##{@form.id}-#{@key}-create-ref")}
              phx-value-type="table"
              class="secondary">
              Table
            </button>

            <button
              type="button"
              phx-click={@create_ref |> hide_modal("##{@form.id}-#{@key}-create-ref")}
              phx-value-type="html"
              class="secondary">
              HTML
            </button>

            <button
              type="button"
              phx-click={@create_ref |> hide_modal("##{@form.id}-#{@key}-create-ref")}
              phx-value-type="svg"
              class="secondary">
              SVG
            </button>

            <button
              type="button"
              phx-click={@create_ref |> hide_modal("##{@form.id}-#{@key}-create-ref")}
              phx-value-type="markdown"
              class="secondary">
              Markdown
            </button>

            <button
              type="button"
              phx-click={@create_ref |> hide_modal("##{@form.id}-#{@key}-create-ref")}
              phx-value-type="map"
              class="secondary">
              Map
            </button>

            <button
              type="button"
              phx-click={@create_ref |> hide_modal("##{@form.id}-#{@key}-create-ref")}
              phx-value-type="comment"
              class="secondary">
              Comment
            </button>

            <button
              type="button"
              phx-click={@create_ref |> hide_modal("##{@form.id}-#{@key}-create-ref")}
              phx-value-type="datasource"
              class="secondary">
              Datasource
            </button>
          </div>
        </.live_component>

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

                <.live_component module={Modal} title="Edit ref" id={"#{@form.id}-#{@key}-ref-#{idx}"} wide>
                  <div class="panels">
                    <%= for ref_data <- inputs_for_block(ref, :data) do %>
                      <%= hidden_input(ref_data, :type, value: input_value(ref_data, :type)) %>
                      <div class="panel">
                        <h2 class="titlecase">Block template</h2>
                        <%= case input_value(ref_data, :type) do %>
                          <% "header" -> %>
                            <%= for block_data <- inputs_for_block(ref_data, :data) do %>
                              <Input.Text.render form={block_data} field={:level} label={gettext "Level"} />
                              <Input.Text.render form={block_data} field={:text} label={gettext "Text"} />
                            <% end %>

                          <% "svg" -> %>
                            <%= for block_data <- inputs_for_block(ref_data, :data) do %>
                              <Input.Text.render form={block_data} field={:class} label={gettext "Class"} />
                              <Input.Code.render
                                id={"#{@form.id}-ref-#{@key}-#{input_value(ref, :name)}-svg-code"}
                                form={block_data}
                                field={:code}
                                label={gettext "Code"}
                              />
                            <% end %>

                          <% "text" -> %>
                            <%= for block_data <- inputs_for_block(ref_data, :data) do %>
                              <Input.Text.render form={block_data} field={:text} label={gettext "Text"} />
                              <Input.Text.render form={block_data} field={:type} label={gettext "Type"} />
                              <Input.Text.render form={block_data} field={:extensions} label={gettext "Extensions"} />
                            <% end %>

                          <% "picture" -> %>
                            <%= for block_data <- inputs_for_block(ref_data, :data) do %>
                              <%= hidden_input(block_data, :cdn) %>
                              <Input.Toggle.render form={block_data} field={:lazyload} label={gettext "Lazyload"} />
                              <Input.Toggle.render form={block_data} field={:moonwalk} label={gettext "Moonwalk"} />
                              <Input.Text.render form={block_data} field={:title} label={gettext "Title/Caption"} />
                              <Input.Text.render form={block_data} field={:alt} label={gettext "Alt. text"} />
                              <Input.Text.render form={block_data} field={:credits} label={gettext "Credits"} />
                              <Input.Text.render form={block_data} field={:link} label={gettext "Link"} />
                              <Input.Text.render form={block_data} field={:picture_class} label={gettext "Picture class(es)"} />
                              <Input.Text.render form={block_data} field={:img_class} label={gettext "Img class(es)"} />
                              <.live_component
                                module={Input.Select}
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
                              <Input.Radios.render
                                form={block_data}
                                field={:type}
                                label={gettext "Type"}
                                opts={[options: [
                                  %{label: gettext("Gallery"), value: :gallery},
                                  %{label: gettext("Slider"), value: :slider},
                                  %{label: gettext("Slideshow"), value: :slideshow},
                                ]]} />
                              <Input.Radios.render
                                form={block_data}
                                field={:display}
                                label={gettext "Display"}
                                opts={[options: [
                                  %{label: gettext("Grid"), value: :grid},
                                  %{label: gettext("List"), value: :list},
                                ]]} />
                              <Input.Text.render form={block_data} field={:class} label={gettext "Class"} />
                              <Input.Text.render form={block_data} field={:series_slug} label={gettext "Series slug"} />
                              <Input.Toggle.render form={block_data} field={:lightbox} label={gettext "Lightbox"} />
                              <Input.Radios.render
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
                              <Input.Text.render form={block_data} field={:url} label={gettext "URL"} />
                              <Input.Radios.render
                                form={block_data}
                                field={:source}
                                label={gettext "Source"}
                                opts={[options: [
                                  %{label: "YouTube", value: "youtube"},
                                  %{label: "Vimeo", value: "vimeo"},
                                  %{label: "File", value: "file"}
                                ]]}
                              />
                              <%= hidden_input(block_data, :width) %>
                              <%= hidden_input(block_data, :height) %>
                              <Input.Text.render form={block_data} field={:remote_id} label={gettext "Remote ID"} />
                              <Input.Text.render form={block_data} field={:poster} label={gettext "Poster"} />
                              <Input.Text.render form={block_data} field={:cover} label={gettext "Cover"} />
                              <Input.Number.render form={block_data} field={:opacity} label={gettext "Opacity"} />
                              <Input.Toggle.render form={block_data} field={:autoplay} label={gettext "Autoplay"} />
                              <Input.Toggle.render form={block_data} field={:preload} label={gettext "Preload"} />
                              <Input.Toggle.render form={block_data} field={:play_button} label={gettext "Play button"} />
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
                                  <Input.Text.render form={tpl_data} field={:picture_class} label={gettext "Picture class"} />
                                  <Input.Text.render form={tpl_data} field={:img_class} label={gettext "Image class"} />
                                  <.live_component
                                    module={Input.Select}
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
                                  <Input.Number.render form={tpl_data} field={:opacity} label={gettext "Opacity"} />
                                  <Input.Toggle.render form={tpl_data} field={:autoplay} label={gettext "Autoplay"} />
                                  <Input.Toggle.render form={tpl_data} field={:preload} label={gettext "Preload"} />
                                  <Input.Toggle.render form={tpl_data} field={:play_button} label={gettext "Play button"} />
                                <% end %>
                              <% end %>

                              <%= if "gallery" in input_value(block_data, :available_blocks) do %>
                                <h2>Gallery block template</h2>
                                <%= for tpl_data <- inputs_for(block_data, :template_gallery) do %>
                                  <Input.Radios.render
                                    form={tpl_data}
                                    field={:type}
                                    label={gettext "Type"}
                                    opts={[options: [
                                      %{label: "Gallery", value: :gallery},
                                      %{label: "Slider", value: :slider},
                                      %{label: "Slideshow", value: :slideshow},
                                    ]]} />
                                  <Input.Radios.render
                                    form={tpl_data}
                                    field={:display}
                                    label={gettext "Display"}
                                    opts={[options: [
                                      %{label: "Grid", value: :grid},
                                      %{label: "List", value: :list},
                                    ]]} />
                                  <Input.Text.render form={tpl_data} field={:class} label={gettext "Class"} />
                                  <Input.Text.render form={tpl_data} field={:series_slug} label={gettext "Series slug"} />
                                  <Input.Toggle.render form={tpl_data} field={:lightbox} label={gettext "Lightbox"} />
                                  <Input.Radios.render
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
                                  <Input.Text.render form={tpl_data} field={:class} label={gettext "Class"} />
                                <% end %>
                              <% end %>

                            <% end %>

                          <% "datasource" -> %>
                            <%= for block_data <- inputs_for_block(ref_data, :data) do %>
                              <Input.Text.render form={block_data} field={:description} label={gettext "Description"} />
                              <Input.Text.render form={block_data} field={:arg} label={gettext "Arg"} />
                              <Input.Text.render form={block_data} field={:limit} label={gettext "Limit"} />
                            <% end %>

                          <% "table" -> %>
                            <%= for block_data <- inputs_for_block(ref_data, :data) do %>
                              <Input.Text.render form={block_data} field={:key} label={gettext "Key"} />
                              <Input.Textarea.render form={block_data} field={:instructions} label={gettext "Instructions"} />

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
                                          <%= hidden_input var, :key %>
                                          <%= hidden_input var, :type %>
                                          <%= hidden_input var, :important %>
                                          <Input.Text.render form={var} field={:label} label={gettext "Label"} />
                                          <Input.Text.render form={var} field={:instructions} label={gettext "Instructions"} />
                                          <Input.Text.render form={var} field={:placeholder} label={gettext "Placeholder"} />
                                          <%= case input_value(var, :type) do %>
                                            <% "text" -> %>
                                              <Input.Text.render form={var} field={:value} label={gettext "Value"} />
                                            <% "string" -> %>
                                              <Input.Text.render form={var} field={:value} label={gettext "Value"} />
                                            <% "boolean" -> %>
                                              <Input.Toggle.render form={var} field={:value} label={gettext "Value"} />
                                            <% "datetime" -> %>
                                              <Input.Datetime.render form={var} field={:value} label={gettext "Value"} />
                                            <% "html" -> %>
                                              <Input.RichText.render form={var} field={:value} label={gettext "Value"} />
                                            <% "color" -> %>
                                              <!-- #TODO: Input.Color -->
                                              <Input.Text.render form={var} field={:value} label={gettext "Value"} />
                                            <% _ -> %>
                                              <Input.Text.render form={var} field={:value} label={gettext "Value"} />
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

                        <Input.Text.render form={ref} field={:name} label={gettext "Name"} />
                        <Input.Text.render form={ref} field={:description} label={gettext "Description"} />
                        <%= hidden_input(ref_data, :uid, value: input_value(ref_data, :uid) || Brando.Utils.generate_uid()) %>
                      </div>
                    <% end %>
                  </div>
                </.live_component>
              </li>
            </Form.inputs>
          </ul>
        </div>

        <.live_component module={Modal} title={gettext "Create var"} id={"#{@form.id}-#{@key}-create-var"} narrow>
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
        </.live_component>

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
                <.live_component module={Modal} title="Edit var" id={"#{@form.id}-#{@key}-var-#{idx}"}>
                  <.live_component module={RenderVar}
                    id={"#{@form.id}-#{@key}-render-var-#{idx}"}
                    var={var}
                    render={:all}
                    edit />
                </.live_component>
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
      </div>
    </div>
    """
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
end
