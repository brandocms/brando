defmodule BrandoAdmin.Components.Form.Input.Blocks.ModuleBlock do
  use Surface.LiveComponent
  use Phoenix.HTML
  alias Surface.Components.Form.HiddenInput
  alias Brando.Villain
  alias BrandoAdmin.Components.Form.MapInputs
  alias BrandoAdmin.Components.Form.Input
  alias BrandoAdmin.Components.Form.Input.RenderVar
  alias BrandoAdmin.Components.Form.Input.Blocks
  alias BrandoAdmin.Components.Form.Input.Blocks.Block
  alias BrandoAdmin.Components.Form.Input.Blocks.Ref
  import BrandoAdmin.Components.Form.Input.Blocks.Utils

  prop block, :any
  prop base_form, :any
  prop index, :any
  prop block_count, :integer

  prop insert_block, :event, required: true
  prop duplicate_block, :event, required: true

  data splits, :list
  data module_name, :string
  data module_class, :string
  data module_code, :string
  data refs, :list
  data important_vars, :list
  data uid, :string
  data module_not_found, :boolean

  def v(form, field) do
    # input_value(form, field)
    Ecto.Changeset.get_field(form.source, field)
    # |> IO.inspect(pretty: true, label: "module_v")
  end

  defp get_module(id) do
    {:ok, modules} = Villain.list_modules(%{cache: {:ttl, :infinite}})

    case Enum.find(modules, &(&1.id == id)) do
      nil -> nil
      module -> module
    end
  end

  def mount(socket) do
    {:ok, assign(socket, :module_not_found, false)}
  end

  def update(assigns, socket) do
    {:ok,
     socket
     |> assign(assigns)
     |> assign_module_data()
     |> parse_module_code()}
  end

  defp assign_module_data(%{assigns: %{block: block}} = socket) do
    case get_module(v(block, :data).module_id) do
      nil ->
        assign(socket, :module_not_found, true)

      module ->
        block_data =
          block
          |> inputs_for(:data)
          |> List.first()

        refs = Enum.with_index(inputs_for(block_data, :refs))
        vars = v(block_data, :vars)

        socket
        |> assign(:uid, v(block, :uid))
        |> assign(:block_data, block_data)
        |> assign(:module_name, module.name)
        |> assign(:module_class, module.class)
        |> assign(:module_code, module.code)
        |> assign(:refs, refs)
        |> assign_new(:important_vars, fn ->
          Enum.filter(vars, &(&1.important == true))
        end)
    end
  end

  defp parse_module_code(%{assigns: %{module_not_found: true}} = socket) do
    socket
  end

  defp parse_module_code(
         %{assigns: %{module_code: module_code, block: block_form, base_form: base_form}} = socket
       ) do
    require Logger

    splits =
      ~r/%{(\w+)}/
      |> Regex.split(module_code, include_captures: true)
      |> Enum.map(fn split ->
        case Regex.run(~r/%{(\w+)}/, split, capture: :all_but_first) do
          nil -> split
          [ref] -> {:ref, ref}
        end
      end)

    socket
    |> assign(:splits, splits)
  end

  def render(%{module_not_found: true} = assigns) do
    ~F"""
    Missing module!
    """
  end

  def render(assigns) do
    ~F"""
    <div
      id={"#{@uid}-wrapper"}
      data-block-index={@index}
      data-block-uid={@uid}>
      <Block
        id={"#{@uid}-base"}
        index={@index}
        block_count={@block_count}
        base_form={@base_form}
        block={@block}
        insert_block={@insert_block}
        duplicate_block={@duplicate_block}>
        <:description>{@module_name}</:description>
        <:config>
          <button type="button" class="secondary" :on-click="reinit_vars">
            Reinitialize variables
          </button>
        </:config>

        {#for block_data <- inputs_for(@block, :data)}
          <div class="module-block" b-editor-tpl={@module_class}>

            {#unless Enum.empty?(@important_vars)}
              <div class="important-vars">
                {#for var <- inputs_for_poly(block_data, :vars)}
                  <RenderVar var={var} important />
                {/for}
              </div>
            {/unless}

            {#for split <- @splits}
              {#case split}
                {#match {:ref, ref}}
                  <Ref
                    module_refs={@refs}
                    module_ref_name={ref}
                    base_form={@base_form} />
                {#match _}
                  {raw split}
              {/case}
            {/for}

            <HiddenInput form={block_data} field={:module_id} />
            <HiddenInput form={block_data} field={:sequence} />
            <HiddenInput form={block_data} field={:multi} />
            <MapInputs
              :let={value: value, name: name}
              form={block_data}
              for={:vars}>
              {name} -> {inspect value}
            </MapInputs>
          </div>
        {/for}
      </Block>
    </div>
    """
  end

  def handle_event(
        "reinit_vars",
        _,
        %{assigns: %{base_form: base_form, uid: block_uid, block_data: block_data}} = socket
      ) do
    require Logger
    Logger.error(inspect("reinit_vars"))
    module_id = input_value(block_data, :module_id)
    {:ok, module} = Villain.get_module(module_id)

    # update_block(uid, %{vars: vars_blueprint})
    changeset = base_form.source
    # TODO -- get data field name somehow
    blocks = Ecto.Changeset.get_field(changeset, :data)

    # TODO -- deep search? inside sections, etc
    source_position = Enum.find_index(blocks, &(&1.uid == block_uid))

    schema = changeset.data.__struct__
    form_id = "#{schema.__naming__.singular}_form"

    old_block = Enum.at(blocks, source_position)
    new_block = put_in(old_block, [Access.key(:data), Access.key(:vars)], module.vars)

    new_blocks =
      put_in(
        blocks,
        [
          Access.filter(&match?(%{uid: ^block_uid}, &1))
        ],
        new_block
      )

    updated_changeset = Ecto.Changeset.put_change(changeset, :data, new_blocks)

    send_update(BrandoAdmin.Components.Form,
      id: form_id,
      updated_changeset: updated_changeset
    )

    {:noreply, socket}
  end
end
