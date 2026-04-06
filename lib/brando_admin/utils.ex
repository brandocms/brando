defmodule BrandoAdmin.Utils do
  @moduledoc false
  use BrandoAdmin.Translator

  import Phoenix.Component
  import Phoenix.LiveView, only: [send_update: 2]

  alias Phoenix.LiveView.JS

  @type component_ref :: {module(), term()}

  @doc """
  Send an update to a component identified by a `{module, id}` ref tuple.
  """
  @spec send_to_ref(component_ref(), map()) :: :ok
  def send_to_ref({module, id}, assigns) when is_atom(module) do
    send_update(module, Map.put(assigns, :id, id))
  end

  def prepare_subform_component(%{assigns: assigns} = socket) do
    schema = assigns.field.form.source.data.__struct__

    socket =
      socket
      |> assign_new(:opts, fn -> [] end)
      |> assign_new(:label, fn -> nil end)
      |> assign_new(:instructions, fn -> nil end)
      |> assign_new(:placeholder, fn -> nil end)
      |> assign_new(:uid, fn -> nil end)
      |> assign_new(:id_prefix, fn -> "" end)

    assign_opts = assigns[:opts] || []

    assign(socket,
      class: assign_opts[:class],
      monospace: assign_opts[:monospace] || false,
      disabled: assign_opts[:disabled] || false,
      debounce: assign_opts[:debounce] || 300,
      compact: assign_opts[:compact],
      instructions: g(schema, Map.get(socket.assigns.subform, :instructions)),
      label: g(schema, Map.get(socket.assigns.subform, :label))
    )
  end

  def prepare_input_component(%{assigns: assigns} = socket) do
    schema = assigns.field.form.source.data.__struct__

    socket =
      socket
      |> assign_new(:opts, fn -> [] end)
      |> assign_new(:label, fn -> nil end)
      |> assign_new(:instructions, fn -> nil end)
      |> assign_new(:placeholder, fn -> nil end)
      |> assign_new(:uid, fn -> nil end)
      |> assign_new(:id_prefix, fn -> "" end)

    assign_opts = assigns[:opts] || []

    assign(socket,
      class: assign_opts[:class],
      monospace: assign_opts[:monospace] || false,
      disabled: assign_opts[:disabled] || false,
      debounce: assign_opts[:debounce] || 300,
      compact: assign_opts[:compact],
      placeholder: g(schema, assign_opts[:placeholder]) || socket.assigns.placeholder,
      instructions: g(schema, assign_opts[:instructions]) || socket.assigns.instructions,
      label: g(schema, assign_opts[:label]) || socket.assigns.label
    )
  end

  def prepare_input_component(assigns) do
    schema = Brando.Utils.try_path(assigns.field, [:form, :source, :data, :__struct__])

    assigns =
      assigns
      |> assign_new(:opts, fn -> [] end)
      |> assign_new(:label, fn -> nil end)
      |> assign_new(:instructions, fn -> nil end)
      |> assign_new(:placeholder, fn -> nil end)
      |> assign_new(:uid, fn -> nil end)
      |> assign_new(:id_prefix, fn -> "" end)

    assign(assigns,
      class: assigns.opts[:class],
      monospace: assigns.opts[:monospace] || false,
      disabled: assigns.opts[:disabled] || false,
      debounce: assigns.opts[:debounce] || 300,
      compact: assigns.opts[:compact],
      placeholder: g(schema, assigns.opts[:placeholder]) || assigns.placeholder,
      instructions: g(schema, assigns.opts[:instructions]) || assigns.instructions,
      label: g(schema, assigns.opts[:label]) || assigns.label
    )
  end

  def make_uid(_field, nil) do
    nil
  end

  def make_uid(field, uid) do
    "#{field.id}-#{uid}"
  end

  def toggle_dropdown(js \\ %JS{}, dropdown_id) do
    JS.toggle(js,
      to: dropdown_id,
      in: {"transition ease-out duration-300", "opacity-0 y-100", "opacity-100 y-0"},
      out: {"transition ease-in duration-300", "opacity-100 y-0", "opacity-0 y-100"},
      time: 300
    )
  end

  def show_dropdown(js \\ %JS{}, dropdown_id) do
    JS.show(js,
      to: dropdown_id,
      transition: {"transition ease-out duration-300", "opacity-0 y-100", "opacity-100 y-0"},
      time: 300
    )
  end

  def hide_dropdown(js \\ %JS{}, dropdown_id) do
    JS.hide(js,
      to: dropdown_id,
      transition: {"transition ease-in duration-300", "opacity-100 y-0", "opacity-0 y-100"},
      time: 300
    )
  end

  def show_modal(js \\ %JS{}, modal_id) do
    js
    |> JS.show(
      to: "#{modal_id}",
      display: "flex",
      blocking: false,
      time: 0
    )
    |> JS.show(
      to: "#{modal_id} .modal-backdrop",
      transition: {"transition ease-out duration-300", "opacity-0", "opacity-100"},
      blocking: false,
      time: 300
    )
    |> JS.show(
      to: "#{modal_id} .modal-dialog",
      blocking: false,
      transition: {"transition ease-out delay-300 duration-300", "opacity-0 y-100", "opacity-100 y-0"},
      time: 600
    )
  end

  def hide_modal(js \\ %JS{}, modal_id) do
    js
    |> JS.hide(
      to: "#{modal_id} .modal-dialog",
      transition: {"transition ease-in duration-100", "opacity-100 y-0", "opacity-0 y-100"},
      blocking: true,
      time: 100
    )
    |> JS.hide(
      to: "#{modal_id} .modal-backdrop",
      transition: {"transition ease-in delay-100 duration-300", "opacity-100", "opacity-0"},
      blocking: false,
      time: 400
    )
    |> JS.hide(
      to: "#{modal_id}",
      transition: {"transition", "opacity-100", "opacity-100"},
      blocking: false,
      time: 400
    )
  end

  def toggle_drawer(js \\ %JS{}, drawer_id) do
    JS.toggle(js,
      to: drawer_id,
      in: {"transition ease-out duration-300", "x-100", "x-0"},
      out: {"transition ease-in duration-300", "x-0", "x-100"},
      time: 300
    )
  end

  @doc """
  Derives the Form component ID from a form name string or a Phoenix.HTML.Form struct.

  Extracts the root name from a nested form path and appends "_form".

      derive_form_id("page[blocks][0][data]")  => "page_form"
      derive_form_id(%Phoenix.HTML.Form{name: "project[blocks][0]"})  => "project_form"
  """
  def derive_form_id(%Phoenix.HTML.Form{name: name}), do: derive_form_id(name)

  def derive_form_id(form_name) when is_binary(form_name) do
    form_name
    |> String.split("[")
    |> hd()
    |> Kernel.<>("_form")
  end

  def make_id(entry) do
    slugged_struct =
      entry.__struct__
      |> to_string()
      |> Brando.Utils.slugify()

    "#{slugged_struct}-#{entry.id}"
  end
end
