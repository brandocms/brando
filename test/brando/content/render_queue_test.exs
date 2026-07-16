defmodule Brando.Content.RenderQueueTest do
  use Brando.ConnCase, async: false

  alias Brando.Content.RenderQueue

  test "enqueue/1 targets the entry renderer without executing it inline" do
    assert {:ok, job} =
             Oban.Testing.with_testing_mode(:manual, fn ->
               RenderQueue.enqueue(%{schema: Brando.Pages.Page, entry_id: 12_345})
             end)

    assert job.worker == "Brando.Worker.EntryRenderer"
    assert job.args == %{entry_id: 12_345, schema: Brando.Pages.Page}
    assert job.tags == ["render_entry"]
  end
end
