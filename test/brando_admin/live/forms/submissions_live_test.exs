defmodule BrandoAdmin.Forms.SubmissionsLiveTest do
  use Brando.LiveCase

  alias Brando.Forms

  setup %{current_user: user} do
    Brando.Forms.RateLimit.reset()

    {:ok, _form} =
      Forms.create_form(
        %{
          "title" => "Contact",
          "key" => "contact",
          "language" => "en",
          "status" => "published",
          "fields" => [
            %{"key" => "name", "type" => "text", "label" => "Name"},
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

    submit = fn fields ->
      {:ok, submission, _} =
        Forms.submit("contact", %{"fields" => fields, "_language" => "en"}, %{ip: "203.0.113.1", url: "/contact"})

      submission
    end

    %{submit: submit}
  end

  test "lists submissions with option labels and opens one", %{conn: conn, submit: submit} do
    submission = submit.(%{"name" => "Ada", "service" => "web"})
    {:ok, view, _html} = live(conn, "/admin/forms/contact/submissions")
    html = render_async(view)

    assert html =~ "Ada"
    assert html =~ "Website"

    html = view |> element("#submission-#{submission.id} button") |> render_click()
    assert html =~ "submission-detail"
    assert html =~ "/contact"
  end

  test "the forms page lists each form once, with what visitors have sent", %{conn: conn, submit: submit} do
    submit.(%{"name" => "Ada"})
    submit.(%{"name" => "Grace"})

    {:ok, _view, html} = live(conn, "/admin/forms")
    [row] = html |> Floki.parse_document!() |> Floki.find("#form-inbox-contact")

    assert Floki.text(row) =~ "Contact"
    assert row |> Floki.find("td.monospace") |> hd() |> Floki.text() |> String.trim() == "2"
    assert Floki.attribute(row, "a", "href") == ["/admin/forms/contact/submissions"]
    assert html =~ ~s(href="/admin/config/forms")
  end

  test "a submission can be deleted", %{conn: conn, submit: submit} do
    submission = submit.(%{"name" => "Ada"})
    {:ok, view, _html} = live(conn, "/admin/forms/contact/submissions")
    render_async(view)

    view |> element("#submission-#{submission.id} button") |> render_click()
    view |> element("#submission-detail button.danger") |> render_click()

    refute render(view) =~ "submission-#{submission.id}"
    assert Forms.count_submissions("contact") == 0
  end

  test "shows whether a submission was emailed, and sends it again", %{conn: conn, current_user: user} do
    form = Forms.get_published_form("contact", "en")
    {:ok, _} = Forms.update_form(form.id, %{"recipients" => [%{"email" => "post@example.com"}]}, user)

    previous = Application.get_env(:brando, :mailer)
    on_exit(fn -> Application.put_env(:brando, :mailer, previous) end)
    Application.put_env(:brando, :mailer, BrandoIntegration.FailingMailer)

    {:ok, submission, _} =
      Forms.submit("contact", %{"fields" => %{"name" => "Ada"}, "_language" => "en"}, %{ip: "203.0.113.1"})

    {:ok, view, _html} = live(conn, "/admin/forms/contact/submissions")
    assert has_element?(view, "#submission-#{submission.id} .form-submission-email.is-failed")

    view |> element("#submission-#{submission.id} button", "Open") |> render_click()
    assert has_element?(view, "#submission-detail .form-submission-error", "503")

    Application.put_env(:brando, :mailer, BrandoIntegration.Mailer)
    view |> element("#submission-detail button", "Send again") |> render_click()

    assert has_element?(view, "#submission-#{submission.id} .form-submission-email.is-sent")
    refute has_element?(view, "#submission-detail .form-submission-error")
  end

  test "exports CSV with labelled columns and spreadsheet formulas neutralised", %{conn: conn, submit: submit} do
    submit.(%{"name" => "=HYPERLINK(\"x\")", "service" => "web"})

    conn = get(conn, "/admin/forms/contact/submissions/export")
    assert response_content_type(conn, :csv) =~ "text/csv"
    [header, row] = conn |> response(200) |> String.split("\r\n", trim: true)

    assert header =~ ~s("Name","Service")
    assert row =~ "\"'=HYPERLINK(\"\"x\"\")\""
    assert row =~ "\"Website\""
  end
end
