defmodule BrandoAdmin.Components.Form.Input.Blocks.Module.EntryBlock do
  use Surface.LiveComponent
  use Phoenix.HTML
  import BrandoAdmin.Components.Form.Input.Blocks.Utils
  alias Brando.Villain
  alias BrandoAdmin.Components.Form.Input.RenderVar
  alias BrandoAdmin.Components.Form.Input.Blocks.Block
  alias BrandoAdmin.Components.Form.Input.Blocks.Module

  prop block, :any
  prop base_form, :any
  prop index, :any
  prop block_count, :integer
  prop uploads, :any
  prop data_field, :atom
  prop entry_template, :map

  prop insert_block, :event, required: true
  prop duplicate_block, :event, required: true

  data splits, :list
  data block_data, :map
  data module_name, :string
  data module_class, :string
  data module_code, :string
  data module_multi, :boolean
  data refs, :list
  data important_vars, :list
  data uid, :string
  data module_not_found, :boolean

  def v(form, field) do
    input_value(form, field)
  end

  def update(assigns, socket) do
    {:ok,
     socket
     |> assign(assigns)
     |> assign_module_data()
     |> parse_module_code()}
  end

  defp assign_module_data(%{assigns: %{block: block, entry_template: entry_template}} = socket) do
    block_data =
      block
      |> inputs_for(:data)
      |> List.first()

    refs = Enum.with_index(inputs_for(block_data, :refs))
    vars = v(block_data, :vars) || []

    socket
    |> assign(:uid, v(block, :uid))
    |> assign(:block_data, block_data)
    |> assign(:module_name, entry_template.name)
    |> assign(:module_class, entry_template.class)
    |> assign(:module_code, entry_template.code)
    |> assign(:module_multi, true)
    |> assign(:refs, refs)
    |> assign_new(:important_vars, fn ->
      Enum.filter(vars, &(&1.important == true))
    end)
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
        is_entry?={true}
        insert_block={@insert_block}
        duplicate_block={@duplicate_block}>
        <:description>{@module_name}</:description>
        <:config>
          {#for var <- inputs_for_poly(@block_data, :vars)}
            <RenderVar var={var} render={:only_regular} />
          {/for}

          <button type="button" class="secondary" :on-click="reinit_vars">
            Reinitialize variables
          </button>

          <button type="button" class="secondary" :on-click="reinit_refs">
            Reset block refs
          </button>
        </:config>

        <div class="module-block" b-editor-tpl={@module_class}>
          {#unless Enum.empty?(@important_vars)}
            <div class="important-vars">
              {#for var <- inputs_for_poly(@block_data, :vars)}
                <RenderVar var={var} render={:only_important} />
              {/for}
            </div>
          {/unless}

          {#for split <- @splits}
            {#case split}
              {#match {:ref, ref}}
                <Module.Ref
                  data_field={@data_field}
                  uploads={@uploads}
                  module_refs={@refs}
                  module_ref_name={ref}
                  base_form={@base_form} />

              {#match _}
                {raw split}
            {/case}
          {/for}
          {hidden_input @block_data, :module_id}
          {hidden_input @block_data, :sequence}
          {hidden_input @block_data, :multi}
        </div>
      </Block>
    </div>
    """
  end

  def handle_event(
        "reinit_vars",
        _,
        %{
          assigns: %{
            base_form: base_form,
            uid: block_uid,
            block_data: block_data,
            data_field: data_field
          }
        } = socket
      ) do
    module_id = input_value(block_data, :module_id)
    {:ok, module} = Brando.Content.get_module(module_id)

    changeset = base_form.source

    updated_changeset =
      Villain.update_block_in_changeset(
        changeset,
        data_field,
        block_uid,
        %{data: %{vars: module.vars}}
      )

    schema = changeset.data.__struct__
    form_id = "#{schema.__naming__.singular}_form"

    send_update(BrandoAdmin.Components.Form,
      id: form_id,
      updated_changeset: updated_changeset
    )

    {:noreply, socket}
  end

  def handle_event(
        "reinit_refs",
        _,
        %{
          assigns: %{
            base_form: base_form,
            uid: block_uid,
            block_data: block_data,
            data_field: data_field
          }
        } = socket
      ) do
    module_id = input_value(block_data, :module_id)
    {:ok, module} = Brando.Content.get_module(module_id)

    changeset = base_form.source

    refs_with_generated_uids = Brando.Villain.add_uid_to_refs(module.refs)

    updated_changeset =
      Villain.update_block_in_changeset(
        changeset,
        data_field,
        block_uid,
        %{data: %{refs: refs_with_generated_uids}}
      )

    schema = changeset.data.__struct__
    form_id = "#{schema.__naming__.singular}_form"

    send_update(BrandoAdmin.Components.Form,
      id: form_id,
      updated_changeset: updated_changeset
    )

    {:noreply, socket}
  end

  defp parse_module_code(%{assigns: %{module_not_found: true}} = socket) do
    socket
  end

  defp parse_module_code(%{assigns: %{module_code: module_code}} = socket) do
    splits =
      ~r/%{(\w+)}|{{ (\w+) }}/
      |> Regex.split(module_code, include_captures: true)
      |> Enum.map(fn chunk ->
        case Regex.run(~r/%{(?<ref>\w+)}|{{ (?<content>content) }}/, chunk, capture: :all_names) do
          nil -> chunk
          [content, ""] -> {:content, content}
          ["", ref] -> {:ref, ref}
        end
      end)

    assign(socket, :splits, splits)
  end
end
