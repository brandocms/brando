if Code.ensure_loaded?(Igniter) do
  defmodule Mix.Brando.Igniter.EncryptionSecret do
    @doc "Requests recompilation when optional Igniter support is removed."
    def __mix_recompile__?, do: not Code.ensure_loaded?(Igniter)

    @moduledoc false

    # Brando.Crypto's secret: one value per site, shared by its environments,
    # so a database copied between them stays readable. On a server it is
    # BRANDO_ENCRYPTION_SECRET in the environment file Florist uploads; in
    # development it is config/dev.secret.exs, which dev.exs imports when it
    # exists and which Git and the Docker build leave out. The files are
    # planned with a marker in place of the value, which brando.install.secrets
    # fills in, one value for all of them.

    alias Mix.Brando.Igniter.Install.Deployment
    alias Mix.Brando.Igniter.Install.Docker
    alias Rewrite.Source

    @variable "BRANDO_ENCRYPTION_SECRET"
    @marker "__BRANDO_ENCRYPTION_SECRET__"
    @dev_secret "config/dev.secret.exs"
    @dev "config/dev.exs"
    @runtime "config/runtime.exs"

    @doc "The development file that holds the secret."
    def dev_secret, do: @dev_secret

    @doc "What `.gitignore` gets, as `Deployment.gitignore/2` takes it."
    def gitignore, do: {"Brando.Crypto's secret for development", ["/" <> @dev_secret]}

    @doc """
    Reads the project's configuration (every `config/**/*.exs`):
    `:configured?` when any file configures `Brando.Crypto`, in any form, and
    `:reads_variable?` when any names `BRANDO_ENCRYPTION_SECRET`.
    """
    def existing(igniter) do
      igniter = Igniter.include_glob(igniter, "config/**/*.exs")

      contents =
        for source <- Rewrite.sources(igniter.rewrite),
            String.starts_with?(source.path, "config/"),
            Path.extname(source.path) == ".exs",
            do: Source.get(source, :content)

      {igniter,
       %{
         configured?: Enum.any?(contents, &configures_crypto?/1),
         reads_variable?: Enum.any?(contents, &String.contains?(&1, @variable))
       }}
    end

    @doc """
    Sets up the secret for an install whose environment files will all hold
    `BRANDO_ENCRYPTION_SECRET`: `config/runtime.exs` reads it in prod,
    `config/dev.secret.exs` holds the marker and `config/dev.exs` imports it.
    Returns the files with a marker to fill in.
    """
    def install(igniter) do
      igniter =
        igniter
        |> dev_secret_file()
        |> import_dev_secret()
        |> Igniter.Project.Config.configure_runtime_env(
          :prod,
          :brando,
          [Brando.Crypto, :secret],
          {:code, Sourceror.parse_string!(~s|System.fetch_env!("#{@variable}")|)}
        )

      {igniter, [@dev_secret]}
    end

    @doc """
    Sets up an existing site, whose value is production's `secret_key_base`,
    which no task can know: `config/runtime.exs` reads
    `BRANDO_ENCRYPTION_SECRET` in prod only when it is set, so a release
    deployed before the variable exists boots as before, and `config/dev.exs`
    imports `config/dev.secret.exs` when it exists. With `ignores: true`, also
    the `.gitignore` line and, in an existing `.dockerignore`, the exclusion;
    the installer adds those itself. A notice lists what is left to do.
    """
    def existing_site(igniter, opts \\ []) do
      igniter
      |> soft_runtime()
      |> import_dev_secret()
      |> ignores(opts[:ignores] == true)
      |> Igniter.add_notice(steps())
    end

    defp ignores(igniter, false), do: igniter
    defp ignores(igniter, true), do: igniter |> Deployment.gitignore([gitignore()]) |> Docker.exclude_dev_secret()

    @doc "`existing_site/2` for a project that does not configure `Brando.Crypto` yet (`mix brando.upgrade`)."
    def upgrade(igniter) do
      case existing(igniter) do
        {igniter, %{configured?: true}} -> igniter
        {igniter, _existing} -> existing_site(igniter, ignores: true)
      end
    end

    defp steps do
      """
      Brando.Crypto, which encrypts two-factor secrets, webhook secrets and other values in
      the database, now reads its secret from #{@variable} in config/runtime.exs, and
      config/dev.exs imports #{@dev_secret} when it exists. Until they are set, Brando keeps
      using each environment's secret_key_base. To give the site one secret, and keep what
      production encrypted readable:
        1. Set #{@variable} in .envrc.prod and .envrc.staging to production's current
           SECRET_KEY_BASE, upload them (florist prod env:upload, florist staging env:upload)
           and deploy.
        2. Give production a new SECRET_KEY_BASE and deploy again: everyone is signed out once.
        3. Write the same value to #{@dev_secret}, which Git leaves out:
             import Config
             config :brando, Brando.Crypto, secret: "<the value>"
      Production's data stays readable. A staging or development database whose users set
      two-factor authentication up there stops reading it: they set it up again, or the
      database is replaced by a copy of production's. mix brando.doctor warns until the
      steps are done. See "Encryption secret" in the deployment guide.
      """
    end

    defp dev_secret_file(igniter) do
      line = ~s|config :brando, Brando.Crypto, secret: "#{@marker}"\n|

      Igniter.create_or_update_file(
        igniter,
        @dev_secret,
        """
        # Brando.Crypto's secret for development: the same value as
        # #{@variable} in .envrc.prod and .envrc.staging, so a copy of
        # their database stays readable here. Keep this file out of Git and
        # the Docker build.
        import Config

        """ <> line,
        &Source.update(&1, :content, fn content -> String.trim_trailing(content) <> "\n\n" <> line end)
      )
    end

    defp import_dev_secret(igniter) do
      import = """
      # Brando.Crypto's secret, shared with the other environments and kept out of
      # Git. Without the file, Brando uses this environment's secret_key_base.
      if File.exists?(Path.join(__DIR__, "dev.secret.exs")), do: import_config("dev.secret.exs")
      """

      Igniter.create_or_update_file(igniter, @dev, "import Config\n\n" <> import, fn source ->
        Source.update(source, :content, fn content ->
          if content =~ "dev.secret.exs", do: content, else: String.trim_trailing(content) <> "\n\n" <> import
        end)
      end)
    end

    # A block of its own at the end of the file: Igniter's code insertion
    # separates comments from the code they precede.
    defp soft_runtime(igniter) do
      block = """
      # Brando.Crypto's secret, the same in every environment of the site. Until
      # it is set, Brando uses the endpoint's secret_key_base.
      if config_env() == :prod do
        encryption_secret = System.get_env("#{@variable}", "")

        if encryption_secret != "" do
          config :brando, Brando.Crypto, secret: encryption_secret
        end
      end
      """

      Igniter.create_or_update_file(igniter, @runtime, "import Config\n\n" <> block, fn source ->
        Source.update(source, :content, &(String.trim_trailing(&1) <> "\n\n" <> block))
      end)
    end

    # Any reference to the module counts: it has no other configuration.
    # A file that does not parse counts when it names the module.
    defp configures_crypto?(content) do
      case Code.string_to_quoted(content) do
        {:ok, quoted} ->
          {_, found?} =
            Macro.prewalk(quoted, false, fn
              {:__aliases__, _, [:Brando, :Crypto]} = node, _found? -> {node, true}
              {:config, _, [:brando, {:__aliases__, _, [:Crypto]} | _]} = node, _found? -> {node, true}
              :"Elixir.Brando.Crypto" = node, _found? -> {node, true}
              node, found? -> {node, found?}
            end)

          found?

        {:error, _} ->
          content =~ "Brando.Crypto"
      end
    end
  end
else
  defmodule Mix.Brando.Igniter.EncryptionSecret do
    @moduledoc false
    # Revisit this source when the optional dependency becomes available.
    def __mix_recompile__?, do: Code.ensure_loaded?(Igniter)
  end
end
