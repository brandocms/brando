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
  """

  @text_limit 4_000

  @type image :: %{
          node_id: String.t(),
          name: String.t(),
          image_ref: String.t(),
          width: integer() | nil,
          height: integer() | nil,
          section: non_neg_integer()
        }

  @doc """
  The sections of the frame in `node` (from `Brando.Figma.node/2`), with its
  name, size and file name.
  """
  @spec outline(map()) :: map()
  def outline(%{document: document} = node) do
    %{
      file_name: node.file_name,
      frame: %{node_id: document["id"], name: document["name"]} |> Map.merge(size(document)),
      sections: sections(node)
    }
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
    names = %{components: node.components, component_sets: node.component_sets}

    document
    |> events(nil, [])
    |> Enum.reverse()
    |> group(names)
    |> Enum.map(&finish(&1, Keyword.get(opts, :keep_refs, false)))
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

  defp group(events, names) do
    {sections, _open} =
      Enum.reduce(events, {[], nil}, fn
        {:instance, node}, {sections, _open} ->
          {[instance_section(node, names) | sections], node["id"]}

        {_kind, _node, nil} = event, {sections, _open} ->
          {[add(loose_section(event), event) | sections], nil}

        {_kind, _node, outer} = event, {[%{node_id: outer} = section | rest], open} ->
          {[add(section, event) | rest], open}
      end)

    Enum.reverse(sections)
  end

  defp instance_section(node, names) do
    component = names.components[node["componentId"]] || %{}
    set = names.component_sets[component["componentSetId"]]

    %{
      kind: "component",
      node_id: node["id"],
      name: node["name"],
      component: (set && set["name"]) || component["name"],
      variant: set && component["name"],
      texts: [],
      images: [],
      videos: []
    }
  end

  defp loose_section({kind, node, nil}) do
    kind = if is_tuple(kind), do: elem(kind, 0), else: kind
    %{kind: to_string(kind), node_id: node["id"], name: node["name"], texts: [], images: [], videos: []}
  end

  defp add(section, {:text, node, _outer}) do
    text = String.slice(node["characters"] || "", 0, @text_limit)
    %{section | texts: [%{node_id: node["id"], name: node["name"], text: text} | section.texts]}
  end

  defp add(section, {{:image, ref}, node, _outer}) do
    image = Map.merge(%{node_id: node["id"], name: node["name"], image_ref: ref}, size(node))
    %{section | images: [image | section.images]}
  end

  defp add(section, {:video, node, _outer}) do
    %{section | videos: [%{node_id: node["id"], name: node["name"]} | section.videos]}
  end

  defp finish(section, keep_refs?) do
    images = Enum.reverse(section.images)
    images = if keep_refs?, do: images, else: Enum.map(images, &Map.delete(&1, :image_ref))

    section
    |> Map.merge(%{texts: Enum.reverse(section.texts), images: images, videos: Enum.reverse(section.videos)})
    |> Map.reject(fn {_key, value} -> is_nil(value) end)
  end

  defp size(%{"absoluteBoundingBox" => %{"width" => width, "height" => height}})
       when is_number(width) and is_number(height),
       do: %{width: round(width), height: round(height)}

  defp size(_node), do: %{}
end
