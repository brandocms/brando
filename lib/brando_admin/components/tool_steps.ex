defmodule BrandoAdmin.Components.ToolSteps do
  @moduledoc """
  What a content tool call did, in a line an editor reads: "Searched for
  “Ident” in Pages", "Read the Figma frame “Home”". The Assistant shows its
  steps with it, and the live page of a connected tool
  (`BrandoAdmin.MCP.WatchLive`) the calls of that tool.

  `label/3` takes the tool's name without a prefix, its arguments and what
  of its result names the subject (all string-keyed, any JSON), and returns
  the line's parts: plain text, and the values in it marked as a term, a
  content type or a strong word. `text/1` renders them.
  """
  use BrandoAdmin, :component
  use Gettext, backend: Brando.Gettext

  @doc """
  The parts of the line for tool `name`, called with `args`, that returned
  `result`. With `failed: true`, the line says the call did not work.
  """
  @spec label(String.t(), map(), map(), keyword()) :: [{:text | :term | :type | :strong, String.t()}]
  def label(name, args, result, opts \\ []) when is_map(args) and is_map(result) do
    label = step_text(name, args, result)
    label = if opts[:failed], do: gettext("%{step} (did not work)", step: label), else: label
    parts(label)
  end

  attr :parts, :list, required: true

  @doc "A line from `label/3`."
  def text(assigns) do
    ~H"""
    <.step_part :for={part <- @parts} part={part} />
    """
  end

  # One part of a step's text, without whitespace around it.
  defp step_part(%{part: {:term, _}} = assigns),
    do: ~H|<span class="assistant-step-term"><.step_words text={elem(@part, 1)} /></span>|

  defp step_part(%{part: {:type, _}} = assigns),
    do: ~H|<span class="assistant-step-type"><.step_words text={elem(@part, 1)} /></span>|

  defp step_part(%{part: {:strong, _}} = assigns), do: ~H|<strong><.step_words text={elem(@part, 1)} /></strong>|
  defp step_part(assigns), do: ~H"<.step_words text={elem(@part, 1)} />"

  # Keep the complete text in the DOM for assistive technology and wrapping.
  # Only the opacity of new words is animated; no simulated streamed text.
  defp step_words(assigns) do
    ~H"""
    <span :for={[word] <- Regex.scan(~r/\S+\s*|\s+/u, @text)} class="assistant-step-word">{word}</span>
    """
  end

  # Values in a step are marked where they are bound, so a translation can
  # move them, and styled when the finished text is split into its parts.
  @mark "\u{E000}"

  defp term(value), do: "#{@mark}term:#{clean(value)}#{@mark}"
  defp type(value), do: "#{@mark}type:#{clean(value)}#{@mark}"
  defp strong(value), do: "#{@mark}strong:#{clean(value)}#{@mark}"

  # These come from stored tool results and the model's arguments: any JSON.
  defp clean(value) when is_binary(value), do: String.replace(value, @mark, "")
  defp clean(value) when is_number(value), do: to_string(value)
  defp clean(_value), do: ""

  defp parts(label) do
    label
    |> String.split(@mark)
    |> Enum.with_index()
    |> Enum.reject(&(elem(&1, 0) == ""))
    |> Enum.map(fn
      {part, index} when rem(index, 2) == 1 ->
        marked_part(part)

      {part, _} ->
        {:text, part}
    end)
    |> hug_quotes()
  end

  defp marked_part("term:" <> text), do: {:term, text}
  defp marked_part("type:" <> text), do: {:type, text}
  defp marked_part("strong:" <> text), do: {:strong, text}
  defp marked_part(text), do: {:text, text}

  # Quotes stay in the same run as the term they enclose: split across
  # elements, a font's kerning between « and the first letter is lost.
  @opening ~w(« “ " ‘ ‹)
  @closing ~w(» ” " ’ ›)

  defp hug_quotes([{:text, before}, {:term, term}, {:text, rest} | tail]) do
    {before, open} = split_last(before, @opening)
    {close, rest} = split_first(rest, @closing)
    parts = [{:text, before}, {:term, open <> term <> close}, {:text, rest}]
    Enum.reject(parts, &(elem(&1, 1) == "")) ++ hug_quotes(tail)
  end

  defp hug_quotes([{:term, _} = term, {:text, rest} | tail]) do
    {close, rest} = split_first(rest, @closing)
    [{:term, elem(term, 1) <> close} | Enum.reject([{:text, rest}], &(elem(&1, 1) == ""))] ++ hug_quotes(tail)
  end

  defp hug_quotes([part | tail]), do: [part | hug_quotes(tail)]
  defp hug_quotes([]), do: []

  defp split_last(text, marks) do
    last = String.last(text)
    if last in marks, do: {String.slice(text, 0..-2//1), last}, else: {text, ""}
  end

  defp split_first(text, marks) do
    first = String.first(text)
    if first in marks, do: {first, String.slice(text, 1..-1//1)}, else: {"", text}
  end

  # The words left out (`BrandoAdmin.MCP.WatchLive`, for someone who may not
  # read what they found)
  defp step_text("search_entries", %{"query" => :hidden} = args, _) do
    case args["content_type"] && content_type_plural(args["content_type"]) do
      nil -> gettext("Searched the entries")
      type -> gettext("Searched %{type}", type: type(type))
    end
  end

  defp step_text("search_entries", args, _) do
    query = if is_binary(args["query"]), do: String.trim(args["query"]), else: ""
    type = args["content_type"] && content_type_plural(args["content_type"])

    cond do
      query == "" and type -> gettext("Listed %{type}", type: type(type))
      query == "" -> gettext("Listed entries")
      type -> gettext("Searched for “%{query}” in %{type}", query: term(query), type: type(type))
      true -> gettext("Searched for “%{query}”", query: term(query))
    end
  end

  defp step_text("entry_outline", _args, %{"title" => title}) when is_binary(title),
    do: gettext("Read “%{title}”", title: term(title))

  defp step_text("entry_outline", _args, _), do: gettext("Read an entry")
  defp step_text("list_content_types", _, _), do: gettext("Looked at the content types")

  defp step_text("describe_content_type", args, _),
    do: gettext("Checked the fields of %{type}", type: type(content_type_label(args["content_type"])))

  defp step_text("list_modules", args, _),
    do: gettext("Looked at the modules for %{type}", type: type(content_type_label(args["content_type"])))

  defp step_text("describe_module", args, _) do
    case module_name(args["module"]) do
      nil -> gettext("Checked a module's slots")
      name -> gettext("Checked the module “%{module}”", module: term(name))
    end
  end

  defp step_text("list_attachments", _, _), do: gettext("Matched the attached media")
  defp step_text("list_selection_options", _, _), do: gettext("Looked at the entries a block can show")
  defp step_text("list_entry_media", _, _), do: gettext("Looked at an entry's media")

  defp step_text("look_at_media", _, %{"media" => media}) when is_list(media),
    do: ngettext("Looked at %{count} picture", "Looked at %{count} pictures", length(media))

  defp step_text("look_at_media", _, _), do: gettext("Looked at pictures")

  defp step_text("search_assets", %{"query" => query}, _) when is_binary(query) and query != "",
    do: gettext("Searched the media library for “%{query}”", query: term(query))

  defp step_text("search_assets", _, _), do: gettext("Searched the media library")

  defp step_text("find_media_folders", %{"name" => name}, _) when is_binary(name),
    do: gettext("Looked for the folder “%{name}”", name: term(name))

  defp step_text("find_media_folders", _, _), do: gettext("Looked for the folder")

  defp step_text("attach_folder", _, %{"folder" => %{"path" => path}, "attached" => attached}) when is_list(attached),
    do:
      ngettext("Attached %{count} item from %{folder}", "Attached %{count} items from %{folder}", length(attached),
        folder: term(path)
      )

  defp step_text("attach_folder", _, _), do: gettext("Attached the folder's media")

  # The Assistant keeps the whole result; the live page, its summary
  defp step_text("prepare_proposal", args, %{"effects" => %{"replaced_images" => count}} = result)
       when not is_map_key(result, "replaced_images"),
       do: step_text("prepare_proposal", args, Map.put(result, "replaced_images", count))

  defp step_text("prepare_proposal", _, %{"version" => version, "applicable" => true, "replaced_images" => count})
       when is_integer(count) and count > 0,
       do:
         ngettext(
           "Prepared version %{version} of the proposal, replacing the file of %{count} image",
           "Prepared version %{version} of the proposal, replacing the files of %{count} images",
           count,
           version: strong(version)
         )

  defp step_text("prepare_proposal", _, %{"version" => version, "applicable" => false}),
    do: gettext("Prepared version %{version}, with problems to fix", version: strong(version))

  defp step_text("prepare_proposal", _, %{"version" => version}),
    do: gettext("Prepared version %{version} of the proposal", version: strong(version))

  defp step_text("prepare_proposal", _, _), do: gettext("Prepared the proposal")

  # A connected tool's own proposals; the live page has the count, and the cancelled version
  defp step_text("list_proposals", _, %{"proposals" => count}) when is_integer(count),
    do: ngettext("Checked %{count} of its proposals", "Checked %{count} of its proposals", count)

  defp step_text("list_proposals", _, _), do: gettext("Checked its proposals")

  defp step_text("cancel_proposal", _, %{"version" => version}) when is_integer(version),
    do: gettext("Cancelled version %{version} of a proposal", version: strong(version))

  defp step_text("cancel_proposal", _, _), do: gettext("Cancelled a proposal")

  defp step_text("preview_proposal", _, %{"shows" => "before"}),
    do: gettext("Opened a preview of a page before its proposal")

  defp step_text("preview_proposal", _, _), do: gettext("Opened a preview of a proposed page")

  # The Figma tools of a connected tool (`Brando.Figma.Tools`)
  defp step_text("read_frame", args, %{"frame" => frame}) when is_binary(frame) do
    if is_integer(args["offset"]) and args["offset"] > 0,
      do: gettext("Read more of the Figma frame “%{frame}”", frame: term(frame)),
      else: gettext("Read the Figma frame “%{frame}”", frame: term(frame))
  end

  defp step_text("read_frame", _, _), do: gettext("Read a Figma frame")

  defp step_text("import_images", _, %{"frame" => frame, "images" => count})
       when is_binary(frame) and is_integer(count),
       do:
         ngettext("Imported %{count} image from “%{frame}”", "Imported %{count} images from “%{frame}”", count,
           frame: term(frame)
         )

  defp step_text("import_images", _, _), do: gettext("Imported images from a Figma frame")

  # The media tools of a connected tool (`Brando.MCP.Media`)
  defp step_text("prepare_upload", %{"filename" => filename}, _) when is_binary(filename),
    do: gettext("Prepared to upload “%{filename}”", filename: term(filename))

  defp step_text("prepare_upload", _, _), do: gettext("Prepared an upload")

  defp step_text("finish_upload", _, %{"reused" => true}),
    do: gettext("Uploaded an image the media library already had")

  defp step_text("finish_upload", _, _), do: gettext("Uploaded an image to the media library")

  defp step_text("import_url", _, %{"reused" => true}),
    do: gettext("Imported an image the media library already had")

  defp step_text("import_url", _, _), do: gettext("Imported an image from an address")
  defp step_text(_, _, _), do: gettext("Looked at the site's content")

  defp content_type_plural(name) do
    case Brando.Content.Proposals.Codec.schema(name) do
      {:ok, schema} -> Brando.Blueprint.get_plural(schema)
      :error -> name
    end
  end

  defp content_type_label(name) do
    case Brando.Content.Proposals.Codec.schema(name) do
      {:ok, schema} -> Brando.Blueprint.get_singular(schema)
      :error -> name
    end
  end

  defp module_name(reference) do
    {origin, id} = Brando.Content.SharedLibrary.reference(reference)

    case Brando.Content.fetch_module(id, origin) do
      %{name: %{} = name} ->
        name[Gettext.get_locale(Brando.Gettext)] || name["en"] || name |> Map.values() |> List.first()

      %{name: name} ->
        name

      _ ->
        nil
    end
  rescue
    _ -> nil
  end
end
