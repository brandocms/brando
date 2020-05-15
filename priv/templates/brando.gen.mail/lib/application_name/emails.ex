defmodule <%= application_module %>.Emails do
  import Swoosh.Email

  @recipient {"Recipient name", "mail@domain.tld"}
  @sender {"<%= application_module %> — form", "no-reply@mailer.domain.tld"}

  @spec contact(Ecto.Changeset.t()) :: Swoosh.Email.t()
  def contact(changeset) do
    name = Ecto.Changeset.get_field(changeset, :name)

    content = """
    <html>
    <head>
    </head>
    <body>
    You have received a new form submission<br>
    <br>
    <code><pre>
    =============
    HEADING
    =============

    Name..................: #{name}

    </pre></code>
    </body>
    </html>
    """

    new()
    |> to(@recipient)
    |> from(@sender)
    |> subject("Subject")
    |> html_body(content)
  end
end
