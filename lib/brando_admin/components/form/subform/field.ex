defmodule BrandoAdmin.Components.Form.Subform.Field do
  @moduledoc false
  use BrandoAdmin, :component
  # use Phoenix.HTML

  alias BrandoAdmin.Components.Form.Primitives
  alias BrandoAdmin.Components.Form.Visibility

  # prop input, :map
  # prop sub_form, :form
  # prop current_user, :any
  # prop label, :string
  # prop instructions, :string
  # prop placeholder, :string
  # prop cardinality, :atom

  def render(assigns) do
    assigns =
      assigns
      |> assign_new(:label, fn -> nil end)
      |> assign_new(:placeholder, fn -> nil end)
      |> assign_new(:instructions, fn -> nil end)
      |> assign_new(:subform_id, fn -> nil end)
      |> assign_new(:table, fn -> false end)
      |> assign(:hidden?, Visibility.hidden?(assigns.input.opts, assigns.sub_form))

    assigns = assign(assigns, :opts, input_opts(assigns.input, assigns.table))

    ~H"""
    <%!-- A table row keeps the cell of a field hidden by `show_if`, so the
          columns after it stay under their headings. --%>
    <div
      :if={@table && @hidden?}
      class="brando-input"
      data-component={Primitives.data_component(@input.type)}
      data-hidden
    >
    </div>
    <Primitives.input
      :if={not @hidden?}
      id={"#{@sub_form.id}-input-#{@cardinality}-#{@input.name}"}
      field={@sub_form[@input.name]}
      label={@label}
      instructions={@instructions}
      placeholder={@placeholder}
      parent_form_id={@parent_form_id}
      subform_id={@subform_id}
      path={@path}
      opts={@opts}
      type={@input.type}
      current_user={@current_user}
    />
    """
  end

  @media_types [:image, :file, :video]

  # A media field in a table row is one line, with its actions behind a menu
  defp input_opts(%{type: type, opts: opts}, true) when type in @media_types,
    do: Keyword.put_new(opts, :presentation, :line)

  defp input_opts(%{opts: opts}, _table), do: opts
end
