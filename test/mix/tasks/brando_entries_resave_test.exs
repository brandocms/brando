defmodule Mix.Tasks.Brando.Entries.ResaveTest do
  use Brando.ConnCase

  alias Mix.Tasks.Brando.Entries.Resave

  # Swaps the global `Mix.shell()`; Brando.ConnCase runs synchronously.
  setup do
    shell = Mix.shell()
    Mix.shell(Mix.Shell.Process)
    on_exit(fn -> Mix.shell(shell) end)

    Mix.Task.reenable("brando.entries.resave")
    Mix.Task.reenable("run")
    :ok
  end

  test "with nobody to answer the prompt, it does nothing and fails" do
    send(self(), {:mix_shell_input, :prompt, :eof})

    assert_raise Mix.Error, ~r/stdin is closed, so nothing was done. Pass --yes/, fn -> Resave.run([]) end
    refute_received {:mix_shell, :info, ["\n==> Done.\n"]}
  end

  test "answering no says nothing was done" do
    send(self(), {:mix_shell_input, :prompt, "n"})

    Resave.run([])

    assert_received {:mix_shell, :info, ["Nothing was done."]}
  end

  test "--yes is accepted" do
    Resave.run(["--yes", "Brando.Pages.Fragment"])

    assert_received {:mix_shell, :info, ["\n==> Done.\n"]}
  end

  test "says that running servers keep their cached pages" do
    Resave.run(["--yes", "Brando.Pages.Fragment"])

    assert_received {:mix_shell, :info,
                     ["Servers that were already running keep serving what they cached before." <> _ = note]}

    assert note =~ "Configuration → Cache → Empty all caches"
  end

  test "ends with one line per image config target that no longer resolves" do
    for n <- 1..10,
        do:
          Brando.Factory.insert(:image, path: "images/gallery/#{n}.jpg", config_target: "image:Brando.Pages.Page:gallery")

    Resave.run(["--yes", "Brando.Pages.Fragment"])

    assert_received {:mix_shell, :info,
                     [
                       "    * 10 images point at a field Brando.Pages.Page no longer has (image:Brando.Pages.Page:gallery); they use the default image config."
                     ]}
  end

  test "prints no colour codes when stdout is not a terminal" do
    ansi = Application.get_env(:elixir, :ansi_enabled)
    Application.put_env(:elixir, :ansi_enabled, false)
    on_exit(fn -> Application.put_env(:elixir, :ansi_enabled, ansi) end)

    user = Brando.Factory.insert(:random_user)
    Brando.Factory.insert(:fragment, creator: user, key: "plain", title: "Plain")

    output = ExUnit.CaptureIO.capture_io(fn -> Resave.run(["--yes", "Brando.Pages.Fragment"]) end)

    assert output =~ "done!"
    refute output =~ "\e["
  end

  test "renders each entry from what it holds when its turn comes, not when the task began" do
    user = Brando.Factory.insert(:random_user, role: :superuser)

    {:ok, module} =
      Brando.Content.create_module(
        Brando.Factory.params_for(:module, %{code: ~s(<div class="paragraph">Title: {{ entry.title }}</div>)}),
        :system
      )

    [_first, second] = for key <- ~w(first second), do: fragment(user, module, key)

    # An editor saves the second entry while the task renders the first
    id = make_ref()
    :ok = :telemetry.attach(id, [:brando, :villain, :parse_and_render], &__MODULE__.save_once/4, second.id)
    on_exit(fn -> :telemetry.detach(id) end)

    ExUnit.CaptureIO.capture_io(fn -> Resave.run(["--yes", "Brando.Pages.Fragment"]) end)

    assert Brando.Repo.get!(Brando.Pages.Fragment, second.id).rendered_blocks =~ "Title: Saved meanwhile"
  end

  @doc false
  def save_once(_event, _measurements, _metadata, id) do
    unless Process.put(:resave_test_saved, true) do
      Brando.Repo.update_all(Ecto.Query.from(f in Brando.Pages.Fragment, where: f.id == ^id),
        set: [title: "Saved meanwhile"]
      )
    end
  end

  defp fragment(user, module, key) do
    {:ok, fragment} =
      %Brando.Pages.Fragment{}
      |> Ecto.Changeset.change(
        Brando.Factory.params_for(:fragment, %{
          parent_key: "resave",
          key: key,
          title: key,
          entry_blocks: [
            %{block: %{type: :module, source: "Elixir.Brando.Pages.Fragment.Blocks", module_id: module.id, refs: []}}
          ]
        })
      )
      |> Brando.Pages.create_fragment(user)

    fragment
  end

  test "an unknown option or a second Blueprint stops the task" do
    assert_raise Mix.Error, ~r/unknown or invalid option --all. It takes: --yes, --force/, fn -> Resave.run(["--all"]) end

    assert_raise Mix.Error, ~r/unexpected argument Brando.Pages.Fragment Brando.Pages.Page/, fn ->
      Resave.run(["Brando.Pages.Fragment", "Brando.Pages.Page"])
    end
  end

  describe "Mix.Brando.confirm?/2" do
    test "--yes and --force answer without asking" do
      assert Mix.Brando.confirm?("Proceed?", yes: true)
      assert Mix.Brando.confirm?("Proceed?", force: true)
      refute_received {:mix_shell, :prompt, _}
    end

    test "an empty answer or y is yes, anything else no" do
      for {answer, expected} <- [{"", true}, {"y", true}, {"Yes\n", true}, {"n", false}, {"nope", false}] do
        send(self(), {:mix_shell_input, :prompt, answer})
        assert Mix.Brando.confirm?("Proceed?") == expected
      end
    end
  end
end
