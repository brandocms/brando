defmodule BrandoAdmin.Components.Form.Input.Blocks.HtmlParams do
  @moduledoc """
  The parts of an HTML ref's form (`Brando.Villain.Blocks.HtmlBlock`): the
  parameter declarations a superuser edits, the values form everyone fills
  in, and the hidden inputs that carry the template through a form that
  does not show it.

  Every field of a ref's data has to be in the form it submits: a
  polymorphic embed is rebuilt from the params, so a field left out is
  blanked (see `Block.Render.block/1`).
  """
  use BrandoAdmin, :component
  use Gettext, backend: Brando.Gettext

  alias Brando.Villain.Blocks.HtmlBlock
  alias BrandoAdmin.Components.Form.Input
  alias BrandoAdmin.Components.Form.Primitives
  alias Phoenix.LiveView.JS

  @doc "The parameter types, labelled, for a select."
  def type_options do
    [
      %{value: "id", label: gettext("ID")},
      %{value: "number", label: gettext("Number")},
      %{value: "url", label: gettext("URL")},
      %{value: "text", label: gettext("Text")}
    ]
  end

  attr :block_data, Phoenix.HTML.Form, required: true

  @doc "A superuser's list of parameter declarations: key, label and type."
  def params_editor(assigns) do
    assigns = assign(assigns, :type_options, type_options())

    ~H"""
    <Primitives.field_base
      field={@block_data[:params]}
      label={gettext("Parameters")}
      instructions={gettext("Editors fill these in. Refer to one in the HTML as {{ key }}.")}
      class="subform html-params"
    >
      <.inputs_for :let={param} field={@block_data[:params]}>
        <div class="subform-entry inline">
          <input type="hidden" name={"#{@block_data.name}[sort_param_ids][]"} value={param.index} />
          <div class="subform-tools">
            <button
              name={"#{@block_data.name}[drop_param_ids][]"}
              type="button"
              value={param.index}
              phx-click={JS.dispatch("change")}
              class="subform-delete"
              aria-label={gettext("Remove parameter")}
            >
              <.icon name="x" />
            </button>
          </div>
          <div class="subform-fields">
            <Input.text field={param[:key]} label={gettext("Key")} monospace />
            <Input.text field={param[:label]} label={gettext("Label")} />
            <Input.radios field={param[:type]} label={gettext("Type")} opts={[options: @type_options]} />
          </div>
        </div>
      </.inputs_for>
      <input type="hidden" name={"#{@block_data.name}[drop_param_ids][]"} />
      <button
        type="button"
        name={"#{@block_data.name}[sort_param_ids][]"}
        value="new"
        phx-click={JS.dispatch("change")}
        class="btn btn--sm add-entry-button"
      >
        {gettext("Add parameter")}
      </button>
    </Primitives.field_base>
    """
  end

  attr :block_data, Phoenix.HTML.Form, required: true

  @doc """
  One input per declared parameter. Values of keys no parameter declares
  (one a superuser removed) are carried as they are.
  """
  def values_form(assigns) do
    data = data(assigns.block_data)
    values = Map.get(data, :values) || %{}
    params = Enum.filter(Map.get(data, :params) || [], &(is_binary(&1.key) and &1.key != ""))
    declared = MapSet.new(params, & &1.key)

    assigns =
      assigns
      |> assign(:fields, Enum.map(params, &value_field(assigns.block_data, &1, values)))
      |> assign(:kept, for({key, value} <- values, not MapSet.member?(declared, key), do: {key, value}))
      |> assign(:name, assigns.block_data[:values].name)

    ~H"""
    <div class="html-values">
      <Input.text
        :for={{field, label, instructions} <- @fields}
        field={field}
        label={label}
        instructions={instructions}
      />
      <input :for={{key, value} <- @kept} type="hidden" name={"#{@name}[#{key}]"} value={value} />
    </div>
    """
  end

  attr :block_data, Phoenix.HTML.Form, required: true

  @doc "The template and its parameters, for a form that does not show them."
  def carried_template(assigns) do
    ~H"""
    <input type="hidden" name={@block_data[:text].name} value={@block_data[:text].value || ""} />
    <.inputs_for :let={param} field={@block_data[:params]}>
      <input type="hidden" name={param[:key].name} value={param[:key].value || ""} />
      <input type="hidden" name={param[:label].name} value={param[:label].value || ""} />
      <input type="hidden" name={param[:type].name} value={param[:type].value || ""} />
    </.inputs_for>
    """
  end

  @doc "Whether the ref's data declares any parameter."
  def params?(block_data), do: (Map.get(data(block_data), :params) || []) != []

  defp data(%Phoenix.HTML.Form{source: %Ecto.Changeset{} = changeset}), do: Ecto.Changeset.apply_changes(changeset)
  defp data(%Phoenix.HTML.Form{data: data}), do: data || %{}

  defp value_field(form, param, values) do
    value = Map.get(values, param.key)
    name = "#{form[:values].name}[#{param.key}]"

    errors =
      if HtmlBlock.valid_value?(param.type, value),
        do: [],
        else: [{type_error(param.type), []}]

    field = %Phoenix.HTML.FormField{
      id: "#{form[:values].id}_#{param.key}",
      name: name,
      errors: errors,
      field: :values,
      form: form,
      value: value
    }

    {field, label(param), instructions(param.type)}
  end

  defp label(%{label: label, key: key}) when label in [nil, ""], do: key
  defp label(%{label: label}), do: label

  defp instructions(:id), do: gettext("Letters, digits, _ and - only")
  defp instructions(:number), do: gettext("A number, such as 42 or 4.5")
  defp instructions(:url), do: gettext("An https:// address, or a path on this site")
  defp instructions(_), do: nil

  defp type_error(:id), do: gettext("Use letters, digits, _ and - only")
  defp type_error(:number), do: gettext("Enter a number")
  defp type_error(:url), do: gettext("Enter an https:// address or a path")
  defp type_error(_), do: gettext("Invalid value")
end
