defmodule Brando.FrontendEdit.FieldsTest do
  use ExUnit.Case, async: false
  use Brando.ConnCase

  import Brando.FrontendEditFixtures
  import Phoenix.LiveViewTest, only: [render_component: 2, rendered_to_string: 1]
  import Phoenix.Component, only: [sigil_H: 2]

  alias Brando.Factory
  alias Brando.FrontendEdit
  alias Brando.FrontendEdit.Fields
  alias Brando.FrontendEdit.Manifest
  alias Brando.Pages.Page

  setup do
    user = Factory.insert(:random_user, role: :superuser)
    on_exit(fn -> FrontendEdit.deactivate() end)
    page = Factory.insert(:page, creator: user, title: "Tom & <Jerry>", uri: "fields")
    {:ok, user: user, page: page}
  end

  describe "keys" do
    test "resolve inputs on the admin form, and nothing else", %{page: page} do
      key = Fields.key(Page, page.id, :title)
      assert Fields.parse_key(key) == {:ok, {Page, page.id, :title}}

      assert Fields.parse_key("Brando.Pages.Page:#{page.id}:not_a_field") == :error
      assert Fields.parse_key("Brando.Pages.Page:#{page.id}:blocks") == :error
      assert Fields.parse_key("Nope.Nope:1:title") == :error
      assert Fields.parse_key("Brando.Pages.Page:x:title") == :error
    end

    test "name fields by their form label", %{page: page} do
      assert Fields.label(Page, :title) == "Title"
      assert Fields.field(page, "title") == :title
      assert Fields.field(page, "nonexistent_field_name") == nil
    end
  end

  describe "values" do
    test "are escaped, except rich text", %{page: page} do
      assert IO.iodata_to_binary(Fields.render_value(page, :title)) == "Tom &amp; &lt;Jerry&gt;"
      refute Fields.rich_text?(Page, :title)
      assert Fields.render_value(%{page | title: nil}, :title) == ""
    end
  end

  describe "components" do
    test "print the value alone outside edit mode", %{page: page} do
      html = render_component(&Brando.HTML.editable_field/1, entry: page, field: :title)
      assert html == "Tom &amp; &lt;Jerry&gt;"

      assigns = %{page: page}
      html = rendered_to_string(~H"<Brando.HTML.editable entry={@page} field={:title}><b>x</b></Brando.HTML.editable>")
      assert html =~ "<b>x</b>"
      refute html =~ "[+:"
    end

    test "mark the field in edit mode", %{page: page} do
      key = Fields.key(Page, page.id, :title)

      FrontendEdit.with_active(fn ->
        html = render_component(&Brando.HTML.editable_field/1, entry: page, field: :title)
        assert html == "<!-- [+:E<#{key}>] -->Tom &amp; &lt;Jerry&gt;<!-- [-:E<#{key}>] -->"

        assigns = %{page: page}
        html = rendered_to_string(~H"<Brando.HTML.editable entry={@page} field={:title}><b>x</b></Brando.HTML.editable>")
        assert html =~ "<!-- [+:W<#{key}>] --><b>x</b><!-- [-:W<#{key}>] -->"
      end)
    end

    test "leave fields that are not on the form unmarked", %{page: page} do
      FrontendEdit.with_active(fn ->
        assert render_component(&Brando.HTML.editable_field/1, entry: page, field: :rendered_blocks) == ""
        assert render_component(&Brando.HTML.editable_field/1, entry: page, field: :sequence) == "0"
      end)
    end
  end

  describe "Liquid tags" do
    setup %{user: user} do
      {:ok, module} =
        Brando.Content.create_module(
          Factory.params_for(:module,
            name: %{"en" => "Title"},
            namespace: %{"en" => "Content"},
            help_text: %{},
            code: ~s(<h2>{% editable_field entry.title %}</h2>{% editable entry.title %}<i>wrapped</i>{% endeditable %}),
            refs: [],
            vars: []
          ),
          user
        )

      {:ok, module: module}
    end

    defp block_for(module, user) do
      %Brando.Content.Block{}
      |> Brando.Content.Block.recursive_block_changeset(
        %{
          "uid" => Brando.Utils.generate_uid(),
          "type" => "module",
          "module_id" => module.id,
          "creator_id" => user.id,
          "source" => to_string(Page.Blocks)
        },
        user
      )
      |> Brando.Repo.insert!()
    end

    test "print plainly in stored HTML, and with markers when annotating", %{page: page, module: module, user: user} do
      block = block_for(module, user)
      attach(Page.Blocks, page, [block])
      {:ok, page} = Brando.Content.Blocks.render_entry(Page, page.id)
      key = Fields.key(Page, page.id, :title)

      assert page.rendered_blocks =~ "<h2>Tom &amp; &lt;Jerry&gt;</h2><i>wrapped</i>"
      refute page.rendered_blocks =~ "[+:E<"

      html = FrontendEdit.with_active(fn -> FrontendEdit.rendered_html(page, :blocks) end)
      assert html =~ "<h2><!-- [+:E<#{key}>] -->Tom &amp; &lt;Jerry&gt;<!-- [-:E<#{key}>] --></h2>"
      assert html =~ "<!-- [+:W<#{key}>] --><i>wrapped</i><!-- [-:W<#{key}>] -->"

      # A preview render of the block annotates too, without edit mode
      preview =
        Brando.Villain.render_block(Brando.Repo.preload(block, [:vars, :refs, :children]), page, annotate_blocks: true)

      assert IO.iodata_to_binary(preview) =~ "[+:E<#{key}>]"
    end

    test "HEEx modules use the components", %{page: page, user: user} do
      {:ok, module} =
        Brando.Content.create_module(
          Factory.params_for(:module,
            type: :heex,
            name: %{"en" => "HEEx title"},
            namespace: %{"en" => "Content"},
            help_text: %{},
            code: ~S(<h3><.editable_field entry={@entry} field={:title} /></h3>),
            refs: [],
            vars: []
          ),
          user
        )

      attach(Page.Blocks, page, [block_for(module, user)])
      {:ok, page} = Brando.Content.Blocks.render_entry(Page, page.id)
      key = Fields.key(Page, page.id, :title)

      assert page.rendered_blocks =~ "<h3>Tom &amp; &lt;Jerry&gt;</h3>"
      html = FrontendEdit.with_active(fn -> FrontendEdit.rendered_html(page, :blocks) end)
      assert html =~ "<h3><!-- [+:E<#{key}>] -->Tom &amp; &lt;Jerry&gt;<!-- [-:E<#{key}>] --></h3>"
    end

    test "print a value that is not an entry field", %{page: page, user: user} do
      {:ok, module} =
        Brando.Content.create_module(
          Factory.params_for(:module,
            name: %{"en" => "Language"},
            namespace: %{"en" => "Content"},
            help_text: %{},
            code: ~s(<p>{% editable_field language %}</p>),
            refs: [],
            vars: []
          ),
          user
        )

      attach(Page.Blocks, page, [block_for(module, user)])
      {:ok, page} = Brando.Content.Blocks.render_entry(Page, page.id)
      assert page.rendered_blocks =~ "<p>en</p>"
    end
  end

  describe "manifest" do
    test "lists marked fields with their labels and permissions", %{page: page, user: user} do
      key = Fields.key(Page, page.id, :title)

      html =
        FrontendEdit.with_active(fn -> render_component(&Brando.HTML.editable_field/1, entry: page, field: :title) end)

      assert %{fields: %{^key => field}} = Manifest.build(html, user)
      assert %{label: "Title", entry: "Tom & <Jerry>", editable: true, shared: false} = field
      assert Manifest.editable?({Page, page.id, :title}, user)
    end
  end
end
