defmodule BrandoAdmin.Components.Form.TransformerNewEntryTest do
  use ExUnit.Case, async: true
  use Brando.ConnCase
  import Phoenix.LiveViewTest

  alias Brando.Blueprint.Forms.Input
  alias Brando.Blueprint.Forms.Subform
  alias BrandoAdmin.Components.Form.Transformer

  defmodule Item do
    use Brando.Blueprint,
      application: "Brando",
      domain: "TransformerNewEntryTest",
      schema: "Item",
      singular: "item",
      plural: "items",
      gettext_module: Brando.Gettext

    attributes do
      attribute :title, :string, default: "Schema default"
      attribute :sequence, :integer
    end

    assets do
      asset :cover, :image, cfg: :default
    end
  end

  defmodule Collection do
    use Brando.Blueprint,
      application: "Brando",
      domain: "TransformerNewEntryTest",
      schema: "Collection",
      singular: "collection",
      plural: "collections",
      gettext_module: Brando.Gettext

    relations do
      relation :items, :has_many, module: Item
    end
  end

  defmodule Host do
    use Phoenix.LiveView, layout: false

    def mount(_, %{"default" => default}, socket) do
      form = %Collection{items: []} |> Ecto.Changeset.change() |> to_form()

      subform = %Subform{
        name: :items,
        cardinality: :many,
        style: {:transformer, :cover},
        default: default,
        sub_fields: [%Input{name: :title, type: :text, opts: [label: "Title"]}]
      }

      {:ok, assign(socket, field: form[:items], subform: subform)}
    end

    def render(assigns) do
      ~H"""
      <.live_component
        module={Transformer}
        id="collection-items"
        field={@field}
        subform={@subform}
        form_id="collection_form"
        current_user={%Brando.Users.User{language: "en"}}
        label="Items"
        instructions={nil}
      />
      """
    end
  end

  # A Blueprint `default` may be written with string keys, as params are; the
  # new entry shows the values it saves
  for {kind, default} <- [atom: %{title: "From the default"}, string: %{"title" => "From the default"}] do
    test "a new entry shows a default written with #{kind} keys", %{conn: conn} do
      {:ok, view, _html} = live_isolated(conn, Host, session: %{"default" => unquote(Macro.escape(default))})

      view |> element(~s(.add-entry-button[phx-click*="add_entry"])) |> render_click()

      assert has_element?(view, ~s(input[name="transformer_item[title]"][value="From the default"]))
    end
  end
end
