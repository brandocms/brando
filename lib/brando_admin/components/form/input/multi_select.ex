defmodule BrandoAdmin.Components.Form.Input.MultiSelect do
  use BrandoAdmin, :live_component
  import Brando.Gettext

  alias BrandoAdmin.Components.Form
  alias BrandoAdmin.Components.Form.Fieldset
  alias BrandoAdmin.Components.Modal

  # prop form, :form
  # prop field, :atom
  # prop label, :string
  # prop placeholder, :string
  # prop instructions, :string
  # prop opts, :list, default: []
  # prop current_user, :map
  # prop uploads, :map

  # data class, :string
  # data monospace, :boolean
  # data disabled, :boolean
  # data debounce, :integer
  # data compact, :boolean

  # data open, :boolean
  # data selected_options, :list
  # data input_options, :list
  # data select_form, :form
  # data select_changeset, :any
  # data selected_labels, :list
  # data filter_string, :string
  # data modal_id, :string
  # data singular, :string
  # data show_filter, :boolean
  # data narrow, :boolean
  # data creating, :boolean
  # data resetable, :boolean
  # data form_translations, :any

  # slot default

  import Brando.Gettext

  def mount(socket) do
    {:ok,
     socket
     |> assign_new(:inner_block, fn -> nil end)
     |> assign(:open, false)
     |> assign(:creating, false)
     |> assign(:filter_string, "")}
  end

  def update(assigns, socket) do
    selected_options = get_selected_options(assigns.form, assigns.field)
    show_filter = Keyword.get(assigns.opts, :filter, true)
    narrow = Keyword.get(assigns.opts, :narrow)
    resetable = Keyword.get(assigns.opts, :resetable)

    changeset_fun = Keyword.get(assigns.opts, :changeset_fun)
    default = Keyword.get(assigns.opts, :default)
    entry_form = Keyword.get(assigns.opts, :form)
    update_relation = Keyword.get(assigns.opts, :update_relation)

    {:ok,
     socket
     |> assign(assigns)
     |> prepare_input_component()
     |> assign(:selected_options, selected_options)
     |> assign_input_options()
     |> assign_label()
     |> assign_labels()
     |> assign(:narrow, narrow)
     |> assign(:resetable, resetable)
     |> assign(:show_filter, show_filter)
     |> assign(:changeset_fun, changeset_fun)
     |> assign(:update_relation, update_relation)
     |> assign(:default, default)
     |> assign(:entry_form, entry_form)
     |> maybe_assign_select_changeset()
     |> maybe_assign_select_form()
     |> assign_new(:modal_id, fn ->
       "select-#{assigns.id}-modal"
     end)}
  end

  defp get_selected_options(form, field) do
    raw_values =
      case input_value(form, field) do
        "" -> []
        nil -> []
        %Ecto.Association.NotLoaded{} -> []
        val -> val
      end

    Enum.map(raw_values, fn
      %{id: id} ->
        to_string(id)

      val ->
        val
    end)
  end

  def assign_input_options(%{assigns: %{form: form, opts: opts}} = socket) do
    assign_new(socket, :input_options, fn -> get_input_options(form, opts) end)
  end

  def update_input_options(%{assigns: %{form: form, opts: opts}} = socket) do
    assign(socket, :input_options, get_input_options(form, opts))
  end

  defp get_input_options(form, opts) do
    case Keyword.get(opts, :options) do
      :languages ->
        languages = Brando.config(:languages)
        Enum.map(languages, fn [{:value, val}, {:text, text}] -> %{label: text, value: val} end)

      :admin_languages ->
        admin_languages = Brando.config(:admin_languages)

        Enum.map(admin_languages, fn [{:value, val}, {:text, text}] ->
          %{label: text, value: val}
        end)

      nil ->
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
    assign(socket, :count_label, get_label(input_options, selected_options))
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
    select_form = target_module.__form__(form_name)
    form_translations = target_module.__translations__()

    socket
    |> assign(:select_form, select_form)
    |> assign(:form_translations, form_translations)
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
    singular = module.__naming__().singular

    socket
    |> assign(:select_changeset, select_changeset)
    |> assign(:singular, singular)
    |> assign(:module, module)
  end

  def render(assigns) do
    ~H"""
    <div>
      <Form.field_base
        form={@form}
        field={@field}
        label={@label}
        instructions={@instructions}
        class={@class}
        compact={@compact}>
        <%= if Enum.empty?(@selected_labels) do %>
          <%= hidden_input @form, @field, id: "#{@form.name}-#{@field}-empty", name: "#{@form.name}[#{@field}]", value: "" %>
        <% else %>
          <%= for opt <- @selected_options do %>
            <%= hidden_input @form, @field, id: "#{@form.name}-#{@field}-#{opt}", name: "#{@form.name}[#{@field}][]", value: opt %>
          <% end %>
        <% end %>

        <%= if !Enum.empty?(@selected_labels) do %>
          <div class="selected-labels">
            <%= for lbl <- @selected_labels do %>
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
                <div class="selected-label-text"><%= lbl %></div>
              </div>
            <% end %>
          </div>
        <% end %>

        <div class="multiselect">
          <div>
            <span>
              <%= if @inner_block do %>
                <%= render_slot @inner_block %>
              <% else %>
                <%= if @selected_options do %>
                  <%= @count_label |> raw %>
                <% else %>
                  <%= gettext("No selection") %>
                <% end %>
              <% end %>
            </span>
          </div>
          <button
            type="button"
            class="button-edit"
            phx-click={show_modal("##{@modal_id}")}>
            <%= if @open do %>
              <%= gettext "Close" %>
            <% else %>
              <%= gettext "Select" %>
            <% end %>
          </button>
          <.live_component module={Modal} title={gettext "Select options"} id={@modal_id} narrow={@narrow}>
            <:header>
              <%= if @select_form && !@creating do %>
                <button class="header-button" type="button" phx-click={JS.push("show_form", target: @myself)}>Create <%= @singular %></button>
              <% end %>
            </:header>
            <%= if @show_filter && !Enum.empty?(@input_options) && !@creating do %>
              <div class="select-filter" id={"#{@form.id}-#{@field}-select-modal-filter"} phx-hook="Brando.SelectFilter">
                <div class="field-wrapper">
                  <div class="label-wrapper">
                    <label for="select-modal-search" class="control-label">
                      <span><%= gettext "Filter options" %></span>
                    </label>
                  </div>
                  <div class="field-base">
                    <input class="text" name="select-modal-search" type="text" value={@filter_string}>
                  </div>
                </div>
              </div>
            <% end %>

            <div class="select-modal-wrapper">
              <%= if !@creating do %>
                <div class="select-modal">
                  <div id={"#{@form.name}-#{@field}-options"} class="options" phx-hook="Brando.RememberScrollPosition">
                    <h2 class="titlecase"><%= gettext "Available options" %></h2>
                    <%= if Enum.empty?(@input_options) do %>
                      <%= gettext "No options found" %>
                    <% end %>
                    <%= for opt <- @input_options do %>
                      <button
                        type="button"
                        class={render_classes([
                          "options-option",
                          "option-selected": opt.value in @selected_options
                        ])}
                        data-label={opt.label}
                        value={opt.value}
                        phx-click={JS.push("select_option", target: @myself)}>
                        <%= opt.label |> raw %>
                      </button>
                    <% end %>
                  </div>

                  <%= if @resetable do %>
                    <div class="reset">
                      <button
                        type="button"
                        class="secondary"
                        phx-click={JS.push("reset", target: @myself) |> hide_modal("##{@modal_id}")}>
                        <%= gettext "Reset value" %>
                      </button>
                    </div>
                  <% end %>
                </div>
                <div class="selected-labels">
                  <h2 class="titlecase"><%= gettext "Currently selected" %></h2>
                  <%= if Enum.empty?(@selected_labels) do %>
                    <div class="empty-label"><%= gettext "None selected" %></div>
                  <% else %>
                    <%= for lbl <- @selected_labels do %>
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
                        <div class="selected-label-text"><%= lbl %></div>
                      </div>
                    <% end %>
                  <% end %>
                </div>
              <% else %>
                <%= if @select_form do %>
                  <.form
                    for={@select_changeset}
                    phx-change={JS.push("validate_new_entry", target: @myself)}
                    let={entry_form}>
                    <%= for tab <- @select_form.tabs do %>
                      <div
                        class={render_classes(["form-tab", active: true])}
                        data-tab-name={tab.name}>
                        <div class="row">
                          <%= for fieldset <- tab.fields do %>
                            <Fieldset.render
                              translations={@form_translations}
                              form={entry_form}
                              uploads={[]}
                              fieldset={fieldset} />
                          <% end %>
                        </div>
                      </div>
                    <% end %>
                    <button
                      phx-click={JS.push("save_new_entry", target: @myself)}
                      type="button" class="primary">
                      Save
                    </button>
                    <button
                      phx-click={JS.push("hide_form", target: @myself)}
                      type="button" class="secondary">
                      Cancel
                    </button>
                  </.form>
                <% end %>
              <% end %>
            </div>
          </.live_component>
        </div>
      </Form.field_base>
    </div>
    """
  end

  defp get_label(_, []) do
    gettext("<None selected>")
  end

  defp get_label(_, selected_options) do
    gettext("%{count} selected", count: Enum.count(selected_options))
  end

  defp get_label_for(input_options, selected_option) do
    case Enum.find(input_options, &(&1.value == selected_option)) do
      nil -> gettext("<No value>")
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
    context = module.__modules__().context

    select_changeset =
      select_changeset
      |> Map.put(:action, :create)

    case apply(context, :"create_#{singular}", [select_changeset, current_user]) do
      {:ok, _} ->
        send(self(), {:toast, "#{String.capitalize(singular)} created"})

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

  def handle_event("reset", _, %{assigns: %{input_options: input_options}} = socket) do
    label = get_label(input_options, [])

    {:noreply,
     socket
     |> assign(:selected_options, [])
     |> assign(:count_label, label)}
  end

  def handle_event("show_form", _, socket) do
    {:noreply, assign(socket, :creating, true)}
  end

  def handle_event("hide_form", _, socket) do
    {:noreply, assign(socket, :creating, false)}
  end
end
