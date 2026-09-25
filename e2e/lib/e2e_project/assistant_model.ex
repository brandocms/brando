defmodule E2eProject.AssistantModel do
  @moduledoc """
  A scripted stand-in for the content assistant's model, for end-to-end tests.

  It speaks ReqLLM's `generate_text/3` contract and drives the real tools:
  for "Put image1 on the Index page" it searches for the page, lists its
  modules, reads the attachments and prepares a proposal that adds a Single
  Asset block with the first attachment. Nothing here bypasses the tools, so
  the admin exercises the same validation, storage and review path as with a
  real model.
  """
  alias ReqLLM.{Context, Message, Response, ToolCall}
  alias ReqLLM.Message.ContentPart

  def generate_text(model, %Context{messages: messages} = context, _opts) do
    reply =
      case List.last(messages) do
        %Message{role: :user} = message -> start(text(message))
        %Message{role: :tool} -> continue(results(messages), user_text(messages))
      end

    {:ok, response(model, context, reply)}
  end

  defp start(text) do
    case Regex.run(~r/(?:on|to) the (.+?) page/i, text) do
      [_, title] -> {:call, "search_entries", %{"query" => title, "content_type" => "Brando.Pages.Page"}}
      nil -> {:text, "Which page should the media go on?"}
    end
  end

  defp continue(results, request) do
    cond do
      results["prepare_proposal"] ->
        case results["prepare_proposal"] do
          %{"applicable" => true} ->
            {:text,
             "I prepared a proposal that adds #{attachment(results)} to #{page(results)["title"]}. " <>
               "The page is published, so the change goes live when you apply it."}

          %{"error" => error} ->
            {:text, "I could not prepare the proposal: #{error}"}

          %{"problems" => problems} ->
            {:text, "The proposal has problems: " <> Enum.map_join(problems, "; ", & &1["message"])}
        end

      results["list_attachments"] ->
        module = Enum.find(results["list_modules"]["modules"], &(&1["name"] == "Single Asset"))
        summary = if request =~ ~r/instead/i, do: "Add the media, adjusted", else: "Add the media"

        {:call, "prepare_proposal",
         %{
           "summary" => "#{summary} to #{page(results)["title"]}" <> case_summary(request),
           "operations" =>
             [
               %{
                 "op" => "insert_block",
                 "target" => %{"content_type" => "Brando.Pages.Page", "id" => page(results)["id"]},
                 "module" => module["module"],
                 "media" => %{"media" => attachment(results)}
               }
             ] ++ case_operations(request, module, results)
         }}

      results["list_modules"] ->
        {:call, "list_attachments", %{}}

      results["search_entries"] ->
        case page(results) do
          nil -> {:text, "I could not find that page."}
          _ -> {:call, "list_modules", %{"content_type" => "Brando.Pages.Page"}}
        end
    end
  end

  # "… and create a case called Sommerro with image2" adds a draft case whose
  # listing image and first block use that attachment.
  defp case_operations(request, module, results) do
    with [_, title, alias] <- Regex.run(~r/case called (\w+) with (\w+)/i, request),
         %{"id" => id} <- Enum.find(results["list_attachments"]["attachments"], &(&1["alias"] == alias)) do
      [
        %{
          "op" => "create_entry",
          "content_type" => "E2eProject.Projects.Project",
          "ref" => "case",
          "fields" => %{
            "title" => title,
            "slug" => String.downcase(title),
            "language" => "en",
            "introduction" => "<p>#{title}</p>",
            "listing_image_id" => id
          }
        },
        %{
          "op" => "insert_block",
          "target" => %{"new" => "case"},
          "module" => module["module"],
          "media" => %{"media" => alias}
        }
      ]
    else
      _ -> []
    end
  end

  defp case_summary(request) do
    case Regex.run(~r/case called (\w+)/i, request) do
      [_, title] -> ", and create the #{title} case"
      _ -> ""
    end
  end

  defp page(results), do: List.first(results["search_entries"]["entries"] || [])

  defp attachment(results) do
    case results["list_attachments"]["attachments"] do
      [%{"alias" => alias} | _] -> alias
      _ -> "image1"
    end
  end

  # The latest result of each tool, decoded, since the last user message.
  defp results(messages) do
    turn = messages |> Enum.reverse() |> Enum.take_while(&(&1.role != :user)) |> Enum.reverse()

    names =
      for %Message{role: :assistant, tool_calls: calls} <- turn, calls, call <- calls, into: %{} do
        {call.id, ToolCall.name(call)}
      end

    for %Message{role: :tool} = message <- turn, into: %{} do
      {names[message.tool_call_id] || message.name, Jason.decode!(text(message))}
    end
  end

  defp user_text(messages) do
    messages |> Enum.reverse() |> Enum.find(&(&1.role == :user)) |> text()
  end

  defp text(%Message{content: parts}) when is_list(parts),
    do: parts |> Enum.filter(&(&1.type == :text)) |> Enum.map_join(& &1.text)

  defp text(%Message{content: content}) when is_binary(content), do: content

  defp response(model, context, {:call, name, args}) do
    call = ToolCall.new("call_" <> Integer.to_string(System.unique_integer([:positive])), name, Jason.encode!(args))
    build(model, context, %Message{role: :assistant, content: [], tool_calls: [call]}, :tool_calls)
  end

  defp response(model, context, {:text, text}),
    do: build(model, context, %Message{role: :assistant, content: [ContentPart.text(text)]}, :stop)

  defp build(model, context, message, finish_reason) do
    %Response{
      id: "e2e-" <> Integer.to_string(System.unique_integer([:positive])),
      model: model,
      context: context,
      message: message,
      usage: %{input_tokens: 800, output_tokens: 60},
      finish_reason: finish_reason
    }
  end
end
