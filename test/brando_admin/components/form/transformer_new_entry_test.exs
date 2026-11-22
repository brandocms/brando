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

    test "a new entry from a default written with #{kind} keys saves the default's values" do
      default = Transformer.build_default(%Subform{default: unquote(Macro.escape(default))}, Item, %{}, nil)

      socket =
        %Phoenix.LiveView.Socket{private: %{lifecycle: %Phoenix.LiveView.Lifecycle{}, live_temp: %{}}}
        |> Phoenix.Component.assign(items: [Transformer.new_item("item-1", default)])
        |> Phoenix.Component.assign(form_id: "collection_form", relation_key: :items)

      {:ok, _} = Transformer.update(%{event: "fetch_transformer_data", tag: "save"}, socket)

      assert_receive {:phoenix, :send_update,
                      {{BrandoAdmin.Components.Form, "collection_form"}, %{transformer_data: rows}}}

      # What the form does with the rows it is given on save
      collection =
        %Collection{items: []}
        |> Ecto.Changeset.change()
        |> Ecto.Changeset.put_assoc(:items, rows)
        |> Ecto.Changeset.apply_changes()

      assert [%Item{title: "From the default", sequence: 0}] = collection.items
    end
  end
end
