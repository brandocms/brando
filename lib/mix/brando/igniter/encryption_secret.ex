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
    # What each environment reads, with the files these import by a literal
    # path. phx.new's import_config "#{config_env()}.exs" is not followed: a
    # secret config/test.exs sets reaches neither. config/dev.secret.exs
    # counts once config/dev.exs imports it: written by hand before that,
    # nothing reads it.
    @prod_configs ~w(config/config.exs config/prod.exs config/runtime.exs)
    @dev_configs ~w(config/config.exs config/dev.exs)

    @doc "The development file that holds the secret."
    def dev_secret, do: @dev_secret

    @doc "What `.gitignore` gets, as `Deployment.gitignore/2` takes it."
    def gitignore, do: {"Brando.Crypto's secret for development", ["/" <> @dev_secret]}

    @doc """
    Reads how the project configures `Brando.Crypto`, in any form: `:prod?`
    when `config/config.exs`, `config/prod.exs` or `config/runtime.exs` do,
    `:dev?` when `config/config.exs` or `config/dev.exs` do (each with the
    files it imports by a literal path, `config/dev.secret.exs` among them
    once it is imported), and `:reads_variable?` when prod's names
    `BRANDO_ENCRYPTION_SECRET`.
    """
    def existing(igniter) do
      {igniter, prod} = contents(igniter, @prod_configs, MapSet.new())
      {igniter, dev} = contents(igniter, @dev_configs, MapSet.new())

      {igniter,
       %{
         prod?: Enum.any?(prod, &configures_crypto?/1),
         dev?: Enum.any?(dev, &configures_crypto?/1),
         reads_variable?: Enum.any?(prod, &String.contains?(&1, @variable))
       }}
    end

    @doc """
    Sets up the secret in `mix brando.install`, for what the project's
    configuration (`existing/1`) leaves to Brando. A new install whose
    environment files will all hold `BRANDO_ENCRYPTION_SECRET`
    (`every_envrc?`) reads it in prod with `System.fetch_env!/1`, and
    `config/dev.secret.exs` holds the marker. Otherwise prod gets what an
    upgrade writes (`upgrade/1`), and no value is made: a rerun may be
    a clone of a site whose environment files Git left out, and production's
    value is its own. Returns whether new environment files get the variable,
    and the files with a marker to fill in.
    """
    def install(igniter, config, every_envrc?, fresh?) do
      variable? = fresh? and if(config.prod?, do: config.reads_variable?, else: every_envrc?)

      igniter =
        igniter
        |> unless_configured(config.prod?, if(variable?, do: &fetch_runtime/1, else: &soft_runtime/1))
        |> unless_configured(config.dev?, &import_dev_secret/1)

      if variable? and not config.dev?,
        do: {dev_secret_file(igniter), true, [@dev_secret]},
        else: {igniter, variable?, []}
    end

    @doc """
    Sets up an existing site (`mix brando.upgrade`), whose value is
    production's `secret_key_base`, which no task can know: unless its
    configuration sets the secret there, `config/runtime.exs` reads
    `BRANDO_ENCRYPTION_SECRET` in prod only when it is set, so a release
    deployed before the variable exists boots as before, and a notice lists
    what is left to do; unless development's does, `config/dev.exs` imports
    `config/dev.secret.exs` when it exists. With either, the `.gitignore` line
    and, in an existing `.dockerignore`, the exclusion.
    """
    def upgrade(igniter) do
      case existing(igniter) do
        {igniter, %{prod?: true, dev?: true}} ->
          igniter

        {igniter, config} ->
          igniter
          |> unless_configured(config.prod?, &soft_runtime/1)
          |> unless_configured(config.dev?, &import_dev_secret/1)
          |> Deployment.gitignore([gitignore()])
          |> Docker.exclude_dev_secret()
      end
    end

    defp unless_configured(igniter, true, _set_up), do: igniter
    defp unless_configured(igniter, false, set_up), do: set_up.(igniter)

    defp fetch_runtime(igniter) do
      Igniter.Project.Config.configure_runtime_env(
        igniter,
        :prod,
        :brando,
        [Brando.Crypto, :secret],
        {:code, Sourceror.parse_string!(~s|System.fetch_env!("#{@variable}")|)}
      )
    end

    # The contents of `paths` and of the files they import by a literal path.
    defp contents(igniter, [], _seen), do: {igniter, []}

    defp contents(igniter, [path | paths], seen) do
      if path in seen or not Igniter.exists?(igniter, path) do
        contents(igniter, paths, MapSet.put(seen, path))
      else
        igniter = Igniter.include_existing_file(igniter, path)
        content = igniter.rewrite |> Rewrite.source!(path) |> Source.get(:content)
        {igniter, rest} = contents(igniter, paths ++ imports(path, content), MapSet.put(seen, path))
        {igniter, [content | rest]}
      end
    end

    defp imports(path, content) do
      case Code.string_to_quoted(content) do
        {:ok, quoted} ->
          {_, imports} =
            Macro.prewalk(quoted, [], fn
              {:import_config, _, [import]} = node, imports when is_binary(import) ->
                {node, [import |> Path.expand(Path.dirname(Path.expand(path))) |> Path.relative_to_cwd() | imports]}

              node, imports ->
                {node, imports}
            end)

          Enum.reverse(imports)

        {:error, _} ->
          []
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
        &Source.update(&1, :content, fn content ->
          # One that holds the secret already, not yet imported, keeps its value
          if configures_crypto?(content), do: content, else: String.trim_trailing(content) <> "\n\n" <> line
        end)
      )
    end

    defp import_dev_secret(igniter) do
      import = """
      # Brando.Crypto's secret, shared with the other environments and kept out of
      # Git. Without the file, Brando uses this environment's secret_key_base.
      if File.exists?(Path.join(__DIR__, "dev.secret.exs")), do: import_config("dev.secret.exs")
      """

      Igniter.create_or_update_file(igniter, @dev, "import Config\n\n" <> import, fn source ->
        Source.update(source, :content, &append_new(&1, import))
      end)
    end

    defp append_new(content, import) do
      if content =~ "dev.secret.exs", do: content, else: String.trim_trailing(content) <> "\n\n" <> import
    end

    # A block of its own at the end of the file: Igniter's code insertion
    # separates comments from the code they precede. A notice lists what is
    # left to do.
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

      igniter
      |> Igniter.create_or_update_file(@runtime, "import Config\n\n" <> block, fn source ->
        Source.update(source, :content, &(String.trim_trailing(&1) <> "\n\n" <> block))
      end)
      |> Igniter.add_notice(steps())
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
