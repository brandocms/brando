defmodule Brando.Users.UserNotifier do
  @moduledoc """
  Email to admin users about their account, sent with `Brando.Mailer`.
  """

  alias Brando.Mailer
  alias Brando.Mailer.Layout

  @doc """
  Deliver instructions to confirm account.
  """
  def deliver_confirmation_instructions(user, url) do
    deliver(user, "Confirm your account", """
    Hi #{user.email},

    You can confirm your account by visiting the URL below:

    #{url}

    If you didn't create an account with us, please ignore this.
    """)
  end

  @doc """
  Deliver instructions to reset a user password.
  """
  def deliver_reset_password_instructions(user, url) do
    deliver(user, "Reset your password", """
    Hi #{user.email},

    You can reset your password by visiting the URL below:

    #{url}

    If you didn't request this change, please ignore this.
    """)
  end

  @doc """
  Deliver instructions to update a user email.
  """
  def deliver_update_email_instructions(user, url) do
    deliver(user, "Change your email address", """
    Hi #{user.email},

    You can change your email by visiting the URL below:

    #{url}

    If you didn't request this change, please ignore this.
    """)
  end

  # The text, with its paragraphs, is also the HTML body.
  defp deliver(user, subject, body) do
    html =
      body
      |> String.split(~r/\n{2,}/, trim: true)
      |> Enum.map(&["<p>", Phoenix.HTML.html_escape(String.trim(&1)) |> Phoenix.HTML.safe_to_string(), "</p>"])

    [to: user.email, subject: subject]
    |> Mailer.new()
    |> Layout.put_body(language: user.language, html: {:safe, html}, text: body)
    |> Mailer.deliver_later()
  end
end
