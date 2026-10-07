defmodule BrandoAdmin.Components.Form.EntryHeaderTest do
  # The entry editor's heading: breadcrumb, title, status choices with the
  # publishing rule, and lifting the status input out of the form's tabs.
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest, only: [rendered_to_string: 1]

  alias Brando.Blueprint.Forms.Fieldset
  alias Brando.Blueprint.Forms.Input
  alias Brando.Blueprint.Forms.Tab
  alias BrandoAdmin.Components.Form.EntryHeader

  describe "crumbs/1" do
    test "names the listing as the sidebar does, with the blueprint's icon" do
      crumbs = EntryHeader.crumbs(Brando.Pages.Page)

      assert crumbs.listing == "Pages"
      assert crumbs.icon == Brando.Blueprint.get_icon(Brando.Pages.Page)
      # A page is called a page: no second name
      assert crumbs.kind == nil
    end
  end

  describe "kind/2" do
    test "is the blueprint's own name for its entries when it renamed them" do
      assert EntryHeader.kind("Case", ["project", "Project"]) == "Case"
    end

    test "is nil for the schema's own name or a translation of it" do
      assert EntryHeader.kind("Page", ["page", "page"]) == nil
      assert EntryHeader.kind("Side", ["page", "side"]) == nil
    end
  end

  describe "language/1" do
    test "upper-cases the entry's language" do
      assert EntryHeader.language(%{language: :no}) == "NO"
      assert EntryHeader.language(%{language: "en"}) == "EN"
    end

    test "is nil without one" do
      assert EntryHeader.language(%{language: nil}) == nil
      assert EntryHeader.language(%{title: "No language field"}) == nil
    end
  end

  describe "title/2" do
    test "a new entry is \"New\" and the blueprint's name" do
      assert EntryHeader.title(Brando.Pages.Page, %Brando.Pages.Page{}) == "New page"
    end

    test "a saved entry is titled as its identifier renders it" do
      page = %Brando.Pages.Page{id: 1, title: "About us", language: :en, uri: "about"}
      assert EntryHeader.title(Brando.Pages.Page, page) == "About us"
    end

    test "falls back to the singular when the entry has no title" do
      page = %Brando.Pages.Page{id: 1, title: "", language: :en, uri: "about"}
      assert EntryHeader.title(Brando.Pages.Page, page) == "Page"
    end
  end

  describe "status_options/3" do
    test "every status, labelled from Gettext, when the user may publish" do
      options = EntryHeader.status_options(:draft, true)

      assert Enum.map(options, & &1.value) == ~w(draft pending published disabled)
      assert Enum.map(options, & &1.label) == ["Draft", "Pending", "Published", "Deactivated"]
      refute Enum.any?(options, & &1.disabled)
    end

    test "without the publish permission, an unpublished entry can't be published" do
      options = EntryHeader.status_options(:draft, false)

      assert disabled(options) == ["published"]
    end

    test "without the publish permission, a published entry keeps its status" do
      options = EntryHeader.status_options(:published, false)

      assert disabled(options) == ~w(draft pending disabled)
    end

    test "a new entry without the permission can't start published" do
      assert disabled(EntryHeader.status_options(nil, false)) == ["published"]
    end

    test "labels are translated" do
      Gettext.with_locale(Brando.Gettext, "no", fn ->
        labels = Enum.map(EntryHeader.status_options(:draft, true), & &1.label)
        assert labels == ["Utkast", "Venter", "Publisert", "Deaktivert"]
      end)
    end

    defp disabled(options), do: for(%{disabled: true, value: value} <- options, do: value)
  end

  describe "lift_status/1" do
    test "takes a plain status input out of its fieldset" do
      status = %Input{name: :status, type: :status, opts: [label: "Status"]}
      title = %Input{name: :title, type: :text, opts: []}
      tabs = [%Tab{name: "Content", fields: [%Fieldset{fields: [status, title]}]}]

      assert {[%Tab{fields: [%Fieldset{fields: [^title]}]}], :status} = EntryHeader.lift_status(tabs)
    end

    test "drops a fieldset left empty, but not one with a legend" do
      status = %Input{name: :status, type: :status, opts: []}
      title = %Input{name: :title, type: :text, opts: []}

      tabs = [%Tab{name: "Content", fields: [%Fieldset{fields: [status]}, %Fieldset{fields: [title]}]}]
      assert {[%Tab{fields: [%Fieldset{fields: [^title]}]}], :status} = EntryHeader.lift_status(tabs)

      labelled = [%Tab{name: "Content", fields: [%Fieldset{label: "Publishing", fields: [status]}]}]
      assert {[%Tab{fields: [%Fieldset{label: "Publishing", fields: []}]}], :status} = EntryHeader.lift_status(labelled)
    end

    test "leaves a status input with options of its own where it is" do
      conditional = %Input{name: :status, type: :status, opts: [show_if: {:type, :page}]}
      tabs = [%Tab{name: "Content", fields: [%Fieldset{fields: [conditional]}]}]
      assert EntryHeader.lift_status(tabs) == {tabs, nil}

      superuser = [
        %Tab{name: "Content", fields: [%Fieldset{superuser: true, fields: [%Input{name: :status, type: :status}]}]}
      ]

      assert EntryHeader.lift_status(superuser) == {superuser, nil}
    end

    test "nothing to lift without a status input" do
      tabs = [%Tab{name: "Content", fields: [%Fieldset{fields: [%Input{name: :status, type: :select}]}]}]
      assert EntryHeader.lift_status(tabs) == {tabs, nil}
    end
  end

  describe "status_control/1" do
    test "posts the field from outside the form, and disables what may not be chosen" do
      html =
        %{
          id: "page_form-status",
          form_id: "page_form_form",
          name: "page[status]",
          value: :draft,
          options: EntryHeader.status_options(:draft, false),
          __changed__: nil
        }
        |> EntryHeader.status_control()
        |> rendered_to_string()

      assert html =~ ~s(data-status="draft")
      assert html =~ ~s(aria-expanded="false")
      assert html =~ ~s(form="page_form_form")
      assert html =~ ~s(data-field-presence="page[status]")
      assert [_] = Regex.scan(~r/<input[^>]*value="draft"[^>]*checked/, html)
      assert [_] = Regex.scan(~r/<input[^>]*value="published"[^>]*disabled/, html)
    end
  end
end
