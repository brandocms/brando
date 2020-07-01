defmodule Mix.Tasks.Brando.Gen.Mail do
  use Mix.Task

  @shortdoc "Generates a mailer template"

  @moduledoc """
  Generates a mailer

      mix brando.gen.mailer

  """
  @spec run(any) :: no_return
  def run(_) do
    Mix.shell().info("""
    % Brando mailer module generator
    ---------------------------------------

    """)

    app = Mix.Project.config()[:app]

    binding = [
      application_module: Phoenix.Naming.camelize(Atom.to_string(app)),
      application_name: Atom.to_string(app)
    ]

    files = [
      {:eex, "lib/application_name/mailer.ex", "lib/application_name/mailer.ex"},
      {:eex, "lib/application_name/emails.ex", "lib/application_name/emails.ex"},
      {:eex, "lib/application_name/contact/contact_form.ex",
       "lib/application_name/contact/contact_form.ex"}
    ]

    Mix.Brando.copy_from(apps(), "priv/templates/brando.gen.mail", "", binding, files)

    Mix.shell().info([:green, "\n==> Add to mix.exs deps\n"])

    Mix.shell().info("""
        {:swoosh, "~> 0.25"},
    """)

    Mix.shell().info([:green, "\n==> Add to config/dev.exs\n"])

    Mix.shell().info("""
        config :#{binding[:application_name]}, #{binding[:application_module]}.Mailer, adapter: Swoosh.Adapters.Local
    """)

    Mix.shell().info([:green, "\n==> Add to config/prod.exs\n"])

    Mix.shell().info("""
        config :#{binding[:application_name]}, #{binding[:application_module]}.Mailer,
          adapter: Swoosh.Adapters.Mailgun,
          api_key: "YOUR API KEY HERE",
          base_url: "https://api.eu.mailgun.net/v3",
          domain: "mailer.domain.tld"
    """)
  end

  defp apps do
    [".", :brando]
  end
end
