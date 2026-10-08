# Email

<!-- llms-description: How Brando sends password and form email through the application's own Swoosh mailer. -->

Brando sends its email — password reset links and "your password was changed"
notices to admin users (see [User accounts and sessions](users.md#reset-a-forgotten-password)),
and the notifications and confirmations of a form submission (see the
[Forms guide](forms.md)) —
through your application's own Swoosh mailer. It needs to know which mailer that is, and which address to send from.

## Set up

`mix brando.gen.mail` creates `MyApp.Mailer` when you don't have one, adds
Swoosh, and points Brando at the mailer. On an existing application,
`mix brando.migrate55` does the last part when it finds `MyApp.Mailer`. Either
way, the configuration is:

```elixir
config :brando, mailer: MyApp.Mailer

config :brando, Brando.Mailer,
  from: {"My site", "noreply@example.com"},
  reply_to: "post@example.com"
```

Swoosh itself needs an API client to start; `mix brando.install` and
`mix brando.migrate55` set Req, which Brando already depends on:

```elixir
config :swoosh, api_client: Swoosh.ApiClient.Req
```

`:from` must be an address your mail provider sends for. Given as a plain
address, it is sent in the name of the site's identity. `:reply_to` is
optional. Configure the mailer's production adapter and credentials in
`runtime.exs`, as for any Swoosh mailer.

On a multi-site installation, a site can send as itself. Its entry under
`:sites`, by site key, comes before the general settings:

```elixir
config :brando, Brando.Mailer,
  from: {"Univers", "noreply@univers.no"},
  sites: %{
    "acme" => [from: {"Acme", "noreply@acme.no"}, reply_to: "post@acme.no"]
  }
```

## Without a mailer

When no mailer or sender is configured, sending raises
`Brando.Exception.ConfigError` in development and test, so it is noticed
early. In production it logs a warning and returns an error, and whatever was
sending carries on without the email. `Brando.Mailer.ensure_configured/0`
makes the same check before work that is pointless without email: the
"Forgot password?" page uses it, and tells the user the site cannot send
email rather than promising a link that never comes.

Email sent outside any site — a password reset asked for on the login page
of a multi-site installation — is queued without a site, and sent from the
general `:from` address.

## Sending your own email

`Brando.Mailer.new/1` starts an email from the current site's sender, and
`Brando.Mailer.Layout.put_body/2` gives it Brando's layout: the site's name
above the message, and a line below saying who sent it, as HTML and as plain
text, in the language you pass.

```elixir
assigns = %{url: url}

Brando.Mailer.new(to: user.email, subject: "Your export is ready")
|> Brando.Mailer.Layout.put_body(
  language: user.language,
  html: ~H"<p>Download it <a href={@url}>here</a>.</p>",
  text: "Download it here: #{url}"
)
|> Brando.Mailer.deliver_later()
```

`deliver_later/1` sends from a background job, which keeps the site it was
sent from and tries again if the provider fails, so a slow or failing provider
never holds up the request. A job cannot carry attachments or provider
options; send such an email with `Brando.Mailer.deliver/1`, which sends it
straight away and returns the mailer's result.

## Testing

Use Swoosh's test adapter and its assertions:

```elixir
# config/test.exs
config :my_app, MyApp.Mailer, adapter: Swoosh.Adapters.Test
```

```elixir
import Swoosh.TestAssertions

assert_email_sent(subject: "Your export is ready")
```

With Oban's `testing: :inline`, email sent with `deliver_later/1` is delivered
before the call returns.
