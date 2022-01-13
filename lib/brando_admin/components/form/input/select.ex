defmodule BrandoAdmin.Components.Form.Input.Select do
  use BrandoAdmin, :live_component
  import Brando.Gettext

  alias BrandoAdmin.Components.Form.FieldBase
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

  # data show_filter, :boolean
  # data resetable, :boolean
  # data open, :boolean
  # data narrow, :boolean
  # data selected_option, :any
  # data input_options, :list
  # data select_label, :string
  # data select_form, :form
  # data select_changeset, :any
  # data filter_string, :string
  # data modal_id, :string
  # data form_translations, :any

  # slot default

  import Brando.Gettext

  def mount(socket) do
    {:ok,
     socket
     |> assign(:open, false)
     |> assign(:filter_string, "")}
  end

  def update(assigns, socket) do
    selected_option = get_selected_option(assigns.form, assigns.field)

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
     |> assign(:selected_option, selected_option)
     |> assign_input_options()
     |> assign_label()
     |> assign(:narrow, narrow)
     |> assign(:resetable, resetable)
     |> assign(:show_filter, show_filter)
     |> assign(:changeset_fun, changeset_fun)
     |> assign(:update_relation, update_relation)
     |> assign(:default, default)
     |> assign(:entry_form, entry_form)
     |> maybe_assign_select_changeset()
     |> maybe_assign_select_form()
     |> assign_new(:inner_block, fn -> nil end)
     |> assign_new(:modal_id, fn ->
       "select-#{assigns.id}-modal"
     end)}
  end

  def assign_input_options(%{assigns: %{form: form, opts: opts}} = socket) do
    assign_new(socket, :input_options, fn -> get_input_options(form, opts) end)
  end

  def update_input_options(%{assigns: %{form: form, opts: opts}} = socket) do
    assign(socket, :input_options, get_input_options(form, opts))
  end

  defp get_selected_option(form, field) do
    case input_value(form, field) do
      "" -> ""
      nil -> nil
      res when is_atom(res) -> to_string(res)
      res when is_integer(res) -> to_string(res)
      res -> res
    end
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

      options when is_list(options) ->
        options
    end
    |> Enum.map(&ensure_string_values/1)
  end

  defp ensure_string_values(%{label: label, value: value}) when not is_binary(value) do
    %{label: label, value: to_string(value)}
  end

  defp ensure_string_values(map), do: map

  def assign_label(
        %{assigns: %{input_options: input_options, selected_option: selected_option}} = socket
      ) do
    assign(socket, :select_label, get_label(input_options, selected_option))
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
    socket
    |> assign(:select_changeset, nil)
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
      <FieldBase.render
        form={@form}
        field={@field}
        label={@label}
        instructions={@instructions}
        class={@class}
        compact={@compact}>

        <%= hidden_input @form, @field, value: @selected_option %>

        <div class="multiselect">
          <div>
            <span class="select-label">
              <%= if @inner_block do %>
                <%= render_slot @inner_block %>
              <% else %>
                <%= if @selected_option do %>
                  <%= @select_label |> raw %>
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
          <.live_component module={Modal} title={gettext "Select option"} id={@modal_id} narrow={@narrow}>
            <div class="select-modal">
              <%= if @show_filter && !Enum.empty?(@input_options) do %>
                <div
                  id={"#{@form.id}-#{@field}-select-modal-filter"}
                  class="select-filter"
                  phx-hook="Brando.SelectFilter">
                  <div class="field-wrapper">
                    <div class="label-wrapper">
                      <label for="select-modal-search" class="control-label">
                        <span><%= gettext("Filter options") %></span>
                      </label>
                    </div>
                    <div class="field-base">
                      <input class="text" name="select-modal-search" type="text" value={@filter_string}>
                    </div>
                  </div>
                </div>
              <% end %>

              <div class="options">
                <h2 class="titlecase"><%= gettext "Available options" %></h2>
                <%= if Enum.empty?(@input_options) do %>
                  <%= gettext("No options found") %>
                <% end %>
                <%= for opt <- @input_options do %>
                  <button
                    type="button"
                    class={render_classes([
                      "options-option",
                      "option-selected": opt.value == @selected_option
                    ])}
                    data-label={opt.label}
                    value={opt.value}
                    phx-click={JS.push("select_option", target: @myself) |> hide_modal("##{@modal_id}")}>
                    <%= opt.label |> raw %>
                  </button>
                <% end %>
              </div>

              <%= if @select_form do %>
                <.form
                  for={@select_changeset}
                  phx-change={JS.push("validate_new_entry", target: @myself)}
                  let={entry_form}>
                  <%= gettext("Create entry") %>

                  <code style="font-family: monospace; font-size: 11px"><pre>
                  <%= inspect @select_changeset, pretty: true %>
                  </pre></code>
                  <br>
                  <%= for tab <- @select_form.tabs do %>
                    <div
                      class={"form-tab active"}
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
                    <%= gettext("Save") %>
                  </button>
                </.form>
              <% end %>

              <%= if @resetable do %>
                <div class="reset">
                  <button
                    type="button"
                    class="secondary"
                    phx-click={JS.push("reset", target: @myself)}>
                    <%= gettext("Reset value") %>
                  </button>
                </div>
              <% end %>
            </div>
          </.live_component>
        </div>
      </FieldBase.render>
    </div>
    """
  end

  defp get_label(input_options, selected_option) do
    case Enum.find(input_options, &(&1.value == selected_option)) do
      nil -> gettext("No selection")
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
         |> update_input_options()}

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
            form: form,
            input_options: input_options,
            update_relation: update_relation
          }
        } = socket
      ) do
    label = get_label(input_options, value)
    changeset = form.source

    module = changeset.data.__struct__
    form_id = "#{module.__naming__().singular}_form"

    if update_relation do
      {update_field, fetcher_fn} = update_relation

      fetched_relation =
        case fetcher_fn.(value) do
          {:ok, fetched_relation} -> fetched_relation
          _ -> nil
        end

      send_update(BrandoAdmin.Components.Form,
        id: form_id,
        action: :update_entry_relation,
        updated_relation: fetched_relation,
        field: update_field,
        force_validation: true
      )
    end

    {:noreply,
     socket
     |> assign(:selected_option, value)
     |> assign(:select_label, label)
     |> push_event("b:validate", %{})}
  end

  def handle_event(
        "reset",
        _,
        %{assigns: %{input_options: input_options}} = socket
      ) do
    label = get_label(input_options, "")

    {:noreply,
     socket
     |> assign(:selected_option, "")
     |> assign(:select_label, label)}
  end
end
