defmodule BrandoAdmin.Components.Form.ModuleProps do
  use Surface.Component
  use Phoenix.HTML

  import BrandoAdmin.Components.Form.Input.Blocks.Utils

  alias BrandoAdmin.Components.Form.Input
  alias BrandoAdmin.Components.Form.Inputs
  alias BrandoAdmin.Components.Modal
  alias BrandoAdmin.Components.Form.PolyInputs

  prop form, :form, required: true
  prop key, :string, default: "default"
  prop entry_form, :boolean, default: false
  prop show_modal, :event, required: true
  prop create_ref, :event, required: true
  prop delete_ref, :event, required: true
  prop create_var, :event, required: true
  prop delete_var, :event, required: true

  def render(assigns) do
    ~F"""
    <div class="properties shaded">
      <div class="inner">
        <Input.Text form={@form} field={:name} />
        <Input.Text form={@form} field={:namespace} />
        <Input.Textarea form={@form} field={:help_text} />
        <Input.Text form={@form} field={:class} />
        <Input.Toggle form={@form} field={:wrapper} />

        <div :if={!@entry_form} class="button-group">
          <button
            :on-click={@show_modal}
            phx-value-id={"#{@form.id}-#{@key}-icon"}
            class="secondary"
            type="button">
            Edit icon
          </button>
        </div>

        <Modal title="Edit icon" id={"#{@form.id}-#{@key}-icon"}>
          <Input.Code id={"#{@form.id}-svg"} form={@form} field={:svg} />
        </Modal>

        <Modal title="Create ref" id={"#{@form.id}-#{@key}-create-ref"} narrow>
          <div class="button-group">
            <button
              type="button"
              :on-click={@create_ref}
              phx-value-type="text"
              phx-value-id={"#{@form.id}-#{@key}-create-ref"}
              class="secondary"
            >
              Text
            </button>
            <button
              type="button"
              :on-click={@create_ref}
              phx-value-type="header"
              phx-value-id={"#{@form.id}-#{@key}-create-ref"}
              class="secondary"
            >
              Header
            </button>
            <button
              type="button"
              :on-click={@create_ref}
              phx-value-type="picture"
              phx-value-id={"#{@form.id}-#{@key}-create-ref"}
              class="secondary"
            >
              Picture
            </button>
            <button
              type="button"
              :on-click={@create_ref}
              phx-value-type="gallery"
              phx-value-id={"#{@form.id}-#{@key}-create-ref"}
              class="secondary"
            >
              Gallery
            </button>
            <button
              type="button"
              :on-click={@create_ref}
              phx-value-type="video"
              phx-value-id={"#{@form.id}-#{@key}-create-ref"}
              class="secondary"
            >
              Video
            </button>
            <button
              type="button"
              :on-click={@create_ref}
              phx-value-type="media"
              phx-value-id={"#{@form.id}-#{@key}-create-ref"}
              class="secondary"
            >
              Media
            </button>
            <button
              type="button"
              :on-click={@create_ref}
              phx-value-type="html"
              phx-value-id={"#{@form.id}-#{@key}-create-ref"}
              class="secondary"
            >
              HTML
            </button>

            <button
              type="button"
              :on-click={@create_ref}
              phx-value-type="svg"
              phx-value-id={"#{@form.id}-#{@key}-create-ref"}
              class="secondary"
            >
              SVG
            </button>
          </div>
        </Modal>

        <div class="refs">
          <h2>
            <div class="header-spread">REFs</div>
            <button
              :on-click={@show_modal}
              phx-value-id={"#{@form.id}-#{@key}-create-ref"}
              type="button"
              class="circle">
              <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="18" height="18"><path fill="none" d="M0 0h24v24H0z" /><path d="M11 11V5h2v6h6v2h-6v6h-2v-6H5v-2z" /></svg>
            </button>
          </h2>

          <ul>
            <Inputs form={@form} for={:refs} :let={form: ref, index: idx}>
              <li class="padded">
                {#for ref_data <- inputs_for_block(ref, :data)}
                  <div>
                    <span class="text-mono">{input_value(ref_data, :type)}</span>
                    <span class="text-mono">- %&lcub;{input_value(ref, :name)}&rcub;</span>
                  </div>
                  <div class="actions">
                    <button
                      class="tiny"
                      type="button"
                      :on-click={@show_modal}
                      phx-value-id={"#{@form.id}-#{@key}-ref-#{idx}"}
                    >
                      <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="12" height="12"><path fill="none" d="M0 0h24v24H0z" /><path d="M6.414 16L16.556 5.858l-1.414-1.414L5 14.586V16h1.414zm.829 2H3v-4.243L14.435 2.322a1 1 0 0 1 1.414 0l2.829 2.829a1 1 0 0 1 0 1.414L7.243 18zM3 20h18v2H3v-2z" /></svg>
                    </button>
                    <button class="tiny" type="button" :on-click={@delete_ref} phx-value-id={input_value(ref, :name)}>
                      <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="12" height="12"><path fill="none" d="M0 0h24v24H0z" /><path d="M17 6h5v2h-2v13a1 1 0 0 1-1 1H5a1 1 0 0 1-1-1V8H2V6h5V3a1 1 0 0 1 1-1h8a1 1 0 0 1 1 1v3zm1 2H6v12h12V8zm-4.586 6l1.768 1.768-1.414 1.414L12 15.414l-1.768 1.768-1.414-1.414L10.586 14l-1.768-1.768 1.414-1.414L12 12.586l1.768-1.768 1.414 1.414L13.414 14zM9 4v2h6V4H9z" /></svg>
                    </button>
                  </div>
                {/for}

                <Modal title="Edit ref" id={"#{@form.id}-#{@key}-ref-#{idx}"}>
                  <div class="panels">
                    {#for ref_data <- inputs_for_block(ref, :data)}
                      {hidden_input(ref_data, :type, value: input_value(ref_data, :type))}
                      <div class="panel">
                        <h2>Block template</h2>
                        {#case input_value(ref_data, :type)}
                          {#match "header"}
                            {#for block_data <- inputs_for_block(ref_data, :data)}
                              <Input.Text form={block_data} field={:level} />
                              <Input.Text form={block_data} field={:text} />
                            {/for}
                          {#match "svg"}
                            {#for block_data <- inputs_for_block(ref_data, :data)}
                              <Input.Text form={block_data} field={:class} />
                              <Input.Code
                                id={"#{@form.id}-ref-#{@key}-#{input_value(ref, :name)}-svg-code"}
                                form={block_data}
                                field={:code}
                              />
                            {/for}
                          {#match "text"}
                            {#for block_data <- inputs_for_block(ref_data, :data)}
                              <Input.Text form={block_data} field={:text} />
                              <Input.Text form={block_data} field={:type} />
                              <Input.Text form={block_data} field={:extensions} />
                            {/for}
                          {#match "picture"}
                            {#for block_data <- inputs_for_block(ref_data, :data)}
                              {hidden_input(block_data, :cdn)}
                              <Input.Text form={block_data} field={:title} />
                              <Input.Text form={block_data} field={:alt} />
                              <Input.Text form={block_data} field={:credits} />
                              <Input.Text form={block_data} field={:link} />
                              <Input.Text form={block_data} field={:picture_class} />
                              <Input.Text form={block_data} field={:img_class} />
                              <Input.Toggle form={block_data} field={:webp} />
                              <Input.Select
                                id={"#{@form.id}-ref-#{@key}-#{input_value(ref, :name)}-placeholder"}
                                form={block_data}
                                field={:placeholder}
                                options={[
                                  %{label: "SVG", value: :svg},
                                  %{label: "Dominant Color", value: :dominant_color},
                                  %{label: "Micro", value: :micro},
                                  %{label: "None", value: :none}
                                ]}
                              />
                            {/for}
                          {#match "gallery"}
                            {#for block_data <- inputs_for_block(ref_data, :data)}
                              {hidden_input(block_data, :cdn)}
                              <Input.Text form={block_data} field={:class} />
                              <Input.Text form={block_data} field={:series_slug} />
                              <Input.Toggle form={block_data} field={:lightbox} />
                              <Input.Radios
                                form={block_data}
                                field={:placeholder}
                                options={[
                                  %{label: "Dominant color", value: "dominant_color"},
                                  %{label: "SVG", value: "svg"},
                                  %{label: "Micro", value: "micro"},
                                  %{label: "None", value: "none"}
                                ]}
                              />
                            {/for}

                          {#match "video"}
                            {#for block_data <- inputs_for_block(ref_data, :data)}
                              <Input.Text form={block_data} field={:url} />
                              <Input.Radios
                                form={block_data}
                                field={:source}
                                options={[
                                  %{label: "YouTube", value: "youtube"},
                                  %{label: "Vimeo", value: "vimeo"},
                                  %{label: "File", value: "file"}
                                ]}
                              />
                              {hidden_input(block_data, :width)}
                              {hidden_input(block_data, :height)}
                              <Input.Text form={block_data} field={:remote_id} />
                              <Input.Text form={block_data} field={:poster} />
                              <Input.Text form={block_data} field={:cover} />
                              <Input.Number form={block_data} field={:opacity} />
                              <Input.Toggle form={block_data} field={:autoplay} />
                              <Input.Toggle form={block_data} field={:preload} />
                              <Input.Toggle form={block_data} field={:play_button} />
                            {/for}

                          {#match type}
                            No matching block {type} found
                        {/case}
                      </div>

                      <div class="panel">
                        <h2>Ref config — {input_value(ref_data, :type)}</h2>

                        <Input.Text form={ref} field={:name} />
                        <Input.Text form={ref} field={:description} />
                        {hidden_input(ref_data, :uid, value: input_value(ref_data, :uid) || Brando.Utils.generate_uid())}
                      </div>
                    {/for}
                  </div>
                </Modal>
              </li>
            </Inputs>
          </ul>
        </div>

        <Modal title="Create var" id={"#{@form.id}-#{@key}-create-var"} narrow>
          <div class="button-group">
            <button
              type="button"
              :on-click={@create_var}
              phx-value-type="text"
              phx-value-id={"#{@form.id}-#{@key}-create-var"}
              class="secondary"
            >
              Text
            </button>
            <button
              type="button"
              :on-click={@create_var}
              phx-value-type="string"
              phx-value-id={"#{@form.id}-#{@key}-create-var"}
              class="secondary"
            >
              String
            </button>
            <button
              type="button"
              :on-click={@create_var}
              phx-value-type="html"
              phx-value-id={"#{@form.id}-#{@key}-create-var"}
              class="secondary"
            >
              Html
            </button>
            <button
              type="button"
              :on-click={@create_var}
              phx-value-type="datetime"
              phx-value-id={"#{@form.id}-#{@key}-create-var"}
              class="secondary"
            >
              Datetime
            </button>
            <button
              type="button"
              :on-click={@create_var}
              phx-value-type="boolean"
              phx-value-id={"#{@form.id}-#{@key}-create-var"}
              class="secondary"
            >
              Boolean
            </button>
            <button
              type="button"
              :on-click={@create_var}
              phx-value-type="color"
              phx-value-id={"#{@form.id}-#{@key}-create-var"}
              class="secondary"
            >
              Color
            </button>
          </div>
        </Modal>

        <div class="vars">
          <h2>
            <div class="header-spread">Vars</div>
            <button
              :on-click={@show_modal}
              phx-value-id={"#{@form.id}-#{@key}-create-var"}
              type="button"
              class="circle"
            >
              <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="18" height="18"><path fill="none" d="M0 0h24v24H0z" /><path d="M11 11V5h2v6h6v2h-6v6h-2v-6H5v-2z" /></svg>
            </button>
          </h2>
          <ul
            id={"#{@form.id}-vars-#{@key}-list"}
            phx-hook="Brando.Sortable"
            data-sortable-id="sortable-vars"
            data-sortable-selector=".var"
            data-sortable-handle=".sort-handle"
          >
            <PolyInputs form={@form} for={:vars} :let={form: var, index: idx}>
              <li class="var padded sort-handle draggable" data-id={idx}>
                <Modal title="Edit var" id={"#{@form.id}-#{@key}-var-#{idx}"}>
                  <Input.Toggle form={var} field={:important} />
                  <Input.Text form={var} field={:key} />
                  <Input.Text form={var} field={:label} />
                  <Input.Radios
                    form={var}
                    field={:type}
                    options={[
                      %{label: "Boolean", value: "boolean"},
                      %{label: "Text", value: "text"},
                      %{label: "String", value: "string"},
                      %{label: "Color", value: "color"},
                      %{label: "Html", value: "html"},
                      %{label: "Datetime", value: "datetime"}
                    ]}
                  />
                  {#case input_value(var, :type)}
                    {#match "text"}
                      <Input.Text form={var} field={:value} />
                    {#match "string"}
                      <Input.Text form={var} field={:value} />
                    {#match "boolean"}
                      <Input.Toggle form={var} field={:value} />
                    {#match "datetime"}
                      <Input.Datetime form={var} field={:value} />
                    {#match "html"}
                      <Input.RichText form={var} field={:value} />
                    {#match "color"}
                      {!-- #TODO: Input.Color --}
                      <Input.Text form={var} field={:value} />
                    {#match _}
                      <Input.Text form={var} field={:value} />
                  {/case}
                </Modal>
                <span class="text-mono">{input_value(var, :type)} - &lcub;&lcub; {input_value(var, :key)} &rcub;&rcub;</span>
                <div class="actions">
                  <button
                    class="tiny"
                    type="button"
                    :on-click={@show_modal}
                    phx-value-id={"#{@form.id}-#{@key}-var-#{idx}"}
                  >
                    <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="12" height="12"><path fill="none" d="M0 0h24v24H0z" /><path d="M6.414 16L16.556 5.858l-1.414-1.414L5 14.586V16h1.414zm.829 2H3v-4.243L14.435 2.322a1 1 0 0 1 1.414 0l2.829 2.829a1 1 0 0 1 0 1.414L7.243 18zM3 20h18v2H3v-2z" /></svg>
                  </button>
                  <button class="tiny" type="button" :on-click={@delete_var} phx-value-id={input_value(var, :key)}>
                    <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="12" height="12"><path fill="none" d="M0 0h24v24H0z" /><path d="M17 6h5v2h-2v13a1 1 0 0 1-1 1H5a1 1 0 0 1-1-1V8H2V6h5V3a1 1 0 0 1 1-1h8a1 1 0 0 1 1 1v3zm1 2H6v12h12V8zm-4.586 6l1.768 1.768-1.414 1.414L12 15.414l-1.768 1.768-1.414-1.414L10.586 14l-1.768-1.768 1.414-1.414L12 12.586l1.768-1.768 1.414 1.414L13.414 14zM9 4v2h6V4H9z" /></svg>
                  </button>
                </div>
              </li>
            </PolyInputs>
          </ul>
        </div>
      </div>
    </div>
    """
  end
end
