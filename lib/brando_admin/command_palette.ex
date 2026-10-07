defmodule BrandoAdmin.CommandPalette do
  @moduledoc """
  What the command palette (⌘K) lists, for one user in the current site and
  environment.

  `context/2` is worked out when the palette opens: the Configuration screens
  and content types the user may open, from the same menu as the sidebar, and
  whether the assistant and Utilities are theirs to use. `results/4` turns a
  query into groups of rows from that context, `content_identifiers` and the
  asset tables.

  A query is matched against entry titles: an exact title first, then titles
  that start with it, then titles that contain it. Published entries come
  before pending ones and drafts, then entries in the user's content language.
  An entry is listed only when the user may read and edit it, exactly as the
  dashboard decides, so every row opens. A query starting with `>` lists
  commands only: actions and settings.

  Recent places are kept by the browser (see `assets/src/hooks/CommandPalette`)
  and handed to `results/4`; the server only checks and labels them.
  """
  use Gettext, backend: Brando.Gettext

  import Ecto.Query, only: [from: 2]

  alias Brando.Authorization.{Boundary, Scope}
  alias Brando.Blueprint
  alias Brando.Content.Identifier
  alias Brando.Repo

  @entry_limit 6
  @recent_limit 8
  @action_limit 6
  @setting_limit 5
  # Identifiers read per round while looking for entries the user may open.
  @batch 24
  @max_batches 4

  @type item :: %{
          required(:id) => String.t(),
          required(:kind) => :entry | :action | :setting | :recent,
          required(:label) => String.t(),
          required(:url) => String.t(),
          optional(atom()) => any()
        }
  @type group :: %{key: atom(), label: String.t(), items: [item()]}

  @doc """
  What the user may reach from the palette, worked out once per opening.
  """
  def context(user, site \\ nil) do
    menu = BrandoAdmin.Menu.get_menu(user, site)
    links = menu_links(menu)
    paths = Enum.map(links, &elem(&1, 0))

    %{
      user: user,
      settings: settings(menu),
      places: places(menu),
      content_types: content_types(user, links),
      assets: asset_types(paths),
      assistant?: assistant?(user),
      utilities: utilities(paths),
      entry_scope: entry_scope(user)
    }
  end

  @doc """
  The palette's groups for `query`. `recent` is the browser's list of
  `%{"path" => …, "title" => …}`, most recent first.
  """
  @spec results(map(), String.t() | nil, [map()], keyword()) :: [group()]
  def results(context, query, recent \\ [], opts \\ []) do
    case parse(query) do
      :empty -> empty_groups(context, recent, opts)
      {:commands, term} -> command_groups(context, term)
      {:search, term} -> search_groups(context, term, recent, opts)
    end
  end

  @doc "How the palette reads a query: nothing, commands (`>`), or a search."
  def parse(query) do
    case String.trim(query || "") do
      "" -> :empty
      ">" <> rest -> {:commands, String.trim(rest)}
      term -> {:search, term}
    end
  end

  ## Groups

  defp empty_groups(context, recent, opts) do
    [
      group(:recent, gettext("Recent"), recent_items(context, recent, nil, opts[:current_path])),
      group(:actions, gettext("Actions"), common_actions(context))
    ]
    |> reject_empty()
  end

  defp command_groups(context, term) do
    actions =
      Enum.filter(
        create_actions(context.content_types) ++ assistant_actions(context, nil) ++ context.utilities,
        &matches?(&1, term)
      )

    [
      group(:actions, gettext("Actions"), actions),
      group(:settings, gettext("Settings"), Enum.filter(context.settings, &matches?(&1, term)))
    ]
    |> reject_empty()
  end

  defp search_groups(context, term, recent, opts) do
    entries =
      entries(context.user, term, [scope: context.entry_scope] ++ Keyword.take(opts, [:language, :limit]))

    actions =
      assistant_actions(context, term) ++
        asset_actions(context, term) ++
        Enum.take(create_matches(context, term, entries), 3) ++
        Enum.filter(context.utilities, &matches?(&1, term))

    [
      group(:entries, gettext("Entries"), entries),
      group(:actions, gettext("Actions"), Enum.take(actions, @action_limit)),
      group(
        :settings,
        gettext("Settings"),
        Enum.take(Enum.filter(context.settings, &matches?(&1, term)), @setting_limit)
      ),
      group(:recent, gettext("Recent"), recent_items(context, recent, term, opts[:current_path]) |> Enum.take(3))
    ]
    |> reject_empty()
  end

  defp group(key, label, items), do: %{key: key, label: label, items: items}
  defp reject_empty(groups), do: Enum.reject(groups, &(&1.items == []))

  ## Entries

  @doc """
  Entries whose title matches `term`, ranked exact > prefix > contains, then
  published before drafts, then the user's content language. Only entries the
  user may read and edit, in the current site and environment.

  Options: `:limit` (default #{@entry_limit}), `:language` to prefer, and
  `:scope`, a query from `entry_scope/1`.
  """
  def entries(user, term, opts \\ []) do
    case term |> String.trim() |> String.downcase() do
      "" -> []
      term -> in_scope(user, fn -> find_entries(user, term, opts) end)
    end
  end

  # The user's authorization scope and tenant, as the listings read them.
  defp in_scope(user, fun) do
    scope = Boundary.actor_scope(user)
    Boundary.with_scope(scope, fn -> Brando.Tenant.with_prefix(scope.prefix || Brando.Tenant.current_prefix(), fun) end)
  end

  defp find_entries(user, term, opts) do
    language = Keyword.get(opts, :language) || content_language(user)
    base = Keyword.get_lazy(opts, :scope, fn -> entry_scope(user) end)
    query = entry_query(base, term, language)
    permissions = permissions(user)

    Stream.unfold(0, &next_batch(query, &1))
    |> Stream.flat_map(&openable(permissions, &1))
    |> Enum.take(Keyword.get(opts, :limit, @entry_limit))
    |> Enum.map(&entry_item/1)
  end

  defp next_batch(_query, offset) when offset >= @batch * @max_batches, do: nil

  defp next_batch(query, offset) do
    case Repo.all(from(i in query, limit: @batch, offset: ^offset)) do
      [] -> nil
      # A short batch was the last one
      batch -> {batch, if(Enum.count(batch) < @batch, do: @batch * @max_batches, else: offset + @batch)}
    end
  end

  @doc """
  The identifiers the user may read, as a query to search in. Building it
  checks every content type's read policy, so the palette builds it once per
  opening and narrows it for each query.
  """
  def entry_scope(user) do
    scope = Boundary.actor_scope(user)
    schemas = searchable_schemas()

    Boundary.with_scope(scope, fn ->
      Boundary.identifiers(from(i in Identifier, where: i.schema in ^schemas))
    end)
  end

  @doc """
  Narrows `base` (from `entry_scope/1`) to titles containing `term`, ranked:
  an exact title, then titles starting with `term`, then the rest; published,
  pending, draft, disabled; `language` first; shorter titles, then the most
  recently updated. The source records are checked after this query.
  """
  def entry_query(base, term, language) do
    like = escape_like(term)
    contains = "%" <> like <> "%"
    prefix = like <> "%"
    language = to_string(language || "")

    from i in base,
      where: ilike(i.title, ^contains),
      order_by: [
        asc:
          fragment(
            "CASE WHEN lower(?) = ? THEN 0 WHEN lower(?) LIKE ? THEN 1 ELSE 2 END",
            i.title,
            ^term,
            i.title,
            ^prefix
          ),
        # published, pending, draft, disabled; entries without a status are live
        asc: fragment("CASE ? WHEN 0 THEN 2 WHEN 2 THEN 1 WHEN 3 THEN 3 ELSE 0 END", i.status),
        asc: fragment("CASE WHEN ? = ? THEN 0 ELSE 1 END", i.language, ^language),
        asc: fragment("length(?)", i.title),
        desc: i.updated_at,
        desc: i.id
      ]
  end

  # Content types with an editor of their own.
  defp searchable_schemas do
    :include_brando
    |> Brando.Content.Identifier.Registry.list_persistent_identifier_modules()
    |> Enum.filter(&function_exported?(&1, :__admin_route__, 2))
    |> Enum.uniq()
  end

  # The identifiers whose entry still exists and the user may open, in order.
  # Source records are loaded with one query per content type in the batch.
  defp openable(permissions, identifiers) do
    records =
      identifiers
      |> Enum.group_by(& &1.schema, & &1.entry_id)
      |> Map.new(fn {schema, ids} ->
        {schema, Map.new(Repo.all(from(e in schema, where: e.id in ^ids)), &{&1.id, &1})}
      end)

    # Lazily: the checks stop once enough entries are found.
    Stream.flat_map(identifiers, fn identifier ->
      entry = get_in(records, [identifier.schema, identifier.entry_id])

      if entry && is_nil(Map.get(entry, :deleted_at)) && allowed?(permissions, :read, entry) &&
           allowed?(permissions, :update, entry) do
        [{identifier, entry}]
      else
        []
      end
    end)
  end

  defp entry_item({identifier, entry}) do
    %{
      id: "palette-entry-#{identifier.id}",
      kind: :entry,
      label: identifier.title,
      url: identifier.schema.__admin_route__(:update, [entry.id]),
      icon: Blueprint.get_icon(identifier.schema),
      cover: identifier.cover,
      type: Blueprint.get_singular(identifier.schema),
      schema: identifier.schema,
      language: identifier.language && identifier.language |> to_string() |> String.upcase(),
      status: identifier.status
    }
  end

  defp content_language(%{config: %{content_language: language}}) when is_binary(language), do: language
  defp content_language(_), do: to_string(Brando.config(:default_language))

  defp escape_like(term), do: String.replace(term, ["\\", "%", "_"], &("\\" <> &1))

  ## Assets

  # Images, files and videos whose name matches, linking to their library
  # filtered by the query, across every folder. One count each, only for
  # libraries in the menu.
  defp asset_actions(context, term) do
    Enum.flat_map(context.assets, fn {kind, path} ->
      case asset_count(kind, term) do
        0 ->
          []

        count ->
          [
            %{
              id: "palette-assets-#{kind}",
              kind: :action,
              label: asset_label(kind, term),
              url: path <> "?" <> URI.encode_query([{"filter:folder_id", "all"}, {asset_filter(kind), term}]),
              icon: asset_icon(kind),
              count: count
            }
          ]
      end
    end)
  end

  defp asset_count(kind, term) do
    contains = "%" <> escape_like(term) <> "%"

    query =
      case kind do
        :images ->
          from(a in Brando.Images.Image, where: ilike(a.path, ^contains))

        :files ->
          from(a in Brando.Files.File, where: ilike(a.filename, ^contains))

        :videos ->
          from(a in Brando.Videos.Video,
            where: ilike(a.title, ^contains) or ilike(a.source_url, ^contains) or ilike(a.remote_id, ^contains)
          )
      end

    Repo.aggregate(from(a in query, where: is_nil(a.deleted_at)), :count)
  end

  defp asset_label(:images, term), do: gettext("Images matching “%{query}”", query: term)
  defp asset_label(:files, term), do: gettext("Files matching “%{query}”", query: term)
  defp asset_label(:videos, term), do: gettext("Videos matching “%{query}”", query: term)

  # The library listing's own search filter for each kind.
  defp asset_filter(:files), do: "filter:filename"
  defp asset_filter(_kind), do: "filter:path"

  defp asset_icon(:images), do: "image"
  defp asset_icon(:files), do: "file"
  defp asset_icon(:videos), do: "film"

  @asset_paths [images: "/admin/assets/images", files: "/admin/assets/files", videos: "/admin/assets/videos"]

  defp asset_types(paths), do: Enum.filter(@asset_paths, fn {_kind, path} -> path in paths end)

  ## Actions

  defp common_actions(context) do
    Enum.take(create_actions(context.content_types), 3) ++ assistant_actions(context, nil)
  end

  defp assistant_actions(%{assistant?: true}, nil),
    do: [
      %{
        id: "palette-assistant",
        kind: :action,
        label: gettext("Ask the Assistant"),
        url: "/admin/assistant",
        icon: "sparkles"
      }
    ]

  defp assistant_actions(%{assistant?: true}, term) do
    [
      %{
        id: "palette-assistant",
        kind: :action,
        label: gettext("Ask the Assistant about “%{query}”", query: term),
        url: "/admin/assistant?" <> URI.encode_query(%{"prompt" => term}),
        icon: "sparkles"
      }
    ]
  end

  defp assistant_actions(_context, _term), do: []

  defp assistant?(user), do: Brando.AI.Agent.available?() and Brando.AI.Agent.allowed?(user)

  # Create actions for the types the query names, or else for the type of the
  # best entry found: "somm" finds a case, so "Create case…" is offered.
  defp create_matches(context, term, entries) do
    actions = create_actions(context.content_types)

    case Enum.filter(actions, &matches?(&1, term)) do
      [] ->
        case entries do
          [%{schema: schema} | _] -> Enum.filter(actions, &(&1.schema == schema))
          [] -> []
        end

      matching ->
        matching
    end
  end

  defp create_actions(content_types) do
    Enum.map(content_types, fn %{schema: schema, singular: singular, url: url, icon: icon} = type ->
      %{
        id: "palette-create-#{schema |> Module.split() |> Enum.join("-") |> String.downcase()}",
        kind: :action,
        label: gettext("Create %{type}…", type: String.downcase(singular)),
        url: url,
        icon: "plus",
        type_icon: icon,
        schema: schema,
        keywords: [singular, type.plural, type.listing]
      }
    end)
  end

  @doc """
  The content types the user may create, in sidebar order: a type is offered
  when its listing is in the user's menu and they may create its entries.
  `links` are the menu's `{path, name}`s; the listing's name is matched too.
  """
  def content_types(user, links) do
    listings = Enum.reject(links, &(elem(&1, 0) == "/admin"))
    permissions = permissions(user)

    searchable_schemas()
    |> Enum.flat_map(fn schema ->
      with {:ok, url} <- create_url(schema),
           position when not is_nil(position) <-
             Enum.find_index(listings, &String.starts_with?(url, elem(&1, 0) <> "/")),
           true <- allowed?(permissions, :create, schema) do
        [
          %{
            schema: schema,
            singular: Blueprint.get_singular(schema),
            plural: Blueprint.get_plural(schema),
            icon: Blueprint.get_icon(schema),
            url: url,
            listing: listings |> Enum.at(position) |> elem(1),
            position: position
          }
        ]
      else
        _ -> []
      end
    end)
    |> Enum.sort_by(& &1.position)
  end

  defp create_url(schema) do
    {:ok, schema.__admin_route__(:create, [])}
  rescue
    _ -> :error
  end

  ## Utilities

  # The maintenance tools open Utilities at their row; loose blocks has a
  # screen of its own.
  defp utilities(paths) do
    if "/admin/config/utils" in paths do
      Enum.map(
        [
          {"utils-identifiers", gettext("Sync identifiers"), "fingerprint", "/admin/config/utils#utils-identifiers"},
          {"utils-loose-blocks", gettext("Review loose blocks"), "blocks", "/admin/config/utils/loose-blocks"},
          {"utils-sitemap", gettext("Generate sitemap"), "map", "/admin/config/utils#utils-sitemap"},
          {"utils-image-sizes", gettext("Recreate image sizes"), "images", "/admin/config/utils#utils-image-sizes"},
          {"utils-dominant-colors", gettext("Recalculate colors"), "palette", "/admin/config/utils#utils-dominant-colors"}
        ],
        &utility/1
      )
    else
      []
    end
  end

  defp utility({id, label, icon, url}),
    do: %{id: "palette-" <> id, kind: :action, label: label, url: url, icon: icon, detail: gettext("Utilities")}

  ## Settings and places

  # Configuration's screens, as the sidebar shows them to this user.
  defp settings(menu) do
    menu
    |> Enum.flat_map(& &1.items)
    |> Enum.find(&(&1[:key] == :configuration))
    |> case do
      %{items: items, name: section} when is_list(items) ->
        items
        |> Enum.filter(&is_binary(&1[:url]))
        |> Enum.map(&menu_item(&1, section, :setting))

      _ ->
        []
    end
  end

  # Every other screen in the sidebar, to name the recent places.
  defp places(menu) do
    menu
    |> Enum.flat_map(& &1.items)
    |> Enum.reject(&(&1[:key] == :configuration))
    |> Enum.flat_map(fn
      %{items: [_ | _] = items, name: parent} -> Enum.map(items, &{&1, parent})
      %{url: url} = item when is_binary(url) -> [{item, nil}]
      _ -> []
    end)
    |> Enum.filter(fn {item, _} -> is_binary(item[:url]) and String.starts_with?(item.url, "/admin") end)
    |> Enum.map(fn {item, parent} -> menu_item(item, parent, :setting) end)
  end

  defp menu_item(item, parent, kind) do
    path = url_path(item.url)

    %{
      id: "palette-#{kind}-" <> (path |> String.replace(~r/[^a-z0-9]+/i, "-") |> String.trim("-")),
      kind: kind,
      label: item.name,
      url: item.url,
      path: path,
      icon: item[:icon] || BrandoAdmin.Menu.fallback_icon(),
      detail: parent
    }
  end

  defp menu_links(menu) do
    menu
    |> Enum.flat_map(& &1.items)
    |> Enum.flat_map(fn item -> [item | item[:items] || []] end)
    |> Enum.filter(&is_binary(&1[:url]))
    |> Enum.map(&{url_path(&1.url), &1.name})
  end

  defp url_path(url), do: URI.parse(url).path || url

  ## Recent

  # The browser's recent places, checked and labelled: a screen in the menu
  # takes its menu name ("Configuration → SEO"), anything else the title the
  # page had. Only admin paths are accepted.
  defp recent_items(context, recent, term, current_path) do
    named = Map.new(context.settings ++ context.places, &{&1.path, &1})

    recent
    |> List.wrap()
    |> Enum.flat_map(&recent_place(&1, named))
    |> Enum.reject(&(&1.path == current_path))
    |> Enum.uniq_by(& &1.path)
    |> Enum.filter(&(is_nil(term) or matches?(&1, term)))
    |> Enum.take(@recent_limit)
  end

  defp recent_place(%{"path" => path} = place, named) when is_binary(path) do
    with true <- admin_path?(path),
         label when is_binary(label) and label != "" <- recent_label(path, place["title"], named) do
      menu_entry = Map.get(named, url_path(path))

      [
        %{
          id: "palette-recent-" <> Base.url_encode64(:crypto.hash(:md5, path), padding: false),
          kind: :recent,
          label: label,
          url: path,
          path: url_path(path),
          icon: (menu_entry && menu_entry.icon) || "history"
        }
      ]
    else
      _ -> []
    end
  end

  defp recent_place(_place, _named), do: []

  defp recent_label(path, title, named) do
    case Map.get(named, url_path(path)) do
      %{label: label, detail: parent} when is_binary(parent) -> parent <> " → " <> label
      %{label: label} -> label
      nil when is_binary(title) -> title |> String.trim() |> String.slice(0, 160)
      nil -> nil
    end
  end

  defp admin_path?(path) do
    uri = URI.parse(path)

    is_nil(uri.scheme) and is_nil(uri.host) and is_binary(uri.path) and
      (uri.path == "/admin" or String.starts_with?(uri.path, "/admin/")) and
      not String.contains?(path, ["//", "\\", "\n", "\r"]) and
      uri.path not in ["/admin/login", "/admin/logout", "/admin/access-denied"]
  end

  ## Matching

  defp matches?(_item, ""), do: true

  defp matches?(item, term) do
    needle = String.downcase(term)

    [item.label, item[:detail] | item[:keywords] || []]
    |> Enum.filter(&is_binary/1)
    |> Enum.any?(&String.contains?(String.downcase(&1), needle))
  end

  ## Permissions

  # One authorization snapshot per search: with groups, every check would
  # otherwise read the user's groups again.
  defp permissions(user) do
    if Brando.Authorization.enabled?(),
      do: {:groups, Brando.Authorization.snapshot(Boundary.current_scope() || Scope.current(user))},
      else: {:legacy, user}
  end

  defp allowed?({:groups, snapshot}, action, subject), do: Brando.Authorization.can?(snapshot, action, subject)

  defp allowed?({:legacy, user}, action, subject) do
    subject = if is_atom(subject), do: struct(subject), else: subject
    Module.concat(Brando.authorization(), Can).can?(user, action, subject) == {:ok, :authorized}
  end
end
