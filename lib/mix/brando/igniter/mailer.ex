if Code.ensure_loaded?(Igniter) do
  defmodule Mix.Brando.Igniter.Mailer do
    @doc "Requests recompilation when optional Igniter support is removed."
    def __mix_recompile__?, do: not Code.ensure_loaded?(Igniter)

    @moduledoc false
    # The application's Swoosh mailer, which Brando sends its own email
    # through. Shared by `mix brando.gen.mail` and `mix brando.migrate55`.

    alias Igniter.Project.Application, as: ProjectApplication
    alias Igniter.Project.Config
    alias Igniter.Project.Module, as: ProjectModule
    alias Mix.Brando.Igniter.Files
    alias Mix.Brando.Igniter.SourceUpgrade
    alias Mix.Brando.Igniter.Template

    @sender_files ~w(config.exs brando.exs prod.exs runtime.exs)
    @sender_comment """
    # Sender for Brando's own email (password resets, form notifications). Set an
    # address the mail provider sends for; the production adapter goes in
    # runtime.exs.
    """

    @doc """
    Gives the application `<App>.Mailer` unless it has one, or has one other
    module that does `use Swoosh.Mailer`, with the local adapter in
    development and the test adapter in test, points Brando at it, and sets
    a placeholder sender for Brando's email when none is set.

    `project` needs `:otp_app` and `:app_module`. Returns the igniter and
    the mailer.
    """
    def ensure(igniter, %{otp_app: otp_app, app_module: app_module}) do
      {igniter, mailer} = find_or_create(igniter, otp_app, app_module)

      igniter =
        igniter
        |> Config.configure_new("dev.exs", otp_app, [mailer, :adapter], Swoosh.Adapters.Local)
        |> Config.configure_new("test.exs", otp_app, [mailer, :adapter], Swoosh.Adapters.Test)
        |> SourceUpgrade.configure_brando_mailer(mailer)
        |> put_placeholder_sender(app_module)

      {igniter, mailer}
    end

    defp find_or_create(igniter, otp_app, app_module) do
      mailer = Module.concat(app_module, "Mailer")

      case ProjectModule.find_module(igniter, mailer) do
        {:ok, {igniter, _source, _zipper}} ->
          {igniter, mailer}

        {:error, igniter} ->
          case swoosh_mailers(igniter) do
            {igniter, [existing]} -> {igniter, existing}
            {igniter, _none_or_several} -> {create(igniter, otp_app, app_module, mailer), mailer}
          end
      end
    end

    @doc """
    Points Brando at the application's mailer for `mix brando.migrate54`
    and `mix brando.migrate55`. A configured `config :brando, mailer:` is
    left alone. The application's one module that does `use Swoosh.Mailer`,
    whatever its name, or else `<App>.Mailer`, is used as it is; with
    several, they are listed in a warning and nothing changes. Without one,
    `ensure/2` creates `<App>.Mailer` and a warning says what is left to
    set. Unless several mailers leave the choice open, a placeholder sender
    is written when none is set.
    """
    def configure_for_upgrade(igniter) do
      app_module = ProjectModule.module_name_prefix(igniter)
      mailer = Module.concat(app_module, "Mailer")

      if brando_mailer_configured?(igniter) do
        put_placeholder_sender(igniter, app_module)
      else
        {igniter, mailers} = swoosh_mailers(igniter)
        use_mailer(igniter, mailers, app_module, mailer)
      end
    end

    # A sender goes in with the mailer: `mix brando.doctor` asks for one, and
    # each later edit of Brando's config recompiles Brando.
    defp use_mailer(igniter, [existing], app_module, _mailer) do
      igniter
      |> SourceUpgrade.configure_brando_mailer(existing)
      |> put_placeholder_sender(app_module)
    end

    defp use_mailer(igniter, [_ | _] = mailers, _app_module, _mailer),
      do: Igniter.add_warning(igniter, several_warning(mailers))

    defp use_mailer(igniter, [], app_module, mailer) do
      if match?({true, _igniter}, ProjectModule.module_exists(igniter, mailer)),
        do: igniter |> SourceUpgrade.configure_brando_mailer(mailer) |> put_placeholder_sender(app_module),
        else: create_for_upgrade(igniter, app_module)
    end

    defp create_for_upgrade(igniter, app_module) do
      project = %{otp_app: ProjectApplication.app_name(igniter), app_module: app_module}
      {igniter, mailer} = ensure(igniter, project)
      Igniter.add_warning(igniter, created_warning(mailer, igniter))
    end

    defp swoosh_mailers(igniter) do
      {igniter, modules} =
        ProjectModule.find_all_matching_modules(igniter, fn _module, zipper ->
          match?({:ok, _zipper}, Igniter.Code.Module.move_to_use(zipper, Swoosh.Mailer))
        end)

      {igniter, Enum.sort(modules)}
    end

    defp several_warning(mailers) do
      """
      The application has several Swoosh mailers: #{Enum.map_join(mailers, ", ", &inspect/1)}.
      Point Brando at the one its email (password resets, form notifications)
      should go through, the one configured for production:
      `config :brando, mailer: MyApp.Mailer`.
      """
    end

    @doc "The notice lines that tell what is left to set for `mailer`."
    def remaining_setup(mailer, igniter) do
      """
      Set the address Brando sends from in `config/#{sender_file(igniter)}`, replacing the
      placeholder: `config :brando, Brando.Mailer, from: {"My site", "noreply@my-site.com"}`.
      Your mail provider must send for it. Then configure #{inspect(mailer)}'s production
      adapter and credentials in `config/runtime.exs`, for example:

          config :#{otp_app_name(igniter)}, #{inspect(mailer)},
            adapter: Swoosh.Adapters.Mailgun,
            api_key: System.fetch_env!("MAILGUN_API_KEY"),
            domain: "mg.my-site.com"
      """
    end

    defp created_warning(mailer, igniter) do
      """
      The application had no Swoosh mailer, so Brando could not send email
      (password resets, form notifications). The task created #{inspect(mailer)},
      with the local adapter in development and the test adapter in test, and
      pointed Brando at it.

      #{remaining_setup(mailer, igniter)}
      """
    end

    defp otp_app_name(igniter), do: ProjectApplication.app_name(igniter)

    defp brando_mailer_configured?(igniter) do
      Enum.any?(~w(config.exs brando.exs), &Config.configures_key?(igniter, &1, :brando, :mailer))
    end

    defp create(igniter, otp_app, app_module, mailer) do
      binding = [application_name: to_string(otp_app), application_module: inspect(app_module)]

      case Template.render(igniter, "brando.gen.mail", "lib/application_name/mailer.ex", binding) do
        {:ok, igniter, contents} -> Files.create(igniter, "lib/#{Macro.underscore(mailer)}.ex", contents)
        {:error, message} -> Igniter.add_issue(igniter, message)
      end
    end

    # Appended to `config/brando.exs`, Brando's own file, with a comment;
    # `config/config.exs` ends by importing the environment's config, so the
    # setting goes in through Igniter there.
    defp put_placeholder_sender(igniter, app_module) do
      name = app_module |> Module.split() |> List.last()
      sender = ~s(config :brando, Brando.Mailer, from: {"#{name}", "noreply@example.com"}\n)

      cond do
        Enum.any?(@sender_files, &Config.configures_key?(igniter, &1, :brando, [Brando.Mailer, :from])) ->
          igniter

        sender_written?(igniter) ->
          igniter

        sender_file(igniter) == "brando.exs" ->
          Igniter.update_file(igniter, "config/brando.exs", fn source ->
            Rewrite.Source.update(source, :content, &(String.trim_trailing(&1) <> "\n\n" <> @sender_comment <> sender))
          end)

        true ->
          sender = quote(do: {unquote(name), "noreply@example.com"})
          Config.configure_new(igniter, "config.exs", :brando, [Brando.Mailer, :from], {:code, sender})
      end
    end

    # Read in the order production loads them; development and test config
    # is not what production sends from.
    @production_config ~w(config.exs brando.exs prod.exs runtime.exs)

    @doc """
    Whether the address Brando sends from in production is still to be set:
    the last sender the production config files set (config.exs, brando.exs,
    prod.exs, then runtime.exs) is missing or on a domain reserved for
    examples, like the placeholder the tasks write.
    """
    def sender_to_set?(igniter) do
      igniter = Igniter.include_glob(igniter, "config/*.exs")

      @production_config
      |> Enum.map(&"config/#{&1}")
      |> Enum.filter(&Rewrite.has_source?(igniter.rewrite, &1))
      |> Enum.flat_map(fn path ->
        content = igniter.rewrite |> Rewrite.source!(path) |> Rewrite.Source.get(:content)
        Regex.scan(~r/\bBrando\.Mailer\s*,[^)]*?\bfrom:([^\n]*)/s, content, capture: :all_but_first)
      end)
      |> List.last()
      |> case do
        nil -> true
        [from] -> from =~ ~r/@(?:[^@"\s]+\.)?(?:example\.(?:com|org|net)|example)"/i
      end
    end

    defp config_contents(igniter) do
      igniter = Igniter.include_glob(igniter, "config/*.exs")

      igniter.rewrite
      |> Rewrite.sources()
      |> Enum.filter(&(Path.dirname(&1.path) == "config" and Path.extname(&1.path) == ".exs"))
      |> Enum.map(&Rewrite.Source.get(&1, :content))
    end

    # `configures_key?/4` reads top-level `config` calls only; a sender set
    # inside `if config_env() == :prod do` in runtime.exs is one too.
    defp sender_written?(igniter),
      do: igniter |> config_contents() |> Enum.any?(&(&1 =~ ~r/\bBrando\.Mailer\s*,[^)]*?\bfrom:/s))

    defp sender_file(igniter), do: if(Igniter.exists?(igniter, "config/brando.exs"), do: "brando.exs", else: "config.exs")
  end
else
  defmodule Mix.Brando.Igniter.Mailer do
    @moduledoc false
    # Revisit this source when the optional dependency becomes available.
    def __mix_recompile__?, do: Code.ensure_loaded?(Igniter)
  end
end
