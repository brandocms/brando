defmodule <%= application_module %>.Emails do
  alias Swoosh.Email

  @doc "Builds a contact notification with explicit :from and :to addresses."
  @spec contact(Ecto.Changeset.t(), keyword()) :: Swoosh.Email.t()
  def contact(changeset, options) do
    form = Ecto.Changeset.apply_action!(changeset, :insert)

    Email.new()
    |> Email.to(Keyword.fetch!(options, :to))
    |> Email.from(Keyword.fetch!(options, :from))
    |> Email.reply_to(form.email)
    |> Email.subject("Contact form submission")
    |> Email.text_body("""
    Name: #{form.name}
    Email: #{form.email}
    Phone: #{form.phone}

    #{form.message}
    """)
  end
end
