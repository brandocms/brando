defmodule BrandoAdmin.Components.Form.Input.MultiSelect do
  use BrandoAdmin, :live_component
  import Brando.Gettext
  import BrandoAdmin.Components.Content.List.Row, only: [status_circle: 1]

  alias Brando.Exception.BlueprintError
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
  # prop parent_uploads, :map

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
    show_filter = Keyword.get(assigns.opts, :filter, true)
    narrow = Keyword.get(assigns.opts, :narrow)
    resetable = Keyword.get(assigns.opts, :resetable)
    relation_key = Keyword.get(assigns.opts, :relation_key, :id)

    changeset_fun = Keyword.get(assigns.opts, :changeset_fun)
    default = Keyword.get(assigns.opts, :default)
    entry_form = Keyword.get(assigns.opts, :form)
    update_relation = Keyword.get(assigns.opts, :update_relation)
    changeset = assigns.field.form.source

    {:ok,
     socket
     |> assign(assigns)
     |> prepare_input_component()
     |> assign(:relation_key, relation_key)
     |> assign_relation_type(assigns.field)
     |> assign_selected_options(changeset, assigns.field)
     |> assign_input_options()
     |> assign_selected_options_forms(assigns.field)
     |> assign_sequenced?(assigns.field)
     |> assign_relation_fields(assigns.field)
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
     |> assign_new(:modal_id, fn -> "select-#{assigns.id}-modal" end)}
  end

  defp assign_relation_fields(socket, field) do
    assign_new(socket, :relation_fields, fn ->
      module = field.form.data.__struct__

      if {:__relations__, 0} in module.__info__(:functions) do
        %{opts: %{module: rel_module}} = module.__relation__(field.field)

        # the rel module must have `@allow_mark_as_deleted true`
        if not rel_module.__allow_mark_as_deleted__ do
          raise BlueprintError,
            message: """
            Missing @allow_mark_as_deleted

            A multi select for a :has_many must have @allow_mark_as_deleted true set on the #{inspect(rel_module)}.
            You can set `@allow_mark_as_deleted true` on the #{inspect(rel_module)} module
            """
        end

        fields =
          Enum.map(rel_module.__relations__, &:"#{&1.name}_id") ++
            Enum.map(rel_module.__assets__, &:"#{&1.name}_id") ++
            Enum.map(rel_module.__attributes__, & &1.name)

        Enum.reject(fields, &(&1 == :sequence))
      else
        []
      end
    end)
  end

  defp assign_sequenced?(socket, field) do
    module = field.form.data.__struct__

    sequenced? =
      if {:__relations__, 0} in module.__info__(:functions) do
        %{opts: %{module: rel_module}} = module.__relation__(field.field)
        rel_module.has_trait(Brando.Trait.Sequenced)
      else
        false
      end

    assign(socket, :sequenced?, sequenced?)
  end

  defp assign_selected_options_forms(socket, field) do
    selected_options_forms =
      if socket.assigns.relation_type == :has_many do
        inputs_for(field.form, field.field)
      else
        nil
      end

    # TODO: assign_new and call again in select_option?
    assign(socket, :selected_options_forms, selected_options_forms)
  end

  defp assign_selected_options(socket, changeset, field) do
    selected_options = get_selected_options(changeset, field, socket.assigns.relation_type)
    assign(socket, :selected_options, selected_options)
  end

  defp assign_relation_type(socket, field) do
    module = field.form.data.__struct__

    relation_type =
      if {:__relations__, 0} in module.__info__(:functions) do
        relation = module.__relation__(field.field)
        relation.type
      else
        Map.get(module.__changeset__, field.field)
      end

    if relation_type == :has_many and socket.assigns.relation_key == :id do
      raise BlueprintError,
        message: """
        Multi selects for a :has_many relation needs a `relation_key`.

        Set this in your form:

            input :article_contributors, :multi_select,
              options: &__MODULE__.get_contributors/2,
              relation_key: :contributor_id,
              resetable: true,
              label: t("Contributors")
        """
    end

    assign(socket, :relation_type, relation_type)
  end

  defp get_selected_options(changeset, field, {:array, _}) do
    Ecto.Changeset.get_field(changeset, field.field) || []
  end

  defp get_selected_options(changeset, field, :many_to_many) do
    Ecto.Changeset.get_assoc(changeset, field.field, :struct)
  end

  defp get_selected_options(changeset, field, :has_many) do
    Ecto.Changeset.get_assoc(changeset, field.field)
  end

  defp get_selected_options(changeset, field, :embeds_many) do
    Ecto.Changeset.get_embed(changeset, field.field, :struct)
  end

  def assign_input_options(%{assigns: %{field: field, opts: opts}} = socket) do
    assign_new(socket, :input_options, fn ->
      get_input_options(field, opts)
    end)
  end

  def update_input_options(%{assigns: %{field: field, opts: opts}} = socket) do
    assign(socket, :input_options, get_input_options(field, opts))
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

      options ->
        options
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
    assign(
      socket,
      :count_label,
      get_count_label(input_options, selected_options, socket.assigns.relation_type)
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
        field={@field}
        label={@label}
        instructions={@instructions}
        class={@class}
        compact={@compact}>
        <%= if !Enum.empty?(@selected_options) do %>
          <div class="selected-labels">
            <.labels
              selected_options={@selected_options}
              input_options={@input_options}
              relation_type={@relation_type}
              relation_key={@relation_key}
              :let={opt}>
              <.get_label opt={opt} />
            </.labels>
          </div>
        <% end %>

        <div class="multiselect">
          <div>
            <span>
              <%= if @inner_block do %>
                <%= render_slot @inner_block %>
              <% else %>
                <%= if @selected_options != [] do %>
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
            phx-click={JS.push("toggle_modal", target: @myself) |> show_modal("##{@modal_id}")}>
            <%= if @open do %>
              <%= gettext "Close" %>
            <% else %>
              <%= gettext "Select" %>
            <% end %>
          </button>
          <Content.modal
            title={gettext "Select options"}
            id={@modal_id}
            narrow={@narrow}
            close={JS.push("toggle_modal", target: @myself) |> hide_modal("##{@modal_id}")}>
            <:header>
              <%= if @select_form && !@creating do %>
                <button class="header-button" type="button" phx-click={JS.push("show_form", target: @myself)}>Create <%= @singular %></button>
              <% end %>
            </:header>
            <%= if @show_filter && !Enum.empty?(@input_options) && !@creating do %>
              <div class="select-filter" id={"#{@field.id}-select-modal-filter"} phx-hook="Brando.SelectFilter">
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
                  <div id={"#{@field.id}-options"} class="options" phx-hook="Brando.RememberScrollPosition">
                    <h2 class="titlecase"><%= gettext "Available options" %></h2>
                    <%= if Enum.empty?(@input_options) do %>
                      <%= gettext "No options found" %>
                    <% end %>
                    <button
                      :for={opt <- @input_options}
                      type="button"
                      class={render_classes([
                        "options-option",
                        "option-selected": is_selected?(opt, @selected_options, @relation_key, @relation_type)
                      ])}
                      data-label={extract_label(opt)}
                      value={extract_value(opt)}
                      phx-click={JS.push("select_option", target: @myself)}>
                      <.get_label opt={opt} />
                    </button>
                  </div>
                </div>
                <div class="selected-labels">
                  <h2 class="titlecase"><%= gettext "Currently selected" %></h2>
                  <.labels
                    selected_options={@selected_options}
                    input_options={@input_options}
                    relation_type={@relation_type}
                    relation_key={@relation_key}
                    :let={opt}>
                    <.get_label opt={opt} target={@myself} deletable />
                  </.labels>
                </div>
              <% else %>
                <%= if @select_form do %>
                  <.form
                    for={@select_changeset}
                    phx-change={JS.push("validate_new_entry", target: @myself)}
                    :let={entry_form}>
                    <div
                      :for={tab <- @select_form.tabs}
                      class={render_classes(["form-tab", active: true])}
                      data-tab-name={tab.name}>
                      <div class="row">
                        <Fieldset.render
                          :for={fieldset <- tab.fields}
                          translations={@form_translations}
                          form={entry_form}
                          parent_uploads={[]}
                          fieldset={fieldset} />
                      </div>
                    </div>
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
            <:footer>
              <div class="flex-h">
                <button
                  type="button"
                  class="primary"
                  phx-click={JS.push("toggle_modal", target: @myself) |> hide_modal("##{@modal_id}")}>
                  OK
                </button>
                <div
                  :if={@resetable}
                  class="reset">
                  <button
                    type="button"
                    class="secondary"
                    phx-click={JS.push("reset", target: @myself)}>
                    <%= gettext("Reset value") %>
                  </button>
                </div>
              </div>
            </:footer>
          </Content.modal>
        </div>

        <%= if Enum.empty?(@selected_options) do %>
          <Input.input
            type={:hidden}
            field={@field}
            id={"#{@field.id}-empty"}
            name={@field.name}
            value={""} />
        <% else %>
          <%= if @relation_type == :has_many do %>
            <%= for {eform, index} <- Enum.with_index(@selected_options_forms) do %>
              <%= Phoenix.HTML.Form.hidden_inputs_for(eform) %>
              <Input.hidden
                :if={@sequenced?}
                field={eform[:sequence]}
                value={index}
              />
              <Input.hidden
                :for={efield <- @relation_fields}
                field={eform[efield]}
              />
            <% end %>
          <% else %>
            <Input.input
              :for={opt <- @selected_options}
              type={:hidden}
              field={@field}
              id={"#{@field.id}-#{maybe_slug(opt)}"}
              name={"#{@field.name}[]"}
              value={extract_value(opt)} />
          <% end %>
        <% end %>
      </Form.field_base>
    </div>
    """
  end

  def labels(%{relation_type: :has_many} = assigns) do
    ~H"""
    <%= if Enum.empty?(@selected_options) do %>
      <div class="empty-label"><%= gettext "None selected" %></div>
    <% else %>
      <div
        :for={opt <- @selected_options}
        :if={Ecto.Changeset.get_change(opt, :marked_as_deleted) in [false, nil]}
        class="selected-label">
        <div class="selected-label-text">
          <%= render_slot(@inner_block, get_opt(opt, @input_options, @relation_key, @relation_type)) %>
        </div>
      </div>
    <% end %>
    """
  end

  def labels(%{relation_type: {:array, _}} = assigns) do
    ~H"""
    <%= if Enum.empty?(@selected_options) do %>
      <div class="empty-label"><%= gettext "None selected" %></div>
    <% else %>
      <div
        :for={opt <- @selected_options}
        class="selected-label">
        <div class="selected-label-text">
          <%= render_slot(@inner_block, get_opt(opt, @input_options, @relation_key, @relation_type)) %>
        </div>
      </div>
    <% end %>
    """
  end

  defp get_opt(%{id: _id} = opt, _opts, _relation_key, _relation_type), do: opt

  defp get_opt(changeset, opts, relation_key, :has_many) do
    wanted_id = Ecto.Changeset.get_field(changeset, relation_key)
    Enum.find(opts, &(to_string(&1.id) == to_string(wanted_id)))
  end

  defp get_opt(opt, opts, _relation_key, _) do
    Enum.find(opts, fn
      %{value: value} -> to_string(value) == opt
      %{id: value} -> to_string(value) == opt
    end)
  end

  defp is_selected?(%{id: id}, selected_opts, relation_key, :has_many) do
    Enum.find_index(
      selected_opts,
      &(to_string(Ecto.Changeset.get_field(&1, relation_key)) == to_string(id) &&
          Ecto.Changeset.get_change(&1, :marked_as_deleted) != true)
    ) != nil
  end

  defp is_selected?(%{id: id}, opts, _, _) do
    Enum.find_index(opts, &(&1.id == id)) != nil
  end

  defp is_selected?(%{value: value}, opts, _, _), do: value in opts

  defp extract_value(%Ecto.Changeset{data: %{id: id}}), do: id
  defp extract_value(%{value: value}), do: value
  defp extract_value(%{id: value}), do: value
  defp extract_value(value), do: value

  defp extract_label(%{opt: %{label: label}}), do: label

  defp extract_label(%{opt: entry}) do
    identifier = entry.__struct__.__identifier__(entry, skip_cover: true)
    identifier.title
  end

  defp extract_label(%{label: label}), do: label

  defp extract_label(entry) do
    identifier = entry.__struct__.__identifier__(entry, skip_cover: true)
    identifier.title
  end

  defp get_label(%{opt: %{label: _}} = assigns) do
    assigns = assign_new(assigns, :deletable, fn -> false end)

    ~H"""
    — <%= @opt.label %>
    """
  end

  defp get_label(%{opt: nil} = assigns) do
    ~H"""
    <%= gettext "Missing option" %>
    """
  end

  defp get_label(%{opt: %Ecto.Changeset{} = changeset} = assigns) do
    entry = changeset.data
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
      <button class="delete tiny" type="button" value={@entry_id} phx-click={JS.push("select_option", target: @target)}>
        <svg viewBox="0 0 16 16" fill="none" xmlns="http://www.w3.org/2000/svg">
          <line x1="1.35355" y1="0.646447" x2="15.4957" y2="14.7886" stroke="#333333"/>
          <line x1="0.576134" y1="14.7168" x2="14.7183" y2="0.574624" stroke="#333333"/>
        </svg>
      </button>
    <% end %>
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
      <button class="delete tiny" type="button" value={@entry_id} phx-click={JS.push("select_option", target: @target)}>
        <svg viewBox="0 0 16 16" fill="none" xmlns="http://www.w3.org/2000/svg">
          <line x1="1.35355" y1="0.646447" x2="15.4957" y2="14.7886" stroke="#333333"/>
          <line x1="0.576134" y1="14.7168" x2="14.7183" y2="0.574624" stroke="#333333"/>
        </svg>
      </button>
    <% end %>
    """
  end

  defp maybe_slug(%Ecto.Changeset{data: %{id: id}}), do: id
  defp maybe_slug(%{id: id}), do: id
  defp maybe_slug(opt) when is_integer(opt), do: opt
  defp maybe_slug(opt) when is_binary(opt), do: String.replace(opt, ~r/\W/u, "_")

  defp get_count_label(_, [], _) do
    gettext("<None selected>")
  end

  defp get_count_label(_, selected_options, :has_many) do
    count =
      selected_options
      |> Enum.reject(&Ecto.Changeset.get_change(&1, :marked_as_deleted))
      |> Enum.count()

    gettext("%{count} selected", count: count)
  end

  defp get_count_label(_, selected_options, _) do
    count = Enum.count(selected_options)

    gettext("%{count} selected", count: count)
  end

  def handle_event("toggle_modal", _, %{assigns: %{relation_type: :has_many}} = socket) do
    socket = assign(socket, :open, !socket.assigns.open)

    {:noreply, socket}
  end

  def handle_event("toggle_modal", _, %{assigns: %{relation_type: _}} = socket) do
    socket = assign(socket, :open, !socket.assigns.open)

    socket = (socket.assigns.open && update_input_options(socket)) || socket
    # || push_event(socket, "b:validate", %{})

    {:noreply, socket}
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
        %{assigns: %{relation_type: {:array, _}}} = socket
      ) do
    current_selected_options = socket.assigns.selected_options

    exists_at_idx =
      Enum.find_index(
        current_selected_options,
        &(&1 == value)
      )

    updated_selected_options =
      if exists_at_idx do
        List.delete_at(current_selected_options, exists_at_idx)
      else
        current_selected_options ++ [value]
      end

    {:noreply,
     socket
     |> assign(:selected_options, updated_selected_options)
     |> assign_label()}
  end

  def handle_event(
        "select_option",
        %{"value" => value},
        %{assigns: %{relation_type: :has_many}} = socket
      ) do
    form = socket.assigns.field.form
    field = socket.assigns.field
    changeset = form.source
    module = form.data.__struct__
    sequenced? = socket.assigns.sequenced?

    %{opts: %{module: rel_module}} = module.__relation__(field.field)

    relation_type = socket.assigns.relation_type
    relation_key = socket.assigns.relation_key
    selected_options = get_selected_options(changeset, field, relation_type)

    exists_at_idx =
      Enum.find_index(
        selected_options,
        &(to_string(Ecto.Changeset.get_field(&1, relation_key)) == value &&
            Ecto.Changeset.get_change(&1, :marked_as_deleted) != true)
      )

    selected_options =
      if exists_at_idx do
        {to_delete, rest} = List.pop_at(selected_options, exists_at_idx)

        if to_delete.data.id do
          List.replace_at(
            selected_options,
            exists_at_idx,
            Ecto.Changeset.change(to_delete, marked_as_deleted: true)
          )
        else
          rest
        end
      else
        sequence_count = Enum.count(selected_options)

        new_rel =
          rel_module
          |> struct!()
          |> Ecto.Changeset.change([{relation_key, value}])
          |> maybe_change_sequence?(sequence_count, sequenced?)

        selected_options ++ [new_rel]
      end

    updated_changeset = update_relation(changeset, field.field, selected_options, relation_type)
    selected_options = get_selected_options(updated_changeset, field, relation_type)

    form_id = "#{module.__naming__().singular}_form"

    send_update(BrandoAdmin.Components.Form,
      id: form_id,
      action: :update_changeset,
      changeset: updated_changeset
    )

    {:noreply, assign(socket, :selected_options, selected_options)}
  end

  def handle_event("reset", _, %{assigns: %{input_options: input_options}} = socket) do
    label = get_count_label(input_options, [], socket.assigns.relation_type)

    {:noreply,
     socket
     |> assign(:selected_options, [])
     |> assign(:count_label, label)
     |> assign_label()}
  end

  def handle_event("show_form", _, socket) do
    {:noreply, assign(socket, :creating, true)}
  end

  def handle_event("hide_form", _, socket) do
    {:noreply, assign(socket, :creating, false)}
  end

  defp update_relation(changeset, field, updated_relation, :has_many) do
    Ecto.Changeset.put_assoc(changeset, field, updated_relation)
  end

  defp update_relation(changeset, field, updated_relation, :many_to_many) do
    Ecto.Changeset.put_assoc(changeset, field, updated_relation)
  end

  defp update_relation(changeset, field, updated_relation, :embeds_many) do
    Ecto.Changeset.put_embed(changeset, field, updated_relation)
  end

  defp maybe_change_sequence?(changeset, sequence_count, true) do
    Ecto.Changeset.change(changeset, [{:sequence, sequence_count}])
  end

  defp maybe_change_sequence?(changeset, _, _) do
    changeset
  end
end
