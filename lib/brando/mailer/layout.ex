defmodule Brando.Mailer.Layout do
  @moduledoc """
  The layout Brando's email share: the site's name above the message, and a
  line below saying who sent it, as HTML and as plain text.

      Brando.Mailer.new(to: user.email, subject: "Reset your password")
      |> Brando.Mailer.Layout.put_body(
        language: user.language,
        html: ~H"<p>Follow <a href={@url}>this link</a> to choose a new password.</p>",
        text: "Follow this link to choose a new password: \#{url}"
      )

  `:html` is HEEx or other safe HTML; a plain string is escaped. `:text` is
  the plain-text version. `:language` words the layout's own text, and picks
  the site's name from its identity in that language.
  """
  use Phoenix.Component
  use Gettext, backend: Brando.Gettext

  alias Swoosh.Email

  @doc """
  Sets `email`'s HTML and text bodies to `:html` and `:text` in the layout.
  Options: `:html`, `:text` (required), `:language` and `:preheader`, the
  line mail clients show after the subject.
  """
  @spec put_body(Email.t(), keyword()) :: Email.t()
  def put_body(%Email{} = email, opts) do
    language = to_string(opts[:language] || Brando.config(:default_language) || "en")
    site = site_name(language, email)

    Gettext.with_locale(Brando.Gettext, language, fn ->
      footer = if site != "", do: gettext("This email was sent by %{site}.", site: site)

      html =
        %{
          language: language,
          site: site,
          subject: email.subject,
          preheader: opts[:preheader],
          content: safe(opts[:html]),
          footer: footer
        }
        |> html()
        |> Phoenix.HTML.Safe.to_iodata()
        |> IO.iodata_to_binary()

      email
      |> Email.html_body(html)
      |> Email.text_body(text(Keyword.fetch!(opts, :text), site, footer))
    end)
  end

  defp html(assigns) do
    ~H"""
    <!DOCTYPE html>
    <html lang={@language}>
      <head>
        <meta charset="utf-8" />
        <meta name="viewport" content="width=device-width, initial-scale=1" />
        <title>{@subject}</title>
      </head>
      <body style="margin:0;padding:0;background:#f4f4f2;">
        <div
          :if={@preheader}
          style="display:none;max-height:0;overflow:hidden;opacity:0;color:transparent;"
        >
          {@preheader}
        </div>
        <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background:#f4f4f2;">
          <tr>
            <td align="center" style="padding:32px 16px;">
              <table
                role="presentation"
                width="100%"
                cellpadding="0"
                cellspacing="0"
                style="max-width:560px;background:#ffffff;border-radius:6px;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Helvetica,Arial,sans-serif;font-size:16px;line-height:1.5;color:#1f1f1f;"
              >
                <tr :if={@site != ""}>
                  <td style="padding:24px 32px 0;font-size:14px;font-weight:600;color:#5b5b5b;">{@site}</td>
                </tr>
                <tr>
                  <td style="padding:16px 32px 32px;">{@content}</td>
                </tr>
              </table>
              <p
                :if={@footer}
                style="margin:16px 0 0;font-family:Helvetica,Arial,sans-serif;font-size:12px;color:#7a7a7a;"
              >
                {@footer}
              </p>
            </td>
          </tr>
        </table>
      </body>
    </html>
    """
  end

  # Signed off below "-- ", the line mail clients recognise as a signature.
  defp text(body, "", nil), do: String.trim_trailing(body) <> "\n"
  defp text(body, site, footer), do: site <> "\n\n" <> String.trim_trailing(body) <> "\n\n-- \n" <> footer <> "\n"

  defp safe(nil), do: ""
  defp safe(content) when is_binary(content), do: Phoenix.HTML.html_escape(content)
  defp safe(content), do: content

  # The site's name in `language`, else the name the email is sent in.
  defp site_name(language, email) do
    case Brando.Cache.Identity.get(language) do
      %{name: name} when is_binary(name) and name != "" -> name
      _ -> sender_name(email.from)
    end
  end

  defp sender_name({name, _address}) when is_binary(name), do: name
  defp sender_name(_), do: ""
end
