defmodule Brando.Figma.Frame do
  @moduledoc """
  A Figma frame as a model rebuilds it: its sections in reading order, each
  with the component it is an instance of, its texts and its images.

  A section is an outermost component instance: everything inside it,
  nested instances included, belongs to it. A text, image or video outside
  every instance is a section of its own. Hidden layers and paints are left
  out.

  Reading order: the children of an auto-layout frame in Figma's order (as
  laid out), others top to bottom, then left to right, by their position on
  the canvas.

  Each section, text, image and video has its layer box in the frame (`x`,
  `y`, `width`, `height`, rounded, from the frame's top left), before
  clipping and masks, and the frame its visible layout grids. A section
  named like a page header, footer or menu says why under `chrome`: its
  layer name or its component's. It is a hint: such sections are still
  listed.
  """

  @text_limit 4_000

  # Page chrome by name: a part of a layer or component name ("Site/Header",
  # "Main navigation") that is one of these words, or a run of them
  # ("NavBar"), with at most the qualifiers below around it. "Menu" and
  # "meny" also name content (a restaurant's menu), so they count only on a
  # short, wide bar at the frame's top or bottom edge.
  @chrome_words ~w(header footer nav navbar navigation navigasjon topp topptekst bunn bunntekst)
  @menu_words ~w(menu meny)
  @chrome_qualifiers ~w(site page main global primary top bottom sticky mobile desktop tablet hoved)

  # Edges within this many pixels count as flush
  @edge_tolerance 1

  @type image :: %{
          required(:node_id) => String.t(),
          required(:name) => String.t(),
          required(:image_ref) => String.t(),
          optional(:x) => integer(),
          optional(:y) => integer(),
          optional(:width) => integer(),
          optional(:height) => integer(),
          required(:section) => non_neg_integer()
        }

  @doc """
  The sections of the frame in `node` (from `Brando.Figma.node/2`), with its
  name, size, layout grids (nil without any) and file name.
  """
  @spec outline(map()) :: map()
  def outline(%{document: document} = node) do
    frame =
      %{node_id: document["id"], name: document["name"]}
      |> Map.merge(Map.take(box(document, origin(document)), [:width, :height]))
      |> Map.put(:layout_grids, layout_grids(document["layoutGrids"]))

    %{file_name: node.file_name, frame: frame, sections: sections(node)}
  end

  @doc """
  The frame's image fills in reading order, each with the index of its
  section. A layer with several image fills has one entry per fill.
  """
  @spec images(map()) :: [image()]
  def images(node) do
    for {section, index} <- Enum.with_index(sections(node, keep_refs: true)),
        image <- section.images,
        do: Map.put(image, :section, index)
  end

  defp sections(%{document: document} = node, opts \\ []) do
    frame = %{id: document["id"], origin: origin(document), box: box(document, origin(document))}

    names = %{components: node.components, component_sets: node.component_sets}

    sections =
      document
      |> events(nil, [])
      |> Enum.reverse()
      |> group(names, frame)

    only? = match?([_], sections)
    Enum.map(sections, &finish(&1, frame, only?, Keyword.get(opts, :keep_refs, false)))
  end

  # What the walk finds, as a reversed list: an outermost instance starts a
  # section; texts, images and videos say which section they are in (nil
  # outside every instance).
  defp events(%{"visible" => false}, _outer, acc), do: acc

  defp events(node, outer, acc) do
    {outer, acc} =
      if node["type"] == "INSTANCE" and is_nil(outer),
        do: {node["id"], [{:instance, node} | acc]},
        else: {outer, acc}

    acc = Enum.reduce(paints(node), acc, &[{&1, node, outer} | &2])
    acc = if node["type"] == "TEXT", do: [{:text, node, outer} | acc], else: acc

    node
    |> children()
    |> Enum.reduce(acc, &events(&1, outer, &2))
  end

  defp paints(node) do
    for %{"type" => type} = paint <- List.wrap(node["fills"]),
        paint["visible"] != false,
        type in ["IMAGE", "VIDEO"],
        type == "VIDEO" or is_binary(paint["imageRef"]),
        do: if(type == "IMAGE", do: {:image, paint["imageRef"]}, else: :video)
  end

  defp children(%{"children" => children} = node) when is_list(children) do
    if node["layoutMode"] in ["HORIZONTAL", "VERTICAL", "GRID"] do
      Enum.reject(children, &(&1["layoutPositioning"] == "ABSOLUTE")) ++
        Enum.filter(children, &(&1["layoutPositioning"] == "ABSOLUTE"))
    else
      children
      |> Enum.with_index()
      |> Enum.sort_by(fn {child, index} -> {position(child, "y"), position(child, "x"), index} end)
      |> Enum.map(&elem(&1, 0))
    end
  end

  defp children(_node), do: []

  defp position(node, axis) do
    case node["absoluteBoundingBox"] do
      %{^axis => value} when is_number(value) -> round(value)
      _ -> 0
    end
  end

  defp group(events, names, frame) do
    {sections, _open} =
      Enum.reduce(events, {[], nil}, fn
        {:instance, node}, {sections, _open} ->
          {[instance_section(node, names, frame.origin) | sections], node["id"]}

        {_kind, _node, nil} = event, {sections, _open} ->
          {[add(loose_section(event, frame.origin), event, frame.origin) | sections], nil}

        {_kind, _node, outer} = event, {[%{node_id: outer} = section | rest], open} ->
          {[add(section, event, frame.origin) | rest], open}
      end)

    Enum.reverse(sections)
  end

  defp instance_section(node, names, origin) do
    component = names.components[node["componentId"]] || %{}
    set = names.component_sets[component["componentSetId"]]

    %{
      kind: "component",
      node_id: node["id"],
      node_type: node["type"],
      name: node["name"],
      component: (set && set["name"]) || component["name"],
      variant: set && component["name"],
      texts: [],
      images: [],
      videos: []
    }
    |> Map.merge(box(node, origin))
  end

  defp loose_section({kind, node, nil}, origin) do
    kind = if is_tuple(kind), do: elem(kind, 0), else: kind

    %{
      kind: to_string(kind),
      node_id: node["id"],
      node_type: node["type"],
      name: node["name"],
      texts: [],
      images: [],
      videos: []
    }
    |> Map.merge(box(node, origin))
  end

  defp add(section, {:text, node, _outer}, origin) do
    text = String.slice(node["characters"] || "", 0, @text_limit)
    text = Map.merge(%{node_id: node["id"], name: node["name"], text: text}, box(node, origin))
    %{section | texts: [text | section.texts]}
  end

  defp add(section, {{:image, ref}, node, _outer}, origin) do
    image = Map.merge(%{node_id: node["id"], name: node["name"], image_ref: ref}, box(node, origin))
    %{section | images: [image | section.images]}
  end

  defp add(section, {:video, node, _outer}, origin) do
    video = Map.merge(%{node_id: node["id"], name: node["name"]}, box(node, origin))
    %{section | videos: [video | section.videos]}
  end

  defp finish(section, frame, only?, keep_refs?) do
    images = Enum.reverse(section.images)
    images = if keep_refs?, do: images, else: Enum.map(images, &Map.delete(&1, :image_ref))

    section
    |> Map.merge(%{texts: Enum.reverse(section.texts), images: images, videos: Enum.reverse(section.videos)})
    |> Map.put(:chrome, if(not only? and section.node_id != frame.id, do: chrome(section, frame.box)))
    |> Map.delete(:node_type)
    |> Map.reject(fn {_key, value} -> is_nil(value) end)
  end

  # Why a section looks like page chrome, or nil. Only an instance, component
  # or frame is named by its designer (Figma names a text layer after its
  # text), and a section of images with no texts is never flagged: a tool
  # leaving it out would have nothing to check first.
  defp chrome(section, frame_box) do
    menu_bar? = menu_bar?(section, frame_box)

    cond do
      section.node_type not in ["INSTANCE", "COMPONENT", "FRAME"] -> nil
      section.texts == [] and (section.images != [] or section.videos != []) -> nil
      chrome_name?(section.name, menu_bar?) -> "name"
      chrome_name?(section[:component], menu_bar?) -> "component"
      true -> nil
    end
  end

  defp chrome_name?(name, menu_bar?) when is_binary(name) do
    name
    |> String.split("/")
    |> Enum.any?(fn part ->
      words = Enum.reject(words(part), &(&1 in @chrome_qualifiers))
      words != [] and chrome_words?(words, menu_bar?)
    end)
  end

  defp chrome_name?(_name, _menu_bar?), do: false

  defp chrome_words?(words, menu_bar?) do
    terms = if menu_bar?, do: @chrome_words ++ @menu_words, else: @chrome_words
    Enum.join(words) in terms or Enum.all?(words, &(&1 in terms))
  end

  # "Site/NavBar 2" → ["site", "nav", "bar"]
  defp words(name) do
    ~r/\p{Lu}?\p{Ll}+|\p{Lu}+(?!\p{Ll})/u
    |> Regex.scan(name)
    |> Enum.map(&String.downcase(hd(&1)))
  end

  # Short (a bar, not a hero), across most of the frame and flush with its
  # top or bottom edge, not past it
  defp menu_bar?(%{y: y, width: width, height: height}, %{width: frame_width, height: frame_height}) do
    height * 4 <= min(frame_width, frame_height) and width * 4 >= frame_width * 3 and
      (abs(y) <= @edge_tolerance or abs(frame_height - (y + height)) <= @edge_tolerance)
  end

  defp menu_bar?(_section, _frame_box), do: false

  # The frame's visible layout grids, as Figma gives them; nil without any
  defp layout_grids(grids) when is_list(grids) do
    case for(
           %{"pattern" => pattern} = grid when is_binary(pattern) <- grids,
           grid["visible"] != false,
           do: layout_grid(grid)
         ) do
      [] -> nil
      grids -> grids
    end
  end

  defp layout_grids(_grids), do: nil

  defp layout_grid(%{"pattern" => "GRID"} = grid),
    do: Map.reject(%{pattern: "grid", size: number(grid["sectionSize"])}, fn {_key, value} -> is_nil(value) end)

  defp layout_grid(grid) do
    alignment = grid["alignment"]

    %{
      pattern: String.downcase(grid["pattern"]),
      count: if(is_integer(grid["count"]) and grid["count"] > 0, do: grid["count"]),
      gutter: number(grid["gutterSize"]),
      margin: if(alignment != "CENTER", do: number(grid["offset"])),
      alignment: if(is_binary(alignment), do: String.downcase(alignment)),
      # Columns stretched to fill the frame have no fixed size
      size: if(alignment != "STRETCH", do: number(grid["sectionSize"]))
    }
    |> Map.reject(fn {_key, value} -> is_nil(value) end)
  end

  defp number(value) when is_number(value), do: round(value)
  defp number(_value), do: nil

  defp origin(%{"absoluteBoundingBox" => %{"x" => x, "y" => y}}) when is_number(x) and is_number(y), do: {x, y}
  defp origin(_node), do: {0, 0}

  # The node's box from the frame's top left, with what Figma gives of it
  defp box(%{"absoluteBoundingBox" => %{} = box}, {origin_x, origin_y}) do
    [x: {"x", origin_x}, y: {"y", origin_y}, width: {"width", 0}, height: {"height", 0}]
    |> Enum.flat_map(fn {key, {field, from}} ->
      case box[field] do
        value when is_number(value) -> [{key, round(value - from)}]
        _ -> []
      end
    end)
    |> Map.new()
  end

  defp box(_node, _origin), do: %{}
end
