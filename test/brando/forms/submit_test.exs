defmodule Brando.Forms.SubmitTest do
  use Brando.ConnCase, async: false

  alias Brando.Factory
  alias Brando.Forms
  alias Brando.Forms.Submission
  alias Brando.Forms.Validation

  setup do
    Cachex.clear(:cache)
    previous = Application.get_env(:brando, Brando.Forms)
    on_exit(fn -> Application.put_env(:brando, Brando.Forms, previous || []) end)

    user = Factory.insert(:random_user)

    {:ok, form} =
      Forms.create_form(
        %{
          "title" => "Contact",
          "key" => "contact",
          "language" => "en",
          "status" => "published",
          "fields" => [
            %{"key" => "name", "type" => "text", "label" => "Name", "required" => "true"},
            %{"key" => "email", "type" => "email", "label" => "Email", "required" => "true"},
            %{"key" => "about", "type" => "section", "label" => "About"},
            %{
              "key" => "service",
              "type" => "select",
              "label" => "Service",
              "option_rows_present" => "1",
              "option_rows" => %{"0" => %{"value" => "web", "label" => "Website"}}
            },
            %{
              "key" => "topics",
              "type" => "checkboxes",
              "label" => "Topics",
              "option_rows_present" => "1",
              "option_rows" => %{"0" => %{"value" => "a", "label" => "A"}, "1" => %{"value" => "b", "label" => "B"}}
            },
            %{"key" => "privacy", "type" => "consent", "label" => "I agree", "required" => "true"},
            %{"key" => "source", "type" => "hidden", "default_value" => "landing"}
          ]
        },
        user
      )

    %{form: Forms.get_published_form("contact", "en"), user: user, form_id: form.id}
  end

  defp valid(extra \\ %{}) do
    Map.merge(
      %{
        "name" => " Ada ",
        "email" => "ada@example.com",
        "service" => "web",
        "topics" => ["b", "a"],
        "privacy" => "true",
        "source" => "landing"
      },
      extra
    )
  end

  defp meta, do: %{ip: "203.0.113.7", user_agent: "Test", url: "https://example.com/contact"}

  describe "validation" do
    test "values are trimmed, choices ordered as the form offers them", %{form: form} do
      assert {:ok, data} = Validation.validate(form, valid())

      assert data == %{
               "name" => "Ada",
               "email" => "ada@example.com",
               "service" => "web",
               "topics" => ["a", "b"],
               "privacy" => true,
               "source" => "landing"
             }

      refute Map.has_key?(data, "about")
    end

    test "required, format and choices are checked, in the form's language", %{form: form} do
      params = valid(%{"name" => "", "email" => "nope", "service" => "other", "topics" => ["x"], "privacy" => nil})
      assert {:error, errors} = Validation.validate(form, params)
      assert Map.keys(errors) |> Enum.sort() == ~w(email name privacy service topics)

      assert {:error, %{"name" => [message]}} = Validation.validate(%{form | language: :no}, valid(%{"name" => ""}))
      assert message == Brando.Forms.Messages.built_in(:required, :no)
      refute message == Brando.Forms.Messages.built_in(:required, :en)
    end

    test "a post that is not a map counts as empty", %{form: form} do
      assert {:error, errors} = Validation.validate(form, "nope")
      assert Map.has_key?(errors, "name")
    end
  end

  describe "submit/3" do
    test "stores the values, the labels at the time and a hashed address", %{form: form} do
      assert {:ok, %Submission{} = submission, _form} =
               Forms.submit("contact", %{"fields" => valid(), "_language" => "en"}, meta())

      assert submission.scope == "public"
      assert submission.form_id == form.id
      assert submission.data["name"] == "Ada"
      assert submission.labels["email"] == "Email"
      assert submission.url == "https://example.com/contact"
      refute submission.ip_hash =~ "203.0.113.7"
      assert [%{id: id}] = Forms.list_submissions("contact")
      assert id == submission.id
    end

    test "a filled-in honeypot looks like a success and stores nothing" do
      assert {:ok, :ignored, _form} =
               Forms.submit("contact", %{"fields" => valid(), "_language" => "en", "_hp" => "spam"}, meta())

      assert Forms.count_submissions("contact") == 0
    end

    test "invalid values are returned by field" do
      assert {:error, {:invalid, %{"email" => [_]}}, _form} =
               Forms.submit("contact", %{"fields" => valid(%{"email" => "x"}), "_language" => "en"}, meta())
    end

    test "an unknown or unpublished form is not found", %{form_id: id, user: user} do
      assert {:error, :not_found} = Forms.submit("other", %{"fields" => valid()}, meta())

      {:ok, _} = Forms.update_form(id, %{"status" => "draft"}, user)
      assert {:error, :not_found} = Forms.submit("contact", %{"fields" => valid(), "_language" => "en"}, meta())
    end

    test "a visitor is limited per window" do
      Application.put_env(:brando, Brando.Forms, rate_limit: [per_visitor: 2])
      params = %{"fields" => valid(), "_language" => "en"}

      assert {:ok, _, _} = Forms.submit("contact", params, meta())
      assert {:ok, _, _} = Forms.submit("contact", params, meta())
      assert {:error, :rate_limited, _} = Forms.submit("contact", params, meta())
      # Another visitor is not
      assert {:ok, _, _} = Forms.submit("contact", params, %{meta() | ip: "198.51.100.1"})
    end

    test "with Turnstile configured, the token must be confirmed" do
      Application.put_env(:brando, Brando.Forms,
        turnstile: [site_key: "site", secret_key: "secret", req_options: [plug: {Req.Test, Brando.Forms.Turnstile}]]
      )

      Req.Test.stub(Brando.Forms.Turnstile, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        params = URI.decode_query(body)
        assert params["secret"] == "secret"
        Req.Test.json(conn, %{"success" => params["response"] == "good"})
      end)

      params = %{"fields" => valid(), "_language" => "en"}
      assert {:error, :rejected, _} = Forms.submit("contact", params, meta())
      assert {:error, :rejected, _} = Forms.submit("contact", Map.put(params, "cf-turnstile-response", "bad"), meta())
      assert {:ok, _, _} = Forms.submit("contact", Map.put(params, "cf-turnstile-response", "good"), meta())
    end
  end

  test "submissions can be deleted, by form key" do
    {:ok, submission, _} = Forms.submit("contact", %{"fields" => valid(), "_language" => "en"}, meta())

    assert {:error, :not_found} = Forms.delete_submission("other", submission.id)
    assert {:ok, _} = Forms.delete_submission("contact", submission.id)
    assert Forms.count_submissions("contact") == 0
  end
end
