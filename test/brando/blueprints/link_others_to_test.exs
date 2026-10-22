defmodule Brando.Blueprint.LinkOthersToTest do
  use ExUnit.Case, async: false
  use Brando.ConnCase

  import Phoenix.LiveViewTest, only: [render_component: 2]

  alias Brando.Content.Identifier
  alias Brando.Content.Var
  alias Brando.LinkTest.Case
  alias BrandoAdmin.Components.Content.Identifier, as: IdentifierRow
  alias BrandoAdmin.Components.Content.SelectIdentifier

  defp insert_case(attrs) do
    case_entry =
      %Case{title: "Client work", slug: "client-work", type: :external_link, external_link: "client.example/work"}
      |> struct(attrs)
      |> Brando.Repo.insert!()

    {:ok, identifier} = Brando.Content.create_identifier(Case, case_entry)
    {case_entry, identifier}
  end

  defp change_case(case_entry, changes) do
    case_entry = case_entry |> Ecto.Changeset.change(changes) |> Brando.Repo.update!()
    {:ok, identifier} = Brando.Content.update_identifier(Case, case_entry)
    {case_entry, identifier}
  end

  defp link_var(identifier), do: %Var{type: :link, link_type: :identifier, identifier: identifier}

  describe "the blueprint" do
    test "a case linked elsewhere has no URL here, but a link destination" do
      linked = %Case{slug: "work", type: :external_link, external_link: "client.example/work"}

      assert Case.__absolute_url__(linked) == nil
      refute Case.__has_url__(linked)
      assert Case.__url_filter__() == %{type: :full_case}
      assert Case.__external_url__(linked) == "https://client.example/work"
    end

    test "a full case has its page and no external destination" do
      full = %Case{slug: "work", type: :full_case, external_link: "https://client.example"}

      assert Case.__absolute_url__(full) == "/cases/work"
      assert Case.__external_url__(full) == nil
    end

    test "an empty or unsafe destination is none" do
      assert Case.__external_url__(%Case{type: :external_link, external_link: nil}) == nil
      assert Case.__external_url__(%Case{type: :external_link, external_link: " "}) == nil
      assert Case.__external_url__(%Case{type: :external_link, external_link: "javascript:alert(1)"}) == nil
    end

    test "is left out of the sitemap and the SEO audit" do
      linked = %Case{slug: "work", type: :external_link, external_link: "https://client.example"}

      refute Brando.Blueprint.URL.has_url?(linked)
      refute Brando.SEO.Audit.has_url?(Case, linked)

      assert [%{loc: "/cases/full"}] ==
               [linked, %Case{slug: "full", type: :full_case}]
               |> Enum.map(&%{loc: Case.__absolute_url__(&1)})
               |> Brando.Sitemap.reject_without_loc(:cases)
               |> Enum.to_list()
    end

    test "link_others_to: needs only: and a field name" do
      assert_raise Brando.Exception.BlueprintError, ~r/link_others_to:/, fn ->
        Code.compile_string("""
        defmodule Brando.Blueprint.LinkOthersToTest.WithoutOnly do
          import Brando.Blueprint.AbsoluteURL
          absolute_url "/x", link_others_to: :external_link
        end
        """)
      end

      assert_raise Brando.Exception.BlueprintError, ~r/names a field/, fn ->
        Code.compile_string("""
        defmodule Brando.Blueprint.LinkOthersToTest.NotAField do
          import Brando.Blueprint.AbsoluteURL
          absolute_url "/x", only: %{type: :full_case}, link_others_to: "external_link"
        end
        """)
      end
    end
  end

  describe "the identifier" do
    test "stores the destination apart from the URL" do
      {_case_entry, identifier} = insert_case(%{})

      assert identifier.url == nil
      assert identifier.external_url == "https://client.example/work"
      assert Identifier.link_url(identifier) == "https://client.example/work"
    end

    test "follows an edited destination and a switch to a full case" do
      {case_entry, _identifier} = insert_case(%{})

      {case_entry, identifier} = change_case(case_entry, external_link: "https://elsewhere.example")
      assert Identifier.link_url(identifier) == "https://elsewhere.example"

      {_case_entry, identifier} = change_case(case_entry, type: :full_case)
      assert identifier.url == "/cases/client-work"
      assert identifier.external_url == nil
      assert Identifier.link_url(identifier) == "/cases/client-work"
    end

    test "rewrites stored rich-text links when the destination changes" do
      {target, identifier} = insert_case(%{})

      summary = ~s(<p>See <a href="https://client.example/work" data-identifier-id="#{identifier.id}">the work</a></p>)
      holder = Brando.Repo.insert!(%Case{title: "Holder", slug: "holder", type: :full_case, summary: summary})

      change_case(target, type: :full_case)
      assert Brando.Repo.get!(Case, holder.id).summary =~ ~s(href="/cases/client-work")

      change_case(Brando.Repo.get!(Case, target.id), type: :external_link)
      assert Brando.Repo.get!(Case, holder.id).summary =~ ~s(href="https://client.example/work")
    end
  end

  describe "links to the entry" do
    test "a link var and a menu item go to the destination, then to the page" do
      {case_entry, identifier} = insert_case(%{})

      assert Brando.Villain.Filters.link_url(link_var(identifier), nil) == "https://client.example/work"
      assert Brando.HTML.get_menu_item_url(%{link: link_var(identifier)}) == "https://client.example/work"

      {_case_entry, identifier} = change_case(case_entry, type: :full_case)

      assert Brando.Villain.Filters.link_url(link_var(identifier), nil) == "/cases/client-work"
      assert Brando.HTML.get_menu_item_url(%{link: link_var(identifier)}) == "/cases/client-work"
    end

    test "the picker lists it where a URL is required" do
      {_case_entry, linked} = insert_case(%{})
      {_case_entry, nowhere} = insert_case(%{slug: "nowhere", external_link: nil})

      props = %{id: "picker", wanted_schemas: [Case], layout: :workspace, require_url: true}
      {:ok, socket} = SelectIdentifier.update(props, %Phoenix.LiveView.Socket{})

      assert Enum.map(socket.assigns.identifiers, & &1.id) == [linked.id]
      assert socket.assigns.schema_counts == %{Case => 1}

      {:noreply, socket} = SelectIdentifier.handle_event("select_identifier", %{"id" => to_string(nowhere.id)}, socket)
      assert socket.assigns.selected_identifier_id == nil
    end

    test "the picker marks it as external, with the host" do
      {_case_entry, identifier} = insert_case(%{external_link: "https://www.client.example/work"})

      html = render_component(&IdentifierRow.destination/1, identifier: identifier)
      assert html =~ "identifier-external"
      assert html =~ ~s(title="https://www.client.example/work")
      assert html =~ "client.example"
      refute html =~ ">https://www.client.example/work<"

      page = render_component(&IdentifierRow.destination/1, identifier: %Identifier{url: "/cases/a"})
      assert page =~ "/cases/a"
      refute page =~ "identifier-external"
    end
  end
end
