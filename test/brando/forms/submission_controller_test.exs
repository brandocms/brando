defmodule Brando.Forms.SubmissionControllerTest do
  use Brando.ConnCase, async: false

  alias Brando.Factory
  alias Brando.Forms

  setup do
    Brando.Forms.RateLimit.reset()
    user = Factory.insert(:random_user)

    {:ok, form} =
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

    %{form: form, user: user}
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

  # Was a browser test (forms/form-submissions.spec.js): the site's own
  # wording reaches the visitor, who sees what this reply says.
  test "a JSON request words the errors as the site does", %{conn: conn, user: user} do
    {:ok, messages} = Forms.ensure_messages(user)
    {:ok, _} = Forms.update_messages(messages.id, %{"required" => %{"en" => "We need this one."}}, user)

    conn = post_form(conn, %{"email" => ""}, @json)
    assert %{"ok" => false, "errors" => %{"email" => ["We need this one."]}} = json_response(conn, 422)
  end

  test "a plain post goes back to the page, to the form's message", %{conn: conn} do
    referer = [{"referer", "http://www.example.com/contact?x=1#top"}]

    sent = post_form(conn, %{"email" => "ada@example.com"}, referer)
    assert redirected_to(sent, 303) == "http://www.example.com/contact?x=1#contact-box-sent"

    failed = post_form(build_conn(), %{"email" => ""}, referer)
    assert redirected_to(failed, 303) == "http://www.example.com/contact?x=1#contact-box-failed"
  end

  describe "with a page to go to once it is sent" do
    setup %{form: form, user: user} do
      {:ok, _} = Forms.update_form(form.id, %{"redirect_url" => "/thank-you?from=contact"}, user)
      :ok
    end

    test "a plain post goes to it, resolved against the page the form was on", %{conn: conn} do
      referer = [{"referer", "http://www.example.com/contact#top"}]

      sent = post_form(conn, %{"email" => "ada@example.com"}, referer)
      assert redirected_to(sent, 303) == "http://www.example.com/thank-you?from=contact"

      # A failure still goes back to the form
      failed = post_form(build_conn(), %{"email" => ""}, referer)
      assert redirected_to(failed, 303) == "http://www.example.com/contact#contact-box-failed"
    end

    test "a JSON reply carries it for the form's script", %{conn: conn} do
      conn = post_form(conn, %{"email" => "ada@example.com"}, @json)
      assert %{"ok" => true, "redirect" => "/thank-you?from=contact"} = json_response(conn, 200)
    end

    test "a full address is gone to as it is", %{conn: conn, form: form, user: user} do
      {:ok, _} = Forms.update_form(form.id, %{"redirect_url" => "https://example.com/thanks"}, user)

      sent = post_form(conn, %{"email" => "ada@example.com"}, [{"referer", "http://www.example.com/contact"}])
      assert redirected_to(sent, 303) == "https://example.com/thanks"
    end
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

  test "the visitor's token is served for the form's script, never cached", %{conn: conn} do
    conn =
      conn
      |> put_req_header("accept", "application/json, text/html;q=0.1")
      |> get("/__brando/forms/csrf-token")

    assert %{"token" => token} = json_response(conn, 200)
    assert is_binary(token) and token != ""
    assert get_resp_header(conn, "cache-control") == ["no-store, private"]
  end

  # Audit F22: behind a same-server proxy every post came from 127.0.0.1
  test "visitors are told apart behind a trusted proxy", %{conn: conn} do
    Application.put_env(:brando, Brando.Forms, rate_limit: [per_visitor: 1])
    on_exit(fn -> Application.delete_env(:brando, Brando.Forms) end)

    proxied = fn ip ->
      %{build_conn() | remote_ip: {127, 0, 0, 1}}
      |> post_form(%{"email" => "ada@example.com"}, [{"x-forwarded-for", ip} | @json])
    end

    assert json_response(proxied.("203.0.113.99"), 200)["ok"]
    assert json_response(proxied.("203.0.113.99"), 429)
    assert json_response(proxied.("198.51.100.4"), 200)["ok"]

    hashes = "contact" |> Forms.list_submissions() |> Enum.map(& &1.ip_hash) |> Enum.sort()
    assert hashes == Enum.sort([Forms.ip_hash("203.0.113.99"), Forms.ip_hash("198.51.100.4")])
    _ = conn
  end

  test "an unknown form is not found", %{conn: conn} do
    conn =
      conn
      |> put_req_header("accept", "application/json, text/html;q=0.1")
      |> post("/__brando/forms/missing", %{"fields" => %{}})

    assert json_response(conn, 404) == %{"ok" => false}
  end
end
