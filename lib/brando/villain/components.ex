defmodule Brando.Villain.Components do
  @moduledoc """
  HEEx function components for use in Villain HEEx templates.

  These components are automatically imported when compiling HEEx module templates
  via `Brando.Villain.HeexRenderer`.

  ## Render context

  Components check `@render_context` (`:publish` or `:admin`) to determine
  their rendering mode.

  ## Example usage in HEEx templates

      <.ref block={@block} ref={:h2} />
      <.picture src={@entry.cover} opts={[sizes: "auto", srcset: "MyApp.Project:cover.default"]} />
      <.content />
      <.fragment parent_key="header" key="default" language={@language} />
  """

  use Phoenix.Component
  import Phoenix.HTML, only: [raw: 1]
  alias Ecto.Changeset

  # -- ref component --

  attr :block, :map, required: true
  attr :ref, :atom, required: true
  attr :headless, :boolean, default: false
  attr :_heex_ctx, :map, default: nil
  slot :inner_block

  @doc """
  Render a ref block.

  Uses `_heex_ctx` to determine rendering mode:
  - Admin context (has `refs_field`): delegates to the block form ref editor.
  - Publish context (has `refs`): renders the ref's published content.
  - No context: falls back to assigns-based lookup (non-HEEx usage).
  """
  def ref(%{_heex_ctx: %{refs_field: _} = ctx} = assigns) do
    ref_name = to_string(assigns.ref)

    assigns =
      assigns
      |> assign(:ref_name, ref_name)
      |> assign(:refs_field, ctx.refs_field)
      |> assign(:parent_uploads, ctx.parent_uploads)
      |> assign(:target, ctx.target)
      |> assign(:target_ref, ctx.target_ref)
      |> assign(:form_id, ctx.form_id)

    ~H"""
    <BrandoAdmin.Components.Form.Block.ref
      ref_name={@ref_name}
      refs_field={@refs_field}
      parent_uploads={@parent_uploads}
      target={@target}
      target_ref={@target_ref}
      form_id={@form_id}
    />
    """
  end

  def ref(%{_heex_ctx: %{refs: refs} = ctx} = assigns) do
    ref_name = to_string(assigns.ref)
    ref_data = Map.get(refs, ref_name)

    assigns =
      assigns
      |> assign(:ref_name, ref_name)
      |> assign(:ref_data, ref_data)
      |> assign(:render_context, ctx[:render_context])
      |> assign(:parser_module, ctx[:parser_module])
      |> assign(:liquex_context, ctx[:liquex_context])

    ~H"""
    {render_ref(@ref_data, @ref_name, @block, @headless, assigns)}
    """
  end

  def ref(assigns) do
    ref_name = to_string(assigns.ref)
    refs = assigns[:refs] || %{}
    ref_data = Map.get(refs, ref_name)

    assigns =
      assigns
      |> assign(:ref_name, ref_name)
      |> assign(:ref_data, ref_data)

    ~H"""
    {render_ref(@ref_data, @ref_name, @block, @headless, assigns)}
    """
  end

  defp render_ref(nil, ref_name, block, _headless, _assigns) do
    module_id = Map.get(block, :module_id)
    Phoenix.HTML.raw("<!-- REF #{ref_name} missing // module: #{module_id}. -->")
  end

  defp render_ref(%{hidden: true}, ref_name, _block, _headless, _assigns),
    do: Phoenix.HTML.raw("<!-- h[[#{ref_name}]] -->")

  defp render_ref(%{data: %{hidden: true}}, ref_name, _block, _headless, _assigns),
    do: Phoenix.HTML.raw("<!-- h[#{ref_name}] -->")

  defp render_ref(%{deleted: true}, _ref_name, _block, _headless, _assigns),
    do: Phoenix.HTML.raw("<!-- d -->")

  defp render_ref(%{active: false}, _ref_name, _block, _headless, _assigns),
    do: Phoenix.HTML.raw("<!-- !a -->")

  defp render_ref(
         %{data: block_data, description: description} = _ref_data,
         ref_name,
         block,
         _headless,
         assigns
       ) do
    render_context = assigns[:render_context]
    parser_module = assigns[:parser_module] || Brando.Villain.Parser
    module_id = Map.get(block, :module_id)

    rendered =
      case block_data do
        %Changeset{} = cs ->
          applied = Changeset.apply_changes(cs)
          render_ref_block(parser_module, applied, assigns)

        _ ->
          render_ref_block(parser_module, block_data, assigns)
      end

    if render_context == :admin do
      Phoenix.HTML.raw("""
      <section phx-click="edit_ref" b-module-id="#{module_id}" b-ref="#{ref_name}" b-ref-desc="#{description}">
        #{rendered}
      </section>
      """)
    else
      Phoenix.HTML.raw(rendered)
    end
  end

  defp render_ref_block(parser_module, block_data, assigns) do
    opts = build_parser_opts(assigns)
    apply(parser_module, String.to_atom(block_data.type), [block_data.data, opts])
  end

  defp build_parser_opts(assigns) do
    {:ok, modules} = Brando.Content.list_modules(cache_opts())
    {:ok, containers} = Brando.Content.list_containers(cache_opts())
    {:ok, palettes} = Brando.Content.list_palettes(cache_opts())

    %{
      context: assigns[:liquex_context] || build_empty_context(),
      containers: containers,
      modules: modules,
      palettes: palettes
    }
  end

  defp build_empty_context do
    Liquex.Context.new(%{})
  end

  defp cache_opts do
    if Brando.config(:env) == :e2e, do: %{}, else: %{cache: {:ttl, :infinite}}
  end

  # -- picture component --

  attr :src, :any, required: true
  attr :opts, :list, default: []

  @doc """
  Render a picture tag. Delegates to `Brando.HTML.Images.picture/1`.
  """
  def picture(assigns) do
    ~H"""
    <Brando.HTML.Images.picture src={@src} opts={@opts} />
    """
  end

  # -- video component --

  attr :src, :any, required: true
  attr :opts, :list, default: []

  @doc """
  Render a video element.
  """
  def video(assigns) do
    ~H"""
    <Brando.HTML.video src={@src} opts={@opts} />
    """
  end

  # -- content component --

  @doc """
  Render the `@content` assign (children HTML in multi modules / containers).

  In `:publish` context, renders the raw HTML content.
  """
  def content(assigns) do
    ~H"""
    {raw(@content)}
    """
  end

  # -- entry_link component --

  attr :href, :string, default: nil
  attr :entry, :map, default: nil
  attr :field, :atom, default: :url
  slot :inner_block, required: true

  @doc """
  Render a link, avoiding collision with `Phoenix.Component.link/1`.

  Can be used with a direct `href` or by extracting the URL from an entry field.
  """
  def entry_link(assigns) do
    href = assigns.href || get_in(assigns, [:entry, assigns.field])
    assigns = assign(assigns, :resolved_href, href)

    ~H"""
    <a href={@resolved_href}>{render_slot(@inner_block)}</a>
    """
  end

  # -- route component --

  attr :helper, :atom, required: true
  attr :action, :atom, required: true
  attr :args, :list, default: []

  @doc """
  Generate a URL using a route helper.

  ## Example

      <.route helper={:project_path} action={:detail} args={[@entry.slug]} />
  """
  def route(assigns) do
    router_module = Brando.helpers()
    url = apply(router_module, assigns.helper, [Brando.endpoint(), assigns.action | assigns.args])
    assigns = assign(assigns, :url, url)

    ~H"""
    {@url}
    """
  end

  # -- route_i18n component --

  attr :helper, :atom, required: true
  attr :action, :atom, required: true
  attr :args, :list, default: []
  attr :language, :string, required: true

  @doc """
  Generate a URL using a route helper with language prefix.
  """
  def route_i18n(assigns) do
    router_module = Brando.helpers()
    url = apply(router_module, assigns.helper, [Brando.endpoint(), assigns.action, assigns.language | assigns.args])
    assigns = assign(assigns, :url, url)

    ~H"""
    {@url}
    """
  end

  # -- fragment component --

  attr :parent_key, :string, required: true
  attr :key, :string, required: true
  attr :language, :string, required: true

  @doc """
  Render a fragment by parent_key, key and language.
  """
  def fragment(assigns) do
    rendered =
      assigns.parent_key
      |> Brando.Pages.render_fragment(assigns.key, assigns.language)
      |> Phoenix.HTML.safe_to_string()

    assigns = assign(assigns, :rendered, rendered)

    ~H"""
    {raw(@rendered)}
    """
  end

  # -- t component --

  attr :no, :string, required: true
  attr :en, :string, required: true
  attr :language, :string, required: true

  @doc """
  Conditional language text. Returns the text matching `@language`.
  """
  def t(assigns) do
    text =
      case assigns.language do
        "no" -> assigns.no
        "en" -> assigns.en
        _ -> assigns.en
      end

    assigns = assign(assigns, :text, text)

    ~H"""
    {@text}
    """
  end
end
