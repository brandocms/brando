defmodule BrandoAdmin.Components.Form.MetaDrawer do
  @moduledoc false
  use BrandoAdmin, :component
  use Gettext, backend: Brando.Gettext

  alias Brando.Blueprint.Forms, as: BlueprintForms
  alias BrandoAdmin.Components.Content
  alias BrandoAdmin.Components.Form.Input
  alias BrandoAdmin.Components.Form.MetaPreviews
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
      |> assign(:tabs, tabs(structured_data?(schema)))
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
        <nav class="pill-tabs pill-tabs--small meta-drawer-tabs" aria-label={gettext("Meta sections")}>
          <button
            :for={{tab, label} <- @tabs}
            id={"#{@id}-tab-#{tab}"}
            type="button"
            aria-pressed={to_string(tab == "meta")}
            data-testid={"meta-tab-#{tab}"}
            phx-click={show_tab(@id, tab, @tabs)}
          >
            {label}
          </button>
        </nav>
        <p id={"#{@id}-meta-info"}>
          {gettext("The title, description and image that search engines and social media show for this entry.")}
        </p>
        <p id={"#{@id}-previews-info"} hidden>
          {gettext(
            "How this entry's page looks when it is found in search, shared, or read by AI tools as Markdown. The cards follow your edits; the address and the Markdown follow the last save."
          )}
        </p>
        <p :if={@structured_data?} id={"#{@id}-structured-data-info"} hidden>
          {gettext(
            "The structured data (JSON-LD) this entry's page gives search engines, checked against what Google requires and recommends. Select a node to see where its properties come from."
          )}
        </p>
      </:info>
      <div id={"#{@id}-previews-pane"} class="meta-drawer-previews" hidden>
        <.live_component
          module={MetaPreviews}
          id={"#{@id}-previews"}
          form={@form}
          schema={@schema}
          entry_id={@entry_id}
        />
      </div>
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
      <div id={"#{@id}-meta-fields"} class="meta-drawer-fields drawer-fields">
        <div class="brando-input">
          <Input.text
            field={@form[:meta_title]}
            opts={@meta_title_opts}
            target={@form_cid}
            label={gettext("Meta title")}
            instructions={gettext("Keep it under 70 characters, with the words people search for.")}
          />
        </div>

        <div class="brando-input">
          <Input.textarea
            field={@form[:meta_description]}
            opts={@meta_description_opts}
            target={@form_cid}
            label={gettext("Meta description")}
            instructions={gettext("Around 155 characters. Longer descriptions are cut short in search results.")}
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
            instructions={gettext("Shown when this entry is shared, in place of its cover image.")}
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

  defp tabs(structured_data?) do
    [{"meta", gettext("Meta tags")}, {"previews", gettext("Previews")}] ++
      if(structured_data?, do: [{"structured-data", gettext("Structured data")}], else: [])
  end

  # Tabs switch on the client: the panes stay mounted, so the meta fields keep
  # their input. The commands are sticky, so they survive the form's patches.
  # Previews and Structured data widen the drawer and load on opening.
  defp show_tab(id, tab, tabs) do
    tabs
    |> Enum.reduce(%JS{}, fn {other, _label}, js ->
      if other == tab do
        js
        |> JS.show(to: "##{pane_id(id, other)}")
        |> JS.show(to: "##{id}-#{other}-info")
        |> JS.set_attribute({"aria-pressed", "true"}, to: "##{id}-tab-#{other}")
      else
        js
        |> JS.hide(to: "##{pane_id(id, other)}")
        |> JS.hide(to: "##{id}-#{other}-info")
        |> JS.set_attribute({"aria-pressed", "false"}, to: "##{id}-tab-#{other}")
      end
    end)
    |> JS.remove_class("structured-data-open previews-open", to: "##{id}")
    |> open_tab(id, tab)
  end

  defp open_tab(js, _id, "meta"), do: js

  defp open_tab(js, id, tab) do
    js
    |> JS.add_class("#{tab}-open", to: "##{id}")
    |> JS.push("load", target: "##{id}-#{tab}")
  end

  defp pane_id(id, "meta"), do: "#{id}-meta-fields"
  defp pane_id(id, tab), do: "#{id}-#{tab}-pane"

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
