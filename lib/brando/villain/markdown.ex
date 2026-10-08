defmodule Brando.Villain.Markdown do
  @moduledoc """
  Renders blocks as Markdown, for an entry's Markdown alternate
  (`Brando.SEO.Markdown`).

  It is a Villain parser (`Brando.Villain.Parser`), so blocks go through the
  same dispatch as the HTML render, block by block:

    * A **module** with a `markdown` template (`Brando.Content.Module`'s
      `markdown_code`) renders it: a Liquid template with the same variables,
      refs and `{{ content }}` as its HTML template, where `{% ref refs.x %}`
      gives the ref as Markdown.
    * Any other module renders its HTML template, and that HTML is turned into
      Markdown (`Brando.Villain.Markdown.HTML`). Its refs are written as plain
      markup for that: rich text as it is, a heading as a heading, a picture
      as `![alt](url)` with its caption, a video or a file as a link, a
      gallery as its images. SVG, maps, comments and form inputs are left
      out, and so are layout wrappers and anything a reader cannot use.
    * A **container** renders its children; its own template is layout.
    * A **fragment** gives its published HTML as Markdown.
    * A **block slot** renders its children.

  Inactive and deleted blocks are left out, as in HTML.
  """

  # The parser callbacks are defined here without `use Brando.Villain.Parser`:
  # that would make this module depend on the HTML parser at compile time,
  # and the HTML helpers it imports reach back here at runtime.

  alias Brando.Content
  alias Brando.Content.BlockSlots
  alias Brando.Pages.FragmentQuery
  alias Brando.Villain
  alias Brando.Villain.Markdown.HTML
  alias Brando.Villain.Parser
  alias Brando.Villain.RenderScope
  alias Brando.Villain.RenderSourceQuery
  alias Brando.Villain.TemplateAdapter
  alias Liquex.Context

  @brando_env Application.compile_env(:brando, :env)
  @cache (@brando_env in [:e2e, :test] && %{}) || %{cache: {:ttl, :infinite}}
  @module_preloads [
    :vars,
    refs: [
      :image,
      :file,
      video: [:thumbnail, :file],
      gallery: [gallery_objects: [:image, video: [:thumbnail, :file]]]
    ]
  ]

  # Set in a module's Liquid context while its `markdown` template renders:
  # refs then give Markdown rather than markup for the HTML conversion.
  @template_flag :brando_markdown_template

  @doc """
  Markdown for an entry's blocks (`entry_blocks` as preloaded on the entry,
  e.g. `entry.entry_blocks`), rendered in `entry`'s context.
  """
  @spec render(list() | nil, map() | nil, keyword()) :: String.t()
  def render(entry_blocks, entry \\ nil, opts \\ [])
  def render(entry_blocks, _entry, _opts) when entry_blocks in [nil, []], do: ""

  def render(entry_blocks, entry, opts) do
    RenderScope.run(fn ->
      {:ok, modules} = RenderSourceQuery.list_modules(Map.put(@cache, :preload, @module_preloads))
      {:ok, containers} = RenderSourceQuery.list_containers(Map.put(@cache, :preload, [:palette]))
      {:ok, palettes} = RenderSourceQuery.list_palettes(@cache)
      {:ok, fragments} = FragmentQuery.list_for_rendering(@cache)

      context =
        entry
        |> Villain.get_base_context()
        |> Villain.add_to_context("url", entry && Brando.Blueprint.URL.resolve(entry))
        |> Context.assign(@template_flag, false)

      opts_map =
        opts
        |> Map.new()
        |> Map.merge(%{
          context: context,
          parser_module: __MODULE__,
          modules: modules,
          containers: containers,
          palettes: palettes,
          fragments: fragments
        })

      entry_blocks
      |> Enum.flat_map(fn
        %{block: %{marked_as_deleted: true}} -> []
        %{block: block} -> [node(block, opts_map)]
        _ -> []
      end)
      |> join()
    end)
  end

  @doc false
  def node(%{active: false}, _opts), do: ""
  def node(%{marked_as_deleted: true}, _opts), do: ""
  def node(%{type: :slot} = slot, opts), do: slot(slot, opts)
  def node(%{type: :module_entry} = block, opts), do: module(block, opts)

  def node(%{type: type} = block, opts) when type in [:module, :container, :fragment],
    do: apply(__MODULE__, type, [block, opts])

  def node(_block, _opts), do: ""

  # -- Structure ---------------------------------------------------------------

  def module(%{active: false}, _opts), do: ""

  def module(%{module_id: id} = block, opts) do
    case Content.find_module(opts.modules, id, Map.get(block, :module_origin, :local)) do
      {:ok, module} -> render_module(module, block, opts)
      {:error, _} -> ""
    end
  end

  def module(_block, _opts), do: ""

  defp render_module(module, block, opts) do
    if template?(module) do
      opts = put_flag(opts, true)
      content = if block.multi == true, do: children(block.children, opts)
      refs = Parser.process_refs(block.refs, block, opts)

      module
      |> Map.put(:code, module.markdown_code)
      |> liquid(block, Parser.process_vars(block.vars), refs, content, opts)
      |> IO.iodata_to_binary()
      |> String.trim()
    else
      module
      |> module_html(block, opts)
      |> HTML.to_markdown()
    end
  end

  # A module's HTML template, with its refs as plain markup, for the HTML
  # conversion. A multi module's entries go into its `{{ content }}` as HTML
  # too, so the parent's list or table keeps them as its items.
  defp module_html(module, block, opts) do
    opts = put_flag(opts, false)
    content = if block.multi == true, do: children_html(block.children, opts)
    refs = Parser.process_refs(block.refs, block, opts)

    module.type
    |> Parser.adapter_for()
    |> render_html(module, block, Parser.process_vars(block.vars), refs, content, opts)
    |> IO.iodata_to_binary()
  end

  defp children_html(children, opts) when is_list(children) do
    children
    |> Enum.flat_map(fn
      %{active: false} -> []
      %{marked_as_deleted: true} -> []
      child -> [child_html(child, opts)]
    end)
    |> Enum.join("\n")
  end

  defp children_html(_children, _opts), do: ""

  defp child_html(%{module_id: id} = child, opts) when not is_nil(id) do
    case Content.find_module(opts.modules, id, Map.get(child, :module_origin, :local)) do
      {:ok, module} ->
        if template?(module), do: passthrough(render_module(module, child, opts)), else: module_html(module, child, opts)

      {:error, _} ->
        ""
    end
  end

  defp child_html(child, opts), do: passthrough(node(child, opts))

  defp render_html(TemplateAdapter.Liquex, module, block, vars, refs, content, opts),
    do: liquid(module, block, vars, refs, content, opts)

  defp render_html(adapter, module, block, vars, refs, nil, opts),
    do: adapter.render_module(module, block, vars, refs, opts)

  defp render_html(adapter, module, block, vars, refs, content, opts),
    do: adapter.render_multi_module(module, block, vars, refs, processed_children(block), content, opts)

  defp liquid(module, block, vars, refs, nil, opts),
    do: TemplateAdapter.Liquex.render_module(module, block, vars, refs, opts)

  defp liquid(module, block, vars, refs, content, opts),
    do: TemplateAdapter.Liquex.render_multi_module(module, block, vars, refs, processed_children(block), content, opts)

  defp processed_children(%{children: children}) when is_list(children) do
    Enum.map(children, fn child ->
      %{child | vars: Parser.process_vars(child.vars), refs: Parser.process_refs(child.refs)}
    end)
  end

  defp processed_children(_block), do: []

  defp template?(%{markdown_code: code}) when is_binary(code), do: String.trim(code) != ""
  defp template?(_module), do: false

  def container(%{active: false}, _opts), do: ""
  def container(%{children: children}, opts), do: opts |> put_flag(false) |> then(&children(children, &1))

  def fragment(%{active: false}, _opts), do: ""
  def fragment(%{fragment_id: nil}, _opts), do: ""

  def fragment(%{fragment_id: id}, opts) do
    case Brando.Pages.find_fragment(opts.fragments, id) do
      {:ok, %{status: :published} = fragment} -> HTML.to_markdown(Map.get(fragment, :rendered_blocks))
      _ -> ""
    end
  end

  defp slot(slot, opts) do
    slot
    |> BlockSlots.children()
    |> children(opts)
  end

  defp children(children, opts) when is_list(children) do
    children
    |> Enum.map(&node(&1, opts))
    |> join()
  end

  defp children(_children, _opts), do: ""

  # A block slot ref: its children, already Markdown.
  def blocks(%{rendered_html: markdown}, opts) when is_binary(markdown), do: markdown_out(markdown, opts)
  def blocks(_data, _opts), do: ""

  # -- Refs --------------------------------------------------------------------

  def text(%{text: text}, opts) when is_binary(text), do: out(text, opts)
  def text(_data, _opts), do: ""

  def html(%{text: html}, opts) when is_binary(html), do: out(html, opts)
  def html(_data, _opts), do: ""

  def header(%{text: text} = data, opts) when is_binary(text) and text != "" do
    level = Map.get(data, :level) || 2
    level = if level in 1..6, do: level, else: 2
    out("<h#{level}>#{escape(text)}</h#{level}>", opts)
  end

  def header(_data, _opts), do: ""

  def markdown(%{text: markdown}, opts) when is_binary(markdown), do: markdown_out(markdown, opts)
  def markdown(_data, _opts), do: ""

  def markdown_source(data, opts), do: out(Brando.MarkdownSources.render(data), opts)

  def picture(data, opts) do
    case image_markup(Brando.Images.resolve_texts(data, Parser.language(opts))) do
      nil -> ""
      markup -> out(markup, opts)
    end
  end

  def gallery(%{gallery: %Brando.Galleries.Gallery{} = gallery}, opts) do
    language = Parser.language(opts)

    gallery
    |> Parser.gallery_media()
    |> Enum.map(fn
      {:image, image} -> image |> Brando.Images.resolve_texts(language) |> image_markup()
      {:video, video} -> video_markup(video)
    end)
    |> Enum.reject(&is_nil/1)
    |> Enum.join()
    |> out(opts)
  end

  def gallery(_data, _opts), do: ""

  def video(data, opts) do
    case video_markup(data) do
      nil -> ""
      markup -> out(markup, opts)
    end
  end

  def file(%{file: %Brando.Files.File{} = file} = data, opts) do
    label = data[:label] || data[:title] || file.title || file.filename
    description = if data[:description] not in [nil, ""], do: "<p>#{escape(data[:description])}</p>", else: ""
    out(~s(<p><a href="#{escape(Brando.Utils.file_url(file))}">#{escape(label)}</a></p>#{description}), opts)
  end

  def file(_data, _opts), do: ""

  def blockquote(%{text: text} = data, opts) when is_binary(text) do
    cite = if data[:cite] not in [nil, ""], do: "<p>— #{escape(data[:cite])}</p>", else: ""
    out("<blockquote>#{text}#{cite}</blockquote>", opts)
  end

  def blockquote(_data, _opts), do: ""

  def divider(_data, opts), do: out("<hr>", opts)

  def svg(_data, _opts), do: ""
  def map(_data, _opts), do: ""
  def comment(_data, _opts), do: ""
  def input(_data, _opts), do: ""
  def media(_data, _opts), do: ""
  def datasource(_data, _opts), do: ""
  def list(_data, _opts), do: ""
  def datatable(_data, _opts), do: ""
  def table(_data, _opts), do: ""
  def timeline(_data, _opts), do: ""
  def render_caption(_data), do: ""
  def video_file_options(_data), do: []

  defp image_markup(%{} = image) do
    case image_url(image) do
      nil ->
        nil

      url ->
        alt = Map.get(image, :alt) || Map.get(image, :title) || ""
        caption = Map.get(image, :title)
        caption = if is_binary(caption) and caption != "", do: "<figcaption>#{escape(caption)}</figcaption>", else: ""
        ~s(<figure><img src="#{escape(url)}" alt="#{escape(alt)}">#{caption}</figure>)
    end
  end

  defp image_markup(_image), do: nil

  defp image_url(%{sizes: sizes} = image) when is_map(sizes) and map_size(sizes) > 0,
    do: image |> Brando.Utils.img_url(:largest, prefix: Brando.Utils.media_url()) |> absolute()

  defp image_url(%{path: path}) when is_binary(path) and path != "",
    do: absolute(Path.join(Brando.Utils.media_url(), path))

  defp image_url(_image), do: nil

  defp absolute("http" <> _ = url), do: url
  defp absolute(path), do: HTML.link_url(path)

  defp video_markup(%{} = video) do
    case video_url(video) do
      nil ->
        nil

      url ->
        title = Map.get(video, :title)
        title = if is_binary(title) and title != "", do: title, else: url
        ~s(<p><a href="#{escape(url)}">#{escape(title)}</a></p>)
    end
  end

  defp video_markup(_video), do: nil

  defp video_url(%{type: :youtube, remote_id: id}) when is_binary(id) and id != "",
    do: "https://www.youtube.com/watch?v=#{URI.encode_www_form(id)}"

  defp video_url(%{type: :vimeo, remote_id: id}) when is_binary(id) and id != "", do: "https://vimeo.com/#{id}"
  defp video_url(%{type: :external_file, source_url: url}) when is_binary(url) and url != "", do: url
  defp video_url(%{file: %Brando.Files.File{} = file}), do: Brando.Utils.file_url(file)
  defp video_url(%{type: :upload, remote_id: url}) when is_binary(url) and url != "", do: absolute(url)
  defp video_url(_video), do: nil

  # -- Output ------------------------------------------------------------------

  # Markup for the HTML conversion, or Markdown inside a markdown template.
  defp out(markup, opts) do
    if template_mode?(opts), do: HTML.to_markdown(markup), else: IO.iodata_to_binary(markup)
  end

  defp markdown_out(markdown, opts) do
    if template_mode?(opts), do: markdown, else: passthrough(markdown)
  end

  defp passthrough(""), do: ""
  defp passthrough(markdown), do: "<brando-markdown>#{escape(markdown)}</brando-markdown>"

  defp template_mode?(%{context: %Context{} = context}), do: Access.get(context, @template_flag) == true
  defp template_mode?(_opts), do: false

  defp put_flag(%{context: %Context{} = context} = opts, value),
    do: %{opts | context: Context.assign(context, @template_flag, value)}

  defp put_flag(opts, _value), do: opts

  defp escape(text), do: text |> to_string() |> Phoenix.HTML.html_escape() |> Phoenix.HTML.safe_to_string()

  defp join(parts) do
    parts
    |> Enum.map(&String.trim(IO.iodata_to_binary(&1)))
    |> Enum.reject(&(&1 == ""))
    |> Enum.join("\n\n")
  end
end
