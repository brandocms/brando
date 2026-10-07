defmodule Brando.MailerTest do
  use Brando.ConnCase, async: false

  import ExUnit.CaptureLog
  import Phoenix.Component, only: [sigil_H: 2]
  import Swoosh.TestAssertions

  alias Brando.Exception.ConfigError
  alias Brando.Factory
  alias Brando.Mailer
  alias Brando.Mailer.Layout
  alias Brando.Users.UserNotifier
  alias Brando.Worker
  alias Swoosh.Email

  setup do
    previous = Map.new([:mailer, Brando.Mailer, :env, :tenancy_mode], &{&1, Application.get_env(:brando, &1)})

    on_exit(fn ->
      Enum.each(previous, fn
        {key, nil} -> Application.delete_env(:brando, key)
        {key, value} -> Application.put_env(:brando, key, value)
      end)
    end)
  end

  defp email, do: Mailer.new(to: "ada@example.com", subject: "Hello", text_body: "Hi")

  describe "the sender" do
    test "is the configured one, with its reply-to address" do
      Application.put_env(:brando, Brando.Mailer, from: {"Brando", "noreply@example.com"}, reply_to: "post@example.com")

      assert %Email{from: {"Brando", "noreply@example.com"}, reply_to: {"", "post@example.com"}} = email()
    end

    test "is the site's own on a multi-site installation" do
      Application.put_env(:brando, Brando.Mailer,
        from: {"Univers", "noreply@univers.no"},
        sites: %{"acme" => [from: {"Acme", "noreply@acme.no"}, reply_to: "post@acme.no"]}
      )

      Application.put_env(:brando, :tenancy_mode, :multi)

      assert Brando.Tenant.with_prefix("tenant_acme_live", &Mailer.sender/0) ==
               [from: {"Acme", "noreply@acme.no"}, reply_to: "post@acme.no"]

      assert Brando.Tenant.with_prefix("tenant_other_live", &Mailer.sender/0) ==
               [from: {"Univers", "noreply@univers.no"}, reply_to: nil]
    end

    test "a plain address is sent in the name of the site's identity" do
      Application.put_env(:brando, Brando.Mailer, from: "noreply@example.com")

      assert {name, "noreply@example.com"} = Mailer.sender()[:from]
      assert name == Brando.Cache.Identity.get("en").name
    end

    test "fields given to new/1 come before it" do
      assert %Email{from: {"Someone", "someone@example.com"}} = Mailer.new(from: {"Someone", "someone@example.com"})
    end
  end

  describe "delivery" do
    test "sends through the application's mailer" do
      assert {:ok, _} = Mailer.deliver(email())
      assert_email_sent(to: [{"", "ada@example.com"}], subject: "Hello", from: {"Brando", "noreply@example.com"})
    end

    test "an email without a sender gets the site's" do
      assert {:ok, _} = Mailer.deliver(Email.new(to: "ada@example.com", subject: "Hello", text_body: "Hi"))
      assert_email_sent(from: {"Brando", "noreply@example.com"})
    end

    test "later, from a job that keeps the email whole" do
      email =
        email()
        |> Email.cc({"Grace", "grace@example.com"})
        |> Email.reply_to([{"A", "a@example.com"}, {"B", "b@example.com"}])
        |> Email.html_body("<p>Hi</p>")
        |> Email.header("X-Form", "contact")

      assert email |> Worker.Mail.args() |> Jason.encode!() |> Jason.decode!() |> Worker.Mail.email() == email

      assert {:ok, %Oban.Job{}} = Mailer.deliver_later(email)
      assert_email_sent(email)
    end

    test "an attachment cannot be queued" do
      email = Email.attachment(email(), %Swoosh.Attachment{filename: "a.txt", data: "a", content_type: "text/plain"})
      assert_raise ArgumentError, fn -> Mailer.deliver_later(email) end
    end

    test "without a mailer, development and test are told" do
      Application.delete_env(:brando, :mailer)

      assert_raise ConfigError, ~r/config :brando, mailer: MyApp.Mailer/, fn -> Mailer.deliver(email()) end
      assert_raise ConfigError, fn -> Mailer.deliver_later(email()) end
    end

    test "without a mailer, production warns and lets the caller carry on" do
      Application.delete_env(:brando, :mailer)
      Application.put_env(:brando, :env, :prod)
      previous = Logger.level()
      Logger.configure(level: :warning)
      on_exit(fn -> Logger.configure(level: previous) end)

      log = capture_log([level: :warning], fn -> assert {:error, :no_mailer} = Mailer.deliver_later(email()) end)
      assert log =~ "No mailer is configured"
      assert_no_email_sent()
    end

    test "without a sender, production warns, and a queued email is not retried" do
      Application.put_env(:brando, Brando.Mailer, [])
      Application.put_env(:brando, :env, :prod)

      capture_log(fn ->
        assert {:error, :no_sender} = Mailer.deliver(Email.new(to: "ada@example.com"))

        assert {:cancel, :no_sender} =
                 Worker.Mail.perform(%Oban.Job{args: Worker.Mail.args(Email.new(to: "ada@example.com"))})
      end)
    end
  end

  describe "the layout" do
    test "puts the message between the site's name and who sent it" do
      url = "https://example.com/reset?token=a&b"
      assigns = %{url: url}

      email =
        Layout.put_body(email(),
          language: "en",
          preheader: "Choose a new password",
          html: ~H"<p>Follow <a href={@url}>this link</a>.</p>",
          text: "Follow this link: #{url}"
        )

      site = Brando.Cache.Identity.get("en").name
      assert email.html_body =~ ~s(<html lang="en">)
      assert email.html_body =~ ~s(<a href="https://example.com/reset?token=a&amp;b">this link</a>)
      assert email.html_body =~ "Choose a new password"
      assert email.html_body =~ site
      assert email.text_body =~ ~r/^#{Regex.escape(site)}\n\nFollow this link: #{Regex.escape(url)}\n\n-- \n/
    end

    test "escapes plain HTML text, and words its own text in the email's language" do
      english = Layout.put_body(email(), language: "en", html: "<b>Ada</b>", text: "Ada")
      norwegian = Layout.put_body(email(), language: "no", html: "<b>Ada</b>", text: "Ada")

      assert english.html_body =~ "&lt;b&gt;Ada&lt;/b&gt;"
      refute footer(english.text_body) == footer(norwegian.text_body)
    end
  end

  defp footer(text), do: text |> String.split("-- \n") |> List.last()

  test "account email is sent in the layout" do
    user = Factory.insert(:random_user)

    assert {:ok, _} = UserNotifier.deliver_reset_password_instructions(user, "https://example.com/reset/abc")

    assert_email_sent(fn email ->
      assert email.to == [{"", user.email}]
      assert email.text_body =~ "https://example.com/reset/abc"
      assert email.html_body =~ ~s(href="https://example.com/reset/abc")
    end)
  end
end
