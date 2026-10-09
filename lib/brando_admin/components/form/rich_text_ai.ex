defmodule BrandoAdmin.Components.Form.RichTextAI do
  @moduledoc """
  Write with AI in the rich-text toolbar: cancellable proposals. Only the
  editor's Accept action changes the ordinary HTML input.

  It is on in every top-level rich text input of an entry form and in block
  text whenever `Brando.AI` is configured. `write_with_ai: false` on an input
  turns it off there, and in the `block_text` site prompt
  (`config :brando, Brando.AI, fields: [block_text: [...]]`) for block text,
  whose `prompt` is added to every request as the site's instructions.
  """
  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [start_async: 3, cancel_async: 2, push_event: 3]

  @actions %{
    "rewrite" => "Rewrite the passage.",
    "shorten" => "Shorten the passage while retaining its meaning.",
    "continue" => "Continue after the passage. Return only the continuation."
  }

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

  @doc """
  Whether Write with AI is on for an input with `opts`, or for block text
  with the `block_text` site prompt's options: AI is configured for the
  model they name, and they do not say `write_with_ai: false`.
  """
  @spec enabled?(keyword()) :: boolean()
  def enabled?(opts) do
    Keyword.get(opts, :write_with_ai) != false and Brando.AI.configured?(Keyword.take(opts, [:model, :api_key]))
  end

  @doc "The `block_text` site prompt's options: its instructions, model and request options."
  @spec block_text_opts() :: keyword()
  def block_text_opts, do: Brando.AI.field_ai_opts(:block_text)

  @doc """
  The prompt for a Write with AI request: the site's instructions (`base`,
  `nil` for none), the mode's, the author's instruction and the passage.
  """
  def prompt(base, params) do
    mode = params["mode"]
    selection = params["selection"] || ""
    instruction = params["instruction"] || ""

    if Map.has_key?(@actions, mode) and bounded?(selection, 0..100_000) and bounded?(instruction, 0..4_000) and
         bounded?(params["request_id"], 1..100) and bounded?(params["tiptap_id"], 1..500) do
      action = Map.fetch!(@actions, mode)

      {:ok,
       Enum.join(
         Enum.reject([base], &(&1 in [nil, ""])) ++
           [
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

  defp bounded?(value, range) when is_binary(value), do: byte_size(value) in range
  defp bounded?(_value, _range), do: false

  defp context(socket) do
    entry = socket.assigns[:entry]
    {socket.assigns[:schema] || (entry && entry.__struct__), entry && entry.id, socket.assigns[:uid]}
  end
end
