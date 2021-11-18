defmodule BrandoAdmin.Utils do
  use BrandoAdmin.Translator, "forms"
  import Phoenix.LiveView
  alias Phoenix.LiveView.JS

  def prepare_input_component(%{assigns: assigns} = socket) do
    schema = assigns.form.source.data.__struct__

    socket =
      socket
      |> assign_new(:opts, fn -> [] end)
      |> assign_new(:label, fn -> nil end)
      |> assign_new(:instructions, fn -> nil end)
      |> assign_new(:placeholder, fn -> nil end)

    assign_opts = assigns[:opts] || []

    assign(socket,
      class: assign_opts[:class],
      monospace: assign_opts[:monospace] || false,
      disabled: assign_opts[:disabled] || false,
      debounce: assign_opts[:debounce] || 750,
      compact: assign_opts[:compact],
      placeholder: g(schema, assign_opts[:placeholder]) || socket.assigns.placeholder,
      instructions: g(schema, assign_opts[:instructions]) || socket.assigns.instructions,
      label: g(schema, assign_opts[:label]) || socket.assigns.label
    )
  end

  def prepare_input_component(assigns) do
    schema = assigns.form.source.data.__struct__

    assigns =
      assigns
      |> assign_new(:opts, fn -> [] end)
      |> assign_new(:label, fn -> nil end)
      |> assign_new(:instructions, fn -> nil end)
      |> assign_new(:placeholder, fn -> nil end)

    assign(assigns,
      class: assigns.opts[:class],
      monospace: assigns.opts[:monospace] || false,
      disabled: assigns.opts[:disabled] || false,
      debounce: assigns.opts[:debounce] || 750,
      compact: assigns.opts[:compact],
      placeholder: g(schema, assigns.opts[:placeholder]) || assigns.placeholder,
      instructions: g(schema, assigns.opts[:instructions]) || assigns.instructions,
      label: g(schema, assigns.opts[:label]) || assigns.label
    )
  end

  def toggle_dropdown(js \\ %JS{}, dropdown_id) do
    js
    |> JS.toggle(
      to: dropdown_id,
      in: {"transition ease-out duration-300", "opacity-0 y-100", "opacity-100 y-0"},
      out: {"transition ease-in duration-300", "opacity-100 y-0", "opacity-0 y-100"},
      time: 300
    )
  end

  def show_dropdown(js \\ %JS{}, dropdown_id) do
    js
    |> JS.show(
      to: dropdown_id,
      transition: {"transition ease-out duration-300", "opacity-0 y-100", "opacity-100 y-0"},
      time: 300
    )
  end

  def hide_dropdown(js \\ %JS{}, dropdown_id) do
    js
    |> JS.hide(
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
      time: 0
    )
    |> JS.show(
      to: "#{modal_id} .modal-backdrop",
      transition: {"transition ease-out duration-500", "opacity-0", "opacity-100"},
      time: 500
    )
    |> JS.show(
      to: "#{modal_id} .modal-dialog",
      transition:
        {"transition ease-out delay-300 duration-300", "opacity-0 y-100", "opacity-100 y-0"},
      time: 600
    )
  end

  def hide_modal(js \\ %JS{}, modal_id) do
    js
    |> JS.hide(
      to: "#{modal_id} .modal-dialog",
      transition: {"transition ease-in duration-300", "opacity-100 y-0", "opacity-0 y-100"},
      time: 300
    )
    |> JS.hide(
      to: "#{modal_id} .modal-backdrop",
      transition: {"transition ease-in delay-300 duration-500", "opacity-100", "opacity-0"},
      time: 800
    )
    |> JS.hide(
      to: "#{modal_id}",
      transition: {"transition", "opacity-100", "opacity-100"},
      time: 800
    )
  end

  def toggle_drawer(js \\ %JS{}, drawer_id) do
    js
    |> JS.toggle(
      to: drawer_id,
      in: {"transition ease-out duration-300", "x-100", "x-0"},
      out: {"transition ease-in duration-300", "x-0", "x-100"},
      time: 300
    )
  end

  def make_id(entry) do
    slugged_struct =
      entry.__struct__
      |> to_string
      |> Brando.Utils.slugify()

    "#{slugged_struct}-#{entry.id}"
  end
end
