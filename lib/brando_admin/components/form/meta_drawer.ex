defmodule BrandoAdmin.Components.Form.MetaDrawer do
  @moduledoc false
  use BrandoAdmin, :component
  use Gettext, backend: Brando.Gettext

  alias Brando.Blueprint.Forms, as: BlueprintForms
  alias BrandoAdmin.Components.Content
  alias BrandoAdmin.Components.Form.Input
  alias BrandoAdmin.Components.Form.StructuredData
  alias Phoenix.LiveView.JS

  # prop form, :form, required: true
  # prop blueprint, :any, required: true
  # prop status, :atom, default: :closed
  # prop close, :event

  def render(assigns) do
    meta_title_opts = get_input_opts(assigns, :meta_title)
    meta_description_opts = get_input_opts(assigns, :meta_description)

    schema = schema_from_assigns(assigns)

    assigns =
      assigns
      |> assign(:meta_title_opts, meta_title_opts)
      |> assign(:meta_description_opts, meta_description_opts)
      |> assign(:schema, schema)
      |> assign(:structured_data?, structured_data?(schema))
      |> assign(:entry_id, Brando.Utils.try_path(assigns, [:form, :source, :data, :id]))

    ~H"""
    <Content.drawer
      id={@id}
      title={gettext("Meta properties")}
      close={@close}
      icon="file-search"
      workspace
      editor
      narrow
    >
      <:info>
        <nav :if={@structured_data?} class="pill-tabs pill-tabs--small meta-drawer-tabs" aria-label={gettext("Meta sections")}>
          <button
            id={"#{@id}-tab-meta"}
            type="button"
            aria-pressed="true"
            phx-click={show_meta_tags(@id)}
          >
            {gettext("Meta tags")}
          </button>
          <button
            id={"#{@id}-tab-structured-data"}
            type="button"
            aria-pressed="false"
            data-testid="meta-tab-structured-data"
            phx-click={show_structured_data(@id)}
          >
            {gettext("Structured data")}
          </button>
        </nav>
        <p id={"#{@id}-meta-info"}>
          {gettext(
            "Meta information for search engines. Try to keep the title tag below 70 characters while incorporating key terms for your content. The description tag should be around 155 characters to prevent getting truncated in search results. You can also attach your own meta image which will override your entry's cover image, if it has one."
          )}
        </p>
        <p :if={@structured_data?} id={"#{@id}-structured-data-info"} hidden>
          {gettext(
            "The structured data (JSON-LD) this entry's page gives search engines, checked against what Google requires and recommends. Select a node to see where its properties come from."
          )}
        </p>
      </:info>
      <div
        :if={@structured_data?}
        id={"#{@id}-structured-data-pane"}
        class="meta-drawer-structured-data"
        hidden
      >
        <.live_component
          module={StructuredData}
          id={"#{@id}-structured-data"}
          schema={@schema}
          entry_id={@entry_id}
          open={@close |> JS.exec("phx-click", to: "##{@id}-tab-structured-data")}
        />
      </div>
      <div id={"#{@id}-meta-fields"} class="meta-drawer-fields">
        <div class="brando-input">
          <Input.text field={@form[:meta_title]} opts={@meta_title_opts} target={@form_cid} label={gettext("Meta title")} />
        </div>

        <div class="brando-input">
          <Input.textarea
            field={@form[:meta_description]}
            opts={@meta_description_opts}
            target={@form_cid}
            label={gettext("Meta description")}
          />
        </div>

        <div class="brando-input">
          <Input.text
            field={@form[:meta_canonical_url]}
            target={@form_cid}
            label={gettext("Canonical URL")}
            placeholder="https://"
            instructions={
              gettext(
                "Leave empty to use this page's own address. Fill in the full address of the original when this content was first published elsewhere."
              )
            }
          />
        </div>

        <div class="brando-input">
          <Input.toggle
            field={@form[:meta_nosnippet]}
            label={gettext("No snippet")}
            instructions={
              gettext(
                "Search engines show no text from this page under its title, and Google leaves it out of AI Overviews and AI Mode."
              )
            }
          />
        </div>

        <div class="brando-input">
          <Input.number
            field={@form[:meta_max_snippet]}
            label={gettext("Snippet length")}
            placeholder={gettext("No limit")}
            instructions={
              gettext(
                "The most characters search engines and AI answers may quote from this page. Empty leaves it to them; 0 means none."
              )
            }
          />
        </div>

        <div class="brando-input">
          <.live_component
            module={Input.Image}
            id={"#{@form.id}-meta-image"}
            field={@form[:meta_image]}
            current_user={@current_user}
            label={gettext("Meta image")}
          />
        </div>
      </div>
    </Content.drawer>
    """
  end

  # The inspector explains a blueprint's json_ld_schema, so it shows for
  # blueprints that declare one.
  defp structured_data?(schema) when is_atom(schema) and not is_nil(schema), do: Brando.JSONLD.Graph.has_json_ld?(schema)
  defp structured_data?(_schema), do: false

  # Tabs switch on the client: the panes stay mounted, so the meta fields keep
  # their input. The commands are sticky, so they survive the form's patches.
  defp show_meta_tags(id) do
    %JS{}
    |> JS.show(to: "##{id}-meta-fields")
    |> JS.show(to: "##{id}-meta-info")
    |> JS.hide(to: "##{id}-structured-data-pane")
    |> JS.hide(to: "##{id}-structured-data-info")
    |> JS.set_attribute({"aria-pressed", "true"}, to: "##{id}-tab-meta")
    |> JS.set_attribute({"aria-pressed", "false"}, to: "##{id}-tab-structured-data")
    |> JS.remove_class("structured-data-open", to: "##{id}")
  end

  defp show_structured_data(id) do
    %JS{}
    |> JS.hide(to: "##{id}-meta-fields")
    |> JS.hide(to: "##{id}-meta-info")
    |> JS.show(to: "##{id}-structured-data-pane")
    |> JS.show(to: "##{id}-structured-data-info")
    |> JS.set_attribute({"aria-pressed", "false"}, to: "##{id}-tab-meta")
    |> JS.set_attribute({"aria-pressed", "true"}, to: "##{id}-tab-structured-data")
    |> JS.add_class("structured-data-open", to: "##{id}")
    |> JS.push("load", target: "##{id}-structured-data")
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
