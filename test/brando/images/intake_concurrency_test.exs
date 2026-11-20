defmodule Brando.Images.IntakeConcurrencyTest do
  # Two different images stored at once into a folder that does not exist
  # yet, on two real connections: the first is stopped inside its store, with
  # the folder made, while the second stores. Outside the sandbox, so that
  # the folder's unique index and the commit between them are real.
  use ExUnit.Case, async: false

  import Ecto.Query, only: [from: 2]

  alias Brando.Images.Image
  alias Brando.Images.Intake
  alias Brando.Media.Folder
  alias BrandoIntegration.Repo
  alias Ecto.Adapters.SQL.Sandbox

  @jpg Path.expand("../../fixtures/sample.jpg", __DIR__)
  @png Path.expand("../../fixtures/sample.png", __DIR__)

  setup do
    folder = "intake-race-#{System.unique_integer([:positive])}"
    dir = Path.join(System.tmp_dir!(), folder)
    File.mkdir_p!(dir)

    user =
      Sandbox.unboxed_run(Repo, fn ->
        Brando.Factory.insert(:random_user, role: :superuser, avatar: nil, config: %Brando.Users.UserConfig{})
      end)

    ctx = Intake.context(user, folder)
    {scope, paths} = folder_paths(ctx.absolute_folder)
    made_before = Sandbox.unboxed_run(Repo, fn -> existing_folders(scope, paths) end)

    on_exit(fn ->
      File.rm_rf(dir)
      File.rm_rf(Path.join(Brando.Tenant.Storage.current_media_root(), ctx.absolute_folder))

      Sandbox.unboxed_run(Repo, fn ->
        Repo.delete_all(from i in Image, where: like(i.path, ^"%/#{folder}/%"))

        # Deepest first: a folder's parent is referenced by it
        for path <- Enum.reverse(paths), path not in made_before do
          Repo.delete_all(from f in Folder, where: f.scope == ^scope and f.path == ^path)
        end

        Repo.delete_all(from u in Brando.Users.User, where: u.id == ^user.id)
      end)
    end)

    %{ctx: ctx, dir: dir, scope: scope, paths: paths}
  end

  # The folder and the folders above it, as `FolderBrowser` stores them
  defp folder_paths(absolute) do
    [scope | segments] = String.split(absolute, "/")
    paths = segments |> Enum.scan(&(&2 <> "/" <> &1))
    {scope, paths}
  end

  defp existing_folders(scope, paths),
    do: Repo.all(from f in Folder, where: f.scope == ^scope and f.path in ^paths, select: f.path)

  test "two images stored at once into a new folder are both stored, in the same folder", %{ctx: ctx, dir: dir} = c do
    parent = self()
    first_path = Path.join(dir, "first.jpg")
    second_path = Path.join(dir, "second.png")
    File.cp!(@jpg, first_path)
    File.cp!(@png, second_path)

    # Stops inside its store, the image row and its folder made, until let go
    pause = fn image ->
      send(parent, {:inside, self()})

      receive do
        :go -> {:stored, image}
      after
        10_000 -> {:stored, image}
      end
    end

    first = Task.async(fn -> unboxed_store(first_path, "first.jpg", "image/jpeg", ctx, pause) end)
    assert_receive {:inside, first_pid}, 5_000

    second = Task.async(fn -> unboxed_store(second_path, "second.png", "image/png", ctx, &{:stored, &1}) end)
    second_early = done_or_waiting(second)

    send(first_pid, :go)
    assert {:stored, %Image{} = first_image} = Task.await(first, 10_000)

    second_answer =
      case second_early do
        {:done, answer} -> answer
        :waiting -> Task.await(second, 10_000)
      end

    assert {:stored, %Image{} = second_image} = second_answer
    assert first_image.folder_id
    assert first_image.folder_id == second_image.folder_id

    Sandbox.unboxed_run(Repo, fn ->
      assert existing_folders(c.scope, c.paths) |> Enum.sort() == Enum.sort(c.paths)
    end)
  end

  defp unboxed_store(path, filename, type, ctx, on_new) do
    Sandbox.unboxed_run(Repo, fn -> Intake.store(path, filename, type, ctx, on_new) end)
  rescue
    error -> {:raised, error}
  end

  # The second store either finishes while the first is stopped, or waits on
  # a lock the first holds
  defp done_or_waiting(task, tries \\ 250) do
    case Task.yield(task, 20) do
      {:ok, answer} ->
        {:done, answer}

      nil ->
        cond do
          lock_waiting?() -> :waiting
          tries == 0 -> flunk("the second store neither finished nor waited")
          true -> done_or_waiting(task, tries - 1)
        end
    end
  end

  defp lock_waiting? do
    Sandbox.unboxed_run(Repo, fn ->
      Repo.query!(
        "SELECT count(*) FROM pg_stat_activity WHERE datname = current_database() AND wait_event_type = 'Lock' AND query LIKE '%media_folders%'"
      ).rows
    end) != [[0]]
  end
end
