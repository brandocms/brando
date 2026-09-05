defmodule BrandoAdmin.Utils do
  @moduledoc false
  use BrandoAdmin.Translator

  import Phoenix.Component
  import Phoenix.LiveView, only: [send_update: 2]

  alias BrandoAdmin.JSCommands
  alias Phoenix.LiveView.JS

  @type component_ref :: {module(), term()}

  @doc """
  Send an update to a component identified by a `{module, id}` ref tuple.
  """
  @spec send_to_ref(component_ref(), map()) :: :ok
  def send_to_ref({module, id}, assigns) when is_atom(module) do
    send_update(module, Map.put(assigns, :id, id))
  end

  @doc "Formats nested changeset errors as a compact, human-readable sentence."
  @spec format_changeset_errors(Ecto.Changeset.t()) :: String.t()
  def format_changeset_errors(%Ecto.Changeset{} = changeset) do
    changeset
    |> Ecto.Changeset.traverse_errors(fn {message, _opts} -> message end)
    |> flatten_changeset_errors([])
    |> Enum.join(", ")
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

  defp flatten_changeset_errors(errors, path) when is_map(errors) do
    Enum.flat_map(errors, fn {field, nested_errors} ->
      flatten_changeset_errors(nested_errors, path ++ [field])
    end)
  end

  defp flatten_changeset_errors(errors, path) when is_list(errors) do
    if Enum.all?(errors, &is_binary/1) do
      Enum.map(errors, &"#{Enum.join(path, ".")} #{&1}")
    else
      errors
      |> Enum.with_index()
      |> Enum.flat_map(fn {nested_errors, index} ->
        flatten_changeset_errors(nested_errors, path ++ [index])
      end)
    end
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

  # The JS command builders live in the leaf `BrandoAdmin.JSCommands`, which needs
  # nothing but `Phoenix.LiveView.JS`. Blueprint `listings` blocks build their
  # actions at compile time, so a schema declaring one used to acquire a
  # compile-time dependency on this module — and through it on the whole admin.
  # See issue #2737. Delegated so every existing call site keeps working.
  defdelegate toggle_dropdown(js \\ %JS{}, dropdown_id), to: JSCommands
  defdelegate show_dropdown(js \\ %JS{}, dropdown_id), to: JSCommands
  defdelegate hide_dropdown(js \\ %JS{}, dropdown_id), to: JSCommands
  defdelegate show_modal(js \\ %JS{}, modal_id), to: JSCommands
  defdelegate hide_modal(js \\ %JS{}, modal_id), to: JSCommands
  defdelegate toggle_drawer(js \\ %JS{}, drawer_id), to: JSCommands

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
