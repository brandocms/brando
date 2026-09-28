defmodule Brando.Content.DefinitionWatcherTest do
  use ExUnit.Case, async: false
  use Brando.ConnCase

  alias Brando.Content.Definition.Watcher
  alias Brando.Content.Module
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

  test "file/1 shows nothing when the watcher is not running" do
    assert Watcher.file("hero-test") == nil
  end

  test "it only starts when configured" do
    Application.delete_env(:brando, Watcher)
    assert Watcher.children() == []
  end
end
