defmodule Brando.Forms.SubmissionControllerTest do
  use Brando.ConnCase, async: false

  alias Brando.Factory
  alias Brando.Forms

  setup do
    Cachex.clear(:cache)
    user = Factory.insert(:random_user)

    {:ok, _form} =
      Forms.create_form(
        %{
          "title" => "Contact",
          "key" => "contact",
          "language" => "en",
          "status" => "published",
          "fields" => [%{"key" => "email", "type" => "email", "label" => "Email", "required" => "true"}]
        },
        user
      )

    :ok
  end

  defp post_form(conn, fields, headers) do
    conn =
      Enum.reduce(headers, conn, fn {name, value}, conn -> put_req_header(conn, name, value) end)

    post(conn, "/__brando/forms/contact", %{"fields" => fields, "_language" => "en", "_form_id" => "contact-box"})
  end

  @json [{"accept", "application/json, text/html;q=0.1"}]

  test "a JSON request gets the success message", %{conn: conn} do
    conn = post_form(conn, %{"email" => "ada@example.com"}, @json)

    assert %{"ok" => true, "message" => message} = json_response(conn, 200)
    assert message =~ "Thank you"
    assert Forms.count_submissions("contact") == 1
  end

  test "a JSON request gets the errors by field", %{conn: conn} do
    conn = post_form(conn, %{"email" => "nope"}, @json)

    assert %{"ok" => false, "errors" => %{"email" => [_]}} = json_response(conn, 422)
    assert Forms.count_submissions("contact") == 0
  end

  test "a plain post goes back to the page, to the form's message", %{conn: conn} do
    referer = [{"referer", "http://www.example.com/contact?x=1#top"}]

    sent = post_form(conn, %{"email" => "ada@example.com"}, referer)
    assert redirected_to(sent, 303) == "http://www.example.com/contact?x=1#contact-box-sent"

    failed = post_form(build_conn(), %{"email" => ""}, referer)
    assert redirected_to(failed, 303) == "http://www.example.com/contact?x=1#contact-box-failed"
  end

  test "a post from another site is refused", %{conn: conn} do
    conn = post_form(conn, %{"email" => "ada@example.com"}, [{"origin", "https://evil.example.net"} | @json])

    assert json_response(conn, 403) == %{"ok" => false}
    assert Forms.count_submissions("contact") == 0
  end

  test "a post from the site itself is accepted", %{conn: conn} do
    conn = post_form(conn, %{"email" => "ada@example.com"}, [{"origin", "http://www.example.com"} | @json])
    assert %{"ok" => true} = json_response(conn, 200)
  end

  test "an unknown form is not found", %{conn: conn} do
    conn =
      conn
      |> put_req_header("accept", "application/json, text/html;q=0.1")
      |> post("/__brando/forms/missing", %{"fields" => %{}})

    assert json_response(conn, 404) == %{"ok" => false}
  end
end
