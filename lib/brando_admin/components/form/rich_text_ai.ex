defmodule BrandoAdmin.Components.Form.RichTextAI do
  @moduledoc """
  Write with AI in the rich-text toolbar: cancellable proposals. Only the
  editor's Accept action changes the ordinary HTML input.

  It is off unless asked for, since every request is a paid call, and shows
  only where `Brando.AI` is configured for its model:

    * in a top-level rich text input of an entry form whose
      `write_with_ai:` (`Brando.Blueprint.Forms.WriteWithAI`) is `true` or
      its options (instructions, fields to read, a model);
    * in the text blocks of a module with **Write with AI** on in the module
      editor (`Brando.Content.Module`'s `write_with_ai`). The `block_text`
      site prompt (`config :brando, Brando.AI, prompts: [block_text: [...]]`)
      adds its `prompt` to every request there and picks the model;
      `write_with_ai: false` in it turns Write with AI off in every module.
  """
  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [start_async: 3, cancel_async: 2, push_event: 3]

  @actions %{
    "rewrite" => "Rewrite the passage.",
    "shorten" => "Shorten the passage while retaining its meaning.",
    "continue" => "Continue after the passage. Return only the continuation."
  }

  @doc """
  Write with AI's options for an input with `opts`: the `write_with_ai:`
  options, `[]` for `write_with_ai: true`, and `:off` when the input does
  not ask for it.
  """
  @spec input_config(keyword()) :: keyword() | :off
  def input_config(opts) do
    case Keyword.get(opts, :write_with_ai) do
      true -> []
      config when is_list(config) -> config
      _ -> :off
    end
  end

  @doc """
  Write with AI's options for a text block, given whether its module turns
  Write with AI on: the `block_text` site prompt's, or `:off` when the module
  does not turn it on or the site prompt says `write_with_ai: false`.
  """
  @spec block_text_config(boolean()) :: keyword() | :off
  def block_text_config(true) do
    opts = Brando.AI.field_ai_opts(:block_text)
    if Keyword.get(opts, :write_with_ai) == false, do: :off, else: opts
  end

  def block_text_config(_module_write_with_ai?), do: :off

  @doc "Whether Write with AI is on with `config`: not `:off`, and AI is configured for its model."
  @spec enabled?(keyword() | :off) :: boolean()
  def enabled?(:off), do: false
  def enabled?(config) when is_list(config), do: Brando.AI.configured?(ai_opts(config))

  @doc "The `Brando.AI` options in `config`: its model and request options."
  @spec ai_opts(keyword()) :: keyword()
  def ai_opts(config), do: Keyword.drop(config, [:prompt, :from, :context, :write_with_ai])

  def start(socket, params, prompt, opts, generate \\ &Brando.AI.generate_text/2) do
    id = params["tiptap_id"]
    request = params["request_id"]
    socket = cancel(socket, %{"tiptap_id" => id})
    requests = Map.get(socket.assigns, :tiptap_ai_requests, %{})
    context = context(socket)

    socket
    |> assign(:tiptap_ai_requests, Map.put(requests, id, {request, context}))
    |> start_async({:tiptap_ai, id, request}, Brando.Tenant.capture_context(fn -> run(prompt, opts, generate) end))
  end

  # `prompt` is the prompt, or a function that builds it in the task
  # (`{:ok, prompt}`), when building it reads the form's fields.
  defp run(build, opts, generate) when is_function(build, 0) do
    with {:ok, prompt} <- build.(), do: generate.(prompt, opts)
  end

  defp run(prompt, opts, generate), do: generate.(prompt, opts)

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
