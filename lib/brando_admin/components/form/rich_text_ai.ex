defmodule BrandoAdmin.Components.Form.RichTextAI do
  @moduledoc "Cancellable proposals. Only the editor's Accept action changes the ordinary HTML input."
  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [start_async: 3, cancel_async: 2, push_event: 3]

  def start(socket, params, prompt, opts, generate \\ &Brando.AI.generate_text/2) do
    id = params["tiptap_id"]
    request = params["request_id"]
    socket = cancel(socket, %{"tiptap_id" => id})
    requests = Map.get(socket.assigns, :tiptap_ai_requests, %{})
    context = context(socket)

    socket
    |> assign(:tiptap_ai_requests, Map.put(requests, id, {request, context}))
    |> start_async({:tiptap_ai, id, request}, Brando.Tenant.capture_context(fn -> generate.(prompt, opts) end))
  end

  def cancel(socket, params) do
    requests = Map.get(socket.assigns, :tiptap_ai_requests, %{})
    id = params["tiptap_id"]
    expected_request = params["request_id"]

    case requests[id] do
      {request, _} when is_nil(expected_request) or request == expected_request ->
        socket
        |> cancel_async({:tiptap_ai, id, request})
        |> assign(:tiptap_ai_requests, Map.delete(requests, id))

      _ ->
        socket
    end
  end

  def finish(socket, id, request, result) do
    requests = Map.get(socket.assigns, :tiptap_ai_requests, %{})
    context = context(socket)

    if requests[id] == {request, context} do
      payload =
        case result do
          {:ok, {:ok, %{text: text}}} when is_binary(text) and text != "" -> %{text: text}
          _ -> %{error: true}
        end

      socket
      |> assign(:tiptap_ai_requests, Map.delete(requests, id))
      |> push_event("b:tiptap:ai:#{id}", Map.put(payload, :request_id, request))
    else
      socket
    end
  end

  def prompt(base, params) do
    mode = params["mode"]
    selection = params["selection"] || ""
    instruction = params["instruction"] || ""
    request = params["request_id"]
    id = params["tiptap_id"]

    if mode in ["rewrite", "shorten", "continue"] and is_binary(selection) and byte_size(selection) <= 100_000 and
         is_binary(instruction) and byte_size(instruction) <= 4_000 and is_binary(request) and
         byte_size(request) in 1..100 and
         is_binary(id) and byte_size(id) in 1..500 do
      action =
        case mode do
          "rewrite" -> "Rewrite the passage."
          "shorten" -> "Shorten the passage while retaining its meaning."
          "continue" -> "Continue after the passage. Return only the continuation."
        end

      {:ok,
       Enum.join(
         [
           base,
           action,
           "Return plain text in the passage's language, without HTML, Markdown or explanatory commentary.",
           "Author instruction: " <> instruction,
           "Passage:\n" <> selection
         ],
         "\n\n"
       )}
    else
      {:error, :invalid_request}
    end
  end

  defp context(socket) do
    entry = socket.assigns[:entry]
    {socket.assigns[:schema] || (entry && entry.__struct__), entry && entry.id, socket.assigns[:uid]}
  end
end
