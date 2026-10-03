defmodule Brando.Forms.NotificationTest do
  use Brando.ConnCase, async: false

  import Swoosh.TestAssertions

  alias Brando.Factory
  alias Brando.Forms
  alias Brando.Forms.Form
  alias Brando.Forms.Notification
  alias Brando.Forms.Submission
  alias Brando.Translations

  setup do
    Brando.Forms.RateLimit.reset()
    previous = Application.get_env(:brando, :mailer)
    on_exit(fn -> Application.put_env(:brando, :mailer, previous) end)

    %{user: Factory.insert(:random_user)}
  end

  defp create_form(user, attrs \\ %{}) do
    %{
      "title" => "Contact",
      "key" => "contact",
      "language" => "en",
      "status" => "published",
      "subject" => "Message from {{ name }} about {{ service }}",
      "recipients" => [
        %{"name" => "Post", "email" => "post@example.com"},
        %{"name" => "Archive", "email" => "archive@example.com", "bcc" => "true"}
      ],
      "fields" => [
        %{"key" => "name", "type" => "text", "label" => "Name", "required" => "true"},
        %{"key" => "email", "type" => "email", "label" => "Email", "required" => "true"},
        %{
          "key" => "service",
          "type" => "select",
          "label" => "Service",
          "option_rows_present" => "1",
          "option_rows" => %{"0" => %{"value" => "web", "label" => "Website"}}
        },
        %{"key" => "message", "type" => "textarea", "label" => "Message"},
        %{"key" => "source", "type" => "hidden", "default_value" => "landing"}
      ]
    }
    |> Map.merge(attrs)
    |> Forms.create_form(user)
  end

  defp submit(fields \\ %{}) do
    fields =
      Map.merge(
        %{
          "name" => "Ada\r\nBcc: evil@example.com",
          "email" => "ada@example.com",
          "service" => "web",
          "message" => "About the engine",
          "source" => "landing"
        },
        fields
      )

    {:ok, submission, _form} =
      Forms.submit("contact", %{"fields" => fields, "_language" => "en"}, %{
        ip: "203.0.113.7",
        url: "https://example.com/contact"
      })

    Brando.Repo.reload!(submission)
  end

  describe "the notification" do
    test "goes to the recipients, blind copies hidden, and replies go to the visitor", %{user: user} do
      {:ok, _} = create_form(user)
      submission = submit()

      assert_email_sent(fn email ->
        assert email.to == [{"Post", "post@example.com"}]
        assert email.bcc == [{"Archive", "archive@example.com"}]
        assert email.reply_to == {"Ada Bcc: evil@example.com", "ada@example.com"}
        # What a visitor types cannot start a header of its own
        assert email.subject == "Message from Ada Bcc: evil@example.com about Website"
        assert email.text_body =~ "Message:\nAbout the engine"
        # The team sees the hidden fields, labelled by key when they have no label
        assert email.text_body =~ "source:\nlanding"
        assert email.text_body =~ "/admin/forms/contact/submissions"
        assert email.html_body =~ "About the engine"
      end)

      assert Submission.email_status(submission) == :sent
      assert submission.queued_at
      assert submission.sent_at
    end

    test "has the form's title as subject when it has none", %{user: user} do
      {:ok, _} = create_form(user, %{"subject" => ""})
      submit()

      assert_email_sent(subject: "New submission: Contact")
    end

    test "is addressed to the site when every recipient is a blind copy", %{user: user} do
      {:ok, _} = create_form(user, %{"recipients" => [%{"email" => "archive@example.com", "bcc" => "true"}]})
      submit()

      assert_email_sent(fn email ->
        assert email.to == [{"Brando", "noreply@example.com"}]
        assert email.bcc == [{"", "archive@example.com"}]
      end)
    end

    test "is not sent for a form without recipients", %{user: user} do
      {:ok, _} = create_form(user, %{"recipients" => []})
      submission = submit()

      assert_no_email_sent()
      assert Submission.email_status(submission) == nil
    end

    test "records why the provider refused it, and is sent again", %{user: user} do
      {:ok, _} = create_form(user)
      Application.put_env(:brando, :mailer, BrandoIntegration.FailingMailer)

      submission = submit()
      assert Submission.email_status(submission) == :failed
      assert submission.send_error =~ "503"
      assert submission.sent_at == nil

      Application.put_env(:brando, :mailer, BrandoIntegration.Mailer)
      assert {:ok, resent} = Forms.resend_submission("contact", submission.id)
      assert Submission.email_status(resent) == :sent
      assert resent.send_error == nil
      assert_email_sent(to: [{"Post", "post@example.com"}])
    end

    test "records that no mailer is configured, and the submission is still stored", %{user: user} do
      {:ok, _} = create_form(user)
      Application.delete_env(:brando, :mailer)

      submission = submit()
      assert submission.send_error == "no_mailer"
      assert Notification.describe_error(submission.send_error) =~ "mailer"
      assert Forms.count_submissions("contact") == 1
    end

    test "cannot be sent again without recipients", %{user: user} do
      {:ok, _} = create_form(user, %{"recipients" => []})
      submission = submit()

      assert Forms.resend_submission("contact", submission.id) == {:error, :no_recipients}
      assert Forms.resend_submission("contact", -1) == {:error, :not_found}
    end
  end

  describe "the confirmation" do
    test "goes to the visitor, without hidden fields, with replies to the form's recipient", %{user: user} do
      {:ok, _} =
        create_form(user, %{
          "recipients" => [%{"name" => "Post", "email" => "post@example.com"}],
          "confirmation" => "true",
          "confirmation_subject" => "Thanks, {{ name }}",
          "confirmation_message" => "We read every message.\n\nTalk soon."
        })

      submit(%{"name" => "Ada"})

      # Queued with the submission, before the notification
      assert_email_sent(fn email ->
        assert email.to == [{"", "ada@example.com"}]
        assert email.subject == "Thanks, Ada"
        assert email.reply_to == {"Post", "post@example.com"}
        assert email.text_body =~ "We read every message."
        assert email.text_body =~ "About the engine"
        refute email.text_body =~ "landing"
        assert email.html_body =~ "<p style=\"margin:0 0 16px;\">Talk soon.</p>"
      end)

      assert_email_sent(to: [{"Post", "post@example.com"}])
    end

    test "is not sent when the form does not ask for one", %{user: user} do
      {:ok, _} = create_form(user, %{"recipients" => []})
      submit()

      assert_no_email_sent()
    end
  end

  describe "the form's settings" do
    test "a confirmation needs an email field", %{user: user} do
      assert {:error, changeset} =
               create_form(user, %{
                 "confirmation" => "true",
                 "fields" => [%{"key" => "name", "type" => "text", "label" => "Name"}]
               })

      assert {_, _} = changeset.errors[:confirmation]
    end

    test "the page after sending is a path or a web address", %{user: user} do
      assert {:error, changeset} = create_form(user, %{"redirect_url" => "javascript:alert(1)"})
      assert changeset.errors[:redirect_url]

      assert {:error, changeset} = create_form(user, %{"redirect_url" => "//evil.example.net"})
      assert changeset.errors[:redirect_url]

      assert {:ok, _} = create_form(user, %{"redirect_url" => "/thank-you"})
      assert {:ok, _} = create_form(user, %{"key" => "other", "redirect_url" => "https://example.com/thanks"})
    end

    test "submissions are kept for at least a day", %{user: user} do
      assert {:error, changeset} = create_form(user, %{"retention_days" => "0"})
      assert changeset.errors[:retention_days]
    end

    test "a recipient needs an email address", %{user: user} do
      assert {:error, changeset} = create_form(user, %{"recipients" => [%{"name" => "Post", "email" => "post"}]})
      assert [%{errors: [email: _]}] = changeset.changes.recipients
    end

    test "a translation emails the source's recipients, in its own words", %{user: user} do
      {:ok, source} = create_form(user, %{"retention_days" => "30"})
      {:ok, target} = Translations.create_target(Form, source.id, :no, user)

      {:ok, _} = Forms.update_form(target.id, %{"subject" => "Melding fra {{ name }}"}, user)
      Translations.target_saved(Form, target.id)

      {:ok, source} = Forms.get_form(%{matches: %{id: source.id}})

      {:ok, _} =
        Forms.update_form(
          source.id,
          %{
            "retention_days" => "60",
            "recipients" => [
              Map.take(Map.from_struct(hd(source.recipients)), [:uid, :name, :email, :bcc]),
              %{"name" => "Sales", "email" => "sales@example.com"}
            ]
          },
          user
        )

      {:ok, source} = Forms.get_form(%{matches: %{id: source.id}, preload: [:fields, :alternate_entries]})
      Translations.source_saved(source)

      payload = Translations.decode_payload(Translations.get_pending_version(Form, target.id))

      assert Enum.map(payload.recipients, & &1.email) == ["post@example.com", "sales@example.com"]
      assert payload.retention_days == 60
      assert payload.subject == "Melding fra {{ name }}"
    end
  end

  describe "retention" do
    test "deletes the submissions older than their form keeps them", %{user: user} do
      {:ok, _} = create_form(user, %{"recipients" => [], "retention_days" => "30"})
      {:ok, _} = create_form(user, %{"recipients" => [], "key" => "newsletter"})

      old = submit()
      recent = submit()
      kept = insert_submission("newsletter", ~U[2020-01-01 00:00:00.000000Z])

      old |> Ecto.Changeset.change(inserted_at: DateTime.add(DateTime.utc_now(), -31, :day)) |> Brando.Repo.update!()

      assert Forms.purge_submissions() == 1
      refute Brando.Repo.get(Submission, old.id)
      assert Brando.Repo.get(Submission, recent.id)
      assert Brando.Repo.get(Submission, kept.id)
    end

    test "runs in every active environment from the nightly job", %{user: user} do
      {:ok, _} = create_form(user, %{"recipients" => [], "retention_days" => "1"})
      old = submit()
      old |> Ecto.Changeset.change(inserted_at: ~U[2020-01-01 00:00:00.000000Z]) |> Brando.Repo.update!()

      assert :ok = Brando.Worker.FormSubmissionPurger.perform(%Oban.Job{args: %{}})
      refute Brando.Repo.get(Submission, old.id)
    end
  end

  defp insert_submission(key, inserted_at) do
    Brando.Repo.insert!(%Submission{
      scope: Submission.current_scope(),
      form_id: 0,
      form_key: key,
      language: "en",
      inserted_at: inserted_at
    })
  end
end
