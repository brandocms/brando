defmodule BrandoAdmin.ContentTransferLiveTest do
  # The content transfer screen (/admin/config/import-export): choosing
  # entries, exporting a bundle, and reviewing, applying and recovering an
  # import. These flows were Playwright tests
  # (e2e/playwright/tests/configuration/content-transfer.spec.js and the
  # first test of admin-refinements.spec.js). Everything they asserted is
  # server-rendered, so it runs here. Focus, keyboard and narrow-layout checks
  # stay in the browser, in content-transfer.spec.js.
  use Brando.LiveCase

  import Brando.ContentTransferFixtures

  @path "/admin/config/import-export"

  # The catalog lists every Blueprint with an identifier. A few test-only
  # Blueprints have no table in the test database; give them an empty one
  # inside this test's transaction so the screen can list content at all.
  setup do
    catalog = Brando.Content.Transfer.Catalog

    for schema <- Enum.uniq(catalog.entry_schemas() ++ catalog.schemas()),
        table = schema.__schema__(:source),
        Repo.query!("SELECT to_regclass($1)::text", [table]).rows == [[nil]] do
      Repo.query!(~s[CREATE TABLE "#{table}" (id bigserial PRIMARY KEY)])
    end

    :ok
  end

  ## Helpers

  defp open(conn) do
    {:ok, view, _html} = live(conn, @path)
    render_async(view)
    view
  end

  defp norwegian(conn, user) do
    user |> Ecto.Changeset.change(language: :no) |> Repo.update!()
    conn |> recycle() |> log_in_user(user)
  end

  defp doc(view), do: view |> render() |> Floki.parse_document!()
  defp find(view, selector), do: view |> doc() |> Floki.find(selector)
  defp text(view, selector), do: view |> find(selector) |> Floki.text() |> squish()
  defp texts(view, selector), do: view |> find(selector) |> Enum.map(&(&1 |> Floki.text() |> squish()))
  defp squish(text), do: text |> String.replace(~r/\s+/u, " ") |> String.trim()
  defp count(view, selector), do: view |> find(selector) |> length()

  # Like Playwright's `getByRole("heading", name: ...)`: any heading level,
  # matching on a substring of its text.
  defp heading?(view, name), do: view |> texts("h1, h2, h3, h4, h5, h6") |> Enum.any?(&String.contains?(&1, name))

  defp click(view, selector, text \\ nil) do
    view |> element(selector, text) |> render_click()
    render_async(view, 5_000)
  end

  # Clicks the one element Floki finds for `selector`, which may use Floki-only
  # pseudo-classes such as `:fl-contains`. LiveViewTest's own parser must
  # not see those (it crashes the VM), so it gets the element's phx-click and
  # phx-value attributes instead.
  defp click_found(view, selector) do
    [{tag, attrs, _}] = find(view, selector)

    attribute_selector =
      for {name, value} <- attrs, name == "phx-click" or String.starts_with?(name, "phx-value-"), into: "" do
        "[#{name}='#{value}']"
      end

    click(view, tag <> attribute_selector)
  end

  defp button(view, label), do: click(view, "button", ~r/^\s*#{Regex.escape(label)}\s*$/)
  defp tab(view, tab), do: click(view, ".transfer-tabs button[phx-value-tab='#{tab}']")

  defp disabled?(view, selector) do
    [element] = find(view, selector)
    Floki.attribute(element, "disabled") != []
  end

  defp apply_disabled?(view), do: disabled?(view, "#transfer-apply")
  defp review_disabled?(view), do: disabled?(view, "#transfer-upload-form button[type=submit]")

  defp search(view, query), do: view |> element("#transfer-search") |> render_change(%{"query" => query})

  defp export(view, conn) do
    button(view, "Prepare export")
    download(view, conn)
  end

  # The bundle behind the download link, as the browser would save it.
  defp download(view, conn) do
    href =
      case view |> find("#transfer-download") |> Floki.attribute("href") do
        [href] -> href
        [] -> flunk("No bundle to download. The screen says: " <> text(view, "[role=alert], .transfer-error"))
      end

    response = get(conn, href)
    assert response.status == 200
    assert get_resp_header(response, "content-disposition") == [~s(attachment; filename="brando-content.zip")]
    assert binary_part(response.resp_body, 0, 2) == "PK"
    response.resp_body
  end

  defp upload(view, binary, name, type \\ "application/zip") do
    view
    |> file_input("#transfer-upload-form", :content_bundle, [%{name: name, content: binary, type: type}])
    |> render_upload(name)
  end

  defp review(view) do
    view |> form("#transfer-upload-form") |> render_submit()
    render_async(view, 5_000)
  end

  defp import_bundle(view, binary, name) do
    upload(view, binary, name)
    refute review_disabled?(view)
    review(view)
    assert has_element?(view, "#transfer-entry-mappings")
  end

  # The control a visible label names, looked up inside `scope`: its form, its
  # input name and, for a select, the value of the option labelled `option`.
  defp control(view, scope, label) do
    html = doc(view)
    [scope_node | _] = Floki.find(html, scope)

    [id] =
      scope_node
      |> Floki.find("label")
      |> Enum.filter(&(squish(Floki.text(&1)) == label))
      |> Enum.flat_map(&Floki.attribute(&1, "for"))

    [control] = Floki.find(html, "[id='#{id}']")
    form = Enum.find(Floki.find(html, "form"), &(Floki.find(&1, "[id='#{id}']") != []))
    [form_id] = Floki.attribute(form, "id")
    {control, "#" <> form_id}
  end

  defp has_label?(view, scope, label) do
    view
    |> find(scope <> " label")
    |> Enum.any?(&(squish(Floki.text(&1)) == label))
  end

  defp value(view, scope, label) do
    {control, _form} = control(view, scope, label)

    case control do
      {"select", _, _} ->
        control |> Floki.find("option[selected]") |> Floki.attribute("value") |> List.first()

      _ ->
        control |> Floki.attribute("value") |> List.first()
    end
  end

  defp option_texts(view, scope, label) do
    {control, _form} = control(view, scope, label)
    control |> Floki.find("option") |> Enum.map(&squish(Floki.text(&1)))
  end

  # Changes one field the way a browser does: the whole form, as rendered,
  # with this one value replaced.
  defp change(view, scope, label, value_or_option) do
    {control, form} = control(view, scope, label)
    [name] = Floki.attribute(control, "name")

    value =
      case {control, value_or_option} do
        {{"select", _, _}, {:option, option}} ->
          control
          |> Floki.find("option")
          |> Enum.find(&(squish(Floki.text(&1)) == option))
          |> Floki.attribute("value")
          |> List.first()

        {_, value} ->
          value
      end

    params = deep_merge(form_params(render(view), form), Plug.Conn.Query.decode(URI.encode_query([{name, value}])))
    view |> element(form) |> render_change(params)
    render_async(view, 5_000)
  end

  defp deep_merge(left, right) do
    Map.merge(left, right, fn
      _key, %{} = l, %{} = r -> deep_merge(l, r)
      _key, _l, r -> r
    end)
  end

  defp entry(title), do: ".transfer-whole-entry:has(h3:fl-contains('#{title}'))"

  # Playwright's `toContainText([...])`: some of the elements contain the
  # expected texts, one each, in the same order.
  defp contains_in_order?(texts, expected) do
    Enum.reduce_while(expected, texts, fn wanted, rest ->
      case Enum.drop_while(rest, &(not String.contains?(&1, wanted))) do
        [_ | rest] -> {:cont, rest}
        [] -> {:halt, :missing}
      end
    end) != :missing
  end

  defp recover(view, within \\ ".transfer-history-row") do
    tab(view, "history")
    [row | _] = find(view, within)
    [id] = row |> Floki.find("button[phx-click='review_restore']") |> Floki.attribute("phx-value-id")
    click(view, "button[phx-click='review_restore'][phx-value-id='#{id}']")
    click(view, ".transfer-recovery-confirm button[phx-click='restore']")
    id
  end

  ## Export

  test "related entries can be included from the export review", %{conn: conn, current_user: user} do
    content_transfer_related(user)
    view = open(conn)

    click(view, "button[aria-label='Select Campaign launch']")
    export(view, conn)

    assert text(view, ".transfer-related") =~ "Destination page"
    assert text(view, ".transfer-reference-paths") =~ "Campaign launch"
    assert text(view, ".transfer-related-title") =~ "Page"

    button(view, "Include entry")
    assert count(view, ".transfer-review-list article") == 2
    assert count(view, ".transfer-related") == 0
    refute text(view, ".transfer-dependency-groups") =~ "Destination page"
    assert text(view, ".transfer-review-list") =~ "Destination page"
  end

  test "type filters keep the selection, and an included parent can reuse its destination unchanged",
       %{conn: conn, current_user: user} do
    content_transfer_related(user)
    view = open(conn)

    campaign = ".transfer-entry:has(h3:fl-contains('Campaign launch'))"
    assert text(view, campaign <> " .transfer-entry-metadata") =~ user.name
    [datetime] = view |> find(campaign <> " time") |> Floki.attribute("datetime")
    assert datetime =~ ~r/^\d{4}-\d{2}-\d{2}T/

    filters = ".transfer-type-filters"
    page_filter = filters <> " button[phx-value-schema='Elixir.Brando.Pages.Page']"
    fragment_filter = filters <> " button[phx-value-schema='Elixir.Brando.Pages.Fragment']"

    click(view, page_filter)
    assert texts(view, ".transfer-entry .transfer-meta > span:first-child") == ["Page", "Page", "Page"]

    click(view, "button[aria-label='Select Campaign launch']")
    click(view, fragment_filter)
    assert count(view, filters <> " [aria-pressed='true']") == 2
    click(view, page_filter)
    assert count(view, "button[aria-label='Select Campaign launch']") == 0
    assert text(view, ".transfer-summary") =~ "Campaign launch"

    click(view, filters <> " .transfer-type-reset")
    assert view |> find("button[aria-label='Select Campaign launch']") |> Floki.attribute("aria-pressed") == ["true"]
    click(view, page_filter)
    click(view, fragment_filter)

    export(view, conn)
    assert text(view, ".transfer-reference-paths") =~ "Campaign launch"
    refute text(view, ".transfer-dependency-groups") =~ "Destination page"
    button(view, "Include entry")
    assert count(view, ".transfer-review-list article") == 2
    binary = download(view, conn)

    tab(view, "import")
    import_bundle(view, binary, "relations.zip")

    change(view, entry("Campaign launch"), "URI", "campaign-with-reused-parent")
    change(view, entry("Destination page"), "Import action", "reuse")
    change(view, entry("Destination page"), "Destination entry", {:option, "Destination page · English"})
    refute has_label?(view, entry("Destination page"), "Publication")
    refute text(view, entry("Destination page")) =~ "Review fields & content"
    refute apply_disabled?(view)

    click(view, "#transfer-apply")
    assert text(view, "#transfer-result") =~ "1 entry saved"

    conn = norwegian(conn, user)
    view = open(conn)
    click(view, page_filter)
    click(view, fragment_filter)
    assert view |> find(filters) |> Floki.attribute("aria-label") == ["Innholdstyper"]
    # The import above made a second "Campaign launch"; take the first, as the
    # browser test did.
    [entry_key | _] = view |> find("button[aria-label='Velg Campaign launch']") |> Floki.attribute("phx-value-entry")
    click(view, "button[aria-label='Velg Campaign launch'][phx-value-entry='#{entry_key}']")
    button(view, "Klargjør eksport")
    assert text(view, ".transfer-reference-paths") =~ "Brukes av"
    assert text(view, ".transfer-details summary") =~ "Inkluderte avhengigheter"
  end

  ## Import

  test "a whole entry is exported, reviewed for conflicts, created as a draft, updated and recovered",
       %{conn: conn, current_user: user} do
    content_transfer(user)
    view = open(conn)

    search(view, "Campaign")
    assert count(view, ".transfer-entry") == 1
    click(view, "button[aria-label='Select Campaign launch']")
    assert view |> find("button[aria-label='Select Campaign launch']") |> Floki.attribute("aria-pressed") == ["true"]
    assert text(view, ".transfer-summary") =~ "1 entry selected"
    search(view, "")
    assert count(view, ".transfer-entry") > 2

    binary = export(view, conn)
    assert heading?(view, "Your bundle is ready")
    assert text(view, ".transfer-review-list") =~ "Whole entry"

    tab(view, "import")
    import_bundle(view, binary, "campaign-launch-entry.zip")
    assert value(view, "#transfer-entry-mappings", "Import action") == "create"
    assert value(view, "#transfer-entry-mappings", "Publication") == "draft"
    assert text(view, ".transfer-inline-error") =~ "already in use"
    assert apply_disabled?(view)

    change(view, "#transfer-entry-mappings", "URI", "campaign-launch-copy")
    refute apply_disabled?(view)
    assert text(view, ".transfer-change-table") =~ "Draft"
    assert text(view, ".admin-text-diff") =~ "2 lines added"
    assert count(view, ".admin-text-diff del") == 0
    assert count(view, ".admin-text-diff ins") == 2

    click(view, "#transfer-apply")
    assert heading?(view, "Content imported")
    assert text(view, "#transfer-result") =~ "1 entry saved"
    assert count(view, "#transfer-result .error") == 0
    assert Repo.get_by(Brando.Pages.Page, uri: "campaign-launch-copy").status == :draft

    recover(view)
    assert text(view, ".transfer-history-row") =~ "Recovered"

    tab(view, "import")
    button(view, "Import another bundle")
    import_bundle(view, binary, "campaign-launch-entry.zip")
    change(view, "#transfer-entry-mappings", "Import action", "update")
    assert has_label?(view, "#transfer-entry-mappings", "Destination entry")
    assert value(view, "#transfer-entry-mappings", "Publication") == "preserve"
    change(view, "#transfer-entry-mappings", "Destination entry", {:option, "Destination page · English"})
    change(view, "#transfer-entry-mappings", "URI", "destination-entry-copy")
    refute apply_disabled?(view)
    assert text(view, ".transfer-change-table") =~ "Destination page"
    assert texts(view, ".admin-text-diff del") == ["Discover the stories behind our previous collection."]
    assert texts(view, ".admin-text-diff ins") == ["A considered introduction to our next collection."]
    assert texts(view, ".admin-text-diff .is-eq .text-diff-text") == ["Introduction"]

    click(view, "#transfer-apply")
    assert heading?(view, "Content imported")
    recover(view)
    [latest | _] = texts(view, ".transfer-history-row")
    assert latest =~ "Recovered"
    assert Process.alive?(view.pid)
  end

  test "media replacements and moves stay in their block context", %{conn: conn, current_user: user} do
    content_transfer_media(user)
    view = open(conn)

    click(view, "button[aria-label='Select Campaign launch']")
    # Untick "media": a browser sends the form as rendered, without it. (A
    # change on the form element would merge the checked box back in.)
    options = view |> render() |> form_params("#transfer-export-options") |> Map.delete("media")
    assert options == %{"definitions" => "true"}
    render_change(view, "export_options", options)
    binary = export(view, conn)

    tab(view, "import")
    import_bundle(view, binary, "campaign-media.zip")
    change(view, "#transfer-entry-mappings", "Import action", "update")
    change(view, "#transfer-entry-mappings", "Destination entry", {:option, "Destination page · English"})
    change(view, "#transfer-entry-mappings", "URI", "destination-media-copy")

    for name <- ["courtyard.jpg", "collection-detail.jpg"] do
      change(view, "#transfer-dependency-mappings", "Destination for images/#{name}", {:option, "images/#{name}"})
    end

    assert contains_in_order?(texts(view, ".admin-text-diff del"), [
             "Discover the stories behind our previous collection.",
             "Image · Hero: coastal-house.jpg",
             "Image · Detail: collection-detail.jpg"
           ])

    assert contains_in_order?(texts(view, ".admin-text-diff ins"), [
             "A considered introduction to our next collection.",
             "Image · Hero: courtyard.jpg",
             "Alt text: The courtyard in morning light",
             "Image · Detail: collection-detail.jpg"
           ])

    rows =
      view
      |> find(".admin-text-diff .text-diff-line")
      |> Enum.map(fn row ->
        {row |> Floki.attribute("class") |> List.first(), row |> Floki.find(".text-diff-text") |> Floki.text()}
      end)

    heading = Enum.find_index(rows, fn {_, text} -> text == "The details" end)
    moved_out = Enum.find_index(rows, fn {class, text} -> text =~ "collection-detail.jpg" and class =~ "is-del" end)
    moved_in = Enum.find_index(rows, fn {class, text} -> text =~ "collection-detail.jpg" and class =~ "is-ins" end)
    assert moved_out < heading
    assert moved_in > heading
    refute text(view, ".admin-text-diff") =~ "Text preview only"

    # Choosing another destination asset shows what will actually be imported.
    change(
      view,
      "#transfer-dependency-mappings",
      "Destination for images/courtyard.jpg",
      {:option, "images/coastal-house.jpg"}
    )

    assert text(view, ".admin-text-diff .is-eq.is-media") =~ "Image · Hero: coastal-house.jpg"
    refute text(view, ".admin-text-diff") =~ "courtyard.jpg"

    conn = norwegian(conn, user)
    view = open(conn)
    tab(view, "import")
    import_bundle(view, binary, "campaign-media.zip")
    diff = text(view, ".admin-text-diff")
    assert diff =~ "Bilde · Hero: courtyard.jpg"
    assert diff =~ "Alternativ tekst: The courtyard in morning light"
    assert diff =~ "Tekst og mediereferanser."
  end

  test "a Norwegian import keeps translated choices and validation after changes", %{conn: conn, current_user: user} do
    content_transfer(user)
    view = open(conn)
    click(view, "button[aria-label='Select Campaign launch']")
    binary = export(view, conn)

    conn = norwegian(conn, user)
    {:ok, view, html} = live(conn, @path)
    render_async(view)
    assert html |> Floki.parse_document!() |> Floki.find("html") |> Floki.attribute("lang") == ["no"]
    assert heading?(view, "Velg innhold")
    assert view |> texts(".transfer-entry") |> List.first() =~ "Engelsk"

    tab(view, "import")
    upload(view, "invalid archive", "invalid.zip")
    review(view)
    assert text(view, "[role=alert]") =~ "forventet et gyldig ZIP-arkiv"

    import_bundle(view, binary, "campaign-launch.zip")
    assert text(view, ".transfer-inline-error") =~ "allerede i bruk"

    entries = "#transfer-entry-mappings"
    assert option_texts(view, entries, "Publisering") == ["Lagre som utkast", "Bruk kildens status: Publisert"]
    assert option_texts(view, entries, "Språk") == ["Engelsk", "Norsk"]
    assert value(view, entries, "Tittel") == "Campaign launch"

    change(view, entries, "URI", "campaign-launch-norsk")
    assert text(view, ".transfer-change-table") =~ "Utkast"
    change(view, entries, "Publisering", "source")
    assert value(view, entries, "Publisering") == "source"
    assert text(view, ".transfer-change-table") =~ "Publisert"
    change(view, entries, "Språk", "no")
    assert value(view, entries, "Språk") == "no"
    assert text(view, ".transfer-change-table") =~ "Norsk"
    change(view, entries, "Publisering", "draft")
    assert text(view, ".transfer-change-table") =~ "Utkast"
    assert text(view, ".admin-text-diff") =~ "2 linjer lagt til"
    assert text(view, ".admin-text-diff") =~ "Ny oppføring · alt innhold legges til"
    assert text(view, "#transfer-apply") == "Importer innhold"
    refute apply_disabled?(view)

    click(view, "#transfer-apply")
    assert heading?(view, "Innhold importert")
    assert text(view, "#transfer-result") =~ "1 oppføring lagret"
    recover(view)
    assert text(view, ".transfer-history-row") =~ "Gjenopprettet"
  end

  test "select fields, export, review, cancel, append and recover saved content", %{conn: conn, current_user: user} do
    content_transfer(user)
    view = open(conn)
    assert heading?(view, "Content transfer")

    view |> element("#transfer-export-scope") |> render_change(%{"scope" => "fields"})
    assert disabled?(view, "button[phx-click='prepare_export']")
    search(view, "Campaign")
    assert count(view, ".transfer-entry") == 1

    row = ".transfer-entry:has(h3:fl-contains('Campaign launch'))"
    field = row <> " .transfer-field-pills button"
    assert text(view, field) == "Blocks"
    click_found(view, field)
    assert text(view, ".transfer-summary") =~ "1 field selected"
    click_found(view, field)
    assert disabled?(view, "button[phx-click='prepare_export']")
    click_found(view, field)
    assert view |> find(field) |> Floki.attribute("aria-pressed") == ["true"]

    search(view, "")
    assert count(view, ".transfer-entry") > 1
    assert view |> find(field) |> Floki.attribute("aria-pressed") == ["true"]
    assert text(view, row) =~ "English"
    assert text(view, row) =~ "Published"

    binary = export(view, conn)
    assert heading?(view, "Your bundle is ready")

    tab(view, "import")
    assert review_disabled?(view)

    assert {:error, [[_ref, :not_accepted]]} = upload(view, "Not a content bundle", "notes.txt", "text/plain")
    assert text(view, "[role=alert]") =~ "Choose a .zip content bundle."
    assert text(view, "#transfer-upload-form") =~ "Upload needs attention"
    assert review_disabled?(view)
    click(view, "#transfer-upload-form button[aria-label='Remove file']")
    assert count(view, "[role=alert]") == 0

    name = "campaign-launch-autumn-2026-content-bundle.zip"
    upload(view, binary, name)
    refute review_disabled?(view)
    assert text(view, "#transfer-upload-form") =~ "Bundle uploaded"
    assert view |> find("#transfer-upload-form input[type=file]") |> Floki.attribute("hidden") != []
    click(view, "#transfer-upload-form button[aria-label='Remove file']")
    assert review_disabled?(view)
    assert view |> find("#transfer-upload-form input[type=file]") |> Floki.attribute("hidden") == []
    upload(view, binary, name)
    refute review_disabled?(view)
    review(view)
    assert has_element?(view, "#transfer-import-review")

    assert apply_disabled?(view)
    change(view, "#transfer-import-review", "Destination entry", {:option, "Destination page · EN · Page"})
    refute apply_disabled?(view)
    assert text(view, "#transfer-import-review") =~ "Compare content"
    assert has_label?(view, "#transfer-import-review", "Import action")

    button(view, "Cancel import")
    tab(view, "history")
    assert heading?(view, "No imports yet")

    tab(view, "import")
    upload(view, binary, name)
    review(view)
    change(view, "#transfer-import-review", "Destination entry", {:option, "Destination page · EN · Page"})
    change(view, "#transfer-import-review", "Import action", "append")
    assert count(view, ".admin-text-diff") == 1
    assert count(view, ".admin-text-diff del") == 0

    assert contains_in_order?(texts(view, ".admin-text-diff .is-eq"), [
             "Introduction",
             "Discover the stories behind our previous collection."
           ])

    assert contains_in_order?(texts(view, ".admin-text-diff ins"), [
             "",
             "Introduction",
             "A considered introduction to our next collection."
           ])

    click(view, "#transfer-apply")
    assert heading?(view, "Content imported")
    recover(view)
    assert text(view, ".transfer-history-row") =~ "Recovered"
    assert Process.alive?(view.pid)
  end

  test "a missing definition is reviewed and installed without importing content until apply",
       %{conn: conn, current_user: user} do
    fixture = content_transfer(user)
    binary = unmatched_bundle(fixture, user)
    view = open(conn)

    tab(view, "import")
    upload(view, binary, "external-content.zip")
    refute review_disabled?(view)
    review(view)
    change(view, "#transfer-import-review", "Destination entry", {:option, "Destination page · EN · Page"})
    assert apply_disabled?(view)

    button(view, "Review included definitions")
    assert heading?(view, "Definition changes")
    button(view, "Install missing definitions")
    refute apply_disabled?(view)

    tab(view, "history")
    assert heading?(view, "No imports yet")

    tab(view, "import")
    click(view, "#transfer-apply")
    assert heading?(view, "Content imported")
    assert Process.alive?(view.pid)
  end
end
