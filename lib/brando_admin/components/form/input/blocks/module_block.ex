defmodule BrandoAdmin.Components.Form.Input.Blocks.ModuleBlock do
  use Surface.LiveComponent
  use Phoenix.HTML
  alias Surface.Components.Form.HiddenInput
  alias BrandoAdmin.Components.Form.MapInputs
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

  data module_name, :string

  def v(form, field) do
    # input_value(form, field)
    Ecto.Changeset.get_field(form.source, field)
    # |> IO.inspect(pretty: true, label: "module_v")
  end

  defp get_module(id) do
    {:ok, modules} = Brando.Villain.list_modules(%{cache: {:ttl, :infinite}})

    case Enum.find(modules, &(&1.id == id)) do
      nil -> nil
      module -> module
    end
  end

  def update(assigns, socket) do
    {:ok,
     socket
     |> assign(assigns)
     |> render_module()
     |> assign_module_data()
     |> parse_module_code()}
  end

  defp assign_module_data(%{assigns: %{block: block}} = socket) do
    module = get_module(v(block, :data).module_id)

    block_data =
      block
      |> inputs_for(:data)
      |> List.first()

    refs = Enum.with_index(inputs_for(block_data, :refs))

    socket
    |> assign(:uid, v(block, :uid))
    |> assign(:module_name, module.name)
    |> assign(:module_class, module.class)
    |> assign(:module_code, module.code)
    |> assign(:refs, refs)
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

  defp render_module(%{assigns: %{block: block_form, base_form: base_form}} = socket) do
    {:ok, modules} = Brando.Villain.list_modules(%{cache: {:ttl, :infinite}})
    parser = Brando.app_module(Villain.Parser)
    context = Liquex.Context.assign(Brando.Villain.get_base_context(), "entry", base_form.data)

    rendered_block =
      parser.module(block_form.data.data, %{
        context: context,
        modules: modules,
        render_for_admin: true
      })
      |> raw

    assign(socket, :rendered_block, rendered_block)
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
        <:config></:config>

        {#for block_data <- inputs_for(@block, :data)}
          <div class="module-block" b-editor-tpl={@module_class}>
            {#for split <- @splits}
              {#case split}
                {#match {:ref, ref}}
                  <Ref
                    id={"#{@uid}-base-#{ref}"}
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
end
