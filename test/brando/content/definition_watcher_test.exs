defmodule Brando.Content.DefinitionWatcherTest do
  use ExUnit.Case, async: false
  use Brando.ConnCase

  alias Brando.Content.Definition.Watcher
  alias Brando.Content.{Container, Module, Palette}
  alias Brando.{Factory, Repo}
  alias Ecto.Changeset

  setup do
    user = Factory.insert(:random_user)
    path = Path.join(System.tmp_dir!(), "brando-watch-#{System.unique_integer([:positive])}")
    File.mkdir_p!(path)
    File.cp!("test/fixtures/definitions/hero.exs.txt", Path.join(path, "hero.exs"))
    on_exit(fn -> File.rm_rf!(path) end)
    %{user: user, path: path, source: File.read!(Path.join(path, "hero.exs"))}
  end

  defp hero, do: Repo.get_by!(Module, uid: "hero-test")
  defp palette, do: Repo.get_by!(Palette, uid: "acme-palette-paper")

  defp write!(c, source), do: File.write!(Path.join(c.path, "hero.exs"), source)

  test "a save applies a clean plan and advances the baseline; an unchanged save does nothing", c do
    assert {:ok, [%{action: :create, uid: "hero-test"}]} = Watcher.sync(c.path, c.user.id)
    assert File.exists?(Path.join(c.path, "modules.lock.json"))
    version = hero().version

    assert {:ok, :unchanged} = Watcher.sync(c.path, c.user.id)
    assert hero().version == version

    write!(c, String.replace(c.source, ~s(class "hero"), ~s(class "new-class")))
    assert {:ok, [%{action: :update}]} = Watcher.sync(c.path, c.user.id)
    assert hero().class == "new-class"

    # The advanced baseline lets the next edit apply too
    write!(c, String.replace(c.source, ~s(class "hero"), ~s(class "third-class")))
    assert {:ok, [%{action: :update}]} = Watcher.sync(c.path, c.user.id)
    assert hero().class == "third-class"
  end

  # brandocms/brando#3541
  test "an invalid file is reported with the file, var, expected type and what it got", c do
    write!(c, String.replace(c.source, "width :half", "width :huge"))

    assert Watcher.sync(c.path, c.user.id) ==
             {:error, ~s|hero.exs: var "theme": width must be one of full, half, third, fourth, auto, fill (got "huge")|}
  end

  test "a module changed in the admin since the baseline is a conflict, and nothing is written", c do
    assert {:ok, _} = Watcher.sync(c.path, c.user.id)
    hero() |> Changeset.change(class: "admin-class") |> Repo.update!()
    lock = File.read!(Path.join(c.path, "modules.lock.json"))

    write!(c, String.replace(c.source, ~s(class "hero"), ~s(class "file-class")))
    assert {:blocked, [%{action: :conflict, uid: "hero-test"}]} = Watcher.sync(c.path, c.user.id)
    assert hero().class == "admin-class"
    assert File.read!(Path.join(c.path, "modules.lock.json")) == lock
  end

  test "a half-saved file is reported and the next save still works", c do
    write!(c, "defmodule Broken do\n  use Brando.Content.Definition\n  uid ")
    assert {:error, message} = Watcher.sync(c.path, c.user.id)
    assert message =~ "syntax"
    assert Repo.aggregate(Module, :count) == 0

    write!(c, c.source)
    assert {:ok, [%{action: :create}]} = Watcher.sync(c.path, c.user.id)
  end

  test "an inactive or missing account is refused", c do
    assert {:error, message} = Watcher.sync(c.path, -1)
    assert message =~ "not an active account"
    assert Repo.aggregate(Module, :count) == 0
  end

  test "status tells the admin how each module relates to its file", c do
    state = fn ->
      assert {:ok, nil, %{"hero-test" => %{state: state, absolute: absolute}}} = Watcher.status(c.path)
      assert absolute == Path.join(c.path, "hero.exs")
      state
    end

    assert state.() == :pending
    assert {:ok, _} = Watcher.sync(c.path, c.user.id)
    assert state.() == :in_sync

    write!(c, String.replace(c.source, ~s(class "hero"), ~s(class "file-class")))
    assert state.() == :pending

    write!(c, c.source)
    hero() |> Changeset.change(class: "admin-class") |> Repo.update!()
    assert state.() == :changed_in_admin

    write!(c, String.replace(c.source, ~s(class "hero"), ~s(class "file-class")))
    assert state.() == :changed_in_both

    # Editing the file to match the admin settles it
    write!(c, String.replace(c.source, ~s(class "hero"), ~s(class "admin-class")))
    assert state.() == :in_sync
  end

  test "a saved palette or container file is imported", c do
    File.cp!("test/fixtures/definitions/styles/paper.exs.txt", Path.join(c.path, "paper.exs"))
    File.cp!("test/fixtures/definitions/styles/tinted.exs.txt", Path.join(c.path, "tinted.exs"))
    assert {:ok, changes} = Watcher.sync(c.path, c.user.id)

    assert Enum.map(changes, &{&1.kind, &1.action}) -- [{"module", :create}] == [
             {"palette", :create},
             {"container", :create}
           ]

    assert Repo.get_by!(Container, uid: "acme-container-tinted").palette_id == palette().id
  end

  # The import ran, and the lockfile kept the baseline from before it
  test "after a failed lockfile write, the last apply is the baseline, and an admin edit since is still a conflict", c do
    paper = Path.join(c.path, "paper.exs")
    source = File.read!("test/fixtures/definitions/styles/paper.exs.txt")
    File.write!(paper, source)
    assert {:ok, _} = Watcher.sync(c.path, c.user.id)

    File.write!(paper, String.replace(source, "#fff9f4", "#eeeeee"))
    File.chmod!(c.path, 0o555)

    try do
      assert {:error, _} = Watcher.sync(c.path, c.user.id)
    after
      File.chmod!(c.path, 0o755)
    end

    assert hd(palette().colors).hex_value == "#eeeeee"

    File.write!(paper, String.replace(source, "#fff9f4", "#dddddd"))
    assert {:ok, [%{action: :update, kind: "palette"}]} = Watcher.sync(c.path, c.user.id)
    assert hd(palette().colors).hex_value == "#dddddd"

    # Again, then an admin edit before the next save
    File.write!(paper, String.replace(source, "#fff9f4", "#cccccc"))
    File.chmod!(c.path, 0o555)

    try do
      assert {:error, _} = Watcher.sync(c.path, c.user.id)
    after
      File.chmod!(c.path, 0o755)
    end

    palette() |> Changeset.change(name: "Edited in the admin") |> Repo.update!()
    File.write!(paper, String.replace(source, "#fff9f4", "#bbbbbb"))
    assert {:blocked, [%{action: :conflict, kind: "palette"}]} = Watcher.sync(c.path, c.user.id)
    assert palette().name == "Edited in the admin"
    assert hd(palette().colors).hex_value == "#cccccc"
  end

  test "a save that removes a var blocks hold logs the plan's count and resolve line", c do
    assert {:ok, _} = Watcher.sync(c.path, c.user.id)

    block =
      Repo.insert!(%Brando.Content.Block{
        uid: Brando.Utils.generate_uid(),
        type: :module,
        module_id: hero().id,
        creator_id: c.user.id
      })

    Repo.insert!(%Brando.Content.Var{block_id: block.id, key: "theme", type: :select, label: %{"en" => "Theme"}})
    without = Regex.replace(~r/\n  vars do\n.*?\n  end\n/s, c.source, "")
    write!(c, String.replace(without, " class={@theme}", ""))

    level = Logger.level()
    Logger.configure(level: :info)

    log =
      try do
        ExUnit.CaptureLog.capture_log(fn ->
          Watcher.handle_info(:sync, %{path: c.path, user_id: c.user.id, config: [], timer: nil, status: nil})
        end)
      after
        Logger.configure(level: level)
      end

    assert log =~ "update module hero-test: removes var theme (1 of 1 blocks hold it, 0 entries)"
    assert log =~ "  resolve: mix brando.modules resolve --uid hero-test --user #{c.user.id} --drop var:theme --apply"
  end

  test "file/1 shows nothing when the watcher is not running" do
    assert Watcher.file("hero-test") == nil
  end

  test "it only starts when configured" do
    Application.delete_env(:brando, Watcher)
    assert Watcher.children() == []
  end
end
