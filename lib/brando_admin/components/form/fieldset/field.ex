defmodule BrandoAdmin.Components.Form.Fieldset.Field do
  @moduledoc false
  use BrandoAdmin, :component
  # use Phoenix.HTML

  alias BrandoAdmin.Components.Form
  alias BrandoAdmin.Components.Form.Subform
  alias Brando.Blueprint.Forms.Input, as: BlueprintInput
  alias Phoenix.HTML.FormField

  # prop input, :map
  # prop form, :form
  # prop parent_uploads, :any
  # prop current_user, :any

  # data label, :string
  # data instructions, :string
  # data placeholder, :string

  def render(assigns) do
    assigns =
      assigns
      |> assign(:label, nil)
      |> assign(:instructions, nil)
      |> assign(:placeholder, nil)
      |> assign(:hidden, hidden?(assigns.input, assigns.form))
      |> assign_new(:form_cid, fn -> nil end)

    ~H"""
    <%= unless @hidden do %>
      <%= if @input.__struct__ == Brando.Blueprint.Forms.Subform do %>
        <%= if @input.component do %>
          <.live_component
            module={@input.component}
            id={"#{@form.id}-#{@input.name}-custom-component"}
            field={@form[@input.name]}
            label={@label}
            instructions={@instructions}
            placeholder={@placeholder}
            subform={@input}
            parent_uploads={@parent_uploads}
            current_user={@current_user}
            form_cid={@form_cid}
            opts={[]}
          />
        <% else %>
          <.live_component
            module={Subform}
            id={"#{@form.id}-subform-#{@input.name}"}
            field={@form[@input.name]}
            parent_uploads={@parent_uploads}
            subform={@input}
            label={@label}
            relations={@relations}
            instructions={@instructions}
            placeholder={@placeholder}
            current_user={@current_user}
            form_cid={@form_cid}
          />
        <% end %>
      <% else %>
        <Form.input
          field={@form[@input.name]}
          label={@label}
          instructions={@instructions}
          placeholder={@placeholder}
          parent_uploads={@parent_uploads}
          opts={@input.opts || []}
          type={@input.type}
          current_user={@current_user}
          form_cid={@form_cid}
          target={@form_cid}
        />
      <% end %>
    <% end %>
    """
  end

  defp hidden?(%BlueprintInput{opts: opts}, form) do
    case Keyword.get(opts || [], :hidden) do
      nil -> false
      false -> false
      true -> true
      {field, expected} -> hidden_for_field?(form, field, expected)
      hidden_fn when is_function(hidden_fn, 1) -> hidden_for_form?(hidden_fn, form)
      _ -> false
    end
  end

  defp hidden?(_, _), do: false

  defp hidden_for_form?(hidden_fn, form) do
    case hidden_fn.(form) do
      true -> true
      _ -> false
    end
  rescue
    _ -> false
  end

  defp hidden_for_field?(form, field, expected) do
    with {:ok, normalized_field} <- normalize_field(field),
         %FormField{value: value} <- form[normalized_field] do
      equivalent?(value, expected)
    else
      _ -> false
    end
  rescue
    _ -> false
  end

  defp normalize_field(field) when is_atom(field), do: {:ok, field}

  defp normalize_field(field) when is_binary(field) do
    {:ok, String.to_existing_atom(field)}
  rescue
    _ -> :error
  end

  defp normalize_field(_), do: :error

  defp equivalent?(left, right) when left === right, do: true
  defp equivalent?(left, right) when is_atom(left) and is_binary(right), do: Atom.to_string(left) == right
  defp equivalent?(left, right) when is_binary(left) and is_atom(right), do: left == Atom.to_string(right)
  defp equivalent?(_, _), do: false
end
