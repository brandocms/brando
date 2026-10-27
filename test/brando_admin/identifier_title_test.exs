defmodule BrandoAdmin.IdentifierTitleTest do
  # A HEEx identifier (`identifier ~H"{@entry.title}"`) stores the entry's
  # title escaped. The admin screens printing it decode it first, so it is
  # escaped exactly once and markup in a title stays text. A Liquid
  # identifier stores the title as written, and it is printed as written.
  use Brando.ConnCase, async: false

  import Phoenix.Component, only: [sigil_H: 2]
  import Phoenix.LiveViewTest

  alias Brando.Authorization.{Groups, Migration, Scope}
  alias Brando.Blueprint.Identifier.HEExTest.HEExIdentifierSchema, as: HEExEntry
  alias Brando.Content.Identifier
  alias Brando.Factory
  alias BrandoAdmin.Components.Content.Identifier, as: IdentifierRow
  alias BrandoAdmin.Components.Content.SelectIdentifier
  alias BrandoAdmin.Components.Form.EntryHeader
  alias BrandoAdmin.Components.Form.Input.Entries
  alias BrandoAdmin.Components.Form.Input.RenderVar
  alias Phoenix.Socket.Broadcast

  @title "Rock & Roll <b>live</b>"
  # The title escaped once, as the page must carry it
  @once "Rock &amp; Roll &lt;b&gt;live&lt;/b&gt;"

  defp stored(title), do: title |> Phoenix.HTML.html_escape() |> Phoenix.HTML.safe_to_string()

  defp identifier(attrs \\ %{}) do
    struct(
      %Identifier{
        id: 1,
        schema: HEExEntry,
        entry_id: 1,
        title: stored(@title),
        status: :published,
        language: :en,
        url: "/rock"
      },
      attrs
    )
  end

  defp heex_entry, do: %HEExEntry{id: 1, title: @title, language: "en", status: :published}

  defp assert_once(html) do
    assert html =~ @once
    refute html =~ "&amp;amp;"
    refute html =~ "<b>"
  end

  test "the stored title is escaped by the HEEx identifier" do
    assert HEExEntry.__identifier__(heex_entry(), skip_cover: true).title == @once <> " [en]"
  end

  test "title_text/1 decodes a HEEx identifier's title only" do
    assert Identifier.title_text(identifier()) == @title
    assert Identifier.title_text(HEExEntry, stored(@title)) == @title
    assert Identifier.title_text(%Identifier{schema: Brando.Pages.Page, title: "Using &lt;br&gt;"}) == "Using &lt;br&gt;"
    assert Identifier.title_text(Brando.Pages.Page, "Using &lt;br&gt;") == "Using &lt;br&gt;"
    assert Identifier.title_text(nil) == nil
    assert Identifier.title_text(HEExEntry, nil) == nil
  end

  describe "identifier components" do
    test "a picker row or a selected entry prints the title once escaped" do
      assigns = %{identifier: identifier()}

      assert_once(rendered_to_string(~H"<IdentifierRow.content identifier={@identifier} />"))
    end

    test "the destination picker labels its rows with the title as text" do
      assigns = %{identifier: identifier()}

      html = rendered_to_string(~H"<SelectIdentifier.identifier identifier={@identifier} />")
      assert html =~ ~s(data-label="#{@once}")
      assert_once(html)

      html = rendered_to_string(~H"<SelectIdentifier.identifier identifier={@identifier} workspace />")
      assert html =~ ~s(data-label="#{@once} /rock")
    end

    test "a related entry row labels itself with the title as text" do
      assigns = %{identifiers: [identifier()]}

      html = rendered_to_string(~H"<Entries.identifier identifier_id={1} available_identifiers={@identifiers} />")
      assert html =~ ~s(data-label="#{@once}")
      assert_once(html)
    end

    # The link preview in a link var, as the menu form shows a menu item
    test "a link to an entry shows its title once escaped, and a label as written" do
      assigns = %{identifier: identifier(), label: "Write &lt;br&gt;"}
      assert_once(rendered_to_string(~H"<RenderVar.link_identifier identifier={@identifier} />"))

      html = rendered_to_string(~H"<RenderVar.link_identifier identifier={@identifier} link_text={@label} />")
      assert html =~ "Write &amp;lt;br&amp;gt;"
    end
  end

  defmodule SelectHost do
    use Phoenix.LiveView, layout: false

    alias Brando.Blueprint.Identifier.HEExTest.HEExIdentifierSchema, as: HEExEntry
    alias Phoenix.Component

    def mount(_, _, socket) do
      entry = %HEExEntry{id: 1, title: "Rock & Roll <b>live</b>", language: "en", status: :published}
      form = %Brando.Pages.Page{} |> Ecto.Changeset.change(parent_id: 1) |> Component.to_form(as: "page")
      {:ok, socket |> Component.assign(:form, form) |> Component.assign(:entry, entry)}
    end

    def handle_info(_message, socket), do: {:noreply, socket}

    def render(assigns) do
      ~H"""
      <.live_component
        module={BrandoAdmin.Components.Form.Input.Select}
        id="parent"
        field={@form[:parent_id]}
        label="Parent"
        opts={[options: [@entry]]}
      />
      """
    end
  end

  # The label of the selected option is rendered with raw/1 and set with
  # innerHTML when an option is picked: it carries the title escaped once
  test "an entry select labels its options once escaped" do
    {:ok, view, html} = live_isolated(build_conn(), SelectHost)
    assert html =~ ~r/data-select-preview="true">\s*#{Regex.escape(@once)} \[en\]\s*</
    assert_once(html)

    html = view |> element("button.button-edit") |> render_click()
    assert html =~ ~s(data-label="#{@once} [en]")
    # HTML in an attribute: escaped once more, read back once by innerHTML
    assert html =~ ~s(data-select-label="#{stored(@once)} [en]")
    assert html =~ "</svg> #{@once} [en]</span>"
    refute html =~ "<b>"
  end

  describe "an entry's own title" do
    test "the entry header and the frontend editor name it as text" do
      assert EntryHeader.title(HEExEntry, heex_entry()) == @title <> " [en]"
      assert Brando.FrontendEdit.Manifest.title(HEExEntry, heex_entry()) == @title <> " [en]"

      page = %Brando.Pages.Page{id: 1, title: "Using &lt;br&gt;", language: :en, uri: "using"}
      assert EntryHeader.title(Brando.Pages.Page, page) == "Using &lt;br&gt;"

      # A note's mention email and notifications
      assert Brando.Notes.entry_title(HEExEntry, heex_entry()) == @title <> " [en]"
      assert Brando.Notes.entry_title(Brando.Pages.Page, page) == "Using &lt;br&gt;"
    end

    test "the delete dialog names it once escaped" do
      %{html: html} = BrandoAdmin.LiveView.Listing.DeleteDescription.describe(HEExEntry, heex_entry())
      assert html =~ "<strong>#{@once} [en]</strong>"
      refute html =~ "&amp;amp;"
    end
  end

  describe "screens reading saved identifiers" do
    setup do
      put_test_env(:authorization_mode, :groups)
      put_test_env(:tenancy_mode, :none)
      owner = Factory.insert(:random_user, role: :superuser)
      user = Factory.insert(:random_user, role: :user)
      {:ok, _} = Migration.run()
      scope = Scope.standalone(owner)

      {:ok, group} =
        Groups.create(scope, %{name: "Editors"}, ~w(brando.admin.access brando.pages.read brando.pages.update))

      {:ok, :ok} = Groups.add_member(scope, group.id, user.id)

      %{user: user}
    end

    defp save_identifier(schema, entry_id, title) do
      Repo.insert!(%Identifier{
        schema: schema,
        entry_id: entry_id,
        title: title,
        status: :published,
        language: :en,
        updated_at: DateTime.utc_now(:second)
      })
    end

    # A page's identifier is Liquid: the title is stored as written
    test "the dashboard and the command palette show a Liquid title as written", c do
      title = "Write &lt;br&gt; & more"
      page = Factory.insert(:page, title: title, status: :published, language: :en)
      save_identifier(Brando.Pages.Page, page.id, title)

      assert [%{title: ^title}] = BrandoAdmin.Dashboard.load(c.user).recent
      assert [%{label: ^title}] = BrandoAdmin.CommandPalette.entries(c.user, "write")
    end

    test "usage lists and webhook deliveries name the entry as text" do
      save_identifier(HEExEntry, 4242, stored(@title))
      save_identifier(Brando.Pages.Page, 4243, "Using &lt;br&gt;")

      assert %{{HEExEntry, 4242} => %{label: @title}, {Brando.Pages.Page, 4243} => %{label: "Using &lt;br&gt;"}} =
               Brando.Content.Usage.labels([{HEExEntry, 4242}, {Brando.Pages.Page, 4243}])

      assert Brando.Webhooks.entry_titles([%{entry_id: 4242}, %{entry_id: 4243}]) == %{
               {to_string(HEExEntry), 4242} => @title,
               {to_string(Brando.Pages.Page), 4243} => "Using &lt;br&gt;"
             }
    end

    # The select prints these labels as HTML: each title is escaped once, a
    # Liquid one too, so markup in it is text
    test "the service page picker escapes each title once" do
      save_identifier(HEExEntry, 4242, stored(@title)) |> Ecto.Changeset.change(url: "/rock") |> Repo.update!()
      liquid = ~s(<img src=x onerror="document.title='MARKER'">)
      save_identifier(Brando.Pages.Page, 4243, liquid) |> Ecto.Changeset.change(url: "/img") |> Repo.update!()

      labels = Brando.Sites.Services.identifier_options(nil, []) |> Enum.map(& &1.label) |> Enum.sort()
      assert [heex, page] = labels
      assert String.ends_with?(heex, ": #{@once}")
      assert page == "Page: &lt;img src=x onerror=&quot;document.title=&#39;MARKER&#39;&quot;&gt;"
    end
  end

  # The toast sets the title as text
  test "a mutation toast carries the title as text" do
    Brando.endpoint().subscribe("lobby")
    on_exit(fn -> Brando.endpoint().unsubscribe("lobby") end)

    Brando.Notifications.push_mutation("updated", identifier(), :system)

    assert_receive %Broadcast{topic: "lobby", event: "toast", payload: %{payload: %{identifier: %{title: @title}}}}
  end
end
