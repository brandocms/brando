defmodule E2eProject.AssistantModel do
  @moduledoc """
  A scripted stand-in for the content assistant's model, for end-to-end tests.

  It speaks ReqLLM's `generate_text/3` contract and drives the real tools:
  for "Put image1 on the Index page" it searches for the page, lists its
  modules, reads the attachments and prepares a proposal that adds a Single
  Asset block with the first attachment. Nothing here bypasses the tools, so
  the admin exercises the same validation, storage and review path as with a
  real model.

  Without a page name it works on the entry selected in the system prompt,
  as when the conversation is opened from the block editor. "… all the images
  in the NAME folder …" finds the folder, attaches it one image per call to
  exercise paging, and adds a Single Asset block for every attached image.
  """
  alias ReqLLM.{Context, Message, Response, ToolCall}
  alias ReqLLM.Message.ContentPart

  def generate_text(model, %Context{messages: messages} = context, _opts) do
    system = Enum.find_value(messages, "", &(&1.role == :system && text(&1)))

    reply =
      case List.last(messages) do
        %Message{role: :user} = message -> start(text(message), system)
        %Message{role: :tool} -> continue(results(messages), user_text(messages), system)
      end

    {:ok, response(model, context, reply)}
  end

  defp start(text, system) do
    cond do
      folder = folder_name(text) ->
        {:call, "find_media_folders", %{"kind" => "image", "name" => folder}}

      true ->
        find_entry(text, system)
    end
  end

  defp find_entry(text, system) do
    case {Regex.run(~r/(?:on|to) the (.+?) page/i, text), selected(system)} do
      {[_, title], _} -> {:call, "search_entries", %{"query" => title, "content_type" => "Brando.Pages.Page"}}
      {nil, %{} = entry} -> {:call, "entry_outline", entry}
      {nil, nil} -> {:text, "Which page should the media go on?"}
    end
  end

  defp folder_name(text) do
    case Regex.run(~r/images in the (\S+) folder/i, text) do
      [_, name] -> name
      nil -> nil
    end
  end

  # The entry the conversation was opened for, from the system prompt.
  defp selected(system) do
    with [_, type] <- Regex.run(~r/^- content_type: (\S+)$/m, system),
         [_, id] <- Regex.run(~r/^- id: (\d+)$/m, system) do
      %{"content_type" => type, "id" => String.to_integer(id)}
    else
      _ -> nil
    end
  end

  defp continue(results, request, system) do
    cond do
      folder = results["find_media_folders"] && !results["search_entries"] && !results["entry_outline"] ->
        attach_folder(folder, results, request, system)

      true ->
        continue(results, request)
    end
  end

  defp attach_folder(_, results, request, system) do
    case {results["find_media_folders"]["folders"], results["attach_folder"]} do
      {[], _} ->
        {:text, "I could not find that folder."}

      {[_, _ | _] = folders, _} ->
        {:text, "Which folder do you mean: " <> Enum.map_join(folders, ", ", & &1["path"]) <> "?"}

      {[folder], nil} ->
        {:call, "attach_folder", %{"kind" => "image", "folder_id" => folder["id"], "limit" => 1}}

      {[folder], %{"next_offset" => offset}} when is_integer(offset) ->
        {:call, "attach_folder", %{"kind" => "image", "folder_id" => folder["id"], "limit" => 1, "offset" => offset}}

      {[_folder], %{"total" => 0}} ->
        {:text, "The folder is empty."}

      {[_folder], _done} ->
        find_entry(request, system)
    end
  end

  defp continue(results, request) do
    cond do
      results["prepare_proposal"] ->
        case results["prepare_proposal"] do
          %{"applicable" => true} ->
            {:text,
             "I prepared a proposal that adds #{placed(results, request)} to #{page(results)["title"]}. " <>
               "The page is published, so the change goes live when you apply it."}

          %{"error" => error} ->
            {:text, "I could not prepare the proposal: #{error}"}

          %{"problems" => problems} ->
            {:text, "The proposal has problems: " <> Enum.map_join(problems, "; ", & &1["message"])}
        end

      results["list_attachments"] ->
        module = Enum.find(results["list_modules"]["modules"], &(&1["name"] == "Single Asset"))
        summary = if request =~ ~r/instead/i, do: "Add the media, adjusted", else: "Add the media"
        aliases = if folder_name(request), do: all_attachments(results), else: [attachment(results)]

        {:call, "prepare_proposal",
         %{
           "summary" => "#{summary} to #{page(results)["title"]}" <> case_summary(request),
           "operations" =>
             Enum.map(aliases, fn alias ->
               %{
                 "op" => "insert_block",
                 "target" => %{"content_type" => page(results)["content_type"], "id" => page(results)["id"]},
                 "module" => module["module"],
                 "media" => %{"media" => alias}
               }
             end) ++ case_operations(request, module, results)
         }}

      results["list_modules"] ->
        {:call, "list_attachments", %{}}

      results["entry_outline"] ->
        {:call, "list_modules", %{"content_type" => results["entry_outline"]["content_type"]}}

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

  defp page(%{"entry_outline" => %{} = entry}), do: entry
  defp page(results), do: List.first(results["search_entries"]["entries"] || [])

  defp placed(results, request),
    do: if(folder_name(request), do: Enum.join(all_attachments(results), ", "), else: attachment(results))

  defp all_attachments(results), do: Enum.map(results["list_attachments"]["attachments"], & &1["alias"])

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
