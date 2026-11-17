defmodule Brando.Content.DefinitionsReleaseTest do
  # A release's definitions against this database's own baseline
  # (`content_definition_applies`), not the developer's lockfile
  use ExUnit.Case, async: false
  use Brando.ConnCase

  import Ecto.Query, only: [from: 2]

  alias Brando.Content.Definition.{Archive, Snapshot}
  alias Brando.Content.{DefinitionApply, Definitions, Module}
  alias Brando.Content.Definitions.Release
  alias Brando.{Factory, Repo}
  alias Ecto.Changeset

  setup do
    user = Factory.insert(:random_user, name: "Rel Ease")
    path = Path.join(System.tmp_dir!(), "brando-release-#{System.unique_integer([:positive])}")
    File.mkdir_p!(path)
    source = File.read!("test/fixtures/definitions/hero.exs.txt")
    File.write!(Path.join(path, "hero.exs"), source)
    on_exit(fn -> File.rm_rf!(path) end)
    %{user: user, path: path, source: source}
  end

  defp opts(c, extra \\ []), do: Keyword.merge([path: c.path, version: "1.0.0"], extra)

  defp write!(c, from, to), do: File.write!(Path.join(c.path, "hero.exs"), String.replace(c.source, from, to))

  defp hero, do: Repo.get_by!(Module, uid: "hero-test")

  defp rows, do: Repo.all(from(a in DefinitionApply, order_by: a.id))

  # The module exists here from before (a database pushed from development,
  # or edited by hand), with nothing recorded as applied
  defp existing!(c) do
    {:ok, bundle} = Definitions.read(c.path)
    {:ok, plan} = Definitions.plan(bundle, c.user)
    {:ok, _} = Definitions.apply(plan, c.user)
    Repo.delete_all(DefinitionApply)
    hero()
  end

  defp lines(fun) do
    {:ok, agent} = Agent.start_link(fn -> [] end)
    result = fun.(fn line -> Agent.update(agent, &[line | &1]) end)
    {result, agent |> Agent.get(& &1) |> Enum.reverse() |> Enum.join("\n")}
  end

  describe "planning against the database's baseline" do
    test "a definition equal to the files with nothing recorded is recorded as applied", c do
      existing!(c)

      assert {:ok, report} = Release.plan(opts(c))
      assert [%{action: :noop, state: :in_sync}] = report.items
      assert report.pending == 0
      assert report.adopted == 1

      assert [%{action: :adopted, source: :release, release: "1.0.0", applied_by_id: nil} = row] = rows()
      assert row.digest == Snapshot.digest(hd(report.plan.bundle["modules"]))

      # Once is enough
      assert {:ok, %{adopted: 0}} = Release.plan(opts(c))
      assert length(rows()) == 1
    end

    test "a definition never applied that differs is a conflict until the operator names it", c do
      existing!(c)
      hero() |> Changeset.change(class: "admin-class") |> Repo.update!()

      assert {:ok, report} = Release.plan(opts(c))
      assert [%{action: :conflict, state: :never_applied, reason: reason}] = report.items
      assert reason =~ "never applied from files"
      assert report.adopted == 0
      assert rows() == []

      assert {:error, message} = Release.apply(:all, opts(c, user: c.user.id))
      assert message =~ "never applied"
      assert hero().class == "admin-class"

      assert {:ok, %{result: result}} = Release.apply(["hero-test"], opts(c, user: c.user.id, replace: ["hero-test"]))
      assert [%{action: :update}] = result.changes
      assert hero().class == "hero"

      assert [%{action: :replaced, source: :release, previous: previous, previous_digest: digest}] = rows()
      assert previous["class"] == "admin-class"
      assert digest == Snapshot.digest(previous)
    end

    test "an update the files bring is one, whatever the shipped lockfile says", c do
      assert {:ok, %{result: %{changes: [%{action: :create}]}}} = Release.apply(:all, opts(c, user: c.user.id))
      assert [%{action: :created, release: "1.0.0", applied_by_id: user_id}] = rows()
      assert user_id == c.user.id

      # Development imported the new version and shipped its lockfile, whose
      # baseline is that version and whose source is another database
      write!(c, ~s(class "hero"), ~s(class "new-class"))
      {:ok, bundle} = Definitions.read(c.path)

      lock = %{
        "format_version" => 1,
        "source" => "the developer's database",
        "baseline" => Snapshot.baselines(bundle),
        "references" => %{}
      }

      File.write!(Path.join(c.path, "modules.lock.json"), Jason.encode!(lock))

      # Against that lockfile it would be a conflict
      {:ok, bundle} = Definitions.read(c.path)
      assert {:ok, %{items: [%{action: :conflict}]}} = Definitions.plan(bundle, c.user, baseline: :lockfile)

      assert {:ok, report} = Release.plan(opts(c, version: "1.1.0"))
      assert [%{action: :update, state: :changed_in_release, class: :render, baseline: :applied}] = report.items
      assert report.pending == 1
      assert report.classes == %{render: 1}

      assert {:ok, _} = Release.apply(["hero-test"], opts(c, user: c.user.id, version: "1.1.0"))
      assert hero().class == "new-class"
      assert [_, %{action: :updated, release: "1.1.0", previous: %{"class" => "hero"}}] = rows()

      assert {:ok, %{pending: 0, items: [%{state: :in_sync}]}} = Release.plan(opts(c, version: "1.1.0"))
    end

    test "both sides changed is a conflict that says who changed it here and when", c do
      {:ok, _} = Release.apply(:all, opts(c, user: c.user.id))
      editor = Factory.insert(:random_user, name: "Ed Itor")
      module = hero() |> Changeset.change(class: "admin-class") |> Repo.update!()
      Brando.Activity.record(:updated, module, editor, fields: ["class"])

      write!(c, ~s(class "hero"), ~s(class "file-class"))
      assert {:ok, report} = Release.plan(opts(c, version: "1.1.0"))

      assert [%{action: :conflict, state: :changed_in_both} = item] = report.items
      assert item.edited.by.id == editor.id
      assert item.applied.release == "1.0.0"
      assert item.applied.by.id == c.user.id

      {:ok, text} = lines(fn info -> Release.status(opts(c, version: "1.1.0", info: info)) end)
      assert text =~ "changed in the admin by Ed Itor"
      assert text =~ "last applied from release 1.0.0 by Rel Ease"
      assert text =~ "1 conflict"

      assert {:error, message} = Release.apply(["hero-test"], opts(c, user: c.user.id))
      assert message =~ "Hero (hero-test)"
      assert hero().class == "admin-class"
    end

    test "an admin edit the release doesn't touch is kept, and nothing waits", c do
      {:ok, _} = Release.apply(:all, opts(c, user: c.user.id))
      hero() |> Changeset.change(class: "admin-class") |> Repo.update!()

      assert {:ok, report} = Release.plan(opts(c))
      assert [%{action: :noop, state: :changed_in_admin}] = report.items
      assert report.pending == 0
      assert {:ok, %{result: %{changes: []}}} = Release.apply(:all, opts(c, user: c.user.id))
      assert hero().class == "admin-class"
    end
  end

  describe "review round 1" do
    test "replace: never overrides a conflict on a definition applied here", c do
      {:ok, _} = Release.apply(:all, opts(c, user: c.user.id))
      hero() |> Changeset.change(class: "admin-class") |> Repo.update!()
      write!(c, ~s(class "hero"), ~s(class "file-class"))

      assert {:ok, %{items: [%{action: :conflict, state: :changed_in_both}]}} =
               Release.plan(opts(c, replace: ["hero-test"]))

      assert {:error, _} = Release.apply(["hero-test"], opts(c, user: c.user.id, replace: ["hero-test"]))
      assert hero().class == "admin-class"
    end

    test "a module in the trash is a conflict of its own, and the rest still plans and applies", c do
      {:ok, _} = Release.apply(:all, opts(c, user: c.user.id))
      hero() |> Changeset.change(deleted_at: DateTime.utc_now() |> DateTime.truncate(:second)) |> Repo.update!()
      other = String.replace(c.source, ~s(uid "hero-test"), ~s(uid "other-test"))
      other = String.replace(other, "Example.Hero", "Example.Other")
      File.write!(Path.join(c.path, "other.exs"), other)

      assert {:ok, report} = Release.plan(opts(c))
      by_uid = Map.new(report.items, &{&1.uid, &1})
      assert %{action: :conflict, state: :deleted, reason: reason} = by_uid["hero-test"]
      assert reason =~ "trash"
      assert %{action: :create} = by_uid["other-test"]

      assert {:ok, _} = Release.apply(["other-test"], opts(c, user: c.user.id))
      assert Repo.get_by(Module, uid: "other-test")
    end

    test "a definition deleted after it was applied is a conflict that replace: creates again", c do
      {:ok, _} = Release.apply(:all, opts(c, user: c.user.id))
      Repo.delete!(hero())

      assert {:ok, %{items: [%{action: :conflict, state: :deleted, reason: reason}]}} = Release.plan(opts(c))
      assert reason =~ "deleted here after it was applied"
      refute reason =~ "trash"

      assert {:ok, %{result: %{changes: [%{action: :create}]}}} =
               Release.apply(["hero-test"], opts(c, user: c.user.id, replace: ["hero-test"]))

      assert hero()
    end

    test "a token the next release drops or renames is no conflict", c do
      image = Factory.insert(:image)
      write!(c, ~s(description "Headline"), ~s(description "Headline"\n      assets image: "cover"))
      {:ok, _} = Release.apply(:all, opts(c, user: c.user.id, references: %{"cover" => image.id}))

      # The next release drops the image
      write!(c, ~s(class "hero"), ~s(class "hero"))
      assert {:ok, %{items: [%{action: :update, state: :changed_in_release}]}} = Release.plan(opts(c))
    end

    test "renaming a token for the same record is no conflict", c do
      image = Factory.insert(:image)
      write!(c, ~s(description "Headline"), ~s(description "Headline"\n      assets image: "z-cover"))
      {:ok, _} = Release.apply(:all, opts(c, user: c.user.id, references: %{"z-cover" => image.id}))

      write!(c, ~s(description "Headline"), ~s(description "Headline"\n      assets image: "a-cover"))
      refs = %{"a-cover" => image.id}
      assert {:ok, %{items: [%{state: state}]}} = Release.plan(opts(c, references: refs))
      assert state in [:in_sync, :changed_in_release]
      assert {:ok, _} = Release.apply(:all, opts(c, user: c.user.id, references: refs))
      assert {:ok, %{items: [%{state: :in_sync}], pending: 0}} = Release.plan(opts(c))
    end

    test "a record two definitions bind under different tokens is in sync for both", c do
      image = Factory.insert(:image)
      write!(c, ~s(description "Headline"), ~s(description "Headline"\n      assets image: "photo"))

      other =
        c.source
        |> String.replace(~s(uid "hero-test"), ~s(uid "other-test"))
        |> String.replace("Example.Hero", "Example.Other")
        |> String.replace(~s(description "Headline"), ~s(description "Headline"\n      assets image: "cover"))

      File.write!(Path.join(c.path, "other.exs"), other)
      refs = %{"photo" => image.id, "cover" => image.id}
      {:ok, _} = Release.apply(:all, opts(c, user: c.user.id, references: refs))

      assert {:ok, %{pending: 0, items: items}} = Release.plan(opts(c))
      assert Enum.all?(items, &(&1.state == :in_sync))
    end

    test "an adoption planned before the database changed is not recorded", c do
      existing!(c)
      {:ok, report} = Release.plan(opts(c, adopt: false))
      hero() |> Changeset.change(class: "meanwhile") |> Repo.update!()

      assert Brando.Content.Definition.Baselines.adopt!(report.plan, source: :release) == 0
      assert rows() == []
    end

    test "apply --release takes no --dry-run", c do
      put_test_env(Definitions, release_path: c.path)

      assert_raise Mix.Error, ~r/--dry-run/, fn ->
        Mix.Tasks.Brando.Modules.run(["apply", "--release", "--all", "--dry-run", "--user", to_string(c.user.id)])
      end

      assert Repo.aggregate(Module, :count) == 0
    end
  end

  describe "applying" do
    test "writes its baseline rows in the apply's transaction", c do
      {:ok, _} = Release.apply(:all, opts(c, user: c.user.id))
      write!(c, ~s(class "hero"), ~s(class "new-class"))

      Ecto.Adapters.SQL.query!(
        Repo.repo(),
        "ALTER TABLE content_definition_applies ADD CONSTRAINT no_rows CHECK (uid = '') NOT VALID"
      )

      assert_raise Postgrex.Error, ~r/no_rows/, fn -> Release.apply(:all, opts(c, user: c.user.id)) end
      # The definition write went with the rows
      assert hero().class == "hero"
    end

    test "a plan made before the database changed writes nothing", c do
      {:ok, _} = Release.apply(:all, opts(c, user: c.user.id))
      write!(c, ~s(class "hero"), ~s(class "new-class"))
      {:ok, report} = Release.plan(opts(c, user: c.user.id))
      hero() |> Changeset.change(class: "meanwhile") |> Repo.update!()

      assert {:error, message} = Definitions.apply(report.plan, c.user, source: :release)
      assert message =~ "target changed"
      assert length(rows()) == 1
    end

    test "takes a user, and a selection of definitions in the release", c do
      assert {:error, "user: is required to apply"} = Release.apply(:all, opts(c))
      assert {:error, message} = Release.apply(["nope"], opts(c, user: c.user.id))
      assert message =~ "nope: is not among the definitions"
      assert {:error, _} = Release.apply(:some, opts(c, user: c.user.id))
      assert rows() == []
    end
  end

  describe "waiting for renders" do
    # A module two entries use, exported as a release that changes its class.
    # Oban runs :manual here; a drainer stands in for the queue (#3611).
    setup c do
      context = Brando.ProposalFixtures.context()
      dir = Path.join(c.path, "release")
      {:ok, _} = Definitions.export(dir, context.user, uids: [context.text_module.uid])
      {:ok, _} = Release.plan(path: dir)
      [file] = dir |> Path.join("**/*.exs") |> Path.wildcard()
      File.write!(file, String.replace(File.read!(file), ~r/^  class .*$/m, ~s(  class "from-the-release")))
      Map.merge(context, %{dir: dir})
    end

    defp drainer do
      Task.async(fn -> drain() end)
    end

    defp drain do
      Oban.Testing.with_testing_mode(:manual, fn -> Oban.drain_queue(queue: :default) end)

      receive do
        :stop -> :ok
      after
        10 -> drain()
      end
    end

    test "apply! reports applied once the affected entries have rendered", c do
      task = drainer()

      {:ok, text} =
        lines(fn info ->
          Oban.Testing.with_testing_mode(:manual, fn ->
            Release.apply!(:all, path: c.dir, user: c.user.id, version: "1.1.0", info: info)
          end)
        end)

      send(task.pid, :stop)
      Task.await(task)

      assert text =~ "Applied 1 definition changes from release 1.1.0"
      assert text =~ ~r/Rendered \d+ entries/
      assert Repo.aggregate(from(j in Oban.Job, where: j.state in ["available", "executing"]), :count) == 0
    end

    test "wait: false leaves the renders queued and says so", c do
      {:ok, text} =
        lines(fn info ->
          Oban.Testing.with_testing_mode(:manual, fn ->
            Release.apply!(:all, path: c.dir, user: c.user.id, info: info, wait: false)
          end)
        end)

      assert text =~ ~r/\d+ render jobs are queued for the running server/
      assert Repo.aggregate(from(j in Oban.Job, where: j.state == "available"), :count) > 0
    end

    test "renders that outlast the timeout make apply! raise", c do
      assert_raise RuntimeError, ~r/still waiting when the timeout passed/, fn ->
        Oban.Testing.with_testing_mode(:manual, fn ->
          Release.apply!(:all, path: c.dir, user: c.user.id, info: fn _ -> :ok end, timeout: 50, interval: 10)
        end)
      end
    end
  end

  test "a ZIP whose lockfile belongs to another database is planned against this one's", c do
    {:ok, _} = Release.apply(:all, opts(c, user: c.user.id))

    # Development imported a new version and exported it, so its baseline is
    # the new version itself
    write!(c, ~s(class "hero"), ~s(class "zip-class"))
    {:ok, bundle} = Definitions.read(c.path)

    lock = %{
      "format_version" => 1,
      "source" => "elsewhere",
      "baseline" => Snapshot.baselines(bundle),
      "references" => %{}
    }

    files = %{
      "hero.exs" => File.read!(Path.join(c.path, "hero.exs")),
      "modules.lock.json" => Jason.encode!(lock)
    }

    {:ok, zip} = Archive.pack(files)
    assert {:ok, %{bundle: uploaded}} = Archive.read(zip)

    assert {:ok, %{mode: :database, items: [%{action: :update, baseline: :applied}]} = plan} =
             Definitions.plan(uploaded, c.user)

    assert {:ok, _} = Definitions.apply(plan, c.user)
    assert hero().class == "zip-class"
    assert [_, %{action: :updated, source: :import}] = rows()
  end

  describe "commands" do
    test "status prints the changes waiting, one line for a deploy, and raises when it can't plan", c do
      {:ok, _} = Release.apply(:all, opts(c, user: c.user.id))
      write!(c, ~s(class "hero"), ~s(class "new-class"))

      {:ok, text} = lines(fn info -> Release.status(opts(c, version: "1.1.0", info: info)) end)
      assert text =~ "Module definitions in release 1.1.0"
      assert text =~ "1 update"
      assert text =~ "1 render"
      assert text =~ "update module Hero (hero-test): render; 0 entries"
      assert text =~ "Review: " <> Release.admin_url()
      assert text =~ ~s|Release.apply!(["hero-test"], user: ID)|

      {:ok, line} = lines(fn info -> Release.status(opts(c, version: "1.1.0", info: info, format: :line)) end)
      assert line == "1 module change waiting in release 1.1.0: " <> Release.admin_url()

      {:ok, line} = lines(fn info -> Release.status(path: Path.join(c.path, "missing"), info: info, format: :line) end)
      assert line == "No module definitions in this release"

      File.write!(Path.join(c.path, "hero.exs"), "defmodule Broken do\n  uid ")

      assert_raise RuntimeError, ~r/Module definitions: .*syntax/, fn ->
        Release.status(opts(c, info: fn _ -> :ok end))
      end
    end

    test "apply! prints what it applied, and raises when it applies nothing", c do
      {:ok, text} = lines(fn info -> Release.apply!(:all, opts(c, user: c.user.id, info: info)) end)
      assert text =~ "create module Hero (hero-test): new"
      assert text =~ "Applied 1 definition changes from release 1.0.0"

      hero() |> Changeset.change(class: "admin-class") |> Repo.update!()
      write!(c, ~s(class "hero"), ~s(class "file-class"))

      assert_raise RuntimeError, ~r/nothing was applied; leave out or resolve: Hero/, fn ->
        Release.apply!(:all, opts(c, user: c.user.id, info: fn _ -> :ok end))
      end
    end

    test "mix brando.modules plan --release and apply --release", c do
      put_test_env(Definitions, release_path: c.path)
      id = to_string(c.user.id)
      previous = Mix.shell()
      Mix.shell(Mix.Shell.Process)
      on_exit(fn -> Mix.shell(previous) end)

      Mix.Tasks.Brando.Modules.run(["plan", "--release", "--user", id])
      assert_received {:mix_shell, :info, ["  create module Hero (hero-test): new"]}
      assert Repo.aggregate(Module, :count) == 0

      assert_raise Mix.Error, ~r/--all or --uid/, fn ->
        Mix.Tasks.Brando.Modules.run(["apply", "--release", "--user", id])
      end

      assert_raise Mix.Error, ~r/take --release/, fn -> Mix.Tasks.Brando.Modules.run(["plan", "--user", id]) end

      Mix.Tasks.Brando.Modules.run(["apply", "--release", "--uid", "hero-test", "--user", id])
      assert_received {:mix_shell, :info, ["Applied 1 definition changes from release " <> _]}
      assert hero().class == "hero"

      hero() |> Changeset.change(class: "admin-class") |> Repo.update!()
      write!(c, ~s(class "hero"), ~s(class "file-class"))

      assert_raise Mix.Error, ~r/nothing was applied/, fn ->
        Mix.Tasks.Brando.Modules.run(["apply", "--release", "--all", "--user", id])
      end
    end
  end
end
