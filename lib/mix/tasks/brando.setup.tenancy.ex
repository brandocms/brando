if Code.ensure_loaded?(Igniter) do
  defmodule Mix.Tasks.Brando.Setup.Tenancy do
    @doc false
    def __mix_recompile__?, do: not Code.ensure_loaded?(Igniter)

    use Igniter.Mix.Task

    alias Igniter.Code.Common
    alias Igniter.Code.Function, as: CodeFunction

    @shortdoc "Prepares an existing Brando application for tenancy"
    @moduledoc """
    #{@shortdoc}.

    This opt-in source migration configures tenancy, adds
    `Brando.Plug.Tenant` to existing browser pipelines, and installs Brando's
    tenant migration support. It does not infer application-owned tenant
    tables, run migrations, provision sites, or copy production data.

        mix brando.setup.tenancy
        mix brando.setup.tenancy --mode single --site-key my-site
        mix brando.setup.tenancy --mode multi

    Pass `--interactive` to ask for missing choices. Normal commands require
    explicit options without prompts. `--yes` only accepts the Igniter diff.

    This task changes source only. It never touches the database, because the
    configuration it writes has to be compiled and the public migrations applied
    before a site can be provisioned. Converting existing content is therefore a
    separate step, `mix brando.migrate_to_tenant`, run afterwards.

    Review the Igniter diff before applying it. Then follow the ordered tenant
    migration and provisioning workflow printed by the task.
    """

    @pipelines [:browser, :browser_api]
    @tenant_migration "20260816002300_add_shared_content_library.exs"
    @tenant_plug Brando.Plug.Tenant
    @content_plugs [Brando.Plug.Identity, Brando.Plug.Navigation, Brando.Plug.Fragment]

    @impl Igniter.Mix.Task
    def info(_argv, _source) do
      %Igniter.Mix.Task.Info{
        group: :brando,
        example: "mix brando.setup.tenancy --mode single --site-key my-site",
        schema: [mode: :string, site_key: :string, interactive: :boolean]
      }
    end

    @impl Igniter.Mix.Task
    def igniter(igniter) do
      case tenancy_options(igniter.args.options) do
        {:ok, mode, site_key} ->
          igniter
          |> Mix.Brando.Igniter.Install.Configuration.configure_tenancy(mode, site_key)
          |> configure_routers()
          |> install_tenant_migration()
          |> add_instructions(mode, site_key)

        {:error, message} ->
          Igniter.add_issue(igniter, message)
      end
    end

    defp tenancy_options(options) do
      with {:ok, mode} <- resolve_mode(options),
           {:ok, site_key} <- resolve_site_key(mode, options) do
        {:ok, mode, site_key}
      end
    end

    defp resolve_mode(options) do
      case options[:mode] do
        nil -> ask_mode(options)
        "single" -> {:ok, :single}
        "multi" -> {:ok, :multi}
        mode -> {:error, "invalid --mode #{inspect(mode)}; expected single or multi"}
      end
    end

    defp ask_mode(options) do
      if interactive?(options) do
        Mix.shell().info("""

        Tenancy mode:

          single  one site with named environments (Production, Staging, ...)
          multi   many isolated sites, each with its own environments
        """)

        case ask("Which tenancy mode? [single/multi] (single) \u276f ") do
          :eof -> {:error, "--mode is required; expected single or multi"}
          mode when mode in ["", "single"] -> {:ok, :single}
          "multi" -> {:ok, :multi}
          other -> retry_mode(options, other)
        end
      else
        {:error, "--mode is required; expected single or multi"}
      end
    end

    defp retry_mode(options, answer) do
      Mix.shell().info("Expected single or multi. Got: #{answer}")
      ask_mode(options)
    end

    defp resolve_site_key(:multi, options) do
      if options[:site_key] do
        {:error, "--site-key can only be used with --mode single"}
      else
        {:ok, nil}
      end
    end

    defp resolve_site_key(:single, options) do
      case options[:site_key] do
        nil -> ask_site_key(options)
        site_key -> validate_site_key(site_key)
      end
    end

    defp ask_site_key(options) do
      if interactive?(options) do
        case ask("Site key for the existing installation (lowercase, URL-safe) \u276f ") do
          :eof -> {:error, "--site-key is required with --mode single"}
          answer -> confirm_site_key(options, answer)
        end
      else
        {:error, "--site-key is required with --mode single"}
      end
    end

    defp confirm_site_key(options, answer) do
      case validate_site_key(answer) do
        {:ok, site_key} ->
          {:ok, site_key}

        {:error, message} ->
          Mix.shell().info(message)
          ask_site_key(options)
      end
    end

    # Closed input must terminate guidance instead of repeating a prompt.
    defp ask(prompt) do
      case Mix.shell().prompt(prompt) do
        :eof -> :eof
        answer -> String.trim(answer)
      end
    end

    defp validate_site_key(site_key) do
      if Brando.Tenant.valid_key?(site_key) do
        {:ok, site_key}
      else
        {:error, "Site key must be a lowercase, URL-safe key such as my-site"}
      end
    end

    defp interactive?(options), do: options[:interactive] == true

    defp configure_routers(igniter) do
      {igniter, routers} = Igniter.Libs.Phoenix.list_routers(igniter)

      case routers do
        [] ->
          Igniter.add_warning(igniter, """
          No Phoenix router could be found. Add `plug Brando.Plug.Tenant` to
          every frontend pipeline before plugs that load tenant content.
          """)

        routers ->
          Enum.reduce(routers, igniter, &configure_router(&2, &1))
      end
    end

    defp configure_router(igniter, router) do
      {igniter, _source, zipper} = Igniter.Project.Module.find_module!(igniter, router)

      configured_pipelines =
        case Common.move_to_do_block(zipper) do
          {:ok, block_zipper} -> Enum.filter(@pipelines, &pipeline_present?(block_zipper, &1))
          :error -> []
        end

      igniter =
        Enum.reduce(configured_pipelines, igniter, fn pipeline, igniter ->
          add_tenant_plug(igniter, router, pipeline)
        end)

      if :browser in configured_pipelines do
        igniter
      else
        Igniter.add_warning(igniter, """
        #{inspect(router)} has no `:browser` pipeline. Add
        `plug Brando.Plug.Tenant` to every frontend pipeline before plugs that
        load tenant content.
        """)
      end
    end

    defp pipeline_present?(zipper, pipeline), do: match?({:ok, _}, move_to_pipeline(zipper, pipeline))

    defp add_tenant_plug(igniter, router, pipeline) do
      Igniter.Project.Module.find_and_update_module!(igniter, router, fn zipper ->
        with {:ok, pipeline_zipper} <- move_to_pipeline(zipper, pipeline),
             {:ok, block_zipper} <- Common.move_to_do_block(pipeline_zipper) do
          insert_tenant_plug(block_zipper)
        else
          _ -> {:ok, zipper}
        end
      end)
    end

    defp move_to_pipeline(zipper, pipeline) do
      CodeFunction.move_to_function_call_in_current_scope(
        zipper,
        :pipeline,
        2,
        &CodeFunction.argument_equals?(&1, 0, pipeline)
      )
    end

    defp insert_tenant_plug(block_zipper) do
      case move_to_plug(block_zipper, [@tenant_plug]) do
        {:ok, tenant_plug_zipper} ->
          {:ok, tenant_plug_zipper}

        :error ->
          case move_to_plug(block_zipper, @content_plugs) do
            {:ok, content_plug_zipper} ->
              {:ok, Common.add_code(content_plug_zipper, "plug Brando.Plug.Tenant", placement: :before)}

            :error ->
              {:ok, Common.add_code(block_zipper, "plug Brando.Plug.Tenant")}
          end
      end
    end

    defp move_to_plug(zipper, plugs) do
      CodeFunction.move_to_function_call_in_current_scope(zipper, :plug, [1, 2], fn zipper ->
        Enum.any?(plugs, &CodeFunction.argument_equals?(zipper, 0, &1))
      end)
    end

    defp install_tenant_migration(igniter) do
      source =
        :brando
        |> Application.app_dir(["priv", "templates", "brando.install", "tenant_migrations"])
        |> Path.join(@tenant_migration)

      target = Path.join(["priv", "repo", "tenant_migrations", @tenant_migration])

      Igniter.copy_template(igniter, source, target, [], on_exists: :skip)
    end

    defp add_instructions(igniter, mode, site_key) do
      key = if mode == :single, do: site_key, else: "my-site"

      Igniter.add_notice(igniter, """
      Brando tenancy source setup prepared for `#{mode}` mode.

      Igniter configured `config/brando.exs`, updated recognized browser
      pipelines, and installed Brando's tenant migration support. No database
      was touched.

      Continue in this order:

        1. Review the Igniter diff, then run `mix format` and
           `mix compile --warnings-as-errors`. Recompiling matters: the tenancy
           mode is read from compiled config, so every later step needs it.

        2. Run `mix brando.upgrade`, review the generated public migrations,
           then apply them with `mix brando.migrate`. This is what gives
           `public` the content tables that each new environment is cloned
           from.

        3. Declare any cross-site tables of your own. Everything else in
           `public` is treated as tenant content, so an undeclared table is
           cloned into every environment and its rows copied with the content:

               config :brando, :shared_tables, ["my_table"]

           Brando cannot handle a table name containing a double quote. Check
           for them, and rename anything that turns up:

               SELECT tablename FROM pg_tables
               WHERE schemaname = 'public' AND tablename LIKE '%"%';

        4. Make sure `pg_dump` and `psql` are available here and in your
           release image. Provisioning shells out to them to clone structure,
           so an environment without them cannot create a site.

        5. Provision a disposable site from `/admin/sites`, or with
           `Brando.Tenant.Setup.create_site/3`, and verify that every
           tenant-scoped query resolves.

        6. Back up the database and media, then convert in a maintenance
           window:

               mix brando.migrate_to_tenant --site-key=#{key}

           Add `--move` to relocate the tables instead of copying them. That
           is constant-time whatever the database weighs, but it leaves no
           legacy rows in `public` to roll back to.

        7. Verify routing, authorization, media, assets, environment copy, and
           rollback before directing production traffic to tenant schemas.

      Content tables need no tenant migrations. `priv/repo/tenant_migrations`
      is only for changes that must reach environments that already exist.

      See `guides/tenancy_and_environments.md` for the complete workflow.
      """)
    end
  end
else
  defmodule Mix.Tasks.Brando.Setup.Tenancy do
    use Mix.Task

    @doc false
    def __mix_recompile__?, do: Code.ensure_loaded?(Igniter)

    @shortdoc "Prepares an existing Brando application for tenancy (requires igniter)"
    @moduledoc """
    #{@shortdoc}.

    This task is built on Igniter, an optional Brando dependency. Add it to your
    application's deps, run `mix deps.get`, then recompile Brando with
    `mix deps.compile brando --force` to enable the task.
    """

    @impl Mix.Task
    def run(_argv), do: Mix.Brando.missing_igniter!("brando.setup.tenancy")
  end
end
