defmodule BrandoAdmin.Components.Form.Subform do
  use BrandoAdmin, :live_component
  # use Phoenix.HTML

  alias Brando.Blueprint.Relations
  alias BrandoAdmin.Components.Form.Input
  alias BrandoAdmin.Components.Form.Input.SubformHelpers
  alias BrandoAdmin.Components.Form.Primitives
  alias BrandoAdmin.Components.Form.Subform
  alias Ecto.Changeset

  use Gettext, backend: Brando.Gettext

  # prop subform, :any
  # prop form, :any
  # prop blueprint, :any
  # prop current_user, :map
  # prop label, :string
  # prop instructions, :string
  # prop placeholder, :string

  # A row's own field (a multi select in it) changed: replace that row in the
  # form's latest list, not in the copy this subform last rendered with.
  def update(%{action: :update_changeset, index: index, updated_changeset: updated_changeset}, socket) do
    {:noreply, socket} = SubformHelpers.send_op(socket, {:replace, index, updated_changeset})
    {:ok, socket}
  end

  def update(assigns, socket) do
    socket =
      socket
      |> assign(assigns)
      |> prepare_subform_component()
      |> assign_new(:open_entries, fn -> %{} end)
      |> assign_relation()
      |> assign(
        :empty_subform_fields,
        SubformHelpers.current_entries(assigns.field.form.source, assigns.subform.name) == []
      )
      |> assign(:path, List.wrap(assigns.subform.name))
      |> assign_table()
      |> assign_new(:parent_form_id, fn ->
        parent_schema = assigns.field.form.data.__struct__
        "#{parent_schema.__naming__().singular}_form"
      end)

    {:ok, socket}
  end

  # Transformer rendering has been moved to BrandoAdmin.Components.Form.Transformer

  # inline
  def render(%{subform: _} = assigns) do
    ~H"""
    <fieldset>
      <Primitives.field_base
        :if={@subform.cardinality == :one}
        field={@field}
        label={@label}
        instructions={@instructions}
        class="subform"
        meta_top
      >
        <.inputs_for :let={sub_form} field={@field} skip_hidden>
          <div class="subform-entry">
            <Input.input type={:hidden} field={sub_form[:id]} />
            <Input.input type={:hidden} field={sub_form[:_persistent_id]} value={sub_form.index} />
            <Subform.Field.render
              :for={input <- @subform.sub_fields}
              cardinality={:one}
              sub_form={sub_form}
              label={@label}
              instructions={@instructions}
              placeholder={@placeholder}
              input={input}
              path={@path}
              parent_form_id={@parent_form_id}
              subform_id={@id}
              current_user={@current_user}
            />
          </div>
        </.inputs_for>
      </Primitives.field_base>
      <Primitives.field_base
        :if={@subform.cardinality == :many}
        field={@field}
        label={@label}
        instructions={@instructions}
        class={["subform", @table? && "subform--table"]}
        meta_top
      >
        <%!-- An inline subform is a table: one line per entry under one row of
              column headings, so every row reads the same. The headings are a
              header group beside the sortable rows, which keeps them out of
              the rows' sibling order. --%>
        <div
          id={@table? && "#{@field.id}-table"}
          class={@table? && "subform-table-frame"}
          phx-hook={@table? && "Brando.TableRows"}
        >
          <div class={@table? && "subform-table-scroll"}>
            <div class={@table? && "subform-table"}>
              <div :if={@table? && !@empty_subform_fields} class="subform-table-head" aria-hidden="true">
                <div class="subform-table-row">
                  <span class="subform-tools"></span>
                  <span :for={column <- @columns} class="brando-input" data-component={column.component}>
                    {column.label}
                  </span>
                  <span class="subform-row-end"></span>
                </div>
              </div>
              <div
                id={"#{@field.id}-sortable"}
                class={@table? && "subform-table-body"}
                data-embeds={@embeds?}
                phx-hook="Brando.SortableEmbeds"
                data-sortable-handle=".subform-handle"
                data-sortable-id={"#{@field.name}-sortable"}
                data-sortable-selector=".subform-entry"
              >
                <.empty_subform :if={@empty_subform_fields} field={@field} />
                <.inputs_for :let={sub_form} field={@field}>
                  <div
                    id={"#{sub_form.id}-entry"}
                    class={[
                      "subform-entry",
                      @subform.style == :inline && "inline",
                      @subform.style == :listing && "summary-entry"
                    ]}
                  >
                    <input type="hidden" name={"#{@field.form.name}[#{@sort_param}][]"} value={sub_form.index} />
                    <div class="subform-tools">
                      <.subentry_insert
                        :if={@table? && @subform.add_entry}
                        on_click={JS.push("insert_subentry", value: %{index: sub_form.index}, target: @myself)}
                      />
                      <.subentry_sequence :if={@sequenced?} />
                      <.subentry_remove
                        :if={!@table?}
                        name={"#{@field.form.name}[#{@drop_param}][]"}
                        index={sub_form.index}
                      />
                    </div>

                    <div :if={@subform.style == :listing} class="subform-summary">
                      <div class="subform-summary-content">
                        {Phoenix.LiveView.TagEngine.component(
                          @subform.listing,
                          [entry: Changeset.apply_changes(sub_form.source)],
                          {__ENV__.module, __ENV__.function, __ENV__.file, __ENV__.line}
                        )}
                      </div>
                      <button
                        type="button"
                        class="subform-summary-edit"
                        aria-expanded={to_string(entry_open?(sub_form, @open_entries))}
                        aria-controls={"#{sub_form.id}-fields"}
                        phx-click={
                          JS.push("edit_subentry",
                            value: %{index: sub_form[:_persistent_id].value, open: !entry_open?(sub_form, @open_entries)},
                            target: @myself
                          )
                        }
                      >
                        <.icon name={if entry_open?(sub_form, @open_entries), do: "chevron-up", else: "square-pen"} />
                        {if entry_open?(sub_form, @open_entries), do: gettext("Done"), else: gettext("Edit")}
                      </button>
                    </div>
                    <div
                      id={"#{sub_form.id}-fields"}
                      class="subform-fields"
                      hidden={@subform.style == :listing && !entry_open?(sub_form, @open_entries)}
                    >
                      <Subform.Field.render
                        :for={input <- @subform.sub_fields}
                        cardinality={:many}
                        table={@table?}
                        sub_form={sub_form}
                        input={input}
                        path={@path ++ [sub_form.index]}
                        parent_form_id={@parent_form_id}
                        subform_id={@id}
                        current_user={@current_user}
                      />
                    </div>
                    <div :if={@table?} class="subform-row-end">
                      <.subentry_remove name={"#{@field.form.name}[#{@drop_param}][]"} index={sub_form.index} />
                    </div>
                  </div>
                </.inputs_for>
                <input type="hidden" name={"#{@field.form.name}[#{@drop_param}][]"} />
              </div>
            </div>
          </div>
          <div :if={@table?} class="subform-table-foot">
            <.subentry_add :if={@subform.add_entry} on_click={JS.push("add_subentry", target: @myself)} />
            <span :if={!@empty_subform_fields} class="subform-table-count">
              {ngettext(
                "1 entry",
                "%{count} entries",
                length(SubformHelpers.current_entries(@field.form.source, @subform.name))
              )}
            </span>
          </div>
        </div>
        <.subentry_add :if={!@table? && @subform.add_entry} on_click={JS.push("add_subentry", target: @myself)} />
      </Primitives.field_base>
    </fieldset>
    """
  end

  def subentry_add(assigns) do
    ~H"""
    <button type="button" class="add-entry-button" phx-click={@on_click}>
      <.icon name="list-plus" />
      {gettext("Add entry")}
    </button>
    """
  end

  # Sits on the line above its row, and adds an entry there
  def subentry_insert(assigns) do
    ~H"""
    <button type="button" class="subform-insert" phx-click={@on_click} aria-label={gettext("Insert entry")}>
      <.icon name="plus" />
    </button>
    """
  end

  def sort_by_filename(assigns) do
    ~H"""
    <button type="button" class="add-entry-button" phx-click={@on_click}>
      <.icon name="arrow-down-a-z" />
      {gettext("Sort by filename")}
    </button>
    """
  end

  def subentry_sequence(assigns) do
    ~H"""
    <button type="button" class="subform-handle" aria-label={gettext("Reorder entry")}>
      <.icon name="arrow-up-down" />
    </button>
    """
  end

  def subentry_edit(assigns) do
    ~H"""
    <button
      class="subform-edit"
      type="button"
      phx-click={@on_click}
      aria-label={if @open, do: gettext("Close entry"), else: gettext("Edit entry")}
    >
      <.icon :if={!@open} name="square-pen" />
      <.icon :if={@open} name="circle-x" />
    </button>
    """
  end

  attr :name, :string, required: true
  attr :index, :integer, required: true

  def subentry_remove(assigns) do
    ~H"""
    <button
      name={@name}
      type="button"
      value={@index}
      phx-click={JS.dispatch("change")}
      class="subform-delete"
      aria-label={gettext("Remove entry")}
    >
      <.icon name="x" />
    </button>
    """
  end

  attr :field, Phoenix.HTML.FormField

  def empty_subform(assigns) do
    ~H"""
    <input type="hidden" name={@field.name} value="" />
    <div class="subform-empty">&rarr; {gettext("No associated entries")}</div>
    """
  end

  def handle_event("focus", _, socket) do
    {:noreply, socket}
  end

  def handle_event("blur", _, socket) do
    {:noreply, socket}
  end

  def handle_event("reposition", _, socket) do
    {:noreply, socket}
  end

  def handle_event("edit_subentry", %{"index" => index, "open" => open}, socket) when is_boolean(open) do
    {:noreply, update(socket, :open_entries, &Map.put(&1, to_string(index), open))}
  end

  # Adds, removals and reorders go to the form as operations on its latest
  # changeset (`SubformHelpers.send_op/3`): building them here, on the copy
  # this component last rendered with, lost a row when "Add entry" was
  # clicked twice before the form re-rendered it.
  def handle_event("add_subentry", _, socket) do
    SubformHelpers.append_subentries(socket, new_entry(socket))
  end

  def handle_event("insert_subentry", %{"index" => index}, socket) do
    SubformHelpers.insert_subentry(socket, index, new_entry(socket))
  end

  def handle_event("remove_subentry", %{"index" => index}, socket) do
    SubformHelpers.remove_subentry(socket, index)
  end

  def handle_event("force_validate", _, socket) do
    {:noreply, push_event(socket, "b:validate", %{})}
  end

  def handle_event("sequenced_subform", %{"ids" => order_indices} = event_params, socket) do
    seen = length(SubformHelpers.current_entries(socket.assigns.field.form.source, socket.assigns.subform.name))
    SubformHelpers.send_op(socket, {:reorder, order_indices, seen, !event_params["embeds"]})
  end

  # How the relation is sequenced, whether it embeds, and the names of its
  # sort and drop params
  defp assign_relation(%{assigns: %{subform: %{name: name}, field: field}} = socket) do
    relation = fn -> Relations.__relation__(field.form.data.__struct__, name) end

    socket
    |> assign_new(:sequenced?, fn -> sequenced?(relation.()) end)
    |> assign_new(:embeds?, fn -> match?(%Relations.Relation{type: :embeds_many}, relation.()) end)
    |> assign_new(:sort_param, fn -> relation_param(relation.(), :sort_param, :"sort_#{name}_ids") end)
    |> assign_new(:drop_param, fn -> relation_param(relation.(), :drop_param, :"drop_#{name}_ids") end)
  end

  # Entries can be reordered when they are embedded, or when the related
  # schema has the :sequenced trait
  defp sequenced?(%Relations.Relation{type: :has_many, opts: %{module: module}}),
    do: module.has_trait(Brando.Trait.Sequenced)

  defp sequenced?(%Relations.Relation{type: :embeds_many}), do: true
  defp sequenced?(_relation), do: false

  defp relation_param(%Relations.Relation{opts: opts}, key, default), do: Map.get(opts, key, default)
  defp relation_param(_relation, _key, default), do: default

  defp assign_table(%{assigns: %{subform: subform, field: field}} = socket) do
    socket
    |> assign_new(:table?, fn -> subform.style == :inline and subform.cardinality == :many end)
    |> assign_new(:columns, fn -> table_columns(subform, field) end)
  end

  defp new_entry(socket) do
    entry = Changeset.apply_changes(socket.assigns.field.form.source)

    case socket.assigns.subform.default do
      fun when is_function(fun) -> fun.(entry, nil)
      struct -> struct
    end
  end

  # One heading per visible column, labelled as its cells' own labels are
  defp table_columns(%{style: :inline, cardinality: :many} = subform, field) do
    schema = related_schema(field.form.data.__struct__, subform.name)

    subform.sub_fields
    |> Enum.reject(&(&1.type == :hidden))
    |> Enum.map(fn input ->
      %{
        component: Primitives.data_component(input.type),
        label: BrandoAdmin.Utils.g(schema, input.opts[:label]) || Brando.Utils.humanize(to_string(input.name))
      }
    end)
  end

  defp table_columns(_subform, _field), do: []

  defp related_schema(parent_schema, name) do
    case Relations.__relation__(parent_schema, name) do
      %Relations.Relation{opts: %{module: module}} when is_atom(module) -> module
      _ -> parent_schema
    end
  end

  # LiveView's persistent form key follows the row through reordering. DOM IDs
  # still come from the nested form, including for entries without a database ID.
  def entry_open?(form, open_entries) do
    key = to_string(form[:_persistent_id].value)
    has_errors? = form.source.action not in [nil, :ignore] && !form.source.valid?
    has_errors? || Map.get(open_entries, key, is_nil(form.data.id))
  end
end
