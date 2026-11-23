defmodule Brando.Figma.Frame do
  @moduledoc """
  A Figma frame as a model rebuilds it: its sections in reading order, each
  with the component it is an instance of, its texts and its images.

  A section is an outermost component instance: everything inside it,
  nested instances included, belongs to it. A text, image or video outside
  every instance is a section of its own. Hidden layers and paints are left
  out.

  A layer with several image fills is one image when its top fill covers it
  (opaque, unblended, and filled, or cropped so the image reaches every
  corner of the layer). One whose top fill is translucent, blended, fit,
  tiled or cropped short of an edge lists every image that shows, in fill
  order, and its section says so under `note`. The image fills that do not
  show (under one that covers, or at no opacity) are listed under the
  bottom image's `hidden_fills`. Each image has the `image_ref` of the
  picture it shows, which identifies it: layers with the same `image_ref`
  show the same picture. Each image has its `scale_mode` (`fill`,
  `fit`, `crop`, `tile`), its `crop` as fractions of the image when
  cropped, its `rotation`, clockwise in degrees, when turned, and
  `mirrored` when a crop flips it (it then has no `rotation`).

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

  # Page chrome by name: the last part of a layer or component name, after
  # any slashes, that is one of these words, or a run of them ("NavBar"),
  # with at most the qualifiers below around it ("Main navigation", "Header
  # v2"), or one of them joined to a qualifier ("Hovedmeny"). The parts
  # before it must be a library's own grouping ("Site/Header",
  # "Global/Footer"): under a module's name ("Case/Header") it is content.
  # "Menu", "meny", "topp" and "bunn" also name content (a restaurant's
  # menu, a page's opening section), so they count only on a short bar
  # across most of the frame at its top or bottom edge.
  @chrome_words ~w(header footer nav navbar navigation navigasjon topptekst bunntekst)
  @menu_words ~w(menu meny topp bunn)
  @chrome_qualifiers ~w(site page main global primary top bottom sticky mobile desktop tablet hoved bar)
  @compound_prefixes ~w(hoved topp bunn top main)
  @library_prefixes ~w(site global layout layouts shared common chrome components component ui felles nettsted)

  # Edges within this many pixels count as flush
  @edge_tolerance 1

  @type image :: %{
          required(:node_id) => String.t(),
          required(:name) => String.t(),
          required(:image_ref) => String.t(),
          required(:scale_mode) => String.t(),
          optional(:crop) => %{x: float(), y: float(), width: float(), height: float()},
          optional(:rotation) => number(),
          optional(:mirrored) => true,
          optional(:hidden_fills) => [%{image_ref: String.t()}],
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
  The frame's images that show, in reading order, each with the index of its
  section, its image ref, scale mode, and crop and rotation when it has
  them. A layer whose top image fill covers it is one entry; one that shows
  several images has one entry per image, in fill order. The image fills
  that do not show are not entries: they are under the bottom entry's
  `hidden_fills`.
  """
  @spec images(map()) :: [image()]
  def images(node) do
    for {section, index} <- Enum.with_index(sections(node)),
        image <- section.images,
        do: Map.put(image, :section, index)
  end

  defp sections(%{document: document} = node) do
    frame = %{id: document["id"], origin: origin(document), box: box(document, origin(document))}

    names = %{components: node.components, component_sets: node.component_sets}

    sections =
      document
      |> events(nil, [])
      |> Enum.reverse()
      |> group(names, frame)

    only? = match?([_], sections)
    Enum.map(sections, &finish(&1, frame, only?))
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

  # A layer's image fills as one event (the images that show, in fill
  # order, and the image fills under them that do not), then one event per
  # video fill
  defp paints(node) do
    fills = for %{"type" => _} = paint <- List.wrap(node["fills"]), paint["visible"] != false, do: paint
    images = for %{"type" => "IMAGE", "imageRef" => ref} = paint <- fills, is_binary(ref), do: paint
    videos = for %{"type" => "VIDEO"} <- fills, do: :video

    case images do
      [] -> videos
      images -> stack(images, videos)
    end
  end

  # Figma paints a layer's fills in list order, the last on top. From the
  # top down, every image fill shows until one covers the layer; the ones
  # under it are hidden, and so is one at no opacity, which shows nothing.
  # Solid and gradient fills are not counted.
  defp stack(images, videos) do
    indexed = Enum.with_index(images)

    showing =
      indexed
      |> Enum.reject(fn {paint, _index} -> paint["opacity"] in [0, +0.0] end)
      |> Enum.reverse()
      |> Enum.split_while(fn {paint, _index} -> not covers?(paint) end)
      |> case do
        {above, [cover | _below]} -> above ++ [cover]
        {above, []} -> above
      end
      |> Enum.reverse()

    shown = MapSet.new(showing, &elem(&1, 1))
    hidden = for {paint, index} <- indexed, index not in shown, do: %{image_ref: paint["imageRef"]}

    case showing do
      [] -> videos
      showing -> [{:image, %{showing: Enum.map(showing, &fill(elem(&1, 0))), hidden: hidden}} | videos]
    end
  end

  # An opaque, unblended fill that fills the layer, or a crop of it that
  # reaches every corner, leaves nothing under it to see; FIT, TILE and a
  # crop moved or shrunk inside the layer can leave part of it bare
  defp covers?(paint) do
    paint["opacity"] in [nil, 1, 1.0] and paint["blendMode"] in [nil, "NORMAL", "PASS_THROUGH"] and
      case paint["scaleMode"] do
        mode when mode in [nil, "FILL"] -> true
        "STRETCH" -> crop_covers?(matrix(paint["imageTransform"]))
        _mode -> false
      end
  end

  # Figma's transforms are rounded floats: a corner this far past the
  # image's edge is still on it
  @corner_tolerance 0.001

  defp crop_covers?(nil), do: false

  defp crop_covers?(matrix) do
    Enum.all?(corners(matrix), fn {x, y} ->
      x >= -@corner_tolerance and x <= 1 + @corner_tolerance and y >= -@corner_tolerance and y <= 1 + @corner_tolerance
    end)
  end

  # The points of the image the layer's four corners show
  defp corners({a, b, tx, c, d, ty}),
    do: for({u, v} <- [{0, 0}, {1, 0}, {0, 1}, {1, 1}], do: {a * u + b * v + tx, c * u + d * v + ty})

  # A crop that flips the image (its transform's determinant is negative)
  defp mirrored?({a, b, _tx, c, d, _ty}), do: a * d - b * c < 0
  defp mirrored?(nil), do: false

  @scale_modes %{"FILL" => "fill", "FIT" => "fit", "TILE" => "tile", "STRETCH" => "crop"}

  defp fill(paint) do
    scale_mode = Map.get(@scale_modes, paint["scaleMode"], "fill")
    matrix = if scale_mode == "crop", do: matrix(paint["imageTransform"])
    mirrored? = mirrored?(matrix)
    rotation = if mirrored?, do: 0, else: rotation(scale_mode, paint, matrix)

    %{
      image_ref: paint["imageRef"],
      scale_mode: scale_mode,
      rotation: if(rotation != 0, do: rotation),
      mirrored: if(mirrored?, do: true)
    }
    |> Map.put(:crop, matrix && crop(matrix, rotation))
    |> Map.reject(fn {_key, value} -> is_nil(value) end)
  end

  # How far the image is turned clockwise as Figma shows it, in degrees from
  # 0 up to 360, to a tenth.
  #
  # FILL, FIT and TILE: the paint's `rotation`, in degrees, in quarter turns,
  # taken as clockwise: 90 shows the image turned a quarter to the right.
  # Figma's REST spec ("Image rotation, in degrees") and plugin docs ("must
  # be in increments of +90") give no direction, and this is not checked
  # against a render by Figma. The evidence, fairly strong but indirect:
  # Figma's help centre says its Rotate 90° control turns an image fill
  # clockwise, it only turns one way, and files hold growing positive
  # values (720, 1170: one click adds 90); OpenPencil, which reads .fig
  # files and copies that control, draws +90 clockwise (its image sampling
  # test pins the pixels); Octopus (opendesigndev) negates the value but
  # then inverts the matrix it builds, so it draws +90 clockwise too. If a
  # Figma render ever shows otherwise, flip the sign in the `degrees(rotation)`
  # clause below to `degrees(-rotation)`.
  #
  # Crop (STRETCH): the turn in `imageTransform` (below); the paint's
  # `rotation` is ignored. A mirrored crop has none (see `fill/1`).
  defp rotation("crop", _paint, nil), do: 0
  defp rotation("crop", _paint, {a, _b, _tx, c, _d, _ty}), do: degrees(:math.atan2(-c, a) * 180 / :math.pi())
  defp rotation(_mode, %{"rotation" => rotation}, _matrix) when is_number(rotation), do: degrees(rotation)
  defp rotation(_mode, _paint, _matrix), do: 0

  defp degrees(degrees) do
    degrees = Float.round(:math.fmod(:math.fmod(degrees * 1.0, 360.0) + 360.0, 360.0), 1)
    degrees = if degrees == 360.0, do: 0.0, else: degrees
    if degrees == Float.round(degrees), do: round(degrees), else: degrees
  end

  # A crop's `imageTransform`, `[[a, b, tx], [c, d, ty]]`, maps a point of
  # the layer to the point of the image shown there, both as fractions of
  # their width and height from the top left (y down): the layer's (u, v)
  # shows the image's (a·u + b·v + tx, c·u + d·v + ty). So
  # `[[1, 0, 0], [0, 0.3635, 0.3453]]` shows the image's full width and the
  # band from 34.53% to 70.88% of its height. An image shown turned θ
  # clockwise has `a = cos θ` and `c = -sin θ`: a quarter turn right is
  # `[[0, 1, 0], [-1, 0, 1]]` (the layer's top left shows the image's
  # bottom left).
  defp matrix([[a, b, tx], [c, d, ty]])
       when is_number(a) and is_number(b) and is_number(tx) and is_number(c) and is_number(d) and is_number(ty),
       do: {a, b, tx, c, d, ty}

  defp matrix(_transform), do: nil

  # The part of the image the layer shows, as fractions of the image as it
  # is imported: turned by a quarter turn, otherwise as stored. Nil for the
  # whole image.
  defp crop(matrix, rotation) do
    {xs, ys} = matrix |> corners() |> Enum.map(&turn(&1, rotation)) |> Enum.unzip()
    [x, y, right, bottom] = Enum.map([Enum.min(xs), Enum.min(ys), Enum.max(xs), Enum.max(ys)], &clamp/1)
    crop = %{x: fraction(x), y: fraction(y), width: fraction(right - x), height: fraction(bottom - y)}

    if crop == %{x: 0.0, y: 0.0, width: 1.0, height: 1.0}, do: nil, else: crop
  end

  # A point of the stored image in the image turned clockwise
  defp turn({x, y}, 90), do: {1 - y, x}
  defp turn({x, y}, 180), do: {1 - x, 1 - y}
  defp turn({x, y}, 270), do: {y, 1 - x}
  defp turn(point, _rotation), do: point

  defp clamp(value), do: value |> max(0) |> min(1)
  defp fraction(value), do: Float.round(value * 1.0, 4)

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

  # The images a layer shows, bottom first. The image fills that do not
  # show (under one that covers the layer, or at no opacity) are listed as
  # hidden_fills of the bottom one; a layer that shows more than one image
  # says so in its section's note.
  defp add(section, {{:image, %{showing: showing, hidden: hidden}}, node, _outer}, origin) do
    layer = Map.merge(%{node_id: node["id"], name: node["name"]}, box(node, origin))
    [bottom | above] = Enum.map(showing, &Map.merge(layer, &1))
    bottom = if hidden != [], do: Map.put(bottom, :hidden_fills, hidden), else: bottom
    images = [bottom | above]

    section = %{section | images: Enum.reverse(images, section.images)}

    case showing do
      [_, _ | _] ->
        Map.update(section, :notes, [stacked_note(node, length(showing))], &[stacked_note(node, length(showing)) | &1])

      _one ->
        section
    end
  end

  defp add(section, {:video, node, _outer}, origin) do
    video = Map.merge(%{node_id: node["id"], name: node["name"]}, box(node, origin))
    %{section | videos: [video | section.videos]}
  end

  defp stacked_note(node, count) do
    ~s[Layer "#{node["name"]}" (#{node["id"]}) shows #{count} images stacked: the ones above are translucent, blended, fit, tiled or cropped short of an edge, so the ones under them show too.]
  end

  defp finish(section, frame, only?) do
    images = Enum.reverse(section.images)

    note =
      case Map.get(section, :notes, []) do
        [] -> nil
        notes -> notes |> Enum.reverse() |> Enum.join(" ")
      end

    section
    |> Map.merge(%{texts: Enum.reverse(section.texts), images: images, videos: Enum.reverse(section.videos)})
    |> Map.delete(:notes)
    |> Map.put(:note, note)
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
    {groups, [last]} = name |> String.split("/") |> Enum.split(-1)
    words = Enum.reject(words(last), &(&1 in @chrome_qualifiers))

    Enum.all?(groups, &library_group?/1) and words != [] and chrome_words?(words, menu_bar?)
  end

  defp chrome_name?(_name, _menu_bar?), do: false

  defp chrome_words?(words, menu_bar?) do
    terms = if menu_bar?, do: @chrome_words ++ @menu_words, else: @chrome_words
    Enum.join(words) in terms or Enum.all?(words, &term?(&1, terms))
  end

  defp term?(word, terms) do
    word in terms or
      Enum.any?(@compound_prefixes, fn prefix ->
        String.starts_with?(word, prefix) and String.replace_prefix(word, prefix, "") in terms
      end)
  end

  defp library_group?(group), do: Enum.all?(words(group), &(&1 in @library_prefixes or &1 in @chrome_qualifiers))

  # "Site/NavBar v2" → ["site", "nav", "bar"]: a single letter (a version's
  # "v") is not a word
  defp words(name) do
    ~r/\p{Lu}?\p{Ll}+|\p{Lu}+(?!\p{Ll})/u
    |> Regex.scan(name)
    |> Enum.map(&String.downcase(hd(&1)))
    |> Enum.reject(&(String.length(&1) < 2))
  end

  # Short (a bar, not a hero), across most of the frame (the part of it
  # inside the frame) and flush with its top or bottom edge, not past it
  defp menu_bar?(%{x: x, y: y, width: width, height: height}, %{width: frame_width, height: frame_height}) do
    across = min(x + width, frame_width) - max(x, 0)

    height * 4 <= min(frame_width, frame_height) and across * 4 >= frame_width * 3 and
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
