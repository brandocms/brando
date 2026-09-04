defmodule Brando.SupervisorTest do
  # Deletes and restores `config :brando, Oban`, which is global.
  use ExUnit.Case, async: false

  # `Brando.Supervisor.oban_config/0` is the one branch no suite reaches:
  # `config/test.exs` and the e2e config both set `config :brando, Oban`, which
  # replaces the default outright. So the cron, pruner and lifeline setup that
  # every production Brando actually runs has never been started by a test —
  # and an Oban major that drops a compatibility shim would land in a release
  # rather than in CI.
  describe "oban_config/0" do
    setup do
      # The default only appears when no app-level config overrides it.
      previous = Application.get_env(:brando, Oban)
      Application.delete_env(:brando, Oban)
      on_exit(fn -> previous && Application.put_env(:brando, Oban, previous) end)
      :ok
    end

    test "is a configuration Oban accepts" do
      assert %Oban.Config{} = Oban.Config.new(Brando.Supervisor.oban_config())
    end

    test "schedules Brando's workers through the cron service" do
      config = Oban.Config.new(Brando.Supervisor.oban_config())

      assert {Oban.Cron, cron_opts} = List.keyfind(config.plugins, Oban.Cron, 0)
      assert {Oban.Pruner, max_age: 300} = List.keyfind(config.plugins, Oban.Pruner, 0)
      assert {Oban.Lifeline, _} = List.keyfind(config.plugins, Oban.Lifeline, 0)

      workers = Enum.map(cron_opts[:crontab], fn {_schedule, worker} -> worker end)

      assert Brando.Worker.SitemapGenerator in workers
      assert Brando.Worker.SoftDeletePurger in workers
      assert Brando.Worker.RevisionPurger in workers
      assert Brando.Worker.VideoUploadReaper in workers
      assert Brando.Worker.UploadIntentReaper in workers
      assert Brando.Worker.MediaOrphanCleanup in workers
    end

    test "gives every queue Brando serializes a limit" do
      config = Oban.Config.new(Brando.Supervisor.oban_config())

      for queue <- [:default, :environment_operations, :ssg_builds, :image_processing, :upload_reaping] do
        assert config.queues[queue] == [limit: 1]
      end
    end
  end
end
