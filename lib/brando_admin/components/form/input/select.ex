defmodule BrandoAdmin.Components.Form.Input.Select do
  use BrandoAdmin, :live_component
  use Gettext, backend: Brando.Gettext
  import BrandoAdmin.Components.Content.List.Row, only: [status_circle: 1]

  alias BrandoAdmin.Components.Content
  alias BrandoAdmin.Components.Form
  alias BrandoAdmin.Components.Form.Fieldset
  alias BrandoAdmin.Components.Form.Input

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

  use Gettext, backend: Brando.Gettext

  def render(assigns) do
    ~H"""
    <div>
      <Form.field_base
        field={@field}
        label={@label}
        instructions={@instructions}
        class={@class}
        compact={@compact}
      >
        <Input.input type={:hidden} field={@field} value={@selected_option} publish={@publish} />
        <div class="multiselect">
          <div>
            <span class="select-label">
              <%= if @inner_block do %>
                <%= render_slot(@inner_block) %>
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
            phx-click={JS.push("toggle_modal", target: @myself) |> show_modal("##{@modal_id}")}
          >
            <%= if @open do %>
              <%= gettext("Close") %>
            <% else %>
              <%= gettext("Select") %>
            <% end %>
          </button>
          <Content.modal
            id={@modal_id}
            title={gettext("Select option")}
            narrow={@narrow}
            close={JS.push("toggle_modal", target: @myself) |> hide_modal("##{@modal_id}")}
          >
            <%= if @open do %>
              <div class="select-modal">
                <%= if @show_filter && !Enum.empty?(@input_options) do %>
                  <div
                    id={"#{@field.id}-select-modal-filter"}
                    class="select-filter"
                    phx-hook="Brando.SelectFilter"
                  >
                    <div class="field-wrapper">
                      <div class="label-wrapper">
                        <label for="select-modal-search" class="control-label">
                          <span><%= gettext("Filter options") %></span>
                        </label>
                      </div>
                      <div class="field-base">
                        <input
                          class="text"
                          name="select-modal-search"
                          type="text"
                          value={@filter_string}
                        />
                      </div>
                    </div>
                  </div>
                <% end %>

                <div class="options">
                  <h2 class="titlecase"><%= gettext("Available options") %></h2>
                  <%= if Enum.empty?(@input_options) do %>
                    <%= gettext("No options found") %>
                  <% end %>
                  <%= for opt <- @input_options do %>
                    <button
                      type="button"
                      class={[
                        "options-option",
                        is_selected?(opt, @selected_option) && "option-selected"
                      ]}
                      data-label={extract_label(opt)}
                      value={extract_value(opt)}
                      phx-click={
                        JS.push("select_option", target: @myself)
                        |> JS.push("toggle_modal", target: @myself)
                        |> hide_modal("##{@modal_id}")
                      }
                    >
                      <%!-- TODO: get rid of is_selected? --%>
                      <.get_label opt={opt} />
                    </button>
                  <% end %>
                </div>

                <%= if @select_form do %>
                  <.form
                    :let={entry_form}
                    for={@select_changeset}
                    phx-change={JS.push("validate_new_entry", target: @myself)}
                  >
                    <%= gettext("Create entry") %>
                    <code style="font-family: monospace; font-size: 11px">
                      <pre>
                    <%= inspect @select_changeset, pretty: true %>
                    </pre>
                    </code>
                    <br />
                    <%= for tab <- @select_form.tabs do %>
                      <div class="form-tab active" data-tab-name={tab.name}>
                        <div class="row">
                          <%= for fieldset <- tab.fields do %>
                            <Fieldset.render
                              translations={@form_translations}
                              form={entry_form}
                              parent_uploads={[]}
                              fieldset={fieldset}
                            />
                          <% end %>
                        </div>
                      </div>
                    <% end %>
                    <button
                      phx-click={JS.push("save_new_entry", target: @myself)}
                      type="button"
                      class="primary"
                    >
                      <%= gettext("Save") %>
                    </button>
                  </.form>
                <% end %>
              </div>
            <% end %>
            <:footer>
              <div class="flex-h">
                <button
                  type="button"
                  class="primary"
                  phx-click={JS.push("toggle_modal", target: @myself) |> hide_modal("##{@modal_id}")}
                >
                  OK
                </button>
                <%= if @resetable do %>
                  <div class="reset">
                    <button
                      type="button"
                      class="secondary"
                      value={nil}
                      phx-click={JS.push("select_option", target: @myself)}
                    >
                      <%= gettext("Reset value") %>
                    </button>
                  </div>
                <% end %>
              </div>
            </:footer>
          </Content.modal>
        </div>
      </Form.field_base>
    </div>
    """
  end

  def mount(socket) do
    {:ok,
     socket
     |> assign(:open, false)
     |> assign(:filter_string, "")
     |> assign_new(:publish, fn -> true end)}
  end

  def update(%{action: :force_refresh_options}, socket) do
    {:ok, update_input_options(socket)}
  end

  def update(assigns, socket) do
    selected_option = get_selected_option(assigns.field)

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
     |> assign_input_options()
     |> assign(:selected_option, selected_option)
     |> assign_label()
     |> assign_new(:narrow, fn -> narrow end)
     |> assign_new(:resetable, fn -> resetable end)
     |> assign_new(:show_filter, fn -> show_filter end)
     |> assign_new(:changeset_fun, fn -> changeset_fun end)
     |> assign_new(:update_relation, fn -> update_relation end)
     |> assign_new(:default, fn -> default end)
     |> assign_new(:entry_form, fn -> entry_form end)
     |> maybe_assign_select_changeset()
     |> maybe_assign_select_form()
     |> assign_new(:inner_block, fn -> nil end)
     |> assign_new(:modal_id, fn -> "select-#{assigns.id}-modal" end)}
  end

  def assign_input_options(%{assigns: %{field: field, opts: opts}} = socket) do
    assign_new(socket, :input_options, fn -> get_input_options(field, opts) end)
  end

  def update_input_options(%{assigns: %{field: field, opts: opts}} = socket) do
    assign(socket, :input_options, get_input_options(field, opts))
  end

  defp get_selected_option(field) do
    case field.value do
      "" -> ""
      nil -> nil
      res when is_atom(res) -> to_string(res)
      res when is_integer(res) -> to_string(res)
      res -> res
    end
  end

  defp get_input_options(field, opts) do
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
        options_fun.(field.form, opts)

      options when is_list(options) ->
        options
    end
    |> Enum.map(&ensure_string_values/1)
    |> Enum.reject(&is_nil/1)
  end

  defp ensure_string_values(%{label: label, value: value}) when not is_binary(value) do
    %{label: label, value: to_string(value)}
  end

  defp ensure_string_values(%Ecto.Changeset{action: :replace}), do: nil

  defp ensure_string_values(%Ecto.Changeset{} = changeset),
    do: Ecto.Changeset.apply_changes(changeset)

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

  defp is_selected?(%{value: value}, opt) do
    value == opt
  end

  defp is_selected?(%{id: id}, opt) do
    to_string(id) == opt
  end

  defp extract_label(%{opt: %{label: label}}), do: label

  defp extract_label(%{opt: entry}) do
    identifier = entry.__struct__.__identifier__(entry, skip_cover: true)
    identifier.title
  end

  defp extract_label(%Brando.Content.Var.Option{label: label}), do: label

  defp extract_label(%{__struct__: _} = entry) do
    identifier = entry.__struct__.__identifier__(entry, skip_cover: true)
    identifier.title
  end

  defp extract_label(%{label: label}) do
    label
  end

  defp extract_label(_) do
    "No label found"
  end

  defp extract_value(%{value: value}), do: value
  defp extract_value(%{id: value}), do: value
  defp extract_value(%Brando.Content.Var.Option{value: value}), do: value

  defp get_label(%{opt: %{label: _}} = assigns) do
    assigns = assign_new(assigns, :deletable, fn -> false end)

    ~H"""
    — <%= @opt.label |> raw %>
    """
  end

  defp get_label(%{opt: nil} = assigns) do
    ~H"""
    <%= gettext("Missing option") %>
    """
  end

  defp get_label(%{opt: entry} = assigns) do
    identifier = entry.__struct__.__identifier__(entry, skip_cover: true)

    assigns =
      assigns
      |> assign(:entry_id, entry.id)
      |> assign(:identifier, identifier)
      |> assign_new(:deletable, fn -> false end)
      |> assign_new(:target, fn -> nil end)

    ~H"""
    <.status_circle status={@identifier.status} /> <%= @identifier.title %>
    <%= if @deletable do %>
      <button
        class="delete tiny"
        type="button"
        value={@entry_id}
        phx-click={JS.push("select_option", target: @target)}
      >
        <svg viewBox="0 0 16 16" fill="none" xmlns="http://www.w3.org/2000/svg">
          <line x1="1.35355" y1="0.646447" x2="15.4957" y2="14.7886" stroke="#333333" />
          <line x1="0.576134" y1="14.7168" x2="14.7183" y2="0.574624" stroke="#333333" />
        </svg>
      </button>
    <% end %>
    """
  end

  defp get_label(input_options, selected_option) do
    case Enum.find(input_options, fn
           %{value: value} -> value == selected_option
           %{id: id} -> to_string(id) == selected_option
         end) do
      nil -> gettext("No selection")
      opt -> extract_label(opt)
    end
  end

  def handle_event("toggle_modal", _, socket) do
    socket = (!socket.assigns.open && update_input_options(socket)) || socket
    {:noreply, assign(socket, :open, !socket.assigns.open)}
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
      |> changeset_fun.(entry_params, current_user)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, select_changeset: select_changeset)}
  end

  def handle_event("select_option", %{"value" => value}, socket) do
    update_relation = socket.assigns.update_relation
    value = if value == "", do: nil, else: value

    if update_relation do
      on_change = socket.assigns.on_change
      {update_field, fetcher_fn} = update_relation

      fetched_relation =
        if is_nil(value) do
          nil
        else
          case fetcher_fn.(value) do
            {:ok, fetched_relation} -> fetched_relation
            _ -> nil
          end
        end

      on_change.(%{
        event: "update_entry_relation",
        path: [update_field],
        updated_relation: fetched_relation
      })
    end

    socket
    |> assign(:selected_option, value)
    |> assign_label()
    |> then(&{:noreply, &1})
  end

  def handle_event("reset", _, socket) do
    {:noreply,
     socket
     |> assign(:selected_option, nil)
     |> assign_label()}
  end
end
