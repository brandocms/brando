defmodule BrandoAdmin.Components.Form.Input.IdentifierChangeTrackingTest do
  use ExUnit.Case, async: false
  use Brando.ConnCase

  import Phoenix.Component, only: [to_form: 2]
  alias Phoenix.Component
  alias Brando.Content.Identifier
  alias BrandoAdmin.Components.Content.SelectIdentifier
  alias BrandoAdmin.Components.Form.Input.Entries
  alias Ecto.Changeset

  test "identifier picker refreshes schemas, counts and results for language and status changes" do
    page_en = identifier(Brando.Pages.Page, :en, :published)
    page_no = identifier(Brando.Pages.Page, :no, :draft)
    fragment = identifier(Brando.Pages.Fragment, :no, :published)

    props = %{
      id: "picker",
      wanted_schemas: [Brando.Pages.Page],
      layout: :workspace,
      language: "en",
      statuses: [:published]
    }

    {:ok, socket} = SelectIdentifier.update(props, %Phoenix.LiveView.Socket{})
    assert Enum.map(socket.assigns.identifiers, & &1.id) == [page_en.id]
    assert socket.assigns.schema_counts == %{Brando.Pages.Page => 1}

    {:ok, socket} = SelectIdentifier.update(%{props | language: "no", statuses: [:draft]}, socket)
    assert Enum.map(socket.assigns.identifiers, & &1.id) == [page_no.id]
    assert socket.assigns.selected_schema == Brando.Pages.Page

    {:ok, socket} = SelectIdentifier.update(%{props | wanted_schemas: [Brando.Pages.Fragment], language: "no"}, socket)

    assert socket.assigns.available_schemas == [
             {Brando.Blueprint.get_plural(Brando.Pages.Fragment), Brando.Pages.Fragment}
           ]

    assert socket.assigns.selected_schema == Brando.Pages.Fragment
    assert Enum.map(socket.assigns.identifiers, & &1.id) == [fragment.id]
    assert socket.assigns.schema_counts == %{Brando.Pages.Fragment => 1}
  end

  test "identifier picker preserves a valid local tab, including all, on filter changes" do
    identifier(Brando.Pages.Page, :en, :published)
    fragment = identifier(Brando.Pages.Fragment, :en, :published)
    props = %{id: "picker", wanted_schemas: [Brando.Pages.Page, Brando.Pages.Fragment], layout: :workspace}
    {:ok, socket} = SelectIdentifier.update(props, %Phoenix.LiveView.Socket{})

    {:noreply, socket} =
      SelectIdentifier.handle_event("select_schema", %{"schema" => to_string(Brando.Pages.Fragment)}, socket)

    {:ok, socket} = SelectIdentifier.update(Map.put(props, :language, "en"), socket)
    assert socket.assigns.selected_schema == Brando.Pages.Fragment
    assert Enum.map(socket.assigns.identifiers, & &1.id) == [fragment.id]

    {:noreply, socket} = SelectIdentifier.handle_event("select_schema", %{"schema" => "all"}, socket)
    {:ok, socket} = SelectIdentifier.update(Map.put(props, :language, "no"), socket)
    assert socket.assigns.selected_schema == :all
    assert socket.assigns.identifiers == []
  end

  test "unrelated picker updates do not reload result sets" do
    first = identifier(Brando.Pages.Page, :en, :published)
    props = %{id: "picker", wanted_schemas: [Brando.Pages.Page], language: "en"}
    {:ok, socket} = SelectIdentifier.update(props, %Phoenix.LiveView.Socket{})
    identifier(Brando.Pages.Page, :en, :published)
    {:ok, socket} = SelectIdentifier.update(Map.put(props, :var_key, "changed"), socket)
    assert Enum.map(socket.assigns.identifiers, & &1.id) == [first.id]
  end

  test "link pickers exclude missing and invalid URLs from entries, content types and counts" do
    linked = identifier(Brando.Pages.Page, :en, :published, "/linked")
    home = identifier(Brando.Pages.Page, :en, :published, "/")
    invalid_urls = [nil, "", " \t\n", "/&lt;url cannot be localized&gt;", "javascript:alert(1)", "data:text/html,hello"]
    Enum.each(invalid_urls, &identifier(Brando.Pages.Page, :en, :published, &1))
    identifier(Brando.Pages.Fragment, :en, :published)
    identifier(Brando.Pages.Page, :en, :draft, "/draft")
    identifier(Brando.Pages.Page, :no, :published, "/norsk")

    props = %{
      id: "picker",
      wanted_schemas: [Brando.Pages.Page, Brando.Pages.Fragment],
      layout: :workspace,
      initial_schema: :all,
      language: "en",
      statuses: [:published],
      require_url: true
    }

    {:ok, socket} = SelectIdentifier.update(props, %Phoenix.LiveView.Socket{})
    assert Enum.sort(Enum.map(socket.assigns.identifiers, & &1.id)) == Enum.sort([linked.id, home.id])
    assert socket.assigns.schema_counts == %{Brando.Pages.Page => 2}
    assert Enum.map(socket.assigns.available_schemas, &elem(&1, 1)) == [Brando.Pages.Page]

    {:noreply, socket} =
      SelectIdentifier.handle_event("select_schema", %{"schema" => to_string(Brando.Pages.Page)}, socket)

    assert length(socket.assigns.identifiers) == 2
    {:noreply, socket} = SelectIdentifier.handle_event("select_schema", %{"schema" => "all"}, socket)
    assert length(socket.assigns.identifiers) == 2

    {:ok, socket} = SelectIdentifier.update(%{props | require_url: false}, socket)
    assert length(socket.assigns.identifiers) == length(invalid_urls) + 3
    assert socket.assigns.schema_counts == %{Brando.Pages.Page => length(invalid_urls) + 2, Brando.Pages.Fragment => 1}
  end

  test "an entry that loses its URL cannot be selected from stale link results" do
    linked = identifier(Brando.Pages.Page, :en, :published, "/linked")

    props = %{
      id: "picker",
      wanted_schemas: [Brando.Pages.Page],
      layout: :workspace,
      require_url: true,
      on_change: fn params -> send(self(), {:selected, params}) end
    }

    {:ok, socket} = SelectIdentifier.update(props, %Phoenix.LiveView.Socket{})
    linked |> Changeset.change(url: nil) |> Brando.Repo.update!()

    {:noreply, socket} = SelectIdentifier.handle_event("select_identifier", %{"id" => to_string(linked.id)}, socket)
    assert socket.assigns.selected_identifier_id == nil
    assert socket.assigns.identifiers == []
    refute_receive {:selected, _}

    {:ok, socket} = SelectIdentifier.update(%{props | require_url: false}, socket)
    {:noreply, socket} = SelectIdentifier.handle_event("select_identifier", %{"id" => to_string(linked.id)}, socket)
    assert socket.assigns.selected_identifier_id == linked.id
    assert_receive {:selected, %{data: %{identifier: %{id: id}}}}
    assert id == linked.id
  end

  test "an existing content link without a current URL keeps its saved address available for repair" do
    identifier = identifier(Brando.Pages.Page, :en, :published)
    alias BrandoAdmin.Components.Form.Input.Blocks.TipTapLinkDialog, as: Dialog
    {:ok, socket} = Dialog.mount(%Phoenix.LiveView.Socket{})

    {:ok, socket} =
      Dialog.update(%{event: :open, current_identifier_id: identifier.id, current_href: "/saved-address"}, socket)

    assert socket.assigns.unavailable_destination
    assert socket.assigns.selected_identifier_id == nil
    assert socket.assigns.link_type == :url
    assert socket.assigns.draft["url"] == "/saved-address"
    assert socket.assigns.has_existing_link?
  end

  test "Entries reconciles parent associations, including unloaded selections and removal" do
    a = identifier(Brando.Pages.Page, :en, :published)
    b = identifier(Brando.Pages.Page, :en, :published)
    socket = %Phoenix.LiveView.Socket{}

    Enum.reduce([[a], [b], []], socket, fn identifiers, socket ->
      joins = Enum.map(identifiers, &%Brando.Content.BlockIdentifier{identifier_id: &1.id})
      form = to_form(Changeset.change(%Brando.Content.Block{block_identifiers: joins}), as: "block")
      props = %{id: "entries", field: form[:block_identifiers], opts: [sources: [{Brando.Pages.Page, %{}}]]}
      {:ok, socket} = Entries.update(props, socket)
      assert Enum.map(socket.assigns.selected_identifiers, & &1.id) == Enum.map(identifiers, & &1.id)
      assert socket.assigns.has_entries == (identifiers != [])
      socket
    end)
  end

  test "Entries reloads its chosen schema when language changes" do
    a = identifier(Brando.Pages.Page, :en, :published)
    b = identifier(Brando.Pages.Page, :no, :published)
    make_form = fn language -> to_form(%{"language" => language}, as: "entry") end
    schema = {Brando.Blueprint.get_plural(Brando.Pages.Page), Brando.Pages.Page, %{}}

    socket =
      %Phoenix.LiveView.Socket{}
      |> Component.assign(:available_schemas, [schema])
      |> Component.assign(:opts, filter_language: true)
      |> Component.assign(:field, make_form.("en")[:entries])

    socket = Entries.assign_selected_schema(socket)
    assert Enum.map(socket.assigns.available_identifiers, & &1.id) == [a.id]
    socket = socket |> Component.assign(:field, make_form.("no")[:entries]) |> Entries.assign_selected_schema()
    assert Enum.map(socket.assigns.available_identifiers, & &1.id) == [b.id]
  end

  defp identifier(schema, language, status, url \\ nil) do
    Brando.Repo.insert!(%Identifier{
      schema: schema,
      language: language,
      status: status,
      url: url,
      entry_id: System.unique_integer([:positive]),
      title: "Fixture"
    })
  end
end
