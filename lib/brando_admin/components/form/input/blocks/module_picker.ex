defmodule BrandoAdmin.Components.Form.Input.Blocks.ModulePicker do
  use Surface.LiveComponent
  use Phoenix.HTML

  alias BrandoAdmin.Components.Modal
  alias Brando.Content

  prop insert_block, :event, required: true
  prop insert_section, :event, required: true
  prop insert_datasource, :event, required: true
  prop insert_index, :integer, required: true
  prop hide_sections, :boolean, default: false

  data modules_by_namespace, :list

  def update(assigns, socket) do
    {:ok, modules} = Content.list_modules(%{cache: {:ttl, :infinite}})

    {:ok,
     socket
     |> assign(assigns)
     |> assign_new(:modules_by_namespace, fn ->
       modules
       |> Brando.Utils.split_by(:namespace)
       |> Enum.map(&__MODULE__.sort_namespace/1)
     end)}
  end

  def render(assigns) do
    ~F"""
    <div>
      <Modal title="Add content block" id={@id} medium>
        <div class="button-group-horizontal">
          <button
            :if={!@hide_sections}
            type="button"
            class="builtin-button"
            :on-click={@insert_section}
            phx-value-index={@insert_index}>
            <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="24" height="24"><path fill="none" d="M0 0h24v24H0z"/><path d="M3 3h18a1 1 0 0 1 1 1v16a1 1 0 0 1-1 1H3a1 1 0 0 1-1-1V4a1 1 0 0 1 1-1zm17 8H4v8h16v-8zm0-2V5H4v4h16zM9 6h2v2H9V6zM5 6h2v2H5V6z"/></svg>
            Insert section
          </button>
          <button
            type="button"
            class="builtin-button"
            :on-click={@insert_datasource}
            phx-value-index={@insert_index}>
            <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="128"><path fill="none" d="M0 0h24v24H0z"/><path d="M5 12.5c0 .313.461.858 1.53 1.393C7.914 14.585 9.877 15 12 15c2.123 0 4.086-.415 5.47-1.107 1.069-.535 1.53-1.08 1.53-1.393v-2.171C17.35 11.349 14.827 12 12 12s-5.35-.652-7-1.671V12.5zm14 2.829C17.35 16.349 14.827 17 12 17s-5.35-.652-7-1.671V17.5c0 .313.461.858 1.53 1.393C7.914 19.585 9.877 20 12 20c2.123 0 4.086-.415 5.47-1.107 1.069-.535 1.53-1.08 1.53-1.393v-2.171zM3 17.5v-10C3 5.015 7.03 3 12 3s9 2.015 9 4.5v10c0 2.485-4.03 4.5-9 4.5s-9-2.015-9-4.5zm9-7.5c2.123 0 4.086-.415 5.47-1.107C18.539 8.358 19 7.813 19 7.5c0-.313-.461-.858-1.53-1.393C16.086 5.415 14.123 5 12 5c-2.123 0-4.086.415-5.47 1.107C5.461 6.642 5 7.187 5 7.5c0 .313.461.858 1.53 1.393C7.914 9.585 9.877 10 12 10z"/></svg>
            Insert datasource
          </button>
        </div>

        <div
          class="modules"
          phx-hook={!@hide_sections && "Brando.ModulePicker"}
          id={"#{@id}-modules"}>
          {#for {namespace, modules} <- @modules_by_namespace}
            {#unless namespace == "general"}
              <button type="button" class="namespace-button">
                <figure>
                  &rarr;
                </figure>
                <div class="info">
                  <div class="name">{namespace}</div>
                  <div class="instructions">{Enum.count(modules)} modules</div>
                </div>
              </button>
              <div class="namespace-modules">
                {#for module <- modules}
                  <button
                    type="button"
                    class="module-button"
                    :on-click={@insert_block}
                    phx-value-index={@insert_index}
                    phx-value-module-id={module.id}>
                    <figure>
                      {module.svg |> raw}
                    </figure>
                    <div class="info">
                      <div class="name">{module.name}</div>
                      <div class="instructions">{module.help_text}</div>
                    </div>
                  </button>
                {/for}
              </div>
            {/unless}
          {/for}
          {#for {namespace, modules} <- @modules_by_namespace}
            {#if namespace == "general"}
              {#for module <- modules}
                <button
                  type="button"
                  class="module-button"
                  :on-click={@insert_block}
                  phx-value-index={@insert_index}
                  phx-value-module-id={module.id}>
                  <figure>
                    {module.svg |> raw}
                  </figure>
                  <div class="info">
                    <div class="name">{module.name}</div>
                    <div class="instructions">{module.help_text}</div>
                  </div>
                </button>
              {/for}
            {/if}
          {/for}
        </div>
      </Modal>
    </div>
    """
  end

  def sort_namespace({namespace, modules}) do
    sorted_modules = Enum.sort(modules, &(&1.sequence <= &2.sequence))
    {namespace, sorted_modules}
  end
end
