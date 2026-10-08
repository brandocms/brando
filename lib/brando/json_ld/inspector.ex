defmodule Brando.JSONLD.Inspector do
  @moduledoc """
  Explains an entry's JSON-LD: the graph its page emits, laid out as nodes
  and labelled edges, each node checked against `Brando.JSONLD.Rules` and
  mapped back to the blueprint field or setting it comes from.

  The graph is the one `Brando.JSONLD.Graph.for_entry/3` builds, which is the
  page's own (see that module for what a controller may add). `json` is the
  exact content of the page's `<script type="application/ld+json">`.

  Besides the graph's nodes, the main entity gets *potential* nodes for what
  it would gain from a field it lacks: an author, an image, a video. They
  are drawn dashed, with the reason.

  Where a field's value comes from is found by calling its `value_fn` with a
  probe: an entry whose every field holds a marker. The markers in the result
  name the fields read, a fallback's alternatives included; a callback that
  computes its value from them reads as computed.
  """

  require Logger

  alias Brando.JSONLD
  alias Brando.JSONLD.Graph
  alias Brando.JSONLD.Rules

  defstruct json: nil,
            url: nil,
            nodes: [],
            edges: [],
            main: nil,
            width: 0,
            height: 0,
            errors: 0,
            warnings: 0

  @type t :: %__MODULE__{}

  # Nested entities drawn as nodes of their own; everything else nested is
  # checked and shown as part of its parent.
  @visual_nested ["ImageObject", "Offer", "AggregateRating", "Review", "Person"]

  @icons %{
    "WebSite" => "globe",
    "WebPage" => "file",
    "AboutPage" => "file",
    "CollectionPage" => "file",
    "ContactPage" => "file",
    "FAQPage" => "file",
    "ItemPage" => "file",
    "SearchResultsPage" => "file",
    "ProfilePage" => "id-card",
    "Organization" => "building",
    "Corporation" => "building",
    "NGO" => "building",
    "EducationalOrganization" => "school",
    "GovernmentOrganization" => "landmark",
    "MedicalOrganization" => "hospital",
    "SportsOrganization" => "trophy",
    "LocalBusiness" => "store",
    "ProfessionalService" => "store",
    "Architect" => "store",
    "ArtGallery" => "palette",
    "EmploymentAgency" => "store",
    "Restaurant" => "utensils",
    "Person" => "user",
    "Article" => "newspaper",
    "NewsArticle" => "newspaper",
    "BlogPosting" => "newspaper",
    "CreativeWork" => "file-text",
    "VisualArtwork" => "palette",
    "BreadcrumbList" => "list",
    "ImageObject" => "image",
    "VideoObject" => "video",
    "Product" => "package",
    "Offer" => "tag",
    "AggregateRating" => "star",
    "Review" => "star",
    "JobPosting" => "briefcase",
    "Recipe" => "chef-hat",
    "Event" => "calendar",
    "ExhibitionEvent" => "calendar",
    "Place" => "map-pin",
    "Service" => "handshake",
    "ItemList" => "list"
  }

  # Where the properties of the site-wide and linked nodes come from.
  @site_sources %{
    identity: %{"url" => :seo, "description" => :seo, "image" => :seo},
    website: %{"url" => :seo},
    webpage: %{
      "url" => :page_url,
      "name" => {:fields, [["title"]]},
      "inLanguage" => :language,
      "breadcrumb" => :breadcrumbs
    },
    breadcrumb: %{"itemListElement" => :breadcrumbs}
  }

  @person_sources %{
    "name" => {:fields, [["name"]]},
    "jobTitle" => {:fields, [["job_title"]]},
    "sameAs" => {:fields, [["same_as"]]},
    "image" => {:fields, [["avatar"]]},
    "url" => :page_url
  }

  @video_sources %{
    "name" => {:fields, [["title"]]},
    "description" => {:fields, [["caption"]]},
    "thumbnailUrl" => :video_thumbnail,
    "uploadDate" => {:fields, [["inserted_at"]]},
    "duration" => :provider,
    "contentUrl" => :provider,
    "embedUrl" => :provider,
    "width" => :provider,
    "height" => :provider
  }

  @node_width 184
  @node_height 58
  @gap_x 20
  @gap_y 64
  @pad 12
  @min_width 560

  @doc "The node box size the layout uses, `{width, height}`."
  def node_size, do: {@node_width, @node_height}

  @doc """
  Loads `module`'s entry `id` with what its JSON-LD mapping reads and inspects
  it. `{:error, reason}` when the entry can't be read.
  """
  @spec inspect_entry(module(), term(), keyword()) :: {:ok, t(), map()} | {:error, term()}
  def inspect_entry(module, id, opts \\ []) do
    context = module.__modules__().context
    singular = module.__naming__().singular

    case apply(context, :"get_#{singular}", [%{matches: %{id: id}}]) do
      {:ok, entry} ->
        entry = Brando.Repo.preload(entry, preloads(module), force: true)

        case safe_build(module, entry, opts) do
          {:ok, inspection} -> {:ok, inspection, entry}
          error -> error
        end

      error ->
        error
    end
  end

  @doc """
  `build/3`, with an error from the site's own mapping (a field function that
  raises) returned as `{:error, {:build_failed, reason}}`, `reason` a short
  message, instead of raised. The full error is logged.
  """
  @spec safe_build(module(), map(), keyword()) :: {:ok, t()} | {:error, {:build_failed, String.t()}}
  def safe_build(module, entry, opts \\ []) do
    {:ok, build(module, entry, opts)}
  rescue
    exception ->
      Logger.warning(
        "[Brando.JSONLD.Inspector] could not build structured data for #{inspect(module)} #{inspect(Map.get(entry, :id))}: " <>
          Exception.format(:error, exception, __STACKTRACE__)
      )

      {:error, {:build_failed, short_reason(exception)}}
  end

  @reason_length 160

  # The first line of the exception's message, cut short: enough to tell an
  # editor what broke (a relation that isn't loaded, a nil date).
  defp short_reason(exception) do
    line = exception |> Exception.message() |> String.split("\n", trim: true) |> List.first("")
    line = String.trim(line)

    if String.length(line) > @reason_length,
      do: String.slice(line, 0, @reason_length - 1) <> "…",
      else: line
  end

  @doc """
  What `module`'s JSON-LD reads beyond the entry's columns: the blueprint's
  relations and assets one level deep, as the entry's form loads them
  (`Brando.Blueprint.preloads_for/2`), since a field function may read any of
  them (a `keywords/1` that lists the entry's categories); the user's avatar
  and a video's thumbnail and file where its mapping reads them; its video
  fields; the URL and identifier's own preloads and, unless `blocks: false`,
  its blocks (for the videos in them).
  """
  @spec preloads(module(), keyword()) :: list()
  def preloads(module, opts \\ []) do
    sources = sources(module)
    associations = module.__schema__(:associations)

    mapped =
      for {_field, {:fields, groups}} <- sources,
          name <- List.flatten(groups),
          association = Enum.find(associations, &(Atom.to_string(&1) == name)),
          do: association_preload(module, association)

    videos =
      if function_exported?(module, :__video_fields__, 0),
        do: Enum.map(module.__video_fields__(), &{&1.name, [:thumbnail, :file]}),
        else: []

    blocks =
      if Keyword.get(opts, :blocks, true) and videos?(module),
        do: Brando.Content.BlockPreloads.for_schema(module),
        else: []

    url_preloads =
      if function_exported?(module, :__absolute_url_preloads__, 0), do: module.__absolute_url_preloads__(), else: []

    module
    |> Brando.Blueprint.preloads_for(skip_blocks: true)
    |> merge_preloads(mapped ++ videos ++ blocks ++ url_preloads ++ Brando.Content.Identifier.preloads_for(module))
  end

  # One entry per association: Ecto refuses an association named twice when
  # one of them is a query. A bare name takes the nested preloads of another
  # entry for it (`:author` and `author: [:avatar]` load the avatar); two
  # nested lists are joined; a query (a sorted has_many) is kept as it is.
  defp merge_preloads(base, extra) do
    {order, specs} =
      Enum.reduce(base ++ extra, {[], %{}}, fn preload, {order, specs} ->
        {name, spec} = normalize_preload(preload)

        case specs do
          %{^name => existing} -> {order, Map.put(specs, name, merge_spec(existing, spec))}
          _ -> {[name | order], Map.put(specs, name, spec)}
        end
      end)

    order
    |> Enum.reverse()
    |> Enum.map(fn name ->
      case Map.fetch!(specs, name) do
        [] -> name
        spec -> {name, spec}
      end
    end)
  end

  defp normalize_preload({name, spec}) when is_atom(name), do: {name, normalize_spec(spec)}
  defp normalize_preload(name) when is_atom(name), do: {name, []}

  defp normalize_spec(spec) when is_atom(spec), do: [spec]
  defp normalize_spec(spec), do: spec

  defp merge_spec([], spec), do: spec
  defp merge_spec(existing, []), do: existing
  defp merge_spec(existing, spec) when is_list(existing) and is_list(spec), do: Enum.uniq(existing ++ spec)
  defp merge_spec(existing, _spec), do: existing

  defp association_preload(module, association) do
    case module.__schema__(:association, association) do
      %{related: Brando.Users.User} -> {association, [:avatar]}
      %{related: Brando.Videos.Video} -> {association, [:thumbnail, :file]}
      _ -> association
    end
  end

  @doc """
  Inspects `entry` of `module`.

  ## Options

    * `:language` — the page's language (default: the entry's)
    * `:sources` — `sources/1` for the module, when inspecting many entries
  """
  @spec build(module(), map(), keyword()) :: t()
  def build(module, entry, opts \\ []) do
    conn = Graph.build_conn(module, entry, Keyword.take(opts, [:language]))

    case Graph.entities(conn) do
      [] ->
        %__MODULE__{}

      entities ->
        json = JSONLD.to_graph_json(entities)
        sources = Keyword.get_lazy(opts, :sources, fn -> sources(module) end)
        main_id = main_id(conn)

        nodes =
          json
          |> Jason.decode!()
          |> Map.get("@graph", [])
          |> to_nodes(main_id, module, sources)

        nodes = validate(nodes)
        {nodes, edges, width} = nodes |> link() |> layout()

        %__MODULE__{
          json: json,
          url: Brando.Utils.current_url(conn),
          nodes: nodes,
          edges: edges,
          main: Enum.find_value(nodes, &(&1.role == :main && &1.key)),
          width: width,
          height: canvas_height(nodes),
          errors: count(nodes, :error),
          warnings: count(nodes, :warning)
        }
    end
  end

  @doc """
  The issues of the nodes that describe the entry itself — its entity, the
  people and videos linked from it, its page and breadcrumbs — leaving out
  the site's identity, website and services, which every page shares. Errors
  come first.
  """
  @spec entry_issues(t()) :: [map()]
  def entry_issues(%__MODULE__{nodes: nodes}) do
    issues =
      for %{origin: :entry, issues: issues} = node <- nodes, issue <- issues do
        issue |> Map.put(:type, node.type) |> Map.update!(:property, &nested_path(node, &1))
      end

    Enum.sort_by(issues, &(&1.level != :error))
  end

  # An offer's price is the product's `offers.price`.
  defp nested_path(%{role: :nested, property: property}, path), do: "#{property}.#{path}"
  defp nested_path(_node, path), do: path

  defp count(nodes, level), do: nodes |> Enum.flat_map(& &1.issues) |> Enum.count(&(&1.level == level))

  defp main_id(%{assigns: %{json_ld_entities: [%{"@id": id} | _]}}), do: id
  defp main_id(_conn), do: nil

  ## Sources

  @doc """
  Where each field of `module`'s `json_ld_schema` comes from, by field name:
  `{:fields, groups}` for the entry fields its callback reads — one group
  per fallback, in order, so `[["meta_description"], ["intro"]]` reads the
  intro when the description is empty — or `:identity`, `:page_url`,
  `:language` or `:computed`.
  """
  @spec sources(module()) :: %{atom() => term()}
  def sources(module) do
    case schema_entity(module) do
      nil -> %{}
      %{fields: fields} -> Map.new(fields, &{&1.name, source(module, &1)})
    end
  end

  defp source(_module, %{type: :identity}), do: :identity
  defp source(_module, %{type: :current_url}), do: :page_url
  defp source(_module, %{type: :language}), do: :language
  defp source(_module, %{value_fn: nil}), do: :computed

  defp source(module, %{value_fn: value_fn}) do
    case probe(module, value_fn) do
      [] -> :computed
      names -> {:fields, names}
    end
  end

  defp schema_entity(module) do
    if Graph.has_json_ld?(module),
      do: module |> Spark.Dsl.Extension.get_entities(:json_ld_schemas) |> List.first()
  end

  @marker "⁣bp:"

  defp probe(module, value_fn) do
    fields = module.__struct__() |> Map.keys() |> Kernel.--([:__struct__, :__meta__])

    entry =
      fields
      |> Enum.reduce(module.__struct__(), &Map.put(&2, &1, marker(&1)))
      |> Map.put(:__meta__, %{current_url: nil, language: nil})

    probe_fallbacks(value_fn, entry, [], 2)
  end

  defp probe_fallbacks(_value_fn, _entry, found, 0), do: found

  defp probe_fallbacks(value_fn, entry, found, tries) do
    case value_fn |> safe_call(entry) |> markers() do
      [] ->
        found

      names ->
        entry = Enum.reduce(names, entry, &Map.put(&2, String.to_existing_atom(&1), nil))
        probe_fallbacks(value_fn, entry, found ++ [names], tries - 1)
    end
  end

  defp marker(field), do: @marker <> Atom.to_string(field) <> "⁣"

  defp safe_call(fun, entry) do
    fun.(entry)
  rescue
    _ -> nil
  catch
    _, _ -> nil
  end

  defp markers(value) when is_binary(value) do
    ~r/\x{2063}bp:([a-zA-Z0-9_?!]+)\x{2063}/u
    |> Regex.scan(value, capture: :all_but_first)
    |> List.flatten()
    |> Enum.uniq()
  end

  defp markers(list) when is_list(list), do: list |> Enum.flat_map(&markers/1) |> Enum.uniq()
  defp markers(%_{} = struct), do: struct |> Map.from_struct() |> markers()
  defp markers(map) when is_map(map), do: map |> Map.values() |> markers()
  defp markers(tuple) when is_tuple(tuple), do: tuple |> Tuple.to_list() |> markers()
  defp markers(_value), do: []

  ## Nodes

  defp to_nodes(graph, main_id, module, sources) do
    {services, graph} = Enum.split_with(graph, &(&1["@type"] == "Service"))
    schema = schema_entity(module)

    top =
      graph
      |> Enum.map(&top_node(&1, main_id))
      |> Kernel.++(service_node(services))

    main = Enum.find(top, &(&1.role == :main))

    nested = top |> Enum.flat_map(&nested_nodes/1) |> Enum.map(&%{&1 | source: nested_source(&1.property, sources)})
    potential = if main && schema, do: potential_nodes(main, module, schema), else: []

    (top ++ nested ++ potential)
    |> Enum.with_index()
    |> Enum.map(fn {node, index} -> Map.put(node, :key, "n#{index}") end)
    |> resolve_parents()
    |> Enum.map(&put_rows(&1, schema, sources, module))
  end

  defp top_node(data, main_id) do
    ref = data["@id"]
    role = role(data, ref, main_id)

    %{
      key: nil,
      ref: ref,
      type: type_name(data),
      role: role,
      origin: if(role in [:identity, :website], do: :site, else: :entry),
      data: data,
      property: nil,
      source: nil,
      parent_ref: nil,
      parent: nil,
      potential: nil,
      issues: [],
      rows: [],
      layer: 0,
      x: 0,
      y: 0
    }
  end

  defp role(data, ref, main_id) when is_binary(ref) do
    cond do
      String.ends_with?(ref, "#webpage") -> :webpage
      ref == main_id -> :main
      String.ends_with?(ref, "#website") -> :website
      String.ends_with?(ref, "#identity") -> :identity
      String.ends_with?(ref, "#breadcrumb") -> :breadcrumb
      data["@type"] in ["Person", "VideoObject"] -> :linked
      true -> :main
    end
  end

  defp role(_data, _ref, _main_id), do: :main

  defp service_node([]), do: []

  defp service_node(services) do
    node = top_node(%{"@type" => "Service", "services" => services}, nil)
    [%{node | role: :service, origin: :site}]
  end

  # Typed objects nested in an entry's node that are drawn on their own: its
  # image, offers, ratings, reviews and people without an `@id`.
  defp nested_nodes(%{origin: :entry, role: role} = parent) when role in [:main, :linked] do
    for {property, value} <- parent.data,
        not String.starts_with?(property, "@"),
        item <- List.wrap(value),
        is_map(item) and item["@type"] in @visual_nested and not reference?(item) do
      %{
        top_node(item, nil)
        | role: :nested,
          origin: :entry,
          property: property,
          parent_ref: parent
      }
    end
  end

  defp nested_nodes(_node), do: []

  defp reference?(%{"@id" => _} = map), do: map_size(map) == 1
  defp reference?(_map), do: false

  defp potential_nodes(main, module, schema) do
    keys = schema.schema.__struct__() |> Map.keys()
    mapped = Enum.map(schema.fields, & &1.name)

    [
      potential(main, keys, mapped, :author, "Person"),
      potential(main, keys, mapped, :image, "ImageObject"),
      potential_video(main, keys, module, schema)
    ]
    |> Enum.reject(&is_nil/1)
  end

  defp potential(main, keys, mapped, property, type) do
    name = Atom.to_string(property)

    if property in keys and not Rules.present?(main.data[name]) do
      reason = if property in mapped, do: :not_set, else: :not_mapped
      potential_node(main, name, type, reason)
    end
  end

  defp potential_video(main, keys, module, schema) do
    if :video in keys and schema.videos and not Rules.present?(main.data["video"]) and
         (video_fields?(module) or blocks?(module)) do
      potential_node(main, "video", "VideoObject", :not_set)
    end
  end

  defp potential_node(main, property, type, reason) do
    %{
      top_node(%{"@type" => type}, nil)
      | role: :potential,
        origin: :entry,
        property: property,
        parent_ref: main,
        potential: reason
    }
  end

  defp resolve_parents(nodes) do
    Enum.map(nodes, fn
      %{parent_ref: nil} = node ->
        node

      %{parent_ref: parent} = node ->
        key = Enum.find_value(nodes, &(&1.data == parent.data and &1.role == parent.role and &1.key))
        %{node | parent: key, parent_ref: nil}
    end)
  end

  defp type_name(%{"@type" => [type | _]}), do: to_string(type)
  defp type_name(%{"@type" => type}) when is_binary(type), do: type
  defp type_name(_data), do: "Thing"

  @doc "The Lucide icon for a schema.org type."
  @spec icon(String.t()) :: String.t()
  def icon(type), do: Map.get(@icons, type, "braces")

  @doc """
  A node's `@id` without the site's host: `#identity`, `/news/a/#article`.
  """
  @spec short_id(String.t() | nil) :: String.t() | nil
  def short_id(nil), do: nil

  def short_id(id) do
    case String.replace_prefix(id, Brando.Utils.hostname(), "") do
      "/#" <> rest -> "#" <> rest
      short -> short
    end
  end

  ## Checks

  defp validate(nodes) do
    index = for %{ref: ref, data: data} <- nodes, is_binary(ref), into: %{}, do: {ref, data}
    lookup = &Map.get(index, &1)

    Enum.map(nodes, fn
      %{role: :potential} = node ->
        node

      %{role: :service} = node ->
        node

      node ->
        issues =
          Rules.validate(node.data,
            lookup: lookup,
            standalone: node.role != :nested,
            skip_nested: @visual_nested
          )

        %{node | issues: issues}
    end)
    |> Enum.map(&put_row_issues/1)
  end

  ## Mapping rows

  defp put_rows(%{role: :potential} = node, _schema, _sources, _module), do: node

  defp put_rows(%{role: :main} = node, schema, sources, _module) when not is_nil(schema) do
    mapped =
      Enum.map(schema.fields, fn field ->
        name = Atom.to_string(field.name)
        row(name, Map.get(sources, field.name, :computed), node.data, true)
      end)

    mapped_names = Enum.map(mapped, & &1.property)

    automatic =
      if Map.has_key?(node.data, "video") and "video" not in mapped_names,
        do: [row("video", :videos, node.data, true)],
        else: []

    known = mapped_names ++ Enum.map(automatic, & &1.property)

    unmapped =
      for {property, _level} <- Rules.properties(node.type), not covered?(property, known) do
        row(property, :not_mapped, node.data, false)
      end

    %{node | rows: mapped ++ automatic ++ unmapped}
  end

  defp put_rows(%{role: role} = node, _schema, sources, _module) do
    table = source_table(node, sources)
    present = node.data |> Map.keys() |> Enum.reject(&String.starts_with?(&1, "@"))
    rule_props = Rules.properties(node.type, standalone: role != :nested) |> Enum.map(&elem(&1, 0))

    ordered = Enum.filter(rule_props, &(&1 in present)) ++ Enum.sort(present -- rule_props)

    rows =
      Enum.map(ordered, fn property ->
        row(property, Map.get(table, property, default_source(node, sources)), node.data, true)
      end)

    missing =
      for property <- rule_props, not covered?(property, present), do: row(property, :not_mapped, node.data, false)

    %{node | rows: rows ++ missing}
  end

  # A rule naming alternatives ("contentUrl | embedUrl") is covered by any of them.
  defp covered?(property, names), do: property |> String.split(" | ") |> Enum.any?(&(&1 in names))

  defp row(property, source, data, mapped?) do
    %{
      property: property,
      source: source,
      mapped: mapped?,
      value: data |> Map.get(property) |> Rules.present?() |> then(&if(&1, do: :set)),
      status: nil
    }
  end

  defp source_table(%{role: role}, _sources) when is_map_key(@site_sources, role),
    do: Map.fetch!(@site_sources, role)

  defp source_table(%{type: "Person"}, _sources), do: @person_sources
  defp source_table(%{type: "VideoObject"}, _sources), do: @video_sources
  defp source_table(_node, _sources), do: %{}

  defp default_source(%{role: role}, _sources) when role in [:identity, :website], do: :identity
  defp default_source(%{role: :service}, _sources), do: :identity
  defp default_source(%{role: :nested, property: property}, sources), do: nested_source(property, sources)
  defp default_source(_node, _sources), do: :computed

  defp nested_source(property, sources) do
    Map.get(sources, String.to_existing_atom(property), :computed)
  rescue
    ArgumentError -> :computed
  end

  # A row's status: an error or a warning when an issue names its property
  # (or a path under it), set when it has a value, otherwise empty.
  defp put_row_issues(node) do
    rows =
      Enum.map(node.rows, fn row ->
        issues = Enum.filter(node.issues, &about?(&1.property, row.property))

        status =
          cond do
            Enum.any?(issues, &(&1.level == :error)) -> :error
            issues != [] -> :warning
            row.value == :set -> :ok
            true -> :empty
          end

        row |> Map.put(:status, status) |> Map.put(:issues, issues)
      end)

    %{node | rows: rows}
  end

  defp about?(issue_property, row_property) do
    issue_first = issue_property |> String.split(" | ") |> Enum.map(&first_segment/1)
    row_first = row_property |> String.split(" | ") |> Enum.map(&first_segment/1)
    Enum.any?(issue_first, &(&1 in row_first))
  end

  defp first_segment(path), do: path |> String.split([".", "["]) |> hd()

  ## Edges and layout

  defp link(nodes) do
    by_ref = for %{ref: ref, key: key} <- nodes, is_binary(ref), into: %{}, do: {ref, key}
    webpage = Enum.find(nodes, &(&1.role == :webpage))

    references =
      for node <- nodes,
          node.role not in [:potential],
          {property, value} <- node.data,
          not String.starts_with?(property, "@"),
          target <- refs(value),
          key = Map.get(by_ref, target),
          key && key != node.key,
          do: {node.key, key, property}

    page =
      for node <- nodes,
          webpage,
          node.data["mainEntityOfPage"] == webpage.data["url"],
          node.key != webpage.key,
          do: {node.key, webpage.key, "mainEntityOfPage"}

    children = for %{parent: parent, property: property, key: key} <- nodes, parent, do: {parent, key, property}

    services =
      for %{role: :service, key: key} <- nodes,
          identity = Enum.find(nodes, &(&1.role == :identity)),
          do: {key, identity.key, "provider"}

    edges =
      (references ++ page ++ children ++ services)
      |> Enum.group_by(fn {from, to, _label} -> Enum.sort([from, to]) end)
      |> Enum.map(fn {_pair, [{from, to, _} | _] = group} ->
        %{from: from, to: to, label: group |> Enum.map(&elem(&1, 2)) |> Enum.uniq() |> Enum.join(", ")}
      end)
      |> Enum.sort_by(&{&1.from, &1.to})

    {nodes, edges}
  end

  defp refs(%{"@id" => id} = map) when map_size(map) == 1, do: [id]
  defp refs(list) when is_list(list), do: Enum.flat_map(list, &refs/1)
  defp refs(_value), do: []

  @rank %{website: 0, identity: 1, webpage: 2, main: 3, breadcrumb: 4, service: 5, linked: 6, nested: 7, potential: 8}
  @property_rank %{"author" => 0, "image" => 1, "video" => 2, "offers" => 3, "aggregateRating" => 4, "review" => 5}

  defp layout({nodes, edges}) do
    layered = assign_layers(nodes, edges)

    rows =
      layered
      |> Enum.group_by(& &1.layer)
      |> Enum.sort_by(&elem(&1, 0))
      |> Enum.map(fn {layer, members} -> {layer, Enum.sort_by(members, &order_key/1)} end)

    width = canvas_width_for(rows)

    positioned =
      Enum.flat_map(rows, fn {layer, members} ->
        count = length(members)
        start = div(width - (count * @node_width + (count - 1) * @gap_x), 2)

        members
        |> Enum.with_index()
        |> Enum.map(fn {node, index} ->
          %{node | x: start + index * (@node_width + @gap_x), y: @pad + layer * (@node_height + @gap_y)}
        end)
      end)

    by_key = Map.new(positioned, &{&1.key, &1})
    nodes = Enum.map(nodes, &Map.fetch!(by_key, &1.key))
    {nodes, Enum.map(edges, &route(&1, by_key)), width}
  end

  defp assign_layers(nodes, edges) do
    fixed = %{website: 0, identity: 1, webpage: 1, main: 2, breadcrumb: 2, service: 2}

    {fixed_nodes, free} = Enum.split_with(nodes, &Map.has_key?(fixed, &1.role))
    fixed_nodes = Enum.map(fixed_nodes, &%{&1 | layer: Map.fetch!(fixed, &1.role)})

    place_free(free, fixed_nodes, edges)
  end

  # Linked, nested and potential nodes sit a layer below the node that links
  # to them, so an author's own image goes under the author.
  defp place_free([], placed, _edges), do: placed

  defp place_free(free, placed, edges) do
    layers = Map.new(placed, &{&1.key, &1.layer})

    {ready, waiting} =
      Enum.split_with(free, fn node -> parent_layer(node, layers, edges) != :pending end)

    case ready do
      [] ->
        placed ++ Enum.map(waiting, &%{&1 | layer: 3})

      ready ->
        ready = Enum.map(ready, &%{&1 | layer: parent_layer(&1, layers, edges) + 1})
        place_free(waiting, placed ++ ready, edges)
    end
  end

  defp parent_layer(node, layers, edges) do
    parents =
      case node.parent do
        nil -> for %{from: from, to: to} <- edges, to == node.key, do: from
        parent -> [parent]
      end

    case parents |> Enum.map(&Map.get(layers, &1)) |> Enum.reject(&is_nil/1) do
      [] when parents == [] -> 2
      [] -> :pending
      found -> Enum.min(found)
    end
  end

  defp order_key(node) do
    {Map.fetch!(@rank, node.role), key_index(node.parent), Map.get(@property_rank, node.property || property_of(node), 9),
     key_index(node.key)}
  end

  defp key_index(nil), do: -1
  defp key_index("n" <> index), do: String.to_integer(index)

  defp property_of(%{type: "Person"}), do: "author"
  defp property_of(%{type: "VideoObject"}), do: "video"
  defp property_of(_node), do: nil

  defp canvas_width_for(rows) do
    widest = rows |> Enum.map(fn {_layer, members} -> length(members) end) |> Enum.max(fn -> 1 end)
    # Never narrower than the canvas's CSS min-width, so a small graph is
    # drawn at the same scale as a large one rather than enlarged.
    max(widest * @node_width + (widest - 1) * @gap_x + 2 * @pad, @min_width)
  end

  defp canvas_height([]), do: 0
  defp canvas_height(nodes), do: (nodes |> Enum.map(& &1.y) |> Enum.max()) + @node_height + @pad

  # A curve from the upper node's bottom edge to the lower node's top edge,
  # or a straight line between neighbours on one row. The label sits at the
  # midpoint.
  defp route(%{from: from, to: to} = edge, by_key) do
    a = Map.fetch!(by_key, from)
    b = Map.fetch!(by_key, to)
    {upper, lower} = if a.y <= b.y, do: {a, b}, else: {b, a}

    if upper.y == lower.y do
      {left, right} = if upper.x <= lower.x, do: {upper, lower}, else: {lower, upper}
      y = left.y + div(@node_height, 2)
      x1 = left.x + @node_width
      x2 = right.x

      Map.merge(edge, %{path: "M#{x1} #{y} L#{x2} #{y}", label_x: div(x1 + x2, 2), label_y: y - 6})
    else
      x1 = upper.x + div(@node_width, 2)
      y1 = upper.y + @node_height
      x2 = lower.x + div(@node_width, 2)
      y2 = lower.y
      mid = div(y1 + y2, 2)

      Map.merge(edge, %{
        path: "M#{x1} #{y1} C#{x1} #{mid} #{x2} #{mid} #{x2} #{y2}",
        label_x: div(x1 + x2, 2),
        label_y: mid + 4
      })
    end
  end

  ## Helpers for callers

  @doc "Whether `module`'s JSON-LD includes the videos it shows."
  @spec videos?(module()) :: boolean()
  def videos?(module) do
    case schema_entity(module) do
      %{videos: true, schema: schema} -> Map.has_key?(schema.__struct__(), :video)
      _ -> false
    end
  end

  defp video_fields?(module),
    do: function_exported?(module, :__video_fields__, 0) and module.__video_fields__() != []

  defp blocks?(module),
    do: function_exported?(module, :__blocks_fields__, 0) and module.__blocks_fields__() != []
end
