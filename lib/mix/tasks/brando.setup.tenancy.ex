if Code.ensure_loaded?(Igniter) do
  defmodule Mix.Tasks.Brando.Setup.Tenancy do
    use Igniter.Mix.Task

    alias Igniter.Code.Common
    alias Igniter.Code.Function, as: CodeFunction
    alias Igniter.Code.Keyword, as: CodeKeyword

    @shortdoc "Prepares an existing Brando application for tenancy"
    @moduledoc """
    #{@shortdoc}.

    This opt-in source migration configures tenancy, adds
    `Brando.Plug.Tenant` to existing browser pipelines, and installs Brando's
    tenant migration support. It does not infer application-owned tenant
    tables, run migrations, provision sites, or copy production data.

        mix brando.setup.tenancy --mode single --site-key my-site
        mix brando.setup.tenancy --mode multi

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
        schema: [mode: :string, site_key: :string],
        required: [:mode]
      }
    end

    @impl Igniter.Mix.Task
    def igniter(igniter) do
      case tenancy_options(igniter.args.options) do
        {:ok, mode, site_key} ->
          igniter
          |> configure_tenancy(mode, site_key)
          |> configure_routers()
          |> install_tenant_migration()
          |> add_instructions(mode, site_key)

        {:error, message} ->
          Igniter.add_issue(igniter, message)
      end
    end

    defp tenancy_options(options) do
      mode = options[:mode]
      site_key = options[:site_key]

      case {mode, site_key} do
        {"single", site_key} when is_binary(site_key) ->
          if Brando.Tenant.valid_key?(site_key) do
            {:ok, :single, site_key}
          else
            {:error, "--site-key must be a lowercase, URL-safe key such as my-site"}
          end

        {"single", nil} ->
          {:error, "--site-key is required with --mode single"}

        {"multi", nil} ->
          {:ok, :multi, nil}

        {"multi", _site_key} ->
          {:error, "--site-key can only be used with --mode single"}

        {mode, _site_key} ->
          {:error, "invalid --mode #{inspect(mode)}; expected single or multi"}
      end
    end

    defp configure_tenancy(igniter, mode, site_key) do
      igniter =
        Igniter.Project.Config.configure(
          igniter,
          "brando.exs",
          :brando,
          [:tenancy_mode],
          mode
        )

      case site_key do
        nil ->
          remove_site_key(igniter)

        site_key ->
          Igniter.Project.Config.configure(
            igniter,
            "brando.exs",
            :brando,
            [:site_key],
            site_key
          )
      end
    end

    defp remove_site_key(igniter) do
      Igniter.update_elixir_file(igniter, "config/brando.exs", fn zipper ->
        Common.update_all_matches(
          zipper,
          &brando_config_with_site_key?/1,
          &remove_site_key_from_config/1
        )
      end)
    end

    defp remove_site_key_from_config(config_zipper) do
      with {:ok, options_zipper} <- CodeFunction.move_to_nth_argument(config_zipper, 1),
           {:ok, options_zipper} <- CodeKeyword.remove_keyword_key(options_zipper, :site_key) do
        {:ok, options_zipper}
      else
        _ -> {:ok, config_zipper}
      end
    end

    defp brando_config_with_site_key?(zipper) do
      CodeFunction.function_call?(zipper, :config, 2) &&
        CodeFunction.argument_equals?(zipper, 0, :brando) &&
        case CodeFunction.move_to_nth_argument(zipper, 1) do
          {:ok, options_zipper} -> CodeKeyword.keyword_has_path?(options_zipper, [:site_key])
          :error -> false
        end
    end

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
      site_option = if mode == :single, do: " --site-key=#{site_key}", else: " --site-key=my-site"

      Igniter.add_notice(igniter, """
      Brando tenancy source setup prepared for `#{mode}` mode.

      Igniter configured `config/brando.exs`, updated recognized browser
      pipelines, and installed Brando's tenant migration support. It did not
      infer application-owned tenant tables or change any database.

      Continue in this order:

        1. Review the complete Igniter diff, then run `mix format` and
           `mix compile --warnings-as-errors`.
        2. Run `mix brando.upgrade`, review its public registry migrations,
           and apply the public migrations.
        3. Create and review tenant migrations for every application content
           table with `mix brando.gen.tenant_migration migration_name`.
        4. Run tenant migrations against a disposable environment and verify
           that every tenant-scoped query has a table.
        5. Back up the database and media, then provision a new site or run
           `mix brando.migrate_to_tenant#{site_option}` in a maintenance window.
        6. Verify routing, authorization, media, assets, environment copy, and
           rollback before directing production traffic to tenant schemas.

      See `guides/tenancy_and_environments.md` for the complete workflow.
      """)
    end
  end
end
