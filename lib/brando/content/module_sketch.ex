defmodule Brando.Content.ModuleSketch do
  @moduledoc """
  A small schematic sketch of a module, drawn by the AI from what the module
  is: its name and description, its template, its refs and vars. It shows the
  layout at a glance in the module picker and the module list, where it is
  stored as the module's `svg`.

  The model is held to a narrow style (a 60×40 canvas, four greys, simple
  shapes) with examples to copy, and whatever it returns is rebuilt from an
  allow-list of elements and attributes before it is used, so the stored SVG
  can only draw shapes.
  """

  alias Brando.Content.Module

  @view_box "0 0 60 40"
  @template_limit 3_000

  @elements ~w(svg g rect circle ellipse line polyline polygon path)

  # Lowercase, as the HTML parser gives them, to the name SVG needs.
  @attributes %{
    "viewbox" => "viewBox",
    "x" => "x",
    "y" => "y",
    "x1" => "x1",
    "y1" => "y1",
    "x2" => "x2",
    "y2" => "y2",
    "cx" => "cx",
    "cy" => "cy",
    "r" => "r",
    "rx" => "rx",
    "ry" => "ry",
    "width" => "width",
    "height" => "height",
    "points" => "points",
    "d" => "d",
    "fill" => "fill",
    "stroke" => "stroke",
    "stroke-width" => "stroke-width",
    "stroke-linecap" => "stroke-linecap",
    "stroke-linejoin" => "stroke-linejoin",
    "stroke-dasharray" => "stroke-dasharray",
    "opacity" => "opacity",
    "fill-opacity" => "fill-opacity",
    "transform" => "transform"
  }

  @style """
  You draw tiny schematic sketches of website content modules, for a picker
  where editors choose which module to insert. The sketch shows the module's
  layout, not its content: where headings, text, images and lists sit.

  Rules:
  - Reply with one <svg> element and nothing else: no prose, no code fence.
  - Use viewBox="0 0 60 40" and no width or height.
  - Use only rect, circle, line and path. No text, no gradients, no filters,
    no images, no style or class attributes.
  - Colours: #6f8177 for headings and strong elements, #9aa8a0 for body text
    lines, #cfd8d2 for images and media, #e3e9e5 for backgrounds and
    secondary areas. Nothing else.
  - Body text is a few thin rounded bars (height 2, rx 1) of varying length.
    A heading is one thicker bar (height 3.5 to 5). An image is a filled rect
    with rx 1.5. Keep a margin of about 3 units; use the whole canvas.
  - A button or link is one small filled rounded rect in #6f8177 (height 4
    to 5, rx 2): never draw its label, and never put a lighter shape on top
    of a darker one.
  - Two columns side by side if the template lays things out in columns;
    a row of equal rects for a slider or gallery, the last one cut off at the
    edge; a quote mark (a small path) before a quote.

  Examples:

  Body text, one column:
  <svg viewBox="0 0 60 40"><rect x="8" y="10" width="44" height="2" rx="1" fill="#9aa8a0"/><rect x="8" y="16" width="44" height="2" rx="1" fill="#9aa8a0"/><rect x="8" y="22" width="44" height="2" rx="1" fill="#9aa8a0"/><rect x="8" y="28" width="30" height="2" rx="1" fill="#9aa8a0"/></svg>

  Heading on the left, text on the right:
  <svg viewBox="0 0 60 40"><rect x="3" y="9" width="22" height="5" rx="1" fill="#6f8177"/><rect x="31" y="9" width="26" height="2" rx="1" fill="#9aa8a0"/><rect x="31" y="15" width="26" height="2" rx="1" fill="#9aa8a0"/><rect x="31" y="21" width="26" height="2" rx="1" fill="#9aa8a0"/><rect x="31" y="27" width="18" height="2" rx="1" fill="#9aa8a0"/></svg>

  Image slider:
  <svg viewBox="0 0 60 40"><rect x="3" y="8" width="22" height="24" rx="1.5" fill="#cfd8d2"/><rect x="28" y="8" width="22" height="24" rx="1.5" fill="#cfd8d2"/><rect x="53" y="8" width="7" height="24" rx="1.5" fill="#e3e9e5"/></svg>
  """

  @doc "Draw a sketch of `module`: `{:ok, svg}` with the SVG markup, or `{:error, reason}`."
  @spec generate(Module.t(), keyword()) :: {:ok, String.t()} | {:error, term()}
  def generate(%Module{} = module, ai_opts \\ []) do
    opts = Keyword.merge([system_prompt: @style, temperature: 0.3, max_tokens: 2_000], ai_opts)

    with {:ok, %{text: text}} <- Brando.AI.generate_text(describe(module), opts) do
      sanitize(text)
    end
  end

  @doc """
  Store `svg` as `module`'s sketch. Only the sketch changes: the module's
  output doesn't, so its entries aren't rendered again (unlike
  `Brando.Content.update_module/3`). Open pickers are told to refresh.
  """
  @spec save(Module.t(), String.t()) :: {:ok, Module.t()} | {:error, Ecto.Changeset.t()}
  def save(%Module{} = module, svg) when is_binary(svg) do
    module
    |> Ecto.Changeset.change(svg: Base.encode64(svg, padding: false))
    |> Brando.Query.Runtime.update()
    |> tap(fn
      {:ok, updated} -> Phoenix.PubSub.broadcast(Brando.pubsub(), "brando:modules", {updated, [:module, :updated]})
      _ -> :ok
    end)
  end

  @doc "Whether sketches can be drawn: the AI is enabled and has a model and key."
  def available?, do: Brando.AI.configured?()

  @doc "The prompt describing `module` to the model."
  @spec describe(Module.t()) :: String.t()
  def describe(%Module{} = module) do
    module = Brando.Repo.preload(module, [:refs, :vars])

    refs =
      Enum.map_join(module.refs, "\n", fn ref ->
        "- #{ref.name} (#{ref_type(ref)})#{if ref.description, do: ": #{ref.description}"}"
      end)

    vars = Enum.map_join(module.vars, "\n", &"- #{&1.key} (#{&1.type}): #{translations(&1.label)}")

    """
    Draw the sketch for this module.

    Name: #{translations(module.name)}
    Description: #{translations(module.help_text)}
    CSS class: #{module.class}
    #{if module.multi, do: "It holds a list of child entries, repeated in its layout.\n"}#{if module.datasource, do: "It lists entries from a datasource.\n"}
    Refs (content slots the template places):
    #{if refs == "", do: "- none", else: refs}

    Vars (settings):
    #{if vars == "", do: "- none", else: vars}

    Template:
    #{String.slice(module.code || "", 0, @template_limit)}
    """
  end

  @doc """
  The first `<svg>` in `text`, rebuilt from allowed elements and attributes
  only, with the sketch's viewBox. `{:error, :invalid_response}` when there
  is none, or nothing drawable in it.
  """
  @spec sanitize(String.t()) :: {:ok, String.t()} | {:error, :invalid_response}
  def sanitize(text) when is_binary(text) do
    with [markup] <- Regex.run(~r/<svg\b.*?<\/svg>/si, text),
         {:ok, tree} <- Floki.parse_fragment(markup),
         {"svg", _attrs, children} <- Enum.find(tree, &match?({"svg", _, _}, &1)),
         [_ | _] = shapes <- Enum.flat_map(children, &clean/1) do
      {:ok, ~s(<svg xmlns="http://www.w3.org/2000/svg" viewBox="#{@view_box}">#{Enum.join(shapes)}</svg>)}
    else
      _ -> {:error, :invalid_response}
    end
  end

  defp clean({tag, attrs, children}) when tag in @elements and tag != "svg" do
    attributes =
      for {name, value} <- attrs,
          canonical = @attributes[name],
          canonical != nil,
          safe_value?(value),
          do: ~s( #{canonical}="#{value}")

    inner = Enum.flat_map(children, &clean/1)

    if inner == [],
      do: ["<#{tag}#{Enum.join(attributes)}/>"],
      else: ["<#{tag}#{Enum.join(attributes)}>#{Enum.join(inner)}</#{tag}>"]
  end

  defp clean(_other), do: []

  # Plain numbers, colours and path data: no references to anything else.
  defp safe_value?(value), do: not String.match?(value, ~r/url\s*\(|javascript:|[<>"]|&/i)

  defp ref_type(%{data: %{type: type}}) when not is_nil(type), do: to_string(type)
  defp ref_type(_ref), do: "unknown"

  defp translations(map) when is_map(map) and map_size(map) > 0,
    do: Enum.map_join(map, " / ", fn {lang, text} -> "#{text} (#{lang})" end)

  defp translations(text) when is_binary(text) and text != "", do: text
  defp translations(_), do: "–"
end
