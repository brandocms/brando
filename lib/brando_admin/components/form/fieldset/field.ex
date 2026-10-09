defmodule BrandoAdmin.Components.Form.Fieldset.Field do
  @moduledoc false
  use BrandoAdmin, :component
  use BrandoAdmin.Translator
  # use Phoenix.HTML

  alias Brando.Blueprint.Forms.Input, as: BlueprintInput
  alias BrandoAdmin.Components.Form.Primitives
  alias BrandoAdmin.Components.Form.Subform
  alias BrandoAdmin.Components.Form.Transformer
  alias BrandoAdmin.Components.Form.Visibility

  # prop input, :map
  # prop form, :form
  # prop current_user, :any

  # data label, :string
  # data instructions, :string
  # data placeholder, :string

  def render(assigns) do
    assigns =
      assigns
      |> assign(:label, subform_text(assigns, :label))
      |> assign(:instructions, subform_text(assigns, :instructions))
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
          opts={user_opts(@input.opts || [], @current_user)}
          type={@input.type}
          current_user={@current_user}
          form_id={@form_id}
          target={@form_cid}
          ai_actions={@input.actions}
        />
      <% end %>
    <% end %>
    """
  end

  # `readonly: :unless_superuser` and `disabled: :unless_superuser` lock a
  # field for everyone but superusers, who can still correct it.
  defp user_opts(opts, user) do
    Enum.map(opts, fn
      {key, :unless_superuser} when key in [:readonly, :disabled] -> {key, !match?(%{role: :superuser}, user)}
      opt -> opt
    end)
  end

  defp hidden?(%BlueprintInput{opts: opts}, form), do: Visibility.hidden?(opts, form)
  defp hidden?(_, _), do: false

  # A subform's label and instructions from the form DSL, translated in the
  # schema's domain. Plain inputs resolve theirs in `Primitives.input/1`.
  defp subform_text(%{input: %Brando.Blueprint.Forms.Subform{} = subform, form: form}, key) do
    case Map.get(subform, key) do
      nil -> nil
      text -> form.source.data.__struct__ |> g(text) |> Phoenix.HTML.safe_to_string()
    end
  end

  defp subform_text(_assigns, _key), do: nil
end
