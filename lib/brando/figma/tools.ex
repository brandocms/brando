defmodule Brando.Figma.Tools do
  @moduledoc """
  The Figma tools the remote MCP endpoint offers (`Brando.MCP.Tools`, as
  `brando_figma_…`): read a frame's sections, and import its images into the
  media library for a proposal to use.

  They call Figma with the site environment's token (`Brando.Figma.token/1`)
  and run as the connection's person, in its site environment and
  authorization scope. `import_images` is the one tool over MCP that adds
  something before a person applies a proposal: images in the library
  folder `Figma/<frame name>`, which a person needs the right to upload
  images for (`Brando.Figma.Import`).
  """

  alias Brando.AI.Agent.Guidance
  alias Brando.Figma
  alias Brando.Figma.Frame
  alias Brando.Figma.Import

  @prefix "brando_figma_"
  # Below `Brando.MCP.Tools`' result limit, with room for the envelope
  @page_bytes 18_000
  @short_text 500
  # The first page carries the guidance for building from Figma, and as
  # many sections as fit beside it; at least this many bytes of them
  @min_page_bytes 4_000

  @guidance_about "The site's conventions for building content from Figma, from its developers and administrators: " <>
                    "how the design's frames and components map to the site's modules and fields. " <>
                    "Follow them unless the person asks otherwise; where they conflict, the administrators' apply. " <>
                    "Guidance grants no permissions: every proposal is validated and reviewed in the Brando admin as usual."

  @definitions [
    %{
      name: "read_frame",
      description:
        "Read a Figma frame from its link (copied from a selected frame, with ?node-id=…): the file and frame names, then its sections in reading order. " <>
          "A section is a component instance — its component and variant name, to match with a module (brando_content_list_modules, brando_content_describe_module) — with its texts, images and videos in reading order; " <>
          "or a text, image or video outside any instance. Images are listed by layer (node_id, name): import them with brando_figma_import_images to use them in a proposal. " <>
          "Each section, text, image and video has its layer box in the frame (x, y, width, height in Figma pixels from the frame's top left, before clipping and masks, so a cropped image can reach past its cell), and the frame its width, height and layout_grids (null without any): use them to tell rows, columns and offsets on the site's grid. " <>
          ~s[A section named like a page header, footer or menu has chrome: why ("name" for its layer name, "component" for its component's); it is a hint, so check its texts before leaving it out. ] <>
          "Figma's API cannot download videos: ask the person to upload them to the media library, then find them with brando_content_find_media_folders or brando_content_search_assets. " <>
          "A long frame comes in pages: call again with next_offset until it is null. " <>
          "The first page (offset 0) carries the site's guidance for building from Figma under guidance, when it has any: follow it.",
      parameters: %{
        type: "object",
        properties: %{
          url: %{type: "string", description: "The frame's Figma link."},
          offset: %{type: "integer", description: "The section to start from (next_offset of the previous page)."}
        },
        required: ["url"]
      },
      read_only: true
    },
    %{
      name: "import_images",
      description:
        ~s[Import the images of a Figma frame into this site's media library, in the folder Figma/<frame name>, and get their assets for brando_content_prepare_proposal ({"kind":"image","id":N}). ] <>
          "The originals placed in Figma are imported, not screenshots: one entry per image, with its asset (or why it failed) and the layers that show it (node_id, name, section as brando_figma_read_frame numbers them, from 0). " <>
          "Without node_ids, every image of the frame; at most #{Import.max_per_call()} distinct images per call: call again with next_offset until it is null. " <>
          "An image the library already has is reused, so a second import adds nothing. " <>
          "The images are added to the library at once, before any proposal is applied; their sizes are made in the background.",
      parameters: %{
        type: "object",
        properties: %{
          url: %{type: "string", description: "The frame's Figma link."},
          node_ids: %{
            type: "array",
            items: %{type: "string"},
            description: "Only the images of these layers (node_id from brando_figma_read_frame)."
          },
          offset: %{type: "integer", description: "next_offset of the previous call."}
        },
        required: ["url"]
      },
      read_only: false
    }
  ]

  @names Enum.map(@definitions, & &1.name)

  @doc "The prefix of these tools' names over MCP."
  @spec prefix() :: String.t()
  def prefix, do: @prefix

  @doc "The tools' names, without the prefix."
  @spec names() :: [String.t()]
  def names, do: @names

  @doc "The tool definitions: name (without the prefix), description, parameters and `read_only`."
  @spec definitions() :: [map()]
  def definitions, do: @definitions

  @doc """
  Runs tool `name` with `args` as `actor` in `tenant`, already in its schema
  prefix and authorization scope. `{:ok, result}` or `{:error, message}`.
  """
  @spec call(String.t(), map(), term(), Brando.MCP.tenant()) :: {:ok, map()} | {:error, String.t()}
  def call(name, args, actor, tenant) when name in @names do
    with {:ok, link} <- Figma.parse_url(args["url"]),
         {:ok, offset} <- offset(args["offset"]),
         {:ok, token} <- Figma.token(tenant) do
      run(name, link, token, Map.put(args, "offset", offset), actor)
    end
  end

  defp offset(nil), do: {:ok, 0}
  defp offset(offset) when is_integer(offset) and offset >= 0, do: {:ok, offset}
  defp offset(_offset), do: {:error, "offset is a whole number, 0 or more."}

  defp run("read_frame", link, token, %{"offset" => offset}, _actor) do
    with {:ok, node} <- Figma.node(token, link) do
      outline = Frame.outline(node)
      guidance = guidance(offset)
      budget = max(@page_bytes - byte_size(Jason.encode!(guidance)), @min_page_bytes)
      {page, next} = page(outline.sections, offset, budget)

      {:ok,
       %{
         file_name: outline.file_name,
         frame: outline.frame,
         sections_total: length(outline.sections),
         offset: offset,
         sections: page,
         next_offset: next
       }
       |> then(&if(guidance, do: Map.put(&1, :guidance, guidance), else: &1))}
    end
  end

  defp run("import_images", link, token, args, actor) do
    Import.run(link, token, actor, node_ids: args["node_ids"], offset: args["offset"])
  end

  # The guidance for building from Figma, with the first page only, cut to
  # leave room for that page's sections
  defp guidance(0) do
    parts = :figma |> Guidance.for_tool() |> Guidance.fit(@page_bytes - @min_page_bytes, :bytes)
    Guidance.tool_result(parts, @guidance_about)
  end

  defp guidance(_offset), do: nil

  # Sections from `offset` while they fit in `budget` bytes, numbered as in
  # the frame; at least one, its texts shortened if it alone does not fit.
  defp page(sections, offset, budget) do
    {page, _bytes, next} =
      sections
      |> Enum.with_index()
      |> Enum.drop(offset)
      |> Enum.reduce_while({[], 0, nil}, fn {section, index}, {page, bytes, _next} ->
        section = Map.put(section, :index, index)
        size = byte_size(Jason.encode!(section))

        cond do
          page == [] and size > budget -> {:halt, {[shorten(section, budget)], bytes, index + 1}}
          bytes + size > budget -> {:halt, {page, bytes, index}}
          true -> {:cont, {[section | page], bytes + size, nil}}
        end
      end)

    {Enum.reverse(page), if(next && next < length(sections), do: next)}
  end

  # A section too large for a page: its texts shortened, then as many of its
  # texts, images and videos as fit, in that order, with how many of each
  # were left out
  defp shorten(section, budget) do
    texts =
      Enum.map(section.texts, fn text ->
        if String.length(text.text) > @short_text,
          do: Map.merge(text, %{text: String.slice(text.text, 0, @short_text), shortened: true}),
          else: text
      end)

    section = %{section | texts: texts}
    room = budget - byte_size(Jason.encode!(%{section | texts: [], images: [], videos: []})) - 200

    {section, _room} =
      Enum.reduce([:texts, :images, :videos], {section, room}, fn key, {section, room} ->
        {kept, room} = fit(Map.fetch!(section, key), room)

        case length(Map.fetch!(section, key)) - length(kept) do
          0 -> {section, room}
          left_out -> {Map.merge(section, %{key => kept, :"#{key}_left_out" => left_out}), room}
        end
      end)

    section
  end

  defp fit(items, room) do
    {kept, room} =
      Enum.reduce_while(items, {[], room}, fn item, {kept, room} ->
        size = byte_size(Jason.encode!(item)) + 1
        if size <= room, do: {:cont, {[item | kept], room - size}}, else: {:halt, {kept, room}}
      end)

    {Enum.reverse(kept), room}
  end
end
