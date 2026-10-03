defmodule Brando.Forms.Notification do
  @moduledoc """
  The email a form submission sends: a notification to the form's recipients,
  and, when the form asks for it, a confirmation to the visitor.

  ## Notification

  A form with recipients queues one when a submission is stored
  (`Brando.Worker.FormNotification`). The job sends it with
  `Brando.Mailer.deliver/1` and records the outcome on the submission —
  `sent_at`, or `send_error` with why not — so the submissions admin can show
  it and send it again. A provider that fails is tried again, up to five
  times.

  Recipients with `bcc` get a blind copy. When every recipient is a blind
  copy, the email is addressed to the site's own sender. The subject is the
  form's, in the language the submission was sent in, with field values put
  in by key (`{{ name }}`); without one it is "New submission" and the form's
  title. Replies go to the first email address the visitor filled in.

  ## Confirmation

  With `confirmation` on, the visitor gets an email at the address they filled
  in, with the form's confirmation message — or its success message — and a
  copy of what they sent, without hidden fields. Replies go to the form's
  first recipient. It is sent with `Brando.Mailer.deliver_later/1`, and is
  left out when no mailer is configured.
  """
  use Phoenix.Component
  use Gettext, backend: Brando.Gettext

  require Logger

  alias Brando.Forms
  alias Brando.Forms.Display
  alias Brando.Forms.Form
  alias Brando.Forms.Recipient
  alias Brando.Forms.Submission
  alias Brando.Mailer
  alias Brando.Mailer.Layout
  alias Brando.Repo
  alias Swoosh.Email

  @email ~r/^[^\s@]+@[^\s@]+\.[^\s@]+$/
  @placeholder ~r/\{\{\s*([A-Za-z][A-Za-z0-9_]*)\s*\}\}/

  @doc "Whether submissions of `form` are emailed to anyone."
  @spec notifies?(Form.t()) :: boolean()
  def notifies?(%Form{recipients: [_ | _]}), do: true
  def notifies?(_form), do: false

  @doc """
  Queues the notification of `submission`, whose `queued_at` is set. Returns
  the submission.
  """
  @spec enqueue(Submission.t()) :: Submission.t()
  def enqueue(%Submission{queued_at: %DateTime{}} = submission) do
    {:ok, _job} =
      %{"submission_id" => submission.id}
      |> Brando.Tenant.Job.attach()
      |> Brando.Worker.FormNotification.new()
      |> Oban.insert()

    submission
  end

  def enqueue(submission), do: submission

  @doc """
  Sends the notification of the submission `id` in the current scope, and
  records the outcome. Returns what the job returns: `:ok`, `{:error, reason}`
  to try again, or `{:cancel, reason}` when trying again cannot help.
  """
  @spec deliver(integer()) :: :ok | {:error, term()} | {:cancel, term()}
  def deliver(id) do
    case Repo.get_by(Submission, id: id, scope: Submission.current_scope()) do
      nil -> {:cancel, :not_found}
      submission -> deliver_submission(submission)
    end
  end

  defp deliver_submission(submission) do
    with {:ok, form} <- fetch_form(submission),
         :ok <- check(notifies?(form), :no_recipients),
         :ok <- check(Mailer.configured?(), :no_mailer),
         :ok <- check(not is_nil(Mailer.sender()[:from]), :no_sender),
         {:ok, _} <- Mailer.deliver(email(submission, form)) do
      record(submission, sent_at: DateTime.utc_now(), send_error: nil)
      :ok
    else
      {:error, reason} when reason in [:no_recipients, :no_mailer, :no_sender, :form_deleted] ->
        record(submission, send_error: to_string(reason))
        {:cancel, reason}

      {:error, reason} ->
        record(submission, send_error: describe(reason))
        {:error, reason}
    end
  end

  defp check(true, _reason), do: :ok
  defp check(false, reason), do: {:error, reason}

  # The form in the language it was sent in, or, should that one be gone,
  # another language of it.
  defp fetch_form(submission) do
    case Repo.get(Form, submission.form_id) || List.first(Forms.list_forms_by_key(submission.form_key)) do
      nil -> {:error, :form_deleted}
      form -> {:ok, Repo.preload(form, :fields)}
    end
  end

  defp record(submission, changes) do
    submission |> Ecto.Changeset.change(changes) |> Repo.update!()
  end

  defp describe(reason) when is_binary(reason), do: String.slice(reason, 0, 500)
  defp describe(reason) when is_atom(reason), do: to_string(reason)
  defp describe({status, body}) when is_integer(status), do: describe("#{status} #{inspect(body)}")
  defp describe(reason), do: describe(inspect(reason))

  @doc """
  The words for what `send_error` records, in the current locale: Brando's own
  reasons explained, a provider's error as it came.
  """
  @spec describe_error(String.t() | nil) :: String.t() | nil
  def describe_error(nil), do: nil
  def describe_error("no_mailer"), do: gettext("No mailer is configured, so the site cannot send email.")
  def describe_error("no_sender"), do: gettext("No address to send from is configured.")
  def describe_error("no_recipients"), do: gettext("The form has no recipients.")
  def describe_error("form_deleted"), do: gettext("The form has been deleted.")
  def describe_error(error), do: error

  @doc "The notification of `submission`, sent with `form`, its fields loaded."
  @spec email(Submission.t(), Form.t()) :: Email.t()
  def email(submission, form) do
    language = submission.language || to_string(form.language)

    Gettext.with_locale(Brando.Gettext, language, fn ->
      {blind, open} = Enum.split_with(form.recipients, & &1.bcc)

      subject =
        case present(form.subject) do
          nil -> gettext("New submission: %{form}", form: form.title)
          subject -> interpolate(subject, submission, form)
        end

      assigns = %{
        rows: submitted(submission, form, :all),
        intro: gettext("Sent with the form %{form}.", form: form.title),
        url: submission.url,
        admin_url: admin_url(form.key)
      }

      Mailer.new(subject: header(subject))
      |> Email.to(Enum.map(open, &mailbox/1))
      |> then(&if(open == [], do: Email.to(&1, Mailer.sender()[:from] || ""), else: &1))
      |> Email.bcc(Enum.map(blind, &mailbox/1))
      |> put_reply_to(visitor_email(submission, form), submission)
      |> Layout.put_body(language: language, html: notification_html(assigns), text: notification_text(assigns))
    end)
  end

  defp notification_html(assigns) do
    ~H"""
    <p style="margin:0 0 16px;">{@intro}</p>
    <.rows rows={@rows} />
    <p :if={@url} style="margin:16px 0 0;font-size:14px;color:#5b5b5b;">
      {gettext("From the page")} <a href={@url} style="color:#1f1f1f;">{@url}</a>
    </p>
    <p style="margin:16px 0 0;font-size:14px;">
      <a href={@admin_url} style="color:#1f1f1f;">{gettext("Read it in the admin")}</a>
    </p>
    """
  end

  defp notification_text(assigns) do
    [
      assigns.intro,
      text_rows(assigns.rows),
      assigns.url && gettext("From the page") <> " " <> assigns.url,
      gettext("Read it in the admin") <> ": " <> assigns.admin_url
    ]
    |> Enum.reject(&is_nil/1)
    |> Enum.join("\n\n")
  end

  @doc """
  Queues the confirmation of `submission` to the visitor, when `form` asks for
  one, the visitor filled in an email address and a mailer is configured.
  """
  @spec confirm(Submission.t(), Form.t()) :: :ok
  def confirm(%Submission{} = submission, %Form{confirmation: true} = form) do
    with address when is_binary(address) <- visitor_email(submission, form),
         true <- Mailer.configured?() and not is_nil(Mailer.sender()[:from]) do
      {:ok, _job} = submission |> confirmation(form, address) |> Mailer.deliver_later()
    else
      _ -> Logger.info("[Brando.Forms] No confirmation sent for the form #{inspect(form.key)}")
    end

    :ok
  end

  def confirm(_submission, _form), do: :ok

  @doc "The confirmation of `submission` to the visitor at `address`."
  @spec confirmation(Submission.t(), Form.t(), String.t()) :: Email.t()
  def confirmation(submission, form, address) do
    language = submission.language || to_string(form.language)

    Gettext.with_locale(Brando.Gettext, language, fn ->
      subject =
        case present(form.confirmation_subject) do
          nil -> form.title
          subject -> interpolate(subject, submission, form)
        end

      assigns = %{
        message: present(form.confirmation_message) || Forms.success_message(form),
        heading: gettext("What you sent"),
        rows: submitted(submission, form, :visible)
      }

      email =
        Mailer.new(subject: header(subject))
        |> Email.to(address)

      email =
        case Enum.find(form.recipients, &(not &1.bcc)) do
          %Recipient{} = recipient -> Email.reply_to(email, mailbox(recipient))
          nil -> email
        end

      Layout.put_body(email, language: language, html: confirmation_html(assigns), text: confirmation_text(assigns))
    end)
  end

  defp confirmation_html(assigns) do
    ~H"""
    <p :for={paragraph <- paragraphs(@message)} style="margin:0 0 16px;">{paragraph}</p>
    <p style="margin:24px 0 8px;font-size:14px;font-weight:600;color:#5b5b5b;">{@heading}</p>
    <.rows rows={@rows} />
    """
  end

  defp confirmation_text(assigns),
    do: Enum.join([assigns.message, assigns.heading <> ":", text_rows(assigns.rows)], "\n\n")

  attr :rows, :list, required: true

  defp rows(assigns) do
    ~H"""
    <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="border-collapse:collapse;">
      <tr :for={{label, value} <- @rows}>
        <td style="padding:8px 0;border-top:1px solid #e6e6e3;vertical-align:top;">
          <div style="font-size:13px;color:#5b5b5b;">{label}</div>
          <div style="white-space:pre-wrap;">{value || "—"}</div>
        </td>
      </tr>
    </table>
    """
  end

  defp text_rows(rows), do: Enum.map_join(rows, "\n\n", fn {label, value} -> "#{label}:\n#{value || "—"}" end)

  # What the visitor sent, labelled as when it was sent. The visitor's own copy
  # leaves out the hidden fields, which they never saw.
  defp submitted(submission, form, which) do
    forms = %{to_string(form.language) => form}
    hidden = for %{type: :hidden, key: key} <- form.fields, do: key

    forms
    |> Display.labels(%{submission | language: to_string(form.language)})
    |> Enum.reject(fn {key, _label} -> which == :visible and key in hidden end)
    |> Enum.map(fn {key, label} ->
      {label, Display.value(forms, %{submission | language: to_string(form.language)}, key)}
    end)
  end

  @doc """
  `template` with `{{ key }}` replaced by what the visitor filled in for the
  field `key`; an unknown key is left empty.
  """
  @spec interpolate(String.t(), Submission.t(), Form.t()) :: String.t()
  def interpolate(template, submission, form) do
    forms = %{to_string(form.language) => form}
    submission = %{submission | language: to_string(form.language)}

    Regex.replace(@placeholder, template, fn _, key -> Display.value(forms, submission, key) || "" end)
  end

  @doc "The first valid email address the visitor filled in, or nil."
  @spec visitor_email(Submission.t(), Form.t()) :: String.t() | nil
  def visitor_email(submission, form) do
    form.fields
    |> Enum.filter(&(&1.type == :email))
    |> Enum.map(&Map.get(submission.data, &1.key))
    |> Enum.find(&(is_binary(&1) and Regex.match?(@email, &1)))
  end

  defp put_reply_to(email, nil, _submission), do: email

  defp put_reply_to(email, address, submission) do
    name =
      case Map.get(submission.data, "name") do
        name when is_binary(name) -> header(name)
        _ -> ""
      end

    Email.reply_to(email, {name, address})
  end

  defp mailbox(%Recipient{name: name, email: email}), do: {header(name || ""), email}

  # A header value on one line, so nothing a visitor typed can add headers.
  defp header(value), do: value |> String.replace(~r/[\r\n]+/, " ") |> String.trim() |> String.slice(0, 250)

  defp paragraphs(text), do: text |> String.split(~r/\n\s*\n/) |> Enum.map(&String.trim/1) |> Enum.reject(&(&1 == ""))

  defp present(value) when is_binary(value), do: if(String.trim(value) == "", do: nil, else: value)
  defp present(_value), do: nil

  defp admin_url(key), do: String.trim_trailing(Brando.endpoint().url(), "/") <> "/admin/forms/#{key}/submissions"
end
