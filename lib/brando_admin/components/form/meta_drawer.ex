defmodule BrandoAdmin.Components.Form.MetaDrawer do
  @moduledoc false
  use BrandoAdmin, :component
  use Gettext, backend: Brando.Gettext

  alias Brando.Blueprint.Forms, as: BlueprintForms
  alias BrandoAdmin.Components.Content
  alias BrandoAdmin.Components.Form.Input

  # prop form, :form, required: true
  # prop blueprint, :any, required: true
  # prop status, :atom, default: :closed
  # prop close, :event

  def render(assigns) do
    meta_title_opts = get_input_opts(assigns, :meta_title)
    meta_description_opts = get_input_opts(assigns, :meta_description)

    assigns =
      assigns
      |> assign(:meta_title_opts, meta_title_opts)
      |> assign(:meta_description_opts, meta_description_opts)

    ~H"""
    <Content.drawer id={@id} title={gettext("Meta properties")} close={@close}>
      <:info>
        <p>
          {gettext(
            "Meta information for search engines. Try to keep the title tag below 70 characters while incorporating key terms for your content. The description tag should be around 155 characters to prevent getting truncated in search results. You can also attach your own META image which will override your entry's cover image, if it has one."
          )}
        </p>
      </:info>
      <div class="brando-input">
        <Input.text field={@form[:meta_title]} opts={@meta_title_opts} target={@form_cid} label={gettext("META title")} />
      </div>

      <div class="brando-input">
        <Input.textarea
          field={@form[:meta_description]}
          opts={@meta_description_opts}
          target={@form_cid}
          label={gettext("META description")}
        />
      </div>

      <div class="brando-input">
        <.live_component
          module={Input.Image}
          id={"#{@form.id}-meta-image"}
          field={@form[:meta_image]}
          current_user={@current_user}
          label={gettext("META image")}
        />
      </div>
    </Content.drawer>
    """
  end

  defp get_input_opts(%{blueprint: nil} = assigns, field), do: maybe_attach_ai_fallback([], assigns, field)

  defp get_input_opts(%{blueprint: blueprint} = assigns, field) do
    opts =
      case BlueprintForms.get_field(field, blueprint) do
        %{opts: opts} when is_list(opts) -> opts
        _ -> []
      end

    maybe_attach_ai_fallback(opts, assigns, field)
  end

  defp maybe_attach_ai_fallback(opts, assigns, field) do
    if Keyword.has_key?(opts, :ai) do
      opts
    else
      schema = schema_from_assigns(assigns)

      case Brando.AI.field_ai_opts(schema, field) do
        [] -> opts
        ai_opts -> Keyword.put(opts, :ai, ai_opts)
      end
    end
  end

  defp schema_from_assigns(assigns) do
    Brando.Utils.try_path(assigns, [:form, :source, :data, :__struct__])
  end
end
