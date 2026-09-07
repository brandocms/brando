if Code.ensure_loaded?(Igniter) do
  defmodule Mix.Tasks.Brando.Gen.Mail do
    @doc false
    def __mix_recompile__?, do: not Code.ensure_loaded?(Igniter)

    use Igniter.Mix.Task

    @shortdoc "Plans mail helpers, reusing an existing Phoenix mailer"
    @moduledoc """
    #{@shortdoc}.

        mix brando.gen.mail

    Adds Swoosh when absent and local/test adapter defaults. Production delivery
    remains an explicit runtime configuration. Consumer templates override defaults.
    Namespace selection uses the shared --module/--web-module/--repo options.
    """

    @impl Igniter.Mix.Task
    def info(_argv, _source) do
      %Igniter.Mix.Task.Info{group: :brando, schema: Mix.Brando.Igniter.Project.options()}
    end

    @impl Igniter.Mix.Task
    def igniter(igniter), do: Mix.Brando.Igniter.Auxiliary.plan(igniter, :mail)
  end
else
  defmodule Mix.Tasks.Brando.Gen.Mail do
    use Mix.Task

    @doc false
    def __mix_recompile__?, do: Code.ensure_loaded?(Igniter)
    @shortdoc "Plans mail helpers, reusing an existing Phoenix mailer (requires igniter)"
    @impl Mix.Task
    def run(_argv), do: Mix.Brando.missing_igniter!("brando.gen.mail")
  end
end
