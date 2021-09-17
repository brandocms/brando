defmodule BrandoAdmin.Components.Form.Input.Blocks.DatasourceBlock do
  use Surface.LiveComponent
  use Phoenix.HTML

  alias BrandoAdmin.Components.Identifier
  alias BrandoAdmin.Components.Form.ArrayInputs
  alias BrandoAdmin.Components.Form.Input
  alias BrandoAdmin.Components.Form.Input.Blocks.Block
  import Brando.Gettext

  prop base_form, :any
  prop block, :any
  prop block_count, :integer
  prop index, :any
  prop is_ref?, :boolean, default: false

  prop insert_block, :event, required: true
  prop duplicate_block, :event, required: true

  data block_data, :map
  data modules, :list
  data available_sources, :list
  data available_queries, :list
  data available_entries, :list
  data selected_entries, :list

  alias Brando.Datasource

  def v(form, field), do: input_value(form, field)

  def update(assigns, socket) do
    {:ok,
     socket
     |> assign(assigns)
     |> assign(:block_data, List.first(inputs_for(assigns.block, :data)))
     |> assign_available_sources()
     |> assign_available_queries()
     |> assign_modules()
     |> assign_selected_entries()}
  end

  def assign_selected_entries(%{assigns: %{block_data: block_data}} = socket) do
    require Logger
    Logger.error(inspect(v(block_data, :module)))
    Logger.error(inspect(v(block_data, :query)))
    Logger.error(inspect(v(block_data, :ids)))

    case v(block_data, :type) do
      :selection ->
        module = v(block_data, :module)
        query = v(block_data, :query)
        ids = v(block_data, :ids)

        {:ok, selected_entries} = Brando.Datasource.get_selection(module, query, ids)
        require Logger
        Logger.error("-> #{inspect(selected_entries, pretty: true)}")
        assign(socket, :selected_entries, selected_entries)

      _ ->
        assign(socket, :selected_entries, [])
    end
  end

  def assign_available_sources(socket) do
    {:ok, available_sources} = Datasource.list_datasources()

    available_sources =
      Enum.map(
        available_sources,
        &%{
          label: String.capitalize(Module.concat(List.wrap(&1)).__naming__().singular),
          value: &1
        }
      )

    assign(socket, :available_sources, available_sources)
  end

  def assign_available_queries(%{assigns: %{block_data: block_data}} = socket) do
    module = v(block_data, :module)
    type = v(block_data, :type)

    if module && type do
      {:ok, all_available_queries} = Datasource.list_datasource_keys(module)

      available_queries_as_options =
        all_available_queries
        |> Map.get(type)
        |> Enum.map(&%{label: &1, value: &1})

      assign(socket, :available_queries, available_queries_as_options)
    else
      assign(socket, :available_queries, [])
    end
  end

  def assign_modules(socket) do
    assign_new(socket, :modules, fn ->
      {:ok, modules} = Brando.Content.list_modules()
      Enum.map(modules, &%{label: "[#{&1.namespace}] #{&1.name}", value: &1.id})
    end)
  end

  def assign_available_entries(%{assigns: %{block_data: block_data}} = socket) do
    {:ok, available_entries} =
      Brando.Datasource.list_selection(
        v(block_data, :module),
        v(block_data, :query),
        v(block_data, :arg)
      )

    assign(socket, :available_entries, available_entries)
  end

  def render(assigns) do
    ~F"""
    <div
      id={"#{v(@block, :uid)}-wrapper"}
      data-block-index={@index}
      data-block-uid={v(@block, :uid)}>
      <Block
        id={"#{v(@block, :uid)}-base"}
        index={@index}
        is_ref?={@is_ref?}
        block_count={@block_count}
        base_form={@base_form}
        block={@block}
        insert_block={@insert_block}
        duplicate_block={@duplicate_block}>
        <:description>{v(@block, :data).description}</:description>
        <:config>
          <Input.Text form={@block_data} field={:description} />
          <Input.Radios form={@block_data} field={:module} options={@available_sources} />
          <Input.Radios form={@block_data} field={:type} options={[
            %{label: "List", value: :list},
            %{label: "Single", value: :single},
            %{label: "Selection", value: :selection},
          ]} />
          <Input.Radios form={@block_data} field={:query} options={@available_queries} />
          <Input.Select id={"#{@block_data.id}-modules"} form={@block_data} field={:module_id} options={@modules} />
          <Input.Text form={@block_data} field={:arg} />
          <Input.Text form={@block_data} field={:limit} />

        </:config>
        <div class="datasource-block">
          <div class="villain-block-datasource-info">
            <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="128"><path fill="none" d="M0 0h24v24H0z"/><path d="M5 12.5c0 .313.461.858 1.53 1.393C7.914 14.585 9.877 15 12 15c2.123 0 4.086-.415 5.47-1.107 1.069-.535 1.53-1.08 1.53-1.393v-2.171C17.35 11.349 14.827 12 12 12s-5.35-.652-7-1.671V12.5zm14 2.829C17.35 16.349 14.827 17 12 17s-5.35-.652-7-1.671V17.5c0 .313.461.858 1.53 1.393C7.914 19.585 9.877 20 12 20c2.123 0 4.086-.415 5.47-1.107 1.069-.535 1.53-1.08 1.53-1.393v-2.171zM3 17.5v-10C3 5.015 7.03 3 12 3s9 2.015 9 4.5v10c0 2.485-4.03 4.5-9 4.5s-9-2.015-9-4.5zm9-7.5c2.123 0 4.086-.415 5.47-1.107C18.539 8.358 19 7.813 19 7.5c0-.313-.461-.858-1.53-1.393C16.086 5.415 14.123 5 12 5c-2.123 0-4.086.415-5.47 1.107C5.461 6.642 5 7.187 5 7.5c0 .313.461.858 1.53 1.393C7.914 9.585 9.877 10 12 10z"/></svg>

            <div class="inside">
              <p>{gettext("Datasource")} — {v(@block, :data).description}</p>
              <p>
                <small>
                  <code>
                    {v(@block, :data).module}<br>
                    {v(@block, :data).type}|{v(@block, :data).query}
                  </code>
                </small>
              </p>

              {#if v(@block_data, :type) == :selection}
                <ArrayInputs
                  :let={value: array_value, name: array_name}
                  form={@block_data}
                  for={:ids}>
                  <input type="hidden" name={array_name} value={array_value} />
                </ArrayInputs>

                <div class="selected-entries">
                  {#for identifier <- @selected_entries}
                    <Identifier identifier={identifier} />
                  {/for}
                </div>

                <button
                  class="tiny select-button"
                  type="button"
                  :on-click="select_entries">
                  Select entries
                </button>
              {/if}
            </div>
          </div>
        </div>
      </Block>
    </div>
    """
  end

  def handle_event("select_entries", _, socket) do
    {:noreply, assign_available_entries(socket)}
  end
end
