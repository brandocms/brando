defmodule Mix.Tasks.Brando.ScheduledPublishing.SweepTest do
  use ExUnit.Case, async: false

  alias Mix.Tasks.Brando.ScheduledPublishing.Sweep

  setup do
    Mix.shell(Mix.Shell.Process)
    on_exit(fn -> Mix.shell(Mix.Shell.IO) end)
  end

  defp found(attrs) do
    Map.merge(
      %{
        environment: "public",
        schema: Brando.Pages.Page,
        id: 1,
        title: "Launch",
        action: :publish,
        at: ~U[2026-10-09 08:00:00Z],
        result: :dry_run
      },
      attrs
    )
  end

  test "lists what the sweep would do, and says nothing changed" do
    Sweep.report([found(%{}), found(%{id: 2, title: "Old", action: :unpublish})], false)

    assert_received {:mix_shell, :info, [first]}
    assert first =~ ~r/^public  would publish +Brando.Pages.Page #1 "Launch"/
    assert_received {:mix_shell, :info, [second]}
    assert second =~ ~r/^public  would deactivate +Brando.Pages.Page #2 "Old"/
    assert_received {:mix_shell, :info, ["\n2 entries. Nothing changed" <> _]}
  end

  test "with --apply, shows what it did and what failed" do
    Sweep.report([found(%{result: :ok}), found(%{id: 2, result: {:error, [title: {"can't be blank", []}]}})], true)

    assert_received {:mix_shell, :info, [first]}
    assert first =~ ~r/^public  published +Brando.Pages.Page #1 /
    refute first =~ "FAILED"
    assert_received {:mix_shell, :info, [second]}
    assert second =~ ~r/^public  published +Brando.Pages.Page #2 .*FAILED/
  end

  test "says when there is nothing to do" do
    Sweep.report([], false)
    assert_received {:mix_shell, :info, ["Nothing to publish or deactivate."]}
  end
end
