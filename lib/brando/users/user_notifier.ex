defmodule Brando.Users.UserNotifier do
  @moduledoc """
  Email to admin users about their account, in the user's own language, sent
  with `Brando.Mailer` in its shared layout.
  """
  use Phoenix.Component
  use Gettext, backend: Brando.Gettext

  alias Brando.Mailer
  alias Brando.Mailer.Layout
  alias Brando.Users.UserToken

  @doc """
  Queues the email with the link `url`, where `user` chooses a new password.
  `reason` is `:requested` when the user asked for the link, and `:admin` when
  an administrator sent it.
  """
  @spec deliver_reset_password_instructions(map(), String.t(), :requested | :admin) ::
          {:ok, Oban.Job.t()} | {:error, term()}
  def deliver_reset_password_instructions(user, url, reason \\ :requested) do
    user |> reset_password_instructions(url, reason) |> Mailer.deliver_later()
  end

  @doc """
  Queues the email telling `user` their password was changed: `by` `:user`
  when they changed it, `:admin` when an administrator set it.
  """
  @spec deliver_password_changed(map(), :user | :admin) :: {:ok, Oban.Job.t()} | {:error, term()}
  def deliver_password_changed(user, by \\ :user) do
    user |> password_changed(Brando.Users.reset_password_url(), by) |> Mailer.deliver_later()
  end

  @doc "The email with the link `url` to choose a new password. See `deliver_reset_password_instructions/3`."
  @spec reset_password_instructions(map(), String.t(), :requested | :admin) :: Swoosh.Email.t()
  def reset_password_instructions(user, url, reason \\ :requested) do
    language = language(user)

    Gettext.with_locale(Brando.Gettext, language, fn ->
      context = if reason == :admin, do: "admin_reset_password", else: "reset_password"
      minutes = UserToken.reset_password_validity_in_minutes(context)

      intro =
        case reason do
          :admin ->
            gettext("An administrator sent you this link to choose a new password for %{email}.", email: user.email)

          :requested ->
            gettext("Somebody asked to reset the password for %{email}.", email: user.email)
        end

      assigns = %{
        intro: intro,
        url: url,
        action: gettext("Choose a new password"),
        expiry: expiry(minutes),
        ignore: gettext("If you did not ask for this, you can ignore this email. Your password stays the same.")
      }

      [to: user.email, subject: gettext("Reset your password")]
      |> Mailer.new()
      |> Layout.put_body(
        language: language,
        preheader: assigns.action,
        html: reset_html(assigns),
        text: Enum.join([assigns.intro, assigns.action <> ":\n" <> url, assigns.expiry, assigns.ignore], "\n\n")
      )
    end)
  end

  defp expiry(minutes) when rem(minutes, 60) == 0 and minutes > 60 do
    ngettext(
      "The link works once and expires in %{count} hour.",
      "The link works once and expires in %{count} hours.",
      div(minutes, 60)
    )
  end

  defp expiry(minutes) do
    ngettext(
      "The link works once and expires in %{count} minute.",
      "The link works once and expires in %{count} minutes.",
      minutes
    )
  end

  defp reset_html(assigns) do
    ~H"""
    <p style="margin:0 0 16px;">{@intro}</p>
    <p style="margin:0 0 16px;">
      <a
        href={@url}
        style="display:inline-block;padding:10px 18px;border-radius:5px;background:#254e3f;color:#ffffff;text-decoration:none;font-weight:500;"
      >
        {@action}
      </a>
    </p>
    <p style="margin:0 0 16px;font-size:14px;color:#5b5b5b;word-break:break-all;">{@url}</p>
    <p style="margin:0 0 16px;">{@expiry}</p>
    <p style="margin:0;">{@ignore}</p>
    """
  end

  @doc """
  The email telling `user` their password was changed, with `url`, where
  they can reset it if somebody else changed it. See
  `deliver_password_changed/2` for `by`.
  """
  @spec password_changed(map(), String.t(), :user | :admin) :: Swoosh.Email.t()
  def password_changed(user, url, by \\ :user) do
    language = language(user)

    Gettext.with_locale(Brando.Gettext, language, fn ->
      {changed, warning} =
        case by do
          :admin ->
            {gettext(
               "An administrator set a new password for %{email}, and the account was logged out everywhere. You will be asked to choose your own password the next time you log in.",
               email: user.email
             ), gettext("If you did not expect this, reset your password now and tell an administrator.")}

          :user ->
            {gettext("The password for %{email} was changed, and the account was logged out on other devices.",
               email: user.email
             ), gettext("If you did not change it, reset your password now and tell an administrator.")}
        end

      assigns = %{
        changed: changed,
        warning: warning,
        action: gettext("Reset your password"),
        url: url
      }

      [to: user.email, subject: gettext("Your password was changed")]
      |> Mailer.new()
      |> Layout.put_body(
        language: language,
        html: changed_html(assigns),
        text: Enum.join([assigns.changed, assigns.warning, assigns.action <> ":\n" <> url], "\n\n")
      )
    end)
  end

  defp changed_html(assigns) do
    ~H"""
    <p style="margin:0 0 16px;">{@changed}</p>
    <p style="margin:0 0 16px;">{@warning}</p>
    <p style="margin:0;"><a href={@url} style="color:#254e3f;">{@action}</a></p>
    """
  end

  defp language(user), do: to_string(user.language || Brando.config(:default_admin_language) || "en")
end
