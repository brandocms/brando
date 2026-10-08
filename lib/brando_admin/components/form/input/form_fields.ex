defmodule BrandoAdmin.Components.Form.Input.FormFields do
  @moduledoc """
  The field designer of a `Brando.Forms.Form`: a canvas of 12-unit rows to
  arrange fields on, beside the form as visitors will see it.

  It is the module editor's variable canvas (`VarLayout`) applied to form
  fields, and shares its CSS, its packing (`Brando.Content.Var.Layout`) and
  its drag hook (`Brando.VarLayout`, which reports drops as
  `reposition_vars`). Chips are keyed by field `uid`, since a key can be
  blank or repeated while an editor types.

  ## State

  The parent Form owns the changeset. Every field's inputs are rendered here —
  editable ones in the field's edit modal, the rest hidden — so the form's
  `validate` always posts a whole field. Structural changes (add, duplicate,
  reorder, width, required) rewrite the `fields` association and hand it to
  the Form with `:update_changeset`; deleting goes through the relation's
  `drop_param`, like a subform.

  A synchronized translation cannot change structure: it gets a read-only
  canvas, and its edit modals show what the source decides beside the text to
  translate. The save check refuses structural changes regardless.
  """
  use BrandoAdmin, :live_component
  use Gettext, backend: Brando.Gettext

  alias Brando.Content.Var.Layout
  alias Brando.Forms.Field
  alias Brando.Forms.Form
  alias Brando.Translations
  alias BrandoAdmin.Components.Content
  alias BrandoAdmin.Components.Form.Input
  alias BrandoAdmin.Components.Form.Input.SubformHelpers
  alias Ecto.Changeset

  @widths [:full, :half, :third, :fourth]

  def mount(socket) do
    {:ok,
     socket
     |> assign(:open_uid, nil)
     |> assign(:locked, false)
     |> assign(:lock_entry_id, :unset)
     |> assign(:source_fields, %{})
     |> assign_new(:widths, fn -> Enum.map(@widths, &%{value: &1, label: width_label(&1), hint: width_hint(&1)}) end)
     |> assign_new(:types, fn -> Enum.map(Field.types(), &%{value: &1, label: type_label(&1)}) end)}
  end

  def update(assigns, socket) do
    {:ok,
     socket
     |> assign(assigns)
     |> assign_lock()
     |> assign_entries()}
  end

  # Whether this form is a synchronized translation, read once per entry.
  defp assign_lock(socket) do
    entry_id = socket.assigns.field.form.source.data.id

    if socket.assigns.lock_entry_id == entry_id do
      socket
    else
      {locked, source_fields, source_language} = lock_state(entry_id)

      socket
      |> assign(:lock_entry_id, entry_id)
      |> assign(:locked, locked)
      |> assign(:source_fields, source_fields)
      |> assign(:source_language, source_language)
    end
  end

  defp lock_state(nil), do: {false, %{}, nil}

  defp lock_state(entry_id) do
    with %{role: :target, synchronized: true, group_id: group_id} <- Translations.get_member(Form, entry_id),
         %{entry_id: source_id, language: language} <- group_id |> Translations.list_members() |> List.first(),
         {:ok, source} <- Brando.Forms.get_form(%{matches: %{id: source_id}, preload: [:fields]}) do
      {true, Map.new(source.fields, &{&1.uid, &1}), language}
    else
      %{role: :target, synchronized: true} -> {true, %{}, nil}
      _ -> {false, %{}, nil}
    end
  end

  defp assign_entries(socket) do
    form = socket.assigns.field.form

    entries =
      form.source
      |> then(&form.impl.to_form(&1, form, :fields, []))
      |> Enum.reject(&(&1.source.action in [:replace, :delete]))
      |> Enum.map(&entry/1)

    socket
    |> assign(:entries, entries)
    |> assign(:rows, entries |> Enum.reject(&(&1.type == :hidden)) |> Layout.pack())
    |> assign(:hidden_entries, Enum.filter(entries, &(&1.type == :hidden)))
    |> assign(:preview, preview(form.source))
  end

  defp entry(field_form) do
    changeset = field_form.source
    type = Changeset.get_field(changeset, :type)

    %{
      form: field_form,
      index: field_form.index,
      uid: Changeset.get_field(changeset, :uid),
      key: Changeset.get_field(changeset, :key),
      type: type,
      label: Changeset.get_field(changeset, :label),
      required: Changeset.get_field(changeset, :required) == true,
      # A section is a heading across the form, whatever width it was given
      width: if(type == :section, do: :full, else: Changeset.get_field(changeset, :width) || :full),
      new_row: type == :section or Changeset.get_field(changeset, :new_row) == true,
      saved_width: Changeset.get_field(changeset, :width) || :full,
      saved_new_row: Changeset.get_field(changeset, :new_row) == true,
      options: changeset |> Changeset.apply_changes() |> Field.options()
    }
  end

  # The form as visitors will see it, pending edits included.
  defp preview(changeset) do
    form = Changeset.apply_changes(changeset)

    fields =
      case form.fields do
        %Ecto.Association.NotLoaded{} -> []
        fields -> Enum.reject(fields || [], &(is_nil(&1.type) or is_nil(&1.key)))
      end

    %{form | fields: fields}
  end

  # -- render -----------------------------------------------------------------

  def render(assigns) do
    ~H"""
    <div class="form-fields-designer" id={@id} data-locked={@locked && "true"}>
      <div class="var-layout var-layout-split">
        <section class="var-layout-panel">
          <div class="var-layout-panel-head">
            <div>
              <h2>{gettext("Fields")}</h2>
              <p :if={!@locked} class="var-layout-sub">
                {gettext("Drag fields between rows, or drag a row by its handle to reorder.")}
                {gettext("Each row holds 12 units. A section starts a new group of fields.")}
              </p>
              <p :if={@locked} class="var-layout-sub">
                {gettext(
                  "The source form decides which fields there are and how they are laid out. Translate their text here."
                )}
              </p>
            </div>
          </div>

          <div class="var-layout-panel-body">
            <div class="var-layout-ruler" aria-hidden="true">
              <span :for={unit <- 1..Layout.row_units()}>{unit}</span>
            </div>

            <div
              id={"#{@id}-rows"}
              class="var-layout-rows"
              phx-hook={!@locked && "Brando.VarLayout"}
              phx-target={@myself}
              data-target={@myself}
              data-surface="content"
            >
              <div class="var-layout-rows-inner">
                <div :if={@rows == []} class="preview-empty">{gettext("No fields yet.")}</div>
                <div
                  :for={{row, index} <- Enum.with_index(@rows)}
                  class={["var-layout-row", section_row?(row) && "form-section-row"]}
                  data-row={index}
                >
                  <div class="var-layout-gutter">
                    <button
                      :if={!@locked}
                      type="button"
                      class="var-row-handle"
                      title={gettext("Drag to reorder this row")}
                      aria-label={gettext("Reorder row %{number}", number: index + 1)}
                    >
                      <.icon name="equal" />
                    </button>
                    <span :if={!section_row?(row)} class="var-row-meter">
                      <b class={Layout.free_units(row) == 0 && "full"}>{Layout.used_units(row)}</b>
                      <i class="rule"></i>
                      <span>{Layout.row_units()}</span>
                    </span>
                  </div>

                  <div class="var-layout-slots" data-row={index}>
                    <.chip
                      :for={entry <- row}
                      entry={entry}
                      widths={@widths}
                      locked={@locked}
                      target={@myself}
                      modal_id={modal_id(@id, entry)}
                      drop_name={"#{@field.form.name}[drop_fields_ids][]"}
                    />
                  </div>
                </div>
              </div>

              <div :if={!@locked} class="var-layout-new-row" data-var-layout-new-row>
                <span>{gettext("Drop here to start a new row")}</span>
              </div>
            </div>

            <div :if={!@locked} class="var-layout-foot">
              <button type="button" class="module-add-button" phx-click={show_modal("##{@id}-add")}>
                <.icon name="plus" />
                {gettext("Add field")}
              </button>
              <div class="form-fields-quick-add">
                <button
                  :for={type <- [:text, :email, :textarea, :select, :consent, :section]}
                  type="button"
                  phx-click={JS.push("add_field", value: %{type: type}, target: @myself)}
                >
                  {type_label(type)}
                </button>
              </div>
            </div>

            <section class="var-layout-tray">
              <div class="var-layout-tray-head">
                <h3>{gettext("Hidden fields")}</h3>
                <p>{gettext("Sent with every submission and never shown to visitors.")}</p>
              </div>
              <div class="var-layout-tray-items">
                <span :if={@hidden_entries == []} class="empty">{gettext("No hidden fields.")}</span>
                <div :for={entry <- @hidden_entries} class="var-tray-chip">
                  <span>{entry.key}</span>
                  <button type="button" phx-click={show_modal("##{modal_id(@id, entry)}")}>
                    {gettext("Edit")}
                  </button>
                  <button
                    :if={!@locked}
                    type="button"
                    name={"#{@field.form.name}[drop_fields_ids][]"}
                    value={entry.index}
                    phx-click={JS.dispatch("change")}
                    aria-label={gettext("Delete field %{key}", key: entry.key)}
                  >
                    {gettext("Delete")}
                  </button>
                </div>
                <button
                  :if={!@locked}
                  type="button"
                  class="form-fields-tray-add"
                  phx-click={JS.push("add_field", value: %{type: :hidden}, target: @myself)}
                >
                  <.icon name="plus" />
                  {gettext("Hidden field")}
                </button>
              </div>
            </section>
          </div>
        </section>

        <section class="var-layout-panel">
          <div class="var-layout-panel-head">
            <div>
              <h2>{gettext("What visitors see")}</h2>
              <p class="var-layout-sub">{gettext("The form's default markup, live from the fields beside it.")}</p>
            </div>
          </div>
          <div class="var-layout-preview-scroll">
            <div class="form-fields-preview">
              <Brando.HTML.Forms.site_form form={@preview} id={"#{@id}-preview"} preview />
            </div>
          </div>
        </section>
      </div>

      <Content.modal :if={!@locked} title={gettext("Add field")} id={"#{@id}-add"} medium>
        <div class="module-type-picker">
          <button
            :for={type <- @types}
            type="button"
            class="module-type-option"
            phx-click={JS.push("add_field", value: %{type: type.value}, target: @myself) |> hide_modal("##{@id}-add")}
          >
            <span>{type.label}</span>
            <small>{type_hint(type.value)}</small>
          </button>
        </div>
      </Content.modal>

      <div class="form-fields-forms">
        <.inputs_for :let={field_form} field={@field} skip_hidden>
          <% entry = Enum.find(@entries, &(&1.index == field_form.index)) %>
          <%= if entry do %>
            <.field_modal
              entry={entry}
              field_form={field_form}
              id={modal_id(@id, entry)}
              show={entry.uid == @open_uid}
              locked={@locked}
              types={@types}
              widths={@widths}
              source={Map.get(@source_fields, entry.uid)}
              source_language={@source_language}
              target={@myself}
            />
          <% end %>

          <%!-- Layout is posted from the changeset, not the field's value: an
                event that puts a value back to the saved one drops the change,
                and the field would then fall back to the stale posted param. --%>
          <input :if={entry} type="hidden" name={field_form[:width].name} value={entry.saved_width} />
          <input :if={entry} type="hidden" name={field_form[:new_row].name} value={to_string(entry.saved_new_row)} />
          <input type="hidden" name={field_form[:id].name} value={field_form[:id].value} />
          <input type="hidden" name={field_form[:_persistent_id].name} value={field_form.index} />
          <input type="hidden" name={field_form[:uid].name} value={field_form[:uid].value} />
          <input type="hidden" name={"#{@field.form.name}[sort_fields_ids][]"} value={field_form.index} />
        </.inputs_for>
        <input type="hidden" name={"#{@field.form.name}[drop_fields_ids][]"} />
      </div>
    </div>
    """
  end

  attr :entry, :map, required: true
  attr :widths, :list, required: true
  attr :locked, :boolean, required: true
  attr :target, :any, required: true
  attr :modal_id, :string, required: true
  attr :drop_name, :string, required: true

  defp chip(%{entry: %{type: :section}} = assigns) do
    ~H"""
    <div class="var-chip form-section-chip" data-key={@entry.uid} data-width="full">
      <span class="var-chip-type">{gettext("Section")}</span>
      <button type="button" class="var-chip-label" phx-click={show_modal("##{@modal_id}")}>
        {@entry.label || gettext("Untitled section")}
      </button>
      <.chip_actions :if={!@locked} entry={@entry} target={@target} drop_name={@drop_name} />
    </div>
    """
  end

  defp chip(assigns) do
    ~H"""
    <div class="var-chip" data-key={@entry.uid} data-width={@entry.width}>
      <div class="var-chip-top">
        <span class="var-chip-key" title={@entry.key}>
          {@entry.key}<span :if={@entry.required} class="form-field-required" title={gettext("Required")}>*</span>
        </span>
        <span class="var-chip-type">{type_label(@entry.type)}{option_count(@entry)}</span>
      </div>

      <button
        type="button"
        class="var-chip-label"
        phx-click={show_modal("##{@modal_id}")}
        aria-label={gettext("Edit field %{key}", key: @entry.key)}
      >
        {@entry.label || @entry.key}
      </button>

      <div class="var-chip-footer">
        <div class="var-chip-widths">
          <div class="var-width-group">
            <button
              :for={width <- @widths}
              type="button"
              class={width.value == @entry.width && "on"}
              title={width.hint}
              disabled={@locked}
              phx-click={JS.push("set_width", value: %{uid: @entry.uid, width: width.value}, target: @target)}
            >
              {width.label}
            </button>
          </div>
        </div>

        <.chip_actions :if={!@locked} entry={@entry} target={@target} drop_name={@drop_name} />
      </div>
    </div>
    """
  end

  attr :entry, :map, required: true
  attr :target, :any, required: true
  attr :drop_name, :string, required: true

  defp chip_actions(assigns) do
    ~H"""
    <div class="var-chip-actions">
      <button
        :if={Field.input?(@entry.type)}
        type="button"
        class={["form-field-required-toggle", @entry.required && "on"]}
        title={
          if @entry.required, do: gettext("Required — click to make optional"), else: gettext("Optional — click to require")
        }
        aria-pressed={to_string(@entry.required)}
        phx-click={JS.push("toggle_required", value: %{uid: @entry.uid}, target: @target)}
      >
        {gettext("req")}
      </button>
      <button
        type="button"
        title={gettext("Duplicate")}
        aria-label={gettext("Duplicate field %{key}", key: @entry.key)}
        phx-click={JS.push("duplicate_field", value: %{uid: @entry.uid}, target: @target)}
      >
        <.icon name="copy" />
      </button>
      <button
        type="button"
        class="var-chip-danger"
        title={gettext("Delete")}
        aria-label={gettext("Delete field %{key}", key: @entry.key)}
        name={@drop_name}
        value={@entry.index}
        phx-click={JS.dispatch("change")}
      >
        <.icon name="trash" />
      </button>
    </div>
    """
  end

  attr :entry, :map, required: true
  attr :field_form, :any, required: true
  attr :id, :string, required: true
  attr :show, :boolean, required: true
  attr :locked, :boolean, required: true
  attr :types, :list, required: true
  attr :widths, :list, required: true
  attr :source, :any, default: nil
  attr :source_language, :any, default: nil
  attr :target, :any, required: true

  defp field_modal(assigns) do
    ~H"""
    <Content.modal
      title={gettext("Edit field")}
      subtitle={"#{@entry.key} · #{type_label(@entry.type)}"}
      icon="list"
      id={@id}
      show={@show}
      close={JS.push("close_field", target: @target) |> hide_modal("##{@id}")}
      wide
    >
      <div class={["form-field-editor", @locked && "is-translation"]}>
        <aside :if={@locked} class="form-field-locked">
          <h3><.icon name="lock" />{gettext("Set by the source form")}</h3>
          <p>{gettext("Change these on the source, so every language submits the same fields.")}</p>
          <dl>
            <dt>{gettext("Key")}</dt>
            <dd>{@entry.key}</dd>
            <dt>{gettext("Type")}</dt>
            <dd>{type_label(@entry.type)}</dd>
            <dt :if={@entry.type != :section}>{gettext("Width")}</dt>
            <dd :if={@entry.type != :section}>{width_label(@entry.width)}</dd>
            <dt :if={Field.input?(@entry.type)}>{gettext("Required")}</dt>
            <dd :if={Field.input?(@entry.type)}>{if @entry.required, do: gettext("Yes"), else: gettext("No")}</dd>
          </dl>
          <input type="hidden" name={@field_form[:key].name} value={@field_form[:key].value} />
          <input type="hidden" name={@field_form[:type].name} value={@field_form[:type].value} />
          <input type="hidden" name={@field_form[:required].name} value={to_string(@entry.required)} />
        </aside>

        <div class="form-field-main">
          <div :if={!@locked} class="form-field-settings">
            <Input.text
              field={@field_form[:key]}
              label={gettext("Key")}
              instructions={gettext("Names the value in submissions. Lowercase letters, digits and underscores.")}
              monospace
            />
            <div class="field-wrapper">
              <label class="control-label" for={"#{@id}-type"}>{gettext("Type")}</label>
              <select id={"#{@id}-type"} class="admin-select" name={@field_form[:type].name}>
                <option :for={type <- @types} value={type.value} selected={type.value == @entry.type}>
                  {type.label}
                </option>
              </select>
            </div>
            <%!-- Checked from the changeset, like the layout inputs: the chip's
                  toggle can put the value back to the saved one. --%>
            <Input.toggle
              :if={Field.input?(@entry.type)}
              field={@field_form[:required]}
              label={gettext("Required")}
              compact
            >
              <input type="hidden" name={@field_form[:required].name} value="false" />
              <input
                type="checkbox"
                id={@field_form[:required].id}
                name={@field_form[:required].name}
                value="true"
                checked={@entry.required}
              />
            </Input.toggle>
            <input
              :if={!Field.input?(@entry.type)}
              type="hidden"
              name={@field_form[:required].name}
              value="false"
            />
          </div>

          <Input.text
            field={@field_form[:label]}
            label={label_label(@entry.type)}
            instructions={source_text(@source, :label, @source_language)}
          />

          <Input.text
            :if={@entry.type in [:text, :email, :tel, :textarea, :number, :select]}
            field={@field_form[:placeholder]}
            label={if @entry.type == :select, do: gettext("Empty choice"), else: gettext("Placeholder")}
            instructions={source_text(@source, :placeholder, @source_language)}
          />
          <input
            :if={@entry.type not in [:text, :email, :tel, :textarea, :number, :select]}
            type="hidden"
            name={@field_form[:placeholder].name}
            value={@field_form[:placeholder].value}
          />

          <Input.textarea
            :if={@entry.type != :hidden}
            field={@field_form[:help_text]}
            label={help_label(@entry.type)}
            instructions={source_text(@source, :help_text, @source_language)}
          />
          <input
            :if={@entry.type == :hidden}
            type="hidden"
            name={@field_form[:help_text].name}
            value={@field_form[:help_text].value}
          />

          <Input.text
            :if={@entry.type in [:hidden, :text, :email, :tel, :number, :date]}
            field={@field_form[:default_value]}
            label={if @entry.type == :hidden, do: gettext("Value"), else: gettext("Default value")}
          />
          <input
            :if={@entry.type not in [:hidden, :text, :email, :tel, :number, :date]}
            type="hidden"
            name={@field_form[:default_value].name}
            value={@field_form[:default_value].value}
          />

          <.options_editor
            :if={Field.options?(@entry.type)}
            entry={@entry}
            field_form={@field_form}
            locked={@locked}
            source={@source}
            target={@target}
          />
        </div>
      </div>

      <:footer>
        <button type="button" class="primary" phx-click={JS.push("close_field", target: @target) |> hide_modal("##{@id}")}>
          {gettext("Done")}
        </button>
      </:footer>
    </Content.modal>
    """
  end

  attr :entry, :map, required: true
  attr :field_form, :any, required: true
  attr :locked, :boolean, required: true
  attr :source, :any, default: nil
  attr :target, :any, required: true

  defp options_editor(assigns) do
    assigns = assign(assigns, :source_options, if(assigns.source, do: Map.new(Field.options(assigns.source)), else: %{}))

    ~H"""
    <div class="form-field-options">
      <div class="form-field-options-head">
        <span class="control-label">{gettext("Options")}</span>
        <small>{gettext("The value is stored with each submission; the label is what visitors see.")}</small>
      </div>
      <input type="hidden" name={"#{@field_form.name}[option_rows_present]"} value="1" />
      <table>
        <thead>
          <tr>
            <th>{gettext("Value")}</th>
            <th>{gettext("Label")}</th>
            <th :if={@locked}>{gettext("Source")}</th>
            <th :if={!@locked}></th>
          </tr>
        </thead>
        <tbody>
          <tr :for={{{value, label}, index} <- Enum.with_index(@entry.options)}>
            <td>
              <input
                type="text"
                class="text monospace"
                name={"#{@field_form.name}[option_rows][#{index}][value]"}
                value={value}
                readonly={@locked}
                aria-label={gettext("Value")}
              />
            </td>
            <td>
              <input
                type="text"
                class="text"
                name={"#{@field_form.name}[option_rows][#{index}][label]"}
                value={if label == value, do: own_label(@entry, value), else: label}
                placeholder={value}
                aria-label={gettext("Label")}
              />
            </td>
            <td :if={@locked} class="form-field-source">{Map.get(@source_options, value)}</td>
            <td :if={!@locked}>
              <button
                type="button"
                class="form-field-option-remove"
                aria-label={gettext("Remove option %{value}", value: value)}
                phx-click={JS.push("remove_option", value: %{uid: @entry.uid, index: index}, target: @target)}
              >
                <.icon name="x" />
              </button>
            </td>
          </tr>
        </tbody>
      </table>
      <button
        :if={!@locked}
        type="button"
        class="module-add-button"
        phx-click={JS.push("add_option", value: %{uid: @entry.uid}, target: @target)}
      >
        <.icon name="plus" />
        {gettext("Add option")}
      </button>
    </div>
    """
  end

  # `Field.options/1` falls back to the value for a missing label; the input
  # should show that the label is missing, not repeat the value.
  defp own_label(entry, value) do
    entry.form.source
    |> Changeset.get_field(:option_labels)
    |> Kernel.||(%{})
    |> Map.get(value)
  end

  # -- events -----------------------------------------------------------------

  def handle_event("add_field", %{"type" => type}, socket) do
    type = to_type(type)
    uid = Brando.Utils.generate_uid()

    # The key is chosen against the form's latest fields, so two quick adds
    # get two different keys.
    {:noreply,
     socket
     |> assign(:open_uid, uid)
     |> put_fields(fn entries ->
       field = %{new_field(type, free_key(entries, default_key(type))) | uid: uid}
       entries ++ [field |> Changeset.change() |> Map.put(:action, :insert)]
     end)}
  end

  def handle_event("duplicate_field", %{"uid" => uid}, socket) do
    {:noreply,
     put_fields(socket, fn entries ->
       case Enum.find_index(entries, &(Changeset.get_field(&1, :uid) == uid)) do
         nil -> entries
         index -> List.insert_at(entries, index + 1, duplicate(entries, index))
       end
     end)}
  end

  def handle_event("toggle_required", %{"uid" => uid}, socket) do
    {:noreply, update_field(socket, uid, &%{required: !(Changeset.get_field(&1, :required) == true)})}
  end

  def handle_event("set_width", %{"uid" => uid, "width" => width}, socket) do
    width = to_width(width)

    case room_for_width(socket.assigns.rows, uid, width) do
      :ok ->
        {:noreply, update_field(socket, uid, fn _ -> %{width: width} end)}

      {:error, free} ->
        send(
          self(),
          {:toast,
           gettext(
             "%{width} needs %{needed} units — only %{free} free in that row. Narrow another field, or start a new row.",
             width: width_label(width),
             needed: Layout.unit_cost(width),
             free: free
           )}
        )

        {:noreply, socket}
    end
  end

  # Reported by the `Brando.VarLayout` hook after a drop: rows of uids.
  def handle_event("reposition_vars", %{"rows" => rows}, socket) do
    rows =
      rows
      |> Enum.map(fn row -> Enum.filter(row, &is_binary/1) end)
      |> Enum.reject(&(&1 == []))

    # The first field of each row starts it.
    placed = for row <- rows, {uid, position} <- Enum.with_index(row), into: %{}, do: {uid, position == 0}

    order = List.flatten(rows)

    # Fields the canvas does not show (hidden ones) keep their place at the end.
    {:noreply,
     put_fields(socket, fn entries ->
       by_uid = Map.new(entries, &{Changeset.get_field(&1, :uid), &1})

       Enum.flat_map(order, fn uid ->
         case by_uid[uid] do
           nil -> []
           entry -> [Changeset.change(entry, %{new_row: Map.fetch!(placed, uid)})]
         end
       end) ++ Enum.reject(entries, &(Changeset.get_field(&1, :uid) in order))
     end)}
  end

  def handle_event("add_option", %{"uid" => uid}, socket) do
    {:noreply,
     update_field(socket, uid, fn changeset ->
       values = Changeset.get_field(changeset, :option_values) || []
       value = free_value(values, length(values) + 1)
       labels = Changeset.get_field(changeset, :option_labels) || %{}

       %{option_values: values ++ [value], option_labels: Map.put(labels, value, "")}
     end)}
  end

  def handle_event("remove_option", %{"uid" => uid, "index" => index}, socket) do
    {:noreply,
     update_field(socket, uid, fn changeset ->
       values = Changeset.get_field(changeset, :option_values) || []
       value = Enum.at(values, index)
       labels = Changeset.get_field(changeset, :option_labels) || %{}

       %{option_values: List.delete_at(values, index), option_labels: Map.delete(labels, value)}
     end)}
  end

  def handle_event("close_field", _, socket) do
    {:noreply, assign(socket, :open_uid, nil)}
  end

  # -- changeset plumbing -----------------------------------------------------

  defp update_field(socket, uid, fun) do
    put_fields(socket, &Enum.map(&1, fn changeset -> change_field(changeset, uid, fun) end))
  end

  defp change_field(changeset, uid, fun) do
    if Changeset.get_field(changeset, :uid) == uid,
      do: Changeset.change(changeset, fun.(changeset)),
      else: changeset
  end

  defp duplicate(entries, index) do
    %Field{} = original = entries |> Enum.at(index) |> Changeset.apply_changes()

    %{
      original
      | id: nil,
        form_id: nil,
        uid: Brando.Utils.generate_uid(),
        key: free_key(entries, "#{original.key}_copy"),
        sequence: nil
    }
    |> Ecto.put_meta(state: :built)
    |> Changeset.change()
    |> Map.put(:action, :insert)
  end

  # The Form owns the changeset; `fun` rebuilds its latest list of fields, not
  # the copy this component last rendered with, so quick changes in a row
  # (two adds, an option added twice) all land. It re-renders this component
  # with the result.
  defp put_fields(socket, fun) do
    {:noreply, socket} = SubformHelpers.send_op(socket, {:update, fun}, field: :fields)
    socket
  end

  defp room_for_width(rows, uid, width) do
    row =
      rows
      |> Enum.find([], fn row -> Enum.any?(row, &(&1.uid == uid)) end)
      |> Enum.reject(&(&1.uid == uid))

    if Layout.used_units(row) + Layout.unit_cost(width) <= Layout.row_units(),
      do: :ok,
      else: {:error, Layout.free_units(row)}
  end

  defp new_field(type, key) do
    options = if Field.options?(type), do: ["option_1", "option_2"], else: []

    %Field{
      uid: Brando.Utils.generate_uid(),
      key: key,
      type: type,
      label: if(type == :hidden, do: nil, else: type_label(type)),
      width: :full,
      new_row: type == :section,
      required: type == :consent,
      option_values: options,
      option_labels: Map.new(options, &{&1, ""})
    }
  end

  defp free_key(entries, base) do
    keys = MapSet.new(entries, &Changeset.get_field(&1, :key))

    Stream.iterate(1, &(&1 + 1))
    |> Stream.map(fn
      1 -> base
      n -> "#{base}_#{n}"
    end)
    |> Enum.find(&(not MapSet.member?(keys, &1)))
  end

  defp free_value(values, n) do
    candidate = "option_#{n}"
    if candidate in values, do: free_value(values, n + 1), else: candidate
  end

  defp default_key(:section), do: "section"
  defp default_key(:checkboxes), do: "choices"
  defp default_key(:radio), do: "choice"
  defp default_key(type), do: to_string(type)

  defp to_type(type) do
    Enum.find(Field.types(), :text, &(to_string(&1) == type))
  end

  defp to_width(width), do: Enum.find(@widths, :full, &(to_string(&1) == width))

  # -- labels -----------------------------------------------------------------

  defp modal_id(id, entry), do: "#{id}-field-#{entry.uid}"

  defp section_row?([%{type: :section}]), do: true
  defp section_row?(_), do: false

  defp option_count(%{type: type, options: options}) do
    if Field.options?(type), do: " · #{length(options)}"
  end

  defp source_text(nil, _field, _language), do: nil

  defp source_text(source, field, language) do
    case Map.get(source, field) do
      text when is_binary(text) and text != "" -> "#{String.upcase(to_string(language))}: #{text}"
      _ -> nil
    end
  end

  defp label_label(:section), do: gettext("Heading")
  defp label_label(:consent), do: gettext("Consent text")
  defp label_label(_), do: gettext("Label")

  defp help_label(:section), do: gettext("Description")
  defp help_label(:consent), do: gettext("Details")
  defp help_label(_), do: gettext("Help text")

  defp width_label(:full), do: "1/1"
  defp width_label(:half), do: "1/2"
  defp width_label(:third), do: "1/3"
  defp width_label(:fourth), do: "1/4"

  defp width_hint(:full), do: gettext("Full row")
  defp width_hint(:half), do: gettext("Half a row — 6 of 12 units")
  defp width_hint(:third), do: gettext("A third — 4 of 12 units")
  defp width_hint(:fourth), do: gettext("A quarter — 3 of 12 units")

  @doc false
  def type_label(:text), do: gettext("Text")
  def type_label(:email), do: gettext("Email")
  def type_label(:tel), do: gettext("Phone")
  def type_label(:textarea), do: gettext("Long text")
  def type_label(:number), do: gettext("Number")
  def type_label(:date), do: gettext("Date")
  def type_label(:select), do: gettext("Dropdown")
  def type_label(:radio), do: gettext("Single choice")
  def type_label(:checkboxes), do: gettext("Multiple choice")
  def type_label(:checkbox), do: gettext("Checkbox")
  def type_label(:consent), do: gettext("Consent")
  def type_label(:hidden), do: gettext("Hidden")
  def type_label(:section), do: gettext("Section")
  def type_label(type), do: to_string(type)

  defp type_hint(:text), do: gettext("A single line, such as a name")
  defp type_hint(:email), do: gettext("Checked as an email address; can be replied to")
  defp type_hint(:tel), do: gettext("A phone number")
  defp type_hint(:textarea), do: gettext("Several lines, such as a message")
  defp type_hint(:number), do: gettext("A number")
  defp type_hint(:date), do: gettext("A date, picked from a calendar")
  defp type_hint(:select), do: gettext("One option from a list")
  defp type_hint(:radio), do: gettext("One option, all shown at once")
  defp type_hint(:checkboxes), do: gettext("Any number of options")
  defp type_hint(:checkbox), do: gettext("A single yes or no")
  defp type_hint(:consent), do: gettext("A box visitors must tick, such as accepting a privacy policy")
  defp type_hint(:hidden), do: gettext("A fixed value sent with every submission")
  defp type_hint(:section), do: gettext("A heading that starts a new group of fields")
end
