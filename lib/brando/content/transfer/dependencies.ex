defmodule Brando.Content.Transfer.Dependencies do
  use Gettext, backend: Brando.Gettext
  @moduledoc false
  import Ecto.Query, only: [from: 2]
  alias Brando.Content.Transfer.{Archive, Catalog, Contracts, Error, Media, Portable}
  alias Brando.Content.Definition.Value
  alias Brando.Drafts.Params
  alias Brando.Repo

  @schemas %{
    "module" => Brando.Content.Module,
    "table_template" => Brando.Content.TableTemplate,
    "container" => Brando.Content.Container,
    "palette" => Brando.Content.Palette,
    "fragment" => Brando.Pages.Fragment,
    "identifier" => Brando.Content.Identifier,
    "image" => Brando.Images.Image,
    "file" => Brando.Files.File,
    "video" => Brando.Videos.Video,
    "gallery" => Brando.Galleries.Gallery,
    "module_set" => Brando.Content.ModuleSet,
    "markdown_source" => Brando.MarkdownSources.Source,
    "markdown_version" => Brando.MarkdownSources.Version
  }
  def kinds, do: ["entry" | Map.keys(@schemas)]

  def validate!(%{"kind" => kind} = dep) do
    if kind == "entry" do
      Value.nonempty!(dep["schema"], "referenced entry schema")
      Value.nonempty!(dep["entry_key"], "referenced entry identity")
    end

    if kind in ~w(module table_template), do: Value.nonempty!(dep["uid"], "definition UID")

    if kind == "module" do
      contract = dep["contract"]

      unless is_map(contract) && is_map(contract["refs"]) && is_map(contract["vars"]) &&
               (is_nil(contract["table"]) || is_map(contract["table"])),
             do: Error.fail!(dgettext("content_transfer", "Invalid module compatibility contract."))
    end

    allowed =
      case kind do
        "image" ->
          ~w(title credits alt focal width height config_target path fetchpriority)

        "file" ->
          ~w(title mime_type filesize filename config_target)

        "video" ->
          ~w(type title caption aspect_ratio width height duration autoplay preload loop controls muted source_url remote_id config_target file_id thumbnail_id)

        "markdown_source" ->
          ~w(name title key provider source_key version sha256)

        "markdown_version" ->
          ~w(name title key provider source_key version sha256)

        _ ->
          nil
      end

    if allowed, do: Value.keys!(dep["data"], allowed, "#{kind} metadata")

    if kind == "gallery" do
      unless is_list(dep["objects"]) && length(dep["objects"]) <= 5_000,
        do: Error.fail!(dgettext("content_transfer", "Invalid gallery object list."))

      Value.unique!(Enum.map(dep["objects"], & &1["key"]), "gallery objects")
      Enum.each(dep["objects"], &Value.keys!(&1, ~w(key image_id video_id config sequence), "gallery object"))
    end

    :ok
  end

  def schema!(kind),
    do: @schemas[kind] || Error.fail!(dgettext("content_transfer", "Unsupported dependency %{value1}.", value1: kind))

  def new(actor, opts), do: %{actor: actor, include_media: Keyword.get(opts, :media, true), dependencies: %{}, files: %{}}

  def add_entry(schema, id, state) do
    id = Catalog.id!(id)
    key = "#{schema}:#{id}"
    token = "entry:" <> Value.digest(key)

    if Map.has_key?(state.dependencies, token) do
      {token, state}
    else
      entry = Brando.Content.Transfer.EntryCodec.load!(schema, id, state.actor, :export)

      dep = %{
        "kind" => "entry",
        "source_id" => id,
        "schema" => to_string(schema),
        "entry_key" => key,
        "hints" => Catalog.hints(entry),
        "label" => label(entry)
      }

      {token, put_in(state.dependencies[token], dep)}
    end
  end

  def add(_, nil, state), do: {nil, state}

  def add(kind, id, state) do
    id = Catalog.id!(id)
    token = "#{kind}:#{id}"

    if Map.has_key?(state.dependencies, token) do
      {token, state}
    else
      record = load!(kind, id, state.actor, :export)
      state = put_in(state.dependencies[token], %{"kind" => kind})
      {data, state} = describe(kind, record, state)
      dependency = Map.merge(data, %{"kind" => kind, "source_id" => id, "label" => label(record)})
      {token, put_in(state.dependencies[token], dependency)}
    end
  end

  def add_set(title, state) do
    set =
      Repo.get_by(Brando.Content.ModuleSet, title: title) ||
        Error.fail!(dgettext("content_transfer", "Module set “%{value1}” is missing.", value1: title))

    add("module_set", set.id, state)
  end

  def load!(kind, id, actor, action \\ :read)

  def load!(%{"kind" => "entry", "schema" => schema}, id, actor, action),
    do: Brando.Content.Transfer.EntryCodec.load!(schema, id, actor, action)

  def load!(%{"kind" => kind}, id, actor, action), do: load!(kind, id, actor, action)

  def load!(kind, id, actor, action) do
    record =
      Repo.get(schema!(kind), id) ||
        Error.fail!(dgettext("content_transfer", "The %{value1} dependency is missing.", value1: kind))

    if Map.get(record, :deleted_at),
      do: Error.fail!(dgettext("content_transfer", "The %{value1} dependency has been deleted.", value1: kind))

    authorize!(kind, record, actor, action)
    record
  end

  defp authorize!("identifier", record, actor, action) do
    schema =
      Brando.Authorization.Catalog.schema(record.schema) ||
        Error.fail!(dgettext("content_transfer", "The referenced content type is not registered."))

    entry =
      Repo.get(schema, record.entry_id) || Error.fail!(dgettext("content_transfer", "The referenced entry is missing."))

    if Map.get(entry, :deleted_at), do: Error.fail!(dgettext("content_transfer", "The referenced entry was deleted."))
    Catalog.authorize!(actor, action, entry)
  end

  defp authorize!(kind, _record, actor, action) when kind in ~w(markdown_source markdown_version) do
    if Brando.MarkdownSources.authorize(actor, if(action == :export, do: :read, else: action)) != :ok,
      do: Error.fail!(dgettext("content_transfer", "You do not have permission to access this Markdown source."))
  end

  defp authorize!(_, record, actor, action), do: Catalog.authorize!(actor, action, record)

  defp describe("module", record, state) do
    if record.source_module_id,
      do: Error.fail!(dgettext("content_transfer", "Shared module overrides are not supported by content transfer."))

    record = Repo.preload(record, [:refs, :vars])
    {table, state} = add("table_template", record.table_template_id, state)
    {parent, state} = add("module", record.parent_id, state)

    {%{
       "uid" => record.uid,
       "contract" => Contracts.capture(record),
       "definition" => Contracts.normalized(record),
       "table_template" => table,
       "parent" => parent
     }, state}
  end

  defp describe("table_template", record, state) do
    record = Repo.preload(record, :vars)
    {%{"uid" => record.uid, "contract" => Contracts.table(record)}, state}
  end

  defp describe("identifier", record, state) do
    entry = Repo.get!(record.schema, record.entry_id)

    {%{
       "schema" => to_string(record.schema),
       "entry_key" => "#{record.schema}:#{record.entry_id}",
       "hints" => Catalog.hints(entry),
       "language" => to_string(record.language),
       "url" => record.url
     }, state}
  end

  defp describe("fragment", record, state),
    do:
      {%{
         "schema" => to_string(record.__struct__),
         "entry_key" => "#{record.__struct__}:#{record.id}",
         "hints" => Catalog.hints(record)
       }, state}

  defp describe("container", record, state) do
    {palette, state} = add("palette", record.palette_id, state)

    {%{
       "palette" => palette,
       "definition" =>
         record |> Params.snapshot() |> Map.take(~w(name namespace type code allow_custom_palette palette_namespace))
     }, state}
  end

  defp describe("palette", record, state),
    do: {%{"definition" => record |> Params.snapshot() |> Map.drop(~w(id deleted_at status))}, state}

  defp describe("module_set", record, state) do
    record = Repo.preload(record, :module_set_modules)

    {members, state} =
      Enum.map_reduce(record.module_set_modules, state, fn member, acc -> add("module", member.module_id, acc) end)

    {%{"members" => members}, state}
  end

  defp describe("gallery", record, state) do
    record = Repo.preload(record, :gallery_objects)

    {objects, state} =
      Enum.map_reduce(record.gallery_objects, state, fn object, acc ->
        {data, acc} =
          object |> Params.snapshot() |> Map.take(~w(image_id video_id config sequence)) |> Portable.encode_values(acc)

        {Map.put(data, "key", "gallery_object:#{object.id}"), acc}
      end)

    {%{"config_target" => record.config_target, "objects" => objects}, state}
  end

  defp describe("video", record, state) do
    {data, state} =
      record
      |> Params.snapshot()
      |> Map.take(
        ~w(type title caption aspect_ratio width height duration autoplay preload loop controls muted source_url remote_id config_target file_id thumbnail_id)
      )
      |> Portable.encode_values(state)

    {%{"data" => data}, state}
  end

  defp describe(kind, record, state) when kind in ~w(image file) do
    fields =
      if kind == "image",
        do: ~w(title credits alt focal width height config_target path fetchpriority),
        else: ~w(title mime_type filesize filename config_target)

    data = record |> Params.snapshot() |> Map.take(fields)

    {original, state} =
      if state.include_media do
        body = Media.read_original!(kind, record)
        sha = Archive.checksum(body)
        path = "media/" <> sha
        total = Enum.reduce(state.files, 0, fn {_, file}, bytes -> bytes + byte_size(file) end)

        if !Map.has_key?(state.files, path) && total + byte_size(body) > 248_000_000,
          do:
            Error.fail!(
              dgettext(
                "content_transfer",
                "The originals exceed the bundle limit. Export fewer fields or omit media originals."
              )
            )

        {%{"sha256" => sha, "bytes" => byte_size(body), "path" => path},
         %{state | files: Map.put(state.files, path, body)}}
      else
        {nil, state}
      end

    {%{"data" => data, "original" => original}, state}
  end

  defp describe(kind, record, state) when kind in ~w(markdown_source markdown_version),
    do:
      {%{
         "unsupported" =>
           "Map this Markdown source and immutable version on the destination; service credentials are not included.",
         "data" => record |> Params.snapshot() |> Map.take(~w(name title key provider source_key version sha256))
       }, state}

  def label(%Brando.Galleries.GalleryObject{} = record),
    do: "Gallery #{record.gallery_id} · item #{(record.sequence || 0) + 1}"

  def label(%Brando.MarkdownSources.Version{} = record), do: "#{record.path} · #{String.slice(record.commit || "", 0, 8)}"

  def label(record) do
    value =
      Map.get(record, :name) || Map.get(record, :title) || Map.get(record, :path) || Map.get(record, :filename) ||
        "#{record.__struct__ |> Module.split() |> List.last() |> Macro.underscore() |> Phoenix.Naming.humanize()} ##{record.id}"

    if is_map(value),
      do:
        Brando.Type.I18nString.get(value, nil) || value |> Map.values() |> Enum.find(&(&1 not in [nil, ""])) || "Untitled",
      else: to_string(value)
  end

  def identifier_for_meta!(key) do
    case Regex.run(~r/^(.*)_(\d+)$/, key) do
      [_, schema_name, id] ->
        schema =
          Enum.find(Brando.Authorization.Catalog.schemas(), &(inspect(&1) == schema_name || to_string(&1) == schema_name)) ||
            Error.fail!(dgettext("content_transfer", "Unknown selected-entry metadata schema."))

        Repo.get_by(Brando.Content.Identifier, schema: schema, entry_id: Catalog.id!(id)) ||
          Error.fail!(dgettext("content_transfer", "Selected-entry metadata references a missing identifier."))

      _ ->
        Error.fail!(dgettext("content_transfer", "Selected-entry metadata has an invalid reference."))
    end
  end

  def suggestions(dependency, actor) do
    kind = dependency["kind"]

    cond do
      kind in ~w(image file) && dependency["original"] ->
        Brando.Content.Transfer.history(actor)
        |> Enum.flat_map(&(&1.mappings["transferred_media"] || []))
        |> Enum.filter(&(&1["kind"] == kind && &1["sha256"] == dependency["original"]["sha256"]))
        |> Enum.uniq_by(& &1["id"])
        |> Enum.flat_map(fn saved ->
          case Error.protect(fn ->
                 record = load!(kind, saved["id"], actor)

                 if Archive.checksum(Media.read_original!(kind, record)) == saved["sha256"],
                   do: [%{id: record.id, label: label(record), match: :checksum}],
                   else: []
               end) do
            {:ok, suggestions} -> suggestions
            _ -> []
          end
        end)

      kind in ~w(identifier fragment entry) ->
        try do
          Catalog.candidates(dependency, actor, :read)
          |> Enum.flat_map(fn entry ->
            if kind == "identifier" do
              case Repo.get_by(Brando.Content.Identifier,
                     schema: Brando.Authorization.Catalog.schema(entry.schema),
                     entry_id: entry.id
                   ) do
                nil -> []
                identifier -> [%{id: identifier.id, label: entry.title, match: :suggestion}]
              end
            else
              [%{id: entry.id, label: entry.title, match: :suggestion}]
            end
          end)
        rescue
          _ in Error -> []
        end

      kind in ~w(module table_template) ->
        schema = schema!(kind)

        query =
          if kind == "module",
            do: from(r in schema, where: is_nil(r.deleted_at), preload: [:refs, :vars]),
            else: from(r in schema, preload: [:vars])

        query = Catalog.scoped_query(query, schema, actor, :read)
        exact = Repo.one(from(r in query, where: r.uid == ^dependency["uid"]))
        candidates = if exact, do: [exact], else: if(kind == "module", do: Repo.all(query), else: [])

        candidates
        |> Enum.filter(&(Brando.Authorization.Boundary.authorize(actor, :read, &1) == :ok))
        |> Enum.filter(fn record ->
          record.uid == dependency["uid"] ||
            (kind == "module" && Contracts.normalized(record) == dependency["definition"])
        end)
        |> Enum.map(&%{id: &1.id, label: label(&1), match: if(&1.uid == dependency["uid"], do: :uid, else: :suggestion)})

      true ->
        []
    end
  end

  def options(kind, actor, query \\ "")

  def options(%{"kind" => "entry", "schema" => name}, actor, query) do
    Brando.Content.Transfer.EntryCodec.schema!(name)
    |> then(&Catalog.search(actor, query, schema: &1, action: :read, entries: true))
    |> Enum.map(&%{id: &1.id, label: &1.title})
  end

  def options(%{"kind" => kind}, actor, query), do: options(kind, actor, query)

  def options(kind, actor, query) do
    schema = schema!(kind)
    label_fields = Enum.filter([:name, :title, :path, :filename], &(&1 in schema.__schema__(:fields)))
    label_fields = if label_fields == [], do: [:id], else: label_fields

    # Match the same fallback order as label/1. Untitled media must remain
    # selectable and searchable by path/filename rather than disappearing in SQL.
    label =
      label_fields
      |> Enum.reverse()
      |> Enum.reduce(Ecto.Query.dynamic([r], ""), fn key, fallback ->
        Ecto.Query.dynamic([r], fragment("COALESCE(CAST(? AS text), ?)", field(r, ^key), ^fallback))
      end)

    # Restrict in SQL before loading assets. The cast also supports translated
    # module names stored as maps. Record authorization is checked below too.
    pattern =
      "%" <>
        (query
         |> String.slice(0, 150)
         |> String.replace("\\", "\\\\")
         |> String.replace("%", "\\%")
         |> String.replace("_", "\\_")) <> "%"

    matching = Ecto.Query.dynamic([r], ilike(^label, ^pattern))

    from(r in schema,
      where: ^matching,
      order_by: [desc: r.id],
      limit: 100
    )
    |> scope_options(kind, schema, actor)
    |> Repo.all()
    |> Enum.filter(&is_nil(Map.get(&1, :deleted_at)))
    |> Enum.filter(fn record ->
      case Error.protect(fn -> authorize!(kind, record, actor, :read) end) do
        {:ok, _} -> String.contains?(String.downcase(label(record)), String.downcase(query))
        _ -> false
      end
    end)
    |> Enum.sort_by(&label/1)
    |> Enum.take(100)
    |> Enum.map(&%{id: &1.id, label: label(&1)})
  end

  def fingerprint(record), do: record |> Params.snapshot() |> Value.digest()

  defp scope_options(query, "identifier", _, actor),
    do:
      Brando.Authorization.Boundary.with_scope(Brando.Authorization.Boundary.actor_scope(actor), fn ->
        Brando.Authorization.Boundary.identifiers(query)
      end)

  defp scope_options(query, kind, _, actor) when kind in ~w(markdown_source markdown_version),
    do: if(Brando.MarkdownSources.authorize(actor, :read) == :ok, do: query, else: from(r in query, where: false))

  defp scope_options(query, _, schema, actor), do: Catalog.scoped_query(query, schema, actor, :read)
end
