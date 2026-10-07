defmodule Brando.Worker.Mail do
  @moduledoc """
  Sends an email queued with `Brando.Mailer.deliver_later/1`, in the site it
  was queued from, and tries again when the mail provider fails.
  """
  use Oban.Worker, queue: :default, max_attempts: 5

  alias Brando.Tenant.Job, as: TenantJob
  alias Swoosh.Email

  @impl Oban.Worker
  def perform(%Oban.Job{args: args} = job) do
    TenantJob.run_current(job, fn ->
      case args |> email() |> Brando.Mailer.deliver() do
        {:ok, _} -> :ok
        {:error, reason} when reason in [:no_mailer, :no_sender] -> {:cancel, reason}
        {:error, reason} -> {:error, reason}
      end
    end)
  end

  @doc """
  The job arguments for `email`: its addresses, subject, bodies and headers.
  Raises for what a job cannot carry — attachments and provider options.
  """
  @spec args(Email.t()) :: map()
  def args(%Email{attachments: [_ | _]}),
    do: raise(ArgumentError, "an email with attachments cannot be queued; send it with Brando.Mailer.deliver/1")

  def args(%Email{provider_options: options}) when map_size(options) > 0,
    do: raise(ArgumentError, "an email with provider options cannot be queued; send it with Brando.Mailer.deliver/1")

  def args(%Email{} = email) do
    %{
      "from" => address(email.from),
      "to" => Enum.map(email.to, &address/1),
      "cc" => Enum.map(email.cc, &address/1),
      "bcc" => Enum.map(email.bcc, &address/1),
      "reply_to" => if(is_list(email.reply_to), do: Enum.map(email.reply_to, &address/1), else: address(email.reply_to)),
      "subject" => email.subject,
      "html_body" => email.html_body,
      "text_body" => email.text_body,
      "headers" => email.headers
    }
  end

  @doc "The email queued as `args`."
  @spec email(map()) :: Email.t()
  def email(args) do
    %Email{
      from: recipient(args["from"]),
      to: Enum.map(args["to"] || [], &recipient/1),
      cc: Enum.map(args["cc"] || [], &recipient/1),
      bcc: Enum.map(args["bcc"] || [], &recipient/1),
      reply_to: reply_to(args["reply_to"]),
      subject: args["subject"] || "",
      html_body: args["html_body"],
      text_body: args["text_body"],
      headers: args["headers"] || %{}
    }
  end

  defp address(nil), do: nil
  defp address({name, address}), do: [name, address]

  defp recipient(nil), do: nil
  defp recipient([name, address]), do: {name, address}

  # One mailbox, `[name, address]`, or a list of them
  defp reply_to([[_, _] | _] = mailboxes), do: Enum.map(mailboxes, &recipient/1)
  defp reply_to(mailbox), do: recipient(mailbox)
end
