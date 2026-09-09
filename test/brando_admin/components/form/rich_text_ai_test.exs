defmodule BrandoAdmin.Components.Form.RichTextAITest do
  use ExUnit.Case, async: true
  alias BrandoAdmin.Components.Form.RichTextAI
  import Phoenix.Component, only: [assign: 2, assign: 3]

  defp socket do
    %Phoenix.LiveView.Socket{private: %{lifecycle: %Phoenix.LiveView.Lifecycle{}, live_temp: %{}}}
    |> assign(schema: Brando.Pages.Page, entry: %Brando.Pages.Page{id: 10}, form: :unchanged)
  end

  defp params(id \\ "one"),
    do: %{
      "tiptap_id" => "page_body-rich-text",
      "request_id" => id,
      "mode" => "rewrite",
      "instruction" => "Warm tone",
      "selection" => "Original passage"
    }

  defp events(socket), do: get_in(socket.private, [:live_temp, :push_events]) || []

  test "request context is explicit and proposals never change the form" do
    assert {:ok, prompt} = RichTextAI.prompt("Configured task", params())
    assert prompt =~ "Configured task"
    assert prompt =~ "Original passage"

    socket =
      RichTextAI.start(socket(), params(), prompt, [], fn _, _ -> flunk("Disconnected render must not call provider") end)

    result = RichTextAI.finish(socket, params()["tiptap_id"], "one", {:ok, {:ok, %{text: "Suggestion"}}})
    assert result.assigns.form == :unchanged
    assert [["b:tiptap:ai:page_body-rich-text", %{text: "Suggestion", request_id: "one"} | _]] = events(result)
  end

  test "canceled, superseded and changed-entry responses do nothing" do
    request = params()
    pending = RichTextAI.start(socket(), request, "Task", [])
    canceled = RichTextAI.cancel(pending, request)
    assert events(RichTextAI.finish(canceled, request["tiptap_id"], "one", {:ok, {:ok, %{text: "Late"}}})) == []
    current = RichTextAI.start(pending, params("two"), "Task", [])
    assert events(RichTextAI.finish(current, request["tiptap_id"], "one", {:ok, {:ok, %{text: "Old"}}})) == []
    changed = assign(pending, :entry, %Brando.Pages.Page{id: 11})
    assert events(RichTextAI.finish(changed, request["tiptap_id"], "one", {:ok, {:ok, %{text: "Wrong entry"}}})) == []
  end

  test "provider failure returns an actionable error without leaking provider internals" do
    socket = RichTextAI.start(socket(), params(), "Task", [])
    result = RichTextAI.finish(socket, params()["tiptap_id"], "one", {:exit, {:timeout, "private provider details"}})
    assert [[_, %{error: true, request_id: "one"} | _]] = events(result)
    assert result.assigns.form == :unchanged
    assert result.assigns.tiptap_ai_requests == %{}
  end

  test "malformed and oversized client prompts are rejected" do
    assert {:error, :invalid_request} = RichTextAI.prompt("Task", Map.put(params(), "mode", "unknown"))

    assert {:error, :invalid_request} =
             RichTextAI.prompt("Task", Map.put(params(), "instruction", String.duplicate("x", 4001)))
  end

  test "a connected request calls a deterministic provider asynchronously" do
    owner = self()
    connected = %{socket() | transport_pid: owner}

    pending =
      RichTextAI.start(connected, params(), "Configured task", [], fn prompt, _opts ->
        send(owner, {:generated, prompt, self()})
        {:ok, %{text: "A deterministic suggestion"}}
      end)

    assert_receive {:generated, "Configured task", worker}
    refute worker == owner
    assert pending.assigns.form == :unchanged
  end
end
