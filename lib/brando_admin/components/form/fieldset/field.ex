defmodule BrandoAdmin.Components.Form.Fieldset.Field do
  @moduledoc false
  use BrandoAdmin, :component
  # use Phoenix.HTML

  alias Brando.Blueprint.Forms.Input, as: BlueprintInput
  alias BrandoAdmin.Components.Form.Primitives
  alias BrandoAdmin.Components.Form.Subform
  alias BrandoAdmin.Components.Form.Transformer
  alias Phoenix.HTML.FormField

  # prop input, :map
  # prop form, :form
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
      # Already resolved at Blueprint compile time by `Forms.Dsl.transform_form/1`.
      |> assign(:custom_component, Map.get(assigns.input, :component))
      |> assign_new(:form_cid, fn -> nil end)
      |> assign_new(:form_id, fn -> nil end)

    ~H"""
    <%= unless @hidden do %>
      <%= if @input.__struct__ == Brando.Blueprint.Forms.Subform do %>
        <%= if @custom_component do %>
          <.live_component
            module={@custom_component}
            id={"#{@form.id}-#{@input.name}-custom-component"}
            field={@form[@input.name]}
            label={@label}
            instructions={@instructions}
            placeholder={@placeholder}
            subform={@input}
            current_user={@current_user}
            form_cid={@form_cid}
            form_id={@form_id}
            opts={[]}
          />
        <% else %>
          <%= if match?({:transformer, _}, @input.style) do %>
            <.live_component
              module={Transformer}
              id={"#{@form.id}-transformer-#{@input.name}"}
              field={@form[@input.name]}
              subform={@input}
              label={@label}
              instructions={@instructions}
              current_user={@current_user}
              form_cid={@form_cid}
              form_id={@form_id}
            />
          <% else %>
            <.live_component
              module={Subform}
              id={"#{@form.id}-subform-#{@input.name}"}
              field={@form[@input.name]}
              subform={@input}
              label={@label}
              relations={@relations}
              instructions={@instructions}
              placeholder={@placeholder}
              current_user={@current_user}
              form_cid={@form_cid}
              form_id={@form_id}
            />
          <% end %>
        <% end %>
      <% else %>
        <Primitives.input
          field={@form[@input.name]}
          label={@label}
          instructions={@instructions}
          placeholder={@placeholder}
          opts={@input.opts || []}
          type={@input.type}
          current_user={@current_user}
          form_id={@form_id}
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
