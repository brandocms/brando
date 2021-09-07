defmodule BrandoAdmin.Components.Form.Input.MultiSelect do
  use Surface.LiveComponent
  use Phoenix.HTML

  alias BrandoAdmin.Components.Form.FieldBase
  alias BrandoAdmin.Components.Form.Fieldset
  alias BrandoAdmin.Components.Modal
  alias BrandoAdmin.Toast

  alias Surface.Components.Form

  prop blueprint, :any
  prop form, :form
  prop field, :any
  prop label, :string
  prop instructions, :string
  prop class, :string
  prop options, :any
  prop current_user, :any

  data open, :boolean
  data selected_options, :list
  data input_options, :list
  data select_form, :form
  data select_changeset, :any
  data selected_labels, :list
  data filter_string, :string
  data modal_id, :string
  data singular, :string
  data show_filter, :boolean
  data narrow, :boolean
  data creating, :boolean
  data resetable, :boolean

  slot default

  # import Brando.Gettext

  def mount(socket) do
    {:ok,
     socket
     |> assign(:open, false)
     |> assign(:creating, false)
     |> assign(:filter_string, "")}
  end

  def update(%{input: %{opts: opts}, blueprint: _blueprint} = assigns, socket) do
    show_filter = Keyword.get(opts, :filter, true)
    narrow = Keyword.get(opts, :narrow)
    resetable = Keyword.get(opts, :resetable)

    changeset_fun = Keyword.get(opts, :changeset_fun)
    default = Keyword.get(opts, :default)
    entry_form = Keyword.get(opts, :form)

    {:ok,
     socket
     |> assign(assigns)
     |> assign_selected_options()
     |> assign_input_options()
     |> assign_label()
     |> assign_labels()
     |> assign(:narrow, narrow)
     |> assign(:resetable, resetable)
     |> assign(:show_filter, show_filter)
     |> assign(:changeset_fun, changeset_fun)
     |> assign(:default, default)
     |> assign(:entry_form, entry_form)
     |> maybe_assign_select_changeset()
     |> maybe_assign_select_form()
     |> assign_new(:modal_id, fn ->
       "select-#{assigns.form.id}-#{assigns.input.name}-modal"
     end)}
  end

  def assign_selected_options(%{assigns: %{form: form, input: %{name: name}}} = socket) do
    assign_new(socket, :selected_options, fn ->
      raw_value =
        case input_value(form, name) do
          nil -> []
          "" -> []
          %Ecto.Association.NotLoaded{} -> []
          val -> val
        end

      selected_options =
        Enum.map(raw_value, fn
          %{id: id} ->
            to_string(id)

          val ->
            val
        end)

      selected_options
    end)
  end

  def assign_input_options(%{assigns: %{form: form, input: %{opts: opts}}} = socket) do
    assign_new(socket, :input_options, fn -> get_input_options(form, opts) end)
  end

  def update_input_options(%{assigns: %{form: form, input: %{opts: opts}}} = socket) do
    assign(socket, :input_options, get_input_options(form, opts))
  end

  defp get_input_options(form, opts) do
    case Keyword.get(opts, :options) do
      :languages ->
        languages = Brando.config(:languages)
        Enum.map(languages, fn [{:value, val}, {:text, text}] -> %{label: text, value: val} end)

      nil ->
        # schema = blueprint.modules.schema
        []

      options_fun when is_function(options_fun) ->
        options_fun.(form, opts)
    end
    |> Enum.map(&ensure_string_values/1)
  end

  defp ensure_string_values(%{label: label, value: value}) when not is_binary(value) do
    %{label: label, value: to_string(value)}
  end

  defp ensure_string_values(map), do: map

  def assign_label(
        %{assigns: %{input_options: input_options, selected_options: selected_options}} = socket
      ) do
    assign(socket, :label, get_label(input_options, selected_options))
  end

  def assign_labels(
        %{assigns: %{input_options: input_options, selected_options: selected_options}} = socket
      ) do
    assign(
      socket,
      :selected_labels,
      Enum.map(selected_options, &get_label_for(input_options, &1))
    )
  end

  def maybe_assign_select_form(%{assigns: %{entry_form: {target_module, form_name}}} = socket) do
    assign(socket, :select_form, target_module.__form__(form_name))
  end

  def maybe_assign_select_form(socket) do
    assign(socket, :select_form, nil)
  end

  def maybe_assign_select_changeset(%{assigns: %{changeset_fun: nil}} = socket) do
    assign(socket, :select_changeset, nil)
  end

  def maybe_assign_select_changeset(
        %{assigns: %{changeset_fun: changeset_fun, default: default, current_user: current_user}} =
          socket
      ) do
    select_changeset = changeset_fun.(default, %{}, current_user, [])
    module = select_changeset.data.__struct__
    singular = module.__naming__.singular

    socket
    |> assign(:select_changeset, select_changeset)
    |> assign(:singular, singular)
    |> assign(:module, module)
  end

  def render(%{input: %{name: name, opts: opts}, blueprint: _blueprint} = assigns) do
    ~F"""
    <FieldBase
      blueprint={@blueprint}
      form={@form}
      class={opts[:class]}
      field={name}>

      {#if Enum.empty?(@selected_labels)}
        {hidden_input @form, name, id: "#{@form.name}-#{name}-empty", name: "#{@form.name}[#{name}]", value: ""}
      {#else}
        {#for opt <- @selected_options}
          {hidden_input @form, name, id: "#{@form.name}-#{name}-#{opt}", name: "#{@form.name}[#{name}][]", value: opt}
        {/for}
      {/if}

      {#if !Enum.empty?(@selected_labels)}
        <div class="selected-labels">
          {#for lbl <- @selected_labels}
            <div class="selected-label">
              <svg
                class="circle-filled"
                xmlns="http://www.w3.org/2000/svg"
                width="12"
                height="12"
                viewBox="0 0 12 12">
                <circle
                  r="6"
                  cy="6"
                  cx="6" />
              </svg>
              <div class="selected-label-text">{lbl}</div>
            </div>
          {/for}
        </div>
      {/if}

      <div class="multiselect">
        <div>
          <span>
            {#if slot_assigned?(:default)}
              <#slot />
            {#else}
              {#if @selected_options}
                {@label}
              {#else}
                No selection
              {/if}
            {/if}
          </span>
        </div>
        <button
          type="button"
          class="button-edit"
          :on-click="toggle"
          phx-value-id={@modal_id}>
          {#if @open}
            Close
          {#else}
            Select
          {/if}
        </button>
        <Modal title="Select options" id={@modal_id} narrow={@narrow}>
          <:header>
            {#if @select_form && !@creating}
              <button class="header-button" type="button" :on-click="show_form">Create {@singular}</button>
            {/if}
          </:header>
          {#if @show_filter && !Enum.empty?(@input_options) && !@creating}
            <div class="select-filter" id={"#{@form.id}-#{name}-select-modal-filter"} phx-hook="Brando.SelectFilter">
              <div class="field-wrapper">
                <div class="label-wrapper">
                  <label for="select-modal-search" class="control-label">
                    <span>Filter options</span>
                  </label>
                </div>
                <div class="field-base">
                  <input class="text" name="select-modal-search" type="text" value={@filter_string}>
                </div>
              </div>
            </div>
          {/if}

          <div class="select-modal-wrapper">
            {#if !@creating}
              <div class="select-modal">
                <div id={"#{@form.name}-#{name}-options"} class="options" phx-hook="Brando.SelectOptionsScroller">
                  <h2 class="titlecase">Available options</h2>
                  {#if Enum.empty?(@input_options)}
                    No options found
                  {/if}
                  {#for opt <- @input_options}
                    <button
                      type="button"
                      class={"options-option", "option-selected": opt.value in @selected_options}
                      data-label={opt.label}
                      value={opt.value}
                      :on-click="select_option">
                      {opt.label}
                    </button>
                  {/for}
                </div>

                {#if @resetable}
                  <div class="reset">
                    <button
                      type="button"
                      class="secondary"
                      :on-click="reset">
                      Reset value
                    </button>
                  </div>
                {/if}
              </div>
              <div class="selected-labels">
                <h2 class="titlecase">Currently selected</h2>
                {#if Enum.empty?(@selected_labels)}
                  None selected
                {#else}
                  {#for lbl <- @selected_labels}
                    <div class="selected-label">
                      <svg
                        class="circle-filled"
                        xmlns="http://www.w3.org/2000/svg"
                        width="12"
                        height="12"
                        viewBox="0 0 12 12">
                        <circle
                          r="6"
                          cy="6"
                          cx="6" />
                      </svg>
                      <div class="selected-label-text">{lbl}</div>
                    </div>
                  {/for}
                {/if}
              </div>
            {#else}
              {#if @select_form}
                <Form
                  for={@select_changeset}
                  change="validate_new_entry"
                  :let={form: entry_form}>
                  {#for {tab, _tab_idx} <- Enum.with_index(@select_form.tabs)}
                    <div
                      class={"form-tab", active: true}
                      data-tab-name={tab.name}>
                      <div class="row">
                        {#for {fieldset, fs_idx} <- Enum.with_index(tab.fields)}
                          <Fieldset
                            id={"#{entry_form.id}-fieldset-#{tab.name}-#{fs_idx}"}
                            blueprint={@blueprint}
                            form={entry_form}
                            uploads={[]}
                            fieldset={fieldset} />
                        {/for}
                      </div>
                    </div>
                  {/for}
                  <button
                    :on-click="save_new_entry"
                    type="button" class="primary">
                    Save
                  </button>
                  <button
                    :on-click="hide_form"
                    type="button" class="secondary">
                    Cancel
                  </button>
                </Form>
              {/if}
            {/if}
          </div>
        </Modal>
      </div>
    </FieldBase>
    """
  end

  defp get_label(_, []) do
    "<None selected>"
  end

  defp get_label(_, selected_options) do
    "#{Enum.count(selected_options)} selected"
  end

  defp get_label_for(input_options, selected_option) do
    case Enum.find(input_options, &(&1.value == selected_option)) do
      nil -> "<No value>"
      %{label: label} -> label
    end
  end

  def handle_event(
        "save_new_entry",
        _,
        %{
          assigns: %{
            select_changeset: select_changeset,
            module: module,
            singular: singular,
            current_user: current_user
          }
        } = socket
      ) do
    context = module.__modules__.context

    select_changeset =
      select_changeset
      |> Map.put(:action, :create)

    case apply(context, :"create_#{singular}", [select_changeset, current_user]) do
      {:ok, _} ->
        Toast.send_delayed("#{String.capitalize(singular)} created")

        {:noreply,
         socket
         |> assign(select_changeset: select_changeset)
         |> assign(:creating, false)
         |> update_input_options()
         |> maybe_assign_select_changeset()}

      {:error, %Ecto.Changeset{} = select_changeset} ->
        {:noreply, assign(socket, select_changeset: select_changeset)}
    end
  end

  def handle_event(
        "validate_new_entry",
        params,
        %{
          assigns: %{
            singular: singular,
            changeset_fun: changeset_fun,
            current_user: current_user,
            default: default
          }
        } = socket
      ) do
    entry_params = Map.get(params, singular)

    select_changeset =
      default
      |> changeset_fun.(entry_params, current_user, skip_villain: true)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, select_changeset: select_changeset)}
  end

  def handle_event(
        "select_option",
        %{"value" => value},
        %{
          assigns: %{
            selected_options: selected_options
          }
        } = socket
      ) do
    selected_options =
      case Enum.find(selected_options, &(&1 == value)) do
        nil ->
          [value | selected_options]

        _ ->
          Enum.reject(selected_options, &(&1 == value))
      end

    {:noreply,
     socket
     |> assign(:selected_options, selected_options)
     |> assign_labels()
     |> assign_label()}
  end

  def handle_event(
        "reset",
        _,
        %{assigns: %{input_options: input_options, modal_id: modal_id}} = socket
      ) do
    label = get_label(input_options, [])

    Modal.hide(modal_id)

    {:noreply,
     socket
     |> assign(:selected_options, [])
     |> assign(:label, label)}
  end

  def handle_event("show_form", _, socket) do
    {:noreply, assign(socket, :creating, true)}
  end

  def handle_event("hide_form", _, socket) do
    {:noreply, assign(socket, :creating, false)}
  end

  def handle_event("toggle", %{"id" => id}, socket) do
    Modal.show(id)
    {:noreply, socket}
  end
end
