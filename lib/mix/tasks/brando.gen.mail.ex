if Code.ensure_loaded?(Igniter) do
  defmodule Mix.Tasks.Brando.Gen.Mail do
    @doc "Requests recompilation when optional Igniter support is removed."
    def __mix_recompile__?, do: not Code.ensure_loaded?(Igniter)

    use Igniter.Mix.Task

    @shortdoc "Plans the application's mailer, reusing an existing Phoenix mailer"
    @moduledoc """
    #{@shortdoc}.

        mix brando.gen.mail
        mix brando.gen.mail --contact

    Creates `MyApp.Mailer` unless the application has one, configures the
    local adapter in development and the test adapter in test, and points
    Brando at it (`config :brando, mailer: MyApp.Mailer`) for the email Brando
    sends itself. When no sender is configured it writes a placeholder,
    `config :brando, Brando.Mailer, from: {"MyApp", "noreply@example.com"}`,
    to replace with an address the mail provider sends for. Production
    delivery remains an explicit runtime configuration.

    Swoosh and Req come with Brando, so no dependency is added for them.

      * `--contact` also scaffolds a contact form,
        `MyApp.Contact.ContactForm`, and `MyApp.Emails.contact/2` to send it.

    Consumer templates under `priv/templates/brando.gen.mail` override the
    defaults. Namespace selection uses the shared --module/--web-module/--repo
    options.
    """

    @impl Igniter.Mix.Task
    def info(_argv, _source) do
      %Igniter.Mix.Task.Info{
        group: :brando,
        schema: Mix.Brando.Igniter.Project.options() ++ [contact: :boolean],
        defaults: [contact: false]
      }
    end

    @impl Mix.Task
    def run(argv), do: Mix.Brando.Igniter.Assets.without_hex_listing(fn -> super(argv) end)

    @impl Igniter.Mix.Task
    def igniter(igniter), do: Mix.Brando.Igniter.Auxiliary.plan(igniter, :mail)
  end
else
  defmodule Mix.Tasks.Brando.Gen.Mail do
    use Mix.Task

    @doc "Requests recompilation when optional Igniter support becomes available."
    def __mix_recompile__?, do: Code.ensure_loaded?(Igniter)
    @shortdoc "Plans the application's mailer, reusing an existing Phoenix mailer (requires igniter)"
    @impl Mix.Task
    def run(_argv), do: Mix.Brando.missing_igniter!("brando.gen.mail")
  end
end
