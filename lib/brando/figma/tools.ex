defmodule Brando.Figma.Tools do
  @moduledoc """
  The Figma tools the remote MCP endpoint offers (`Brando.MCP.Tools`, as
  `brando_figma_…`): read a frame's sections, import its images into the
  media library for a proposal to use, and check the site's Figma token
  (`status`).

  They call Figma with the site environment's token (`Brando.Figma.token/1`)
  and run as the connection's person, in its site environment and
  authorization scope. `import_images` is the one tool over MCP that adds
  something before a person applies a proposal: images in the library
  folder `figma/<frame name as a slug>`, which a person needs the right to upload
  images for (`Brando.Figma.Import`).

  In the token's last `Brando.Figma.warning_days/0` days by the expiry date
  recorded with it, `read_frame` and `import_images` carry a `token_note` for
  the tool to pass on. A passed date stops nothing: Figma decides.
  """

  alias Brando.AI.Agent.Guidance
  alias Brando.Figma
  alias Brando.Figma.Frame
  alias Brando.Figma.Import
  alias Brando.MCP
  alias Brando.MCP.Tools, as: MCPTools

  @prefix "brando_figma_"
  # Below `Brando.MCP.Tools`' result limit, with room for the envelope
  @page_bytes 18_000
  @short_text 500

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
          "Each image has its scale_mode (fill, fit, crop or tile), its crop when cropped ({x, y, width, height} as fractions of the image, from its top left) its rotation when turned (clockwise, in degrees), and mirrored: true when a crop flips it (it then has no rotation). " <>
          "A layer whose top image fill covers it (opaque, unblended, and filled, or cropped to reach every corner of the layer) is one image. " <>
          "A layer whose top fill is translucent, blended, fit, tiled or cropped short of an edge lists every image that shows, in fill order, and its section says so under note. " <>
          "The image fills that do not show (under one that covers, or at no opacity) are listed under the bottom image's hidden_fills (their image_ref); they are not imported, so mention them only if the person asks about a layer's other pictures. " <>
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
        ~s[Import the images of a Figma frame into this site's media library, in the folder figma/<frame name as a slug>, and get their assets for brando_content_prepare_proposal ({"kind":"image","id":N}). ] <>
          "The originals placed in Figma are imported, not screenshots: one entry per image, with its asset (or why it failed) and the layers that show it (node_id, name, section as brando_figma_read_frame numbers them, from 0). " <>
          "Without node_ids, every image of the frame; at most #{Import.max_per_call()} distinct images per call: call again with next_offset until it is null. " <>
          "Only the images read_frame lists are imported, not hidden_fills. " <>
          "An image shown turned 90, 180 or 270° is imported as a turned copy; another angle, a mirrored crop and the turn of an animated GIF or WebP are not applied. A cropped image keeps its whole file, with its focal point set so the site, its cropped sizes and its share cards show the crop Figma shows (exactly, in a box of the layer's proportions, when the crop spans the image's width or height; a crop that zooms in on both shows with more of the image around it). " <>
          "Each entry says what was applied and what was not (applied, not_applied), in words to pass on to the person; when several layers show the image, what one of them missed names that layer. " <>
          "An image the library already has is reused, so a second import adds nothing; a reused image keeps its own focal point. " <>
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
    },
    %{
      name: "status",
      description:
        "Check the site's Figma token before starting from a Figma frame: whether one is set (token_set), " <>
          "and its state as Figma answers now: valid (with the handle of the Figma account it belongs to), expired, invalid " <>
          "(with Figma's own words under figma_error), no_account_scope (the token may not read its own account, so it " <>
          "could not be checked; it may still read files), unreachable (Figma could not be asked; try again later), " <>
          "or unreadable (stored but no longer decryptable). expires_on is the expiry date an administrator recorded " <>
          "when saving the token, or null when none was. message says it all in words to pass on to the person: " <>
          "when the token needs replacing, tell them an administrator replaces it in the Brando admin.",
      parameters: %{type: "object", properties: %{}},
      read_only: true
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
  def call("status", _args, _actor, tenant), do: {:ok, status(tenant)}

  def call(name, args, actor, tenant) when name in @names do
    with {:ok, link} <- Figma.parse_url(args["url"]),
         {:ok, offset} <- offset(args["offset"]),
         {:ok, token} <- Figma.token(tenant) do
      run(name, link, token, Map.put(args, "offset", offset), actor, tenant)
    end
  end

  defp offset(nil), do: {:ok, 0}
  defp offset(offset) when is_integer(offset) and offset >= 0, do: {:ok, offset}
  defp offset(_offset), do: {:error, "offset is a whole number, 0 or more."}

  defp run("read_frame", link, token, %{"offset" => offset}, _actor, tenant) do
    with {:ok, node} <- Figma.node(token, link) do
      outline = Frame.outline(node)
      {page, next} = page(outline.sections, offset, @page_bytes)

      result =
        with_expiry_note(
          %{
            file_name: outline.file_name,
            frame: outline.frame,
            sections_total: length(outline.sections),
            offset: offset,
            sections: page,
            next_offset: next
          },
          tenant
        )

      {:ok, if(offset == 0, do: with_guidance(result), else: result)}
    end
  end

  defp run("import_images", link, token, args, actor, tenant) do
    with {:ok, result} <- Import.run(link, token, actor, node_ids: args["node_ids"], offset: args["offset"]) do
      {:ok, with_expiry_note(result, tenant)}
    end
  end

  # In the token's last days, a note for the tool to pass on. Before the
  # guidance, which is cut to the room left.
  defp with_expiry_note(result, tenant) do
    case Figma.expiry_note(tenant) do
      nil -> result
      note -> Map.put(result, :token_note, note)
    end
  end

  @connect_token "An administrator adds a Figma access token under Configuration → Integrations → Connected AI tools."
  @replace_token "An administrator replaces it under Configuration → Integrations → Connected AI tools."

  # What `brando_figma_status` answers: never the token, its hint or an email
  defp status(tenant) do
    case MCP.figma_token_status(tenant) do
      nil ->
        %{
          token_set: false,
          message: "No Figma token is set for this site, so the Figma tools cannot read Figma. " <> @connect_token
        }

      stored ->
        expires_on = stored.expires_on
        {state, fields, said} = state(Figma.check_token(tenant))
        message = Enum.join([said, expiry_sentence(Figma.expiry(expires_on), state)], " ")

        Map.merge(
          %{token_set: true, state: state, expires_on: expires_on && Date.to_iso8601(expires_on), message: message},
          fields
        )
    end
  end

  defp state({:valid, nil}), do: {"valid", %{handle: nil}, "The site's Figma token works."}

  defp state({:valid, handle}),
    do: {"valid", %{handle: handle}, "The site's Figma token works. It belongs to the Figma account “#{handle}”."}

  defp state({:expired, err}),
    do: {"expired", %{figma_error: err}, "The site's Figma token has expired. " <> @replace_token}

  defp state({:invalid, err}) do
    said = if err, do: " Figma said: “#{err}”.", else: ""
    {"invalid", %{figma_error: err}, "Figma does not accept the site's token." <> said <> " " <> @replace_token}
  end

  defp state({:no_account_scope, err}) do
    {"no_account_scope", %{figma_error: err},
     "The site's Figma token could not be checked: it may not read its own Figma account " <>
       "(Figma's current_user:read scope), which the check asks for. It may still read files, " <>
       "so try the Figma tools; for the check to work, an administrator replaces it with a token that also has current_user:read."}
  end

  defp state(:unreachable),
    do: {"unreachable", %{}, "Figma could not be reached to check the site's token. Try again in a moment."}

  # Stored, but the tools have no token to call with
  defp state(:no_token) do
    {"unreadable", %{},
     "The site's Figma token can no longer be decrypted, as after a change of the site's encryption secret, " <>
       "so the Figma tools cannot reach Figma. " <> @replace_token}
  end

  defp expiry_sentence(:not_recorded, _state), do: "No expiry date was recorded when it was saved."

  defp expiry_sentence({:later, date}, _state),
    do: "It expires on #{Date.to_iso8601(date)}, by the date recorded with it."

  defp expiry_sentence({:soon, date, days}, _state),
    do: Figma.expiry_text(date, days) <> " It needs replacing before then."

  defp expiry_sentence({:passed, date}, "valid"),
    do: "The expiry date recorded with it, #{Date.to_iso8601(date)}, has passed, but Figma still accepts it."

  defp expiry_sentence({:passed, date}, _state),
    do: "The expiry date recorded with it was #{Date.to_iso8601(date)}."

  # The first page carries the guidance for building from Figma. Its
  # sections are the ones a page without guidance would have, so guidance
  # never shortens one: the last ones move to the next page to make room,
  # and what still does not fit beside the first section is cut from the
  # guidance. (A page with no sections would have to point back at itself.)
  defp with_guidance(result) do
    case Guidance.for_tool(:figma) do
      [] ->
        result

      parts ->
        # What the whole guidance adds to a result, with the comma before it
        added = byte_size(Jason.encode!(Guidance.put_tool_result(%{}, parts, @guidance_about, :infinity))) - 1
        result |> make_room(added) |> Guidance.put_tool_result(parts, @guidance_about, MCPTools.result_limit())
    end
  end

  defp make_room(%{sections: [_, _ | _] = sections} = result, added) do
    if byte_size(Jason.encode!(result)) + added <= MCPTools.result_limit() do
      result
    else
      {kept, [moved]} = Enum.split(sections, -1)
      make_room(%{result | sections: kept, next_offset: moved.index}, added)
    end
  end

  defp make_room(result, _added), do: result

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
