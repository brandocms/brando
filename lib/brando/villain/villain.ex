defmodule Brando.Villain do
  @moduledoc """
  Block rendering engine.

  Parses block structures into HTML using Liquex templates.
  All block data management (queries, orchestration, sync, duplication)
  lives in `Brando.Content.Blocks`.
  """
  alias Liquex.Context
  alias Brando.Cache
  alias Brando.Content
  alias Brando.Pages
  alias Brando.Utils

  @module_cache_ttl (Brando.config(:env) in [:e2e, :test] &&
                       %{
                         preload: [
                           :vars,
                           refs: [
                             :image,
                             :file,
                             video: [:thumbnail, :file],
                             gallery: [gallery_objects: [:image, video: [:thumbnail, :file]]]
                           ]
                         ]
                       }) ||
                      %{
                        cache: {:ttl, :infinite},
                        preload: [
                          :vars,
                          refs: [
                            :image,
                            :file,
                            video: [:thumbnail, :file],
                            gallery: [gallery_objects: [:image, video: [:thumbnail, :file]]]
                          ]
                        ]
                      }
  @container_cache_ttl (Brando.config(:env) in [:e2e, :test] && %{preload: [:palette]}) ||
                         %{cache: {:ttl, :infinite}, preload: [:palette]}
  @palette_cache_ttl (Brando.config(:env) in [:e2e, :test] && %{}) || %{cache: {:ttl, :infinite}}
  @fragment_cache_ttl (Brando.config(:env) in [:e2e, :test] && %{}) || %{cache: {:ttl, :infinite}}

  @doc """
  Parse blocks

  Delegates to the parser module configured in the otp_app's brando.exs.
  Renders to HTML.
  """
  def parse(entry_blocks_list, entry \\ nil, opts \\ [])
  def parse([], _, _), do: ""
  def parse("", _, _), do: ""
  def parse(nil, _, _), do: ""

  def parse(entry_blocks_list, entry, opts) do
    start = System.monotonic_time()
    opts_map = Enum.into(opts, %{})
    parser = Brando.config(Brando.Villain)[:parser]

    {:ok, modules} = Content.list_modules(@module_cache_ttl)
    {:ok, containers} = Content.list_containers(@container_cache_ttl)
    {:ok, palettes} = Content.list_palettes(@palette_cache_ttl)
    {:ok, fragments} = Pages.list_fragments(@fragment_cache_ttl)

    entry = maybe_put_timestamps(entry)

    context =
      entry
      |> Brando.Villain.get_base_context()
      |> add_request_to_context(opts_map)
      |> add_url_to_context(entry)

    opts_map =
      opts_map
      |> Map.put(:context, context)
      |> Map.put(:modules, modules)
      |> Map.put(:containers, containers)
      |> Map.put(:palettes, palettes)
      |> Map.put(:fragments, fragments)

    html =
      entry_blocks_list
      |> Enum.reduce([], fn
        nil, acc -> acc
        %{block: %{marked_as_deleted: true}}, acc -> acc
        %{block: block}, acc -> [parse_node(parser, block, opts_map) | acc]
      end)
      |> Enum.reverse()

    output = parse_and_render(html, context)

    :telemetry.execute([:brando, :villain, :parse_and_render], %{
      duration: System.monotonic_time() - start
    })

    output
  end

  def render_block(block, entry, opts \\ [])
  def render_block(%{active: false}, _entry, _opts), do: ""
  def render_block(%{marked_as_deleted: true}, _entry, _opts), do: ""

  def render_block(%Content.Block{} = block, entry, opts) do
    opts_map = Enum.into(opts, %{})
    parser = Brando.config(Brando.Villain)[:parser]

    {:ok, modules} = Content.list_modules(@module_cache_ttl)
    {:ok, containers} = Content.list_containers(@container_cache_ttl)
    {:ok, palettes} = Content.list_palettes(@palette_cache_ttl)
    {:ok, fragments} = Pages.list_fragments(@fragment_cache_ttl)

    entry = maybe_put_timestamps(entry)

    context =
      entry
      |> Brando.Villain.get_base_context()
      |> add_request_to_context(opts_map)
      |> add_url_to_context(entry)

    opts_map =
      opts_map
      |> Map.put(:context, context)
      |> Map.put(:modules, modules)
      |> Map.put(:containers, containers)
      |> Map.put(:palettes, palettes)
      |> Map.put(:fragments, fragments)

    parser
    |> parse_node(block, opts_map)
    |> parse_and_render(context)
  end

  def render_block(%{block: block} = _entry_block, entry, opts) do
    render_block(block, entry, opts)
  end

  defp add_request_to_context(ctx, %{conn: conn}) do
    request = %{
      params: conn.path_params,
      url: conn.request_path
    }

    add_to_context(ctx, "request", request)
  end

  defp add_request_to_context(ctx, _), do: ctx

  defp add_url_to_context(ctx, entry) do
    add_to_context(ctx, "url", Brando.HTML.absolute_url(entry))
  end

  defp parse_node(parser, block, opts_map) do
    type_atom = if block.type == :module_entry, do: :module, else: block.type

    if not is_atom(type_atom) or is_nil(type_atom) do
      raise """
      Expected type to be an atom, got: #{inspect(type_atom)}

      Data node: #{inspect(block, pretty: true)}
      """
    end

    apply(parser, type_atom, [block, opts_map])
  end

  def get_base_context do
    locale = Gettext.get_locale(Brando.gettext())

    do_get_base_context(locale)
    |> add_to_context("language", locale)
    |> add_to_context("locale", locale)
  end

  def get_base_context(%{language: entry_language} = entry) do
    language = (entry_language in [nil, ""] && Brando.config(:default_language)) || entry_language

    do_get_base_context(to_string(language))
    |> add_to_context("language", to_string(language))
    |> add_to_context("locale", to_string(language))
    |> add_to_context("entry", entry)
  end

  def get_base_context(entry) do
    locale = Brando.config(:default_language)

    do_get_base_context(locale)
    |> add_to_context("language", locale)
    |> add_to_context("locale", locale)
    |> add_to_context("entry", entry)
  end

  defp do_get_base_context(language) do
    identity = Cache.Identity.get(language)
    globals = Cache.Globals.get(language)
    navigation = Cache.Navigation.get()

    %{}
    |> create_context()
    |> add_to_context("identity", identity)
    |> add_to_context("links", identity)
    |> add_to_context("globals", globals)
    |> add_to_context("navigation", navigation)
  end

  def create_context(vars) do
    Context.new(
      vars,
      filter_module: Brando.web_module(Villain.Filters)
    )
  end

  def add_to_context(context, "links" = key, %{links: links}) do
    links = Enum.map(links, &{String.downcase(&1.name), &1}) |> Enum.into(%{})
    Context.assign(context, key, links)
  end

  def add_to_context(context, "links" = key, _) do
    Context.assign(context, key, %{})
  end

  def add_to_context(context, "globals" = key, global_sets) do
    parsed_globals =
      global_sets
      |> Enum.map(fn {g_key, g_category} ->
        cat_globs =
          g_category
          |> Enum.map(fn {key, %{value: value}} -> {key, value} end)
          |> Enum.into(%{})

        {g_key, cat_globs}
      end)
      |> Enum.into(%{})

    Context.assign(context, key, parsed_globals)
  end

  def add_to_context(context, key, value) do
    Context.assign(context, key, value)
  end

  def parse_and_render(html, context) do
    liquex_parser = Brando.config(Brando.Villain)[:liquex_parser] || Brando.Villain.LiquexParser

    html_string =
      html
      |> ensure_string()
      |> strip_identifier_data_attributes()

    with {:ok, parsed_doc} <- liquex_parse(html_string, liquex_parser),
         {result, _} <- liquex_render(html_string, [], parsed_doc, context) do
      Enum.join(result)
    else
      {:error, reason, line} ->
        require Logger

        Logger.error("""

        >>> Error parsing liquex template <<<

        #{inspect(html, pretty: true)}

        --> #{reason} (line #{line})

        """)

        "!!! Error parsing liquex template !!!"
    end
  end

  defp ensure_string(html) when is_binary(html), do: html
  defp ensure_string(html) when is_list(html), do: IO.iodata_to_binary(html)

  @doc """
  Update the `href` of all links with `data-identifier-id="ID"` in HTML.

  Used when an identifier's URL changes to update stored HTML
  in block refs and rich text fields.
  """
  def update_identifier_url_in_html(html, identifier_id, new_url)
      when is_binary(html) and is_integer(identifier_id) do
    # href always comes before data-identifier-id (we control the attribute order)
    pattern = ~r/(<a\b[^>]*?\bhref=")([^"]*)("[^>]*?data-identifier-id="#{identifier_id}")/

    if Regex.match?(pattern, html) do
      {:updated, Regex.replace(pattern, html, "\\1#{new_url}\\3")}
    else
      :unchanged
    end
  end

  @doc """
  Strip editor-only `data-identifier-id` attributes from rendered output.
  """
  def strip_identifier_data_attributes(html) when is_binary(html) do
    String.replace(html, ~r/ data-identifier-id="\d+"/, "")
  end

  def strip_identifier_data_attributes(html), do: html

  defp liquex_parse(html, liquex_parser) do
    Liquex.parse(html, liquex_parser)
  end

  defp liquex_render(html_string, [], parsed_doc, context) do
    Liquex.Render.render!([], parsed_doc, context)
  rescue
    error in Protocol.UndefinedError ->
      case error do
        %{protocol: Liquex.Collection, value: nil} ->
          require Logger

          for_lines = extract_for_lines(html_string)

          Logger.error("""

          >>> Liquex.Collection error: trying to iterate over nil <<<

          This usually happens when a template tries to iterate over a collection that doesn't exist.
          Common causes:
          - Gallery refs using old syntax: `refs.*.images` instead of `refs.*.gallery_objects`
          - For loops over nil collections: `{% for item in nil_collection %}`

          For loops in template:
          #{for_lines}

          Context variables:
          #{inspect(context.scope.stack, pretty: true, limit: :infinity)}

          Parsed template:
          #{inspect(parsed_doc, pretty: true, limit: 10)}

          """)

          {["<!-- Liquex template error: trying to iterate over nil collection -->"], context}

        _ ->
          reraise error, __STACKTRACE__
      end
  end

  defp extract_for_lines(html_string) do
    html_string
    |> String.split("\n")
    |> Enum.with_index(1)
    |> Enum.filter(fn {line, _idx} -> String.contains?(line, "{% for") end)
    |> Enum.map(fn {line, idx} -> {idx, String.trim(line)} end)
    |> Enum.map_join("\n", fn {idx, line} -> "  line #{idx}: #{line}" end)
    |> case do
      "" -> "  (none found)"
      lines -> lines
    end
  end

  defp maybe_put_timestamps(%{inserted_at: nil} = entry) do
    datetime = DateTime.from_unix!(System.os_time(:second), :second)
    %{entry | updated_at: datetime, inserted_at: datetime}
  end

  defp maybe_put_timestamps(entry), do: entry

  @doc """
  Map out images
  """
  def map_images(images) do
    Enum.map(images, fn image ->
      sizes = Map.new(image.sizes, fn {k, v} -> {k, Utils.media_url(v)} end)

      %{
        src: Utils.media_url(image.path),
        thumb: image |> Utils.img_url(:thumb) |> Utils.media_url(),
        sizes: sizes,
        dominant_color: image.dominant_color,
        formats: image.formats,
        alt: image.alt,
        title: image.title,
        credits: image.credits,
        inserted_at: image.inserted_at,
        width: image.width,
        height: image.height
      }
    end)
  end
end
