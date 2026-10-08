defmodule BrandoAdmin.Forms.FormFormLiveTest do
  use Brando.LiveCase

  alias Brando.Forms
  alias Brando.Forms.Form
  alias Brando.Translations

  setup %{current_user: user} do
    {:ok, form} =
      Forms.create_form(
        %{
          "title" => "Contact",
          "key" => "contact",
          "language" => "en",
          "status" => "published",
          "fields" => [
            %{"key" => "name", "type" => "text", "label" => "Full name", "width" => "half"},
            %{"key" => "email", "type" => "email", "label" => "Email", "width" => "half"},
            %{"key" => "message", "type" => "textarea", "label" => "Message"}
          ]
        },
        user
      )

    %{form: load(form.id)}
  end

  defp load(id) do
    {:ok, form} = Forms.get_form(%{matches: %{id: id}, preload: [:fields]})
    form
  end

  defp open(conn, id) do
    {view, html} = live_form(conn, "/admin/config/forms/update/#{id}", "form_form")
    {view, html}
  end

  defp rows(html) do
    html
    |> Floki.parse_document!()
    |> Floki.find(".form-fields-designer .var-layout-row")
    |> Enum.map(fn row ->
      row |> Floki.find(".var-chip-key") |> Enum.map(&(&1 |> Floki.text() |> String.trim() |> String.trim_trailing("*")))
    end)
  end

  defp save(view) do
    view |> form("#form_form_form") |> render_submit()
    assert_redirect(view, 3_000)
  end

  test "fields are laid out in rows and shown as visitors will see them", %{conn: conn, form: form} do
    {_view, html} = open(conn, form.id)

    assert rows(html) == [["name", "email"], ["message"]]
    assert html =~ ~s(class="site-form)
    assert html =~ "Full name"
  end

  test "a drop reorders the fields and starts the rows it reports", %{conn: conn, form: form} do
    {view, _html} = open(conn, form.id)
    [name, email, message] = Enum.map(form.fields, & &1.uid)

    view
    |> element(".form-fields-designer [phx-hook='Brando.VarLayout']")
    |> render_hook("reposition_vars", %{"rows" => [[message], [email, name]], "surface" => "content"})

    # The Form applies the change in its own update, after the event returns.
    assert rows(render(view)) == [["message"], ["email", "name"]]

    save(view)

    assert form.id |> load() |> Map.fetch!(:fields) |> Enum.map(&{&1.key, &1.new_row}) ==
             [{"message", true}, {"email", true}, {"name", false}]
  end

  test "an added field opens for editing and is saved with the form", %{conn: conn, form: form} do
    {view, _html} = open(conn, form.id)

    view |> element(".form-fields-quick-add button", "Dropdown") |> render_click()
    html = await_selector(view, ".modal.visible .form-field-options")

    assert rows(html) == [["name", "email"], ["message"], ["select"]]

    params = form_params(html, "#form_form_form")
    [{index, _}] = Enum.filter(params["form"]["fields"], fn {_, field} -> field["key"] == "select" end)

    params =
      params
      |> put_in(["form", "fields", index, "key"], "service")
      |> put_in(["form", "fields", index, "option_rows", "0", "label"], "Website")

    view |> element("#form_form_form") |> render_change(params)
    save(view)

    service = form.id |> load() |> Map.fetch!(:fields) |> Enum.find(&(&1.key == "service"))
    assert service.type == :select
    assert service.option_values == ["option_1", "option_2"]
    assert service.option_labels["option_1"] == "Website"
  end

  test "widths that do not fit the row are refused", %{conn: conn, form: form} do
    {view, _html} = open(conn, form.id)
    name = Enum.find(form.fields, &(&1.key == "name"))

    view
    |> element(".var-chip[data-key='#{name.uid}'] .var-width-group button", "1/1")
    |> render_click()

    assert rows(render(view)) == [["name", "email"], ["message"]]
  end

  test "a synchronized translation gets a read-only canvas", %{conn: conn, form: form, current_user: user} do
    {:ok, target} = Translations.create_target(Form, form.id, :no, user)
    {_view, html} = open(conn, target.id)

    assert html =~ ~s(data-locked="true")
    refute html =~ "Add field"
    refute html =~ ~s(phx-hook="Brando.VarLayout")
    assert html =~ "Set by the source form"
    assert rows(html) == [["name", "email"], ["message"]]
  end

  test "a translation saves its own wording", %{conn: conn, form: form, current_user: user} do
    {:ok, source} =
      Forms.update_form(
        form.id,
        %{
          "fields" => [
            %{"id" => Enum.at(form.fields, 0).id},
            %{"id" => Enum.at(form.fields, 1).id},
            %{"id" => Enum.at(form.fields, 2).id},
            %{
              "key" => "service",
              "type" => "select",
              "label" => "Service",
              "option_rows_present" => "1",
              "option_rows" => %{"0" => %{"value" => "web", "label" => "Website"}}
            }
          ]
        },
        user
      )

    {:ok, target} = Translations.create_target(Form, source.id, :no, user)
    {view, html} = open(conn, target.id)

    params = form_params(html, "#form_form_form")
    [{index, _}] = Enum.filter(params["form"]["fields"], fn {_, field} -> field["key"] == "service" end)

    params =
      params
      |> put_in(["form", "fields", index, "label"], "Tjeneste")
      |> put_in(["form", "fields", index, "option_rows", "0", "label"], "Nettside")

    view |> element("#form_form_form") |> render_change(params)
    view |> form("#form_form_form") |> render_submit()
    assert_redirect(view, 3_000)

    service = target.id |> load() |> Map.fetch!(:fields) |> Enum.find(&(&1.key == "service"))
    assert service.label == "Tjeneste"
    assert service.option_labels == %{"web" => "Nettside"}
  end

  test "who is emailed, the page after sending and the retention are saved with the form", %{
    conn: conn,
    form: form
  } do
    {view, html} = open(conn, form.id)
    assert html =~ ~s(id="form-usage-title")

    params =
      html
      |> form_params("#form_form_form")
      |> put_in(["form", "recipients"], %{
        "0" => %{"name" => "Post", "email" => "post@example.com", "bcc" => "false"},
        "1" => %{"name" => "", "email" => "archive@example.com", "bcc" => "true"}
      })
      |> put_in(["form", "subject"], "From {{ name }}")
      |> put_in(["form", "confirmation"], "true")
      |> put_in(["form", "redirect_url"], "/thank-you")
      |> put_in(["form", "retention_days"], "90")

    view |> element("#form_form_form") |> render_change(params)
    save(view)

    {:ok, saved} = Forms.get_form(%{matches: %{id: form.id}})
    assert Enum.map(saved.recipients, &{&1.email, &1.bcc}) == [{"post@example.com", false}, {"archive@example.com", true}]
    assert Enum.all?(saved.recipients, & &1.uid)
    assert saved.subject == "From {{ name }}"
    assert saved.confirmation
    assert saved.redirect_url == "/thank-you"
    assert saved.retention_days == 90
  end

  # A browser posts the whole form on every change; each `validate/1` does the same.
  defp validate(view) do
    html = render(view)
    view |> element("#form_form_form") |> render_change(form_params(html, "#form_form_form"))
  end

  test "layout and required survive validates, including a toggle put back", %{conn: conn, form: form} do
    {view, _html} = open(conn, form.id)
    [name, email, message] = Enum.map(form.fields, & &1.uid)

    view
    |> element(".form-fields-designer [phx-hook='Brando.VarLayout']")
    |> render_hook("reposition_vars", %{"rows" => [[name], [email, message]]})

    toggle = element(view, ".var-chip[data-key='#{name}'] .form-field-required-toggle")
    render_click(toggle)
    validate(view)
    validate(view)
    render_click(toggle)
    validate(view)
    validate(view)
    save(view)

    fields = form.id |> load() |> Map.fetch!(:fields)
    assert Enum.map(fields, &{&1.key, &1.new_row}) == [{"name", true}, {"email", true}, {"message", false}]
    refute Enum.find(fields, &(&1.key == "name")).required
  end

  test "a translation that changes what the source controls is refused, not crashed", %{
    conn: conn,
    form: form,
    current_user: user
  } do
    {:ok, target} = Translations.create_target(Form, form.id, :no, user)
    {view, html} = open(conn, target.id)

    params = form_params(html, "#form_form_form")
    [{index, _}] = Enum.filter(params["form"]["fields"], fn {_, field} -> field["key"] == "name" end)
    params = put_in(params, ["form", "fields", index, "required"], "true")

    view |> element("#form_form_form") |> render_change(params)
    view |> form("#form_form_form") |> render_submit()

    # Still on the form, and nothing was written
    assert render(view) =~ "form-fields-designer"
    refute target.id |> load() |> Map.fetch!(:fields) |> Enum.find(&(&1.key == "name")) |> Map.fetch!(:required)
  end

  # A saved field the editor removes stays in the changeset, marked for
  # removal; the next add wrote it back and took the LiveView down.
  test "a field can be added after a saved one is removed", %{conn: conn, form: form} do
    {view, _html} = open(conn, form.id)
    message = Enum.find(form.fields, &(&1.key == "message"))
    index = Enum.find_index(form.fields, &(&1.uid == message.uid))

    view |> element("#form_form_form") |> render_change(%{"form" => %{"drop_fields_ids" => ["#{index}"]}})
    assert rows(settle(view)) == [["name", "email"]]

    view |> element(".form-fields-quick-add button", "Dropdown") |> render_click()
    assert rows(settle(view)) == [["name", "email"], ["select"]]

    save(view)
    assert form.id |> load() |> Map.fetch!(:fields) |> Enum.map(& &1.key) == ["name", "email", "select"]
  end

  # Both clicks of a double click on an option's × reach the server before
  # it has re-rendered the list. By position, the second removed the option
  # that moved into the first one's place.
  test "a double click on an option's × removes that option only", %{conn: conn, form: form} do
    {view, _html} = open(conn, form.id)
    view |> element(".form-fields-quick-add button", "Dropdown") |> render_click()
    await_selector(view, ".modal.visible .form-field-options")

    view
    |> element(".modal.visible .form-field-option-remove[aria-label='Remove option option_1']")
    |> then(&queue_clicks(view, &1))

    refute has_element?(view, ".modal.visible .form-field-option-remove[aria-label='Remove option option_1']")
    assert has_element?(view, ".modal.visible .form-field-option-remove[aria-label='Remove option option_2']")
  end
end
