defmodule BrandoAdmin.Menu do
  @moduledoc """
      import MyAppAdmin.Gettext

      menus do
        menu_item t("Projects"), icon: "folder" do
          menu_subitem t("Projects"), "/admin/projects/projects", icon: "briefcase"
          menu_subitem t("Categories"), "/admin/projects/categories", icon: "tags"
          menu_subitem MyApp.Project.Something
        end

        menu_item MyApp.Team.Member
      end

  Every item shows a [Lucide](https://lucide.dev/icons) icon in the sidebar.
  Items built from a blueprint use its `content_icon` (see
  `Brando.Blueprint.get_icon/1`); others take an `icon:` option. Names are
  checked at compile time. An item without one shows a dot, so the icon column
  stays aligned.
  """

  use Gettext, backend: Brando.Gettext

  alias Brando.Tenant

  defmacro __using__(_) do
    quote do
      import BrandoAdmin.Menu

      @before_compile BrandoAdmin.Menu
    end
  end

  defmacro __before_compile__(_) do
    quote location: :keep,
          unquote: false do
      def __menus__ do
        @menus
        |> Enum.reverse()
        |> translate_menus()
      end
    end
  end

  def translate_menus(menus) do
    Enum.map(menus, &__MODULE__.translate_menu/1)
  end

  def translate_menu(%{name: msgid, items: items} = menu) when is_nil(items) or items == [] do
    %{menu | name: translate_msgid(msgid)}
  end

  def translate_menu(%{name: msgid, items: items} = menu) do
    translated_items = translate_menus(items)
    %{menu | name: translate_msgid(msgid), items: translated_items}
  end

  def translate_menu(%{name: msgid} = menu) do
    %{menu | name: translate_msgid(msgid)}
  end

  defp translate_msgid({:translate, gettext_domain, msgid}) do
    Brando.gettext_admin()
    |> Gettext.dgettext(gettext_domain, msgid)
    |> String.capitalize()
  end

  defp translate_msgid(msgid) do
    Gettext.dgettext(Brando.gettext_admin(), "menus", msgid)
  end

  defmacro menus(do: block) do
    menus(__CALLER__, block)
  end

  defp menus(_caller, block) do
    quote generated: true, location: :keep do
      Module.register_attribute(__MODULE__, :menus, accumulate: true)
      unquote(block)
    end
  end

  @fallback_icon "dot"

  @doc "The icon shown for menu items that set none."
  def fallback_icon, do: @fallback_icon

  @doc """
  Raises unless `icon` is nil or a current Lucide icon name. Called at compile
  time by the menu macros.
  """
  def validate_icon!(nil), do: nil

  def validate_icon!(icon) do
    if Brando.Icons.exists?(icon) do
      icon
    else
      hint =
        case Brando.Icons.resolve(icon) do
          {:ok, current} -> "use #{inspect(current)}"
          :error -> "see https://lucide.dev/icons"
        end

      raise ArgumentError, "unknown menu icon #{inspect(icon)}, #{hint}"
    end
  end

  @doc """
  Generate a menu item from blueprint schema
  """
  defmacro menu_item(schema) do
    do_menu_item(:schema, schema, nil, [])
  end

  defmacro menu_item(name, do: block) do
    do_menu_item(:block, name, [], do: block)
  end

  defmacro menu_item(name, url) when is_binary(url) do
    do_menu_item(:url, name, url, [])
  end

  defmacro menu_item(schema, opts) when is_list(opts) do
    do_menu_item(:schema, schema, nil, opts)
  end

  defmacro menu_item(name, schema) do
    do_menu_item(:schema, schema, name, [])
  end

  defmacro menu_item(name, opts, do: block) when is_list(opts) do
    do_menu_item(:block, name, opts, do: block)
  end

  defmacro menu_item(name, url, opts) when is_binary(url) do
    do_menu_item(:url, name, url, opts)
  end

  defmacro menu_item(name, schema, opts) do
    do_menu_item(:schema, schema, name, opts)
  end

  defp do_menu_item(:schema, schema, name, opts) do
    quote location: :keep,
          generated: true,
          bind_quoted: [schema: schema, name: name, opts: opts] do
      domain = schema.__naming__().domain
      snake_domain = Macro.underscore(domain)
      schema_name = schema.__naming__().schema
      plural = schema.__naming__().plural

      url_base = "/admin/#{snake_domain}/#{plural}"
      default_listing = Enum.find(schema.__listings__(), &(&1.name == :default))

      if !default_listing do
        raise Brando.Exception.BlueprintError,
          message: "Missing default listing for menu_item `#{inspect(schema)}`"
      end

      query_params = BrandoAdmin.Menu.encode_listing_query(default_listing.query)

      name =
        if name do
          name
        else
          msgid = Brando.Utils.humanize(plural, :downcase)
          gettext_domain = String.downcase("#{domain}_#{schema_name}")
          {:translate, gettext_domain, msgid}
        end

      url = Enum.join([url_base, query_params], "?")
      icon = BrandoAdmin.Menu.validate_icon!(opts[:icon]) || Brando.Blueprint.get_icon(schema)

      Module.put_attribute(__MODULE__, :menus, %{
        name: name,
        url: url,
        icon: icon
      })
    end
  end

  defp do_menu_item(:block, name, opts, do: block) do
    quote location: :keep,
          generated: true do
      var!(b_menu_subitems) = []
      subitems = unquote(block)

      Module.put_attribute(__MODULE__, :menus, %{
        name: unquote(name),
        items: Enum.reverse(subitems),
        url: nil,
        icon: BrandoAdmin.Menu.validate_icon!(unquote(opts)[:icon]) || BrandoAdmin.Menu.fallback_icon()
      })
    end
  end

  defp do_menu_item(:url, name, url, opts) do
    quote location: :keep,
          generated: true,
          bind_quoted: [name: name, url: url, opts: opts] do
      icon = BrandoAdmin.Menu.validate_icon!(opts[:icon]) || BrandoAdmin.Menu.fallback_icon()
      Module.put_attribute(__MODULE__, :menus, %{name: name, url: url, icon: icon})
    end
  end

  @doc "Encodes a listing query as the query string of a menu item's URL."
  def encode_listing_query(query) do
    query
    |> strip_preloads()
    |> encode_advanced_order()
    |> Plug.Conn.Query.encode()
    |> String.replace("%3A", ":")
    |> String.replace("%5B", "[")
    |> String.replace("%5D", "]")
  end

  def strip_preloads(query) do
    Map.delete(query, :preload)
  end

  def encode_advanced_order(%{order: orders} = query) when is_binary(orders) do
    query
  end

  def encode_advanced_order(%{order: orders} = query) do
    order_string =
      orders
      |> stringify_orders()
      |> Enum.join(", ")

    Map.put(query, :order, order_string)
  end

  def encode_advanced_order(query), do: query

  defp stringify_orders(orders) do
    Enum.reduce(orders, [], fn
      {dir, {relation, field}}, acc ->
        acc ++ List.wrap("#{dir} #{relation}.#{field}")

      {dir, field}, acc ->
        acc ++ List.wrap("#{dir} #{field}")
    end)
  end

  defmacro menu_subitem(schema) do
    do_menu_subitem(schema, [])
  end

  defmacro menu_subitem(schema, opts) when is_list(opts) do
    do_menu_subitem(schema, opts)
  end

  defmacro menu_subitem(name, url) do
    do_menu_subitem(name, url, [])
  end

  defmacro menu_subitem(name, url, opts) do
    do_menu_subitem(name, url, opts)
  end

  defp do_menu_subitem(schema, opts) do
    quote location: :keep,
          generated: true,
          bind_quoted: [schema: schema, opts: opts] do
      domain = schema.__naming__().domain
      snake_domain = Macro.underscore(domain)
      schema_name = schema.__naming__().schema
      plural = schema.__naming__().plural
      msgid = Brando.Utils.humanize(plural, :downcase)

      url_base = "/admin/#{snake_domain}/#{plural}"
      default_listing = Enum.find(schema.__listings__(), &(&1.name == :default))

      if !default_listing do
        raise Brando.Exception.BlueprintError,
          message: "Missing default listing for menu_subitem `#{inspect(schema)}`"
      end

      query_params = BrandoAdmin.Menu.encode_listing_query(default_listing.query)

      url = Enum.join([url_base, query_params], "?")
      gettext_domain = String.downcase("#{domain}_#{schema_name}")
      icon = BrandoAdmin.Menu.validate_icon!(opts[:icon]) || Brando.Blueprint.get_icon(schema)

      var!(b_menu_subitems) = [
        %{name: {:translate, gettext_domain, msgid}, url: url, icon: icon} | var!(b_menu_subitems)
      ]
    end
  end

  defp do_menu_subitem(name, url, opts) do
    quote location: :keep,
          generated: true do
      icon = BrandoAdmin.Menu.validate_icon!(unquote(opts)[:icon]) || BrandoAdmin.Menu.fallback_icon()
      var!(b_menu_subitems) = [%{name: unquote(name), url: unquote(url), icon: icon} | var!(b_menu_subitems)]
    end
  end

  defmacro t(msgid) do
    quote do
      dgettext("menus", unquote(msgid))
    end
  end

  # Shown to users who may use the assistant, when a model is configured or
  # proposals from connected tools (MCP) wait for their review: those need no
  # model to be reviewed and applied.
  defp assistant_menu_item(current_user) do
    if current_user && Brando.AI.Agent.allowed?(current_user) &&
         (Brando.AI.Agent.available?() || external_proposals?(current_user)),
       do: %{name: gettext("Assistant"), url: "/admin/assistant", icon: "sparkles"}
  end

  defp external_proposals?(current_user) do
    Brando.Content.Proposals.count_external(current_user) > 0
  rescue
    _ -> false
  end

  # Shown to users who may configure the assistant; superusers by default.
  defp assistant_guidance_menu_item(current_user) do
    if current_user && Brando.AI.Agent.Guidance.configurable?(current_user),
      do: %{name: gettext("Assistant guidance"), url: "/admin/config/assistant", icon: "message-square-text"}
  end

  @doc """
  The sidebar's sections for `current_user`: `[%{name: "System", items: [...]}, ...]`.
  An item links (`url`) or opens a submenu (`items`). A submenu may also carry
  `groups`, `[%{key: :site, name: "Site"}, ...]`, with each of its items naming
  one as `group`; the sidebar shows those items under the group's heading (see
  `grouped_items/1`), while `items` stays one flat list in group order.
  """
  def get_menu(current_user \\ nil, current_site \\ nil) do
    content_menus = Brando.admin_module(Menus).__menus__()

    menus = [
      %{
        name: gettext("System"),
        items:
          [
            %{
              name: gettext("Dashboard"),
              icon: "layout-dashboard",
              url: "/admin"
            },
            %{
              name: gettext("Calendar"),
              icon: "calendar-days",
              url: "/admin/calendar"
            },
            assistant_menu_item(current_user),
            sites_menu_item(current_user),
            configuration_menu_item(current_user, current_site),
            %{
              name: gettext("Assets"),
              icon: "images",
              url: nil,
              items: [
                %{
                  name: gettext("Images"),
                  icon: "image",
                  url: "/admin/assets/images"
                },
                %{
                  name: gettext("Files"),
                  icon: "file",
                  url: "/admin/assets/files"
                },
                %{
                  name: gettext("Videos"),
                  icon: "film",
                  url: "/admin/assets/videos"
                },
                %{
                  name: gettext("Galleries"),
                  icon: "gallery-horizontal-end",
                  url: "/admin/assets/galleries"
                }
              ]
            },
            %{
              name: gettext("Users"),
              icon: "users",
              url: "/admin/users"
            }
          ]
          |> Enum.reject(&(&1 in [false, nil]))
      },
      %{
        name: gettext("Content"),
        items:
          [
            %{
              name: gettext("Pages & Sections"),
              icon: "file-text",
              url: "/admin/pages"
            },
            forms_menu_item(),
            globals_menu_item()
          ]
          |> Enum.reject(&is_nil/1)
          |> Kernel.++(content_menus)
      }
    ]

    if Brando.Authorization.enabled?(), do: filter_authorized(menus, current_user), else: menus
  end

  # Configuration's screens under four headings. `items` stays one flat list,
  # in group order, for everything that reads it as a list (the command
  # palette, page titles, the "go to" shortcut); each item names its group,
  # and `groups` gives the headings' order and labels for the sidebar. A group
  # with nothing left for this user is dropped, heading and all.
  defp configuration_menu_item(current_user, current_site) do
    groups =
      [
        {:site, gettext("Site"),
         [
           %{name: gettext("Navigation"), icon: "list-tree", url: "/admin/config/navigation/menus"},
           %{name: gettext("Forms"), icon: "text-cursor-input", url: "/admin/config/forms"},
           %{name: gettext("Identity"), icon: "building-complex", url: "/admin/config/identity"},
           %{name: gettext("SEO"), icon: "search", url: "/admin/config/seo"},
           developer_items(current_user, [
             %{name: gettext("Global fields (setup)"), url: "/admin/config/global_sets", icon: "globe"}
           ])
         ]},
        {:publishing, gettext("Publishing"),
         [
           %{name: gettext("Scheduled publishing"), icon: "calendar-clock", url: "/admin/config/scheduled_publishing"},
           environments_menu_item(),
           publishing_menu_item(current_site),
           developer_items(current_user, [
             %{name: gettext("Content transfer"), url: "/admin/config/import-export", icon: "arrow-left-right"}
           ])
         ]},
        {:building_blocks, gettext("Building blocks"),
         developer_items(current_user, [
           %{name: gettext("Block modules"), icon: "blocks", url: "/admin/config/content/modules"},
           shared_library_menu_item(current_user),
           %{name: gettext("Block module sets"), icon: "boxes", url: "/admin/config/content/module_sets"},
           %{name: gettext("Containers"), icon: "square-dashed", url: "/admin/config/content/containers"},
           %{name: gettext("Templates"), icon: "layout-template", url: "/admin/config/content/templates"},
           %{name: gettext("Table Templates"), icon: "table", url: "/admin/config/content/table_templates"},
           %{name: gettext("Palettes"), icon: "palette", url: "/admin/config/content/palettes"},
           %{name: gettext("Markdown sources"), url: "/admin/config/markdown-sources", icon: "file-code"}
         ])},
        {:operations, gettext("Operations"),
         [
           if(Brando.Authorization.enabled?() or match?(%{role: :superuser}, current_user),
             do: %{name: gettext("Permissions"), url: "/admin/groups", icon: "shield-check"}
           ),
           activity_menu_item(current_user),
           integrations_menu_item(current_user),
           developer_items(current_user, [
             assistant_guidance_menu_item(current_user),
             frontend_assets_menu_item(current_user),
             %{name: gettext("Cache"), icon: "database-zap", url: "/admin/config/cache"},
             %{name: gettext("Utilities"), icon: "wrench", url: "/admin/config/utils"}
           ])
         ]}
      ]
      |> Enum.map(fn {key, name, items} ->
        {key, name, items |> List.flatten() |> Enum.reject(&(&1 in [false, nil]))}
      end)

    %{
      name: gettext("Configuration"),
      key: :configuration,
      icon: "settings",
      url: nil,
      groups: Enum.map(groups, fn {key, name, _} -> %{key: key, name: name} end),
      items: for({key, _, items} <- groups, item <- items, do: Map.put(item, :group, key))
    }
  end

  @doc """
  A submenu's items under their headings: `[%{key: :site, name: "Site", items:
  [...]}, ...]` in the order of the item's `groups`, without empty groups. Items
  whose `group` is not among them come last, under no heading (`key` and `name`
  nil), as do all the items of a submenu without `groups`.
  """
  def grouped_items(%{items: items} = item) when is_list(items) do
    groups = Map.get(item, :groups) || []
    keys = Enum.map(groups, & &1.key)

    grouped = Enum.map(groups, &%{key: &1.key, name: &1.name, items: Enum.filter(items, fn i -> i[:group] == &1.key end)})
    ungrouped = %{key: nil, name: nil, items: Enum.reject(items, &(&1[:group] in keys))}

    Enum.reject(grouped ++ [ungrouped], &(&1.items == []))
  end

  def grouped_items(_item), do: []

  # What visitors have sent: there is nothing to read until a form is built
  # under Configuration. With tenants the item stays, as for Globals.
  defp forms_menu_item do
    if Tenant.mode() != :none or Brando.Repo.aggregate(Brando.Forms.Form, :count) > 0,
      do: %{name: gettext("Forms"), url: "/admin/forms", icon: "inbox"}
  end

  # Globals is empty until a developer adds a global set; a menu item leading
  # to "no globals configured" is a dead end for editors. With tenants the
  # item stays: platform pages have no site whose global sets to count.
  defp globals_menu_item do
    if Tenant.mode() != :none or Brando.Repo.aggregate(Brando.Sites.GlobalSet, :count) > 0,
      do: %{name: gettext("Globals"), url: "/admin/globals", icon: "earth"}
  end

  @doc """
  The site's own menu entries (the app's `Menus` module), as links the user
  may open: `[%{name: "Projects", url: "/admin/works/projects", icon: "briefcase"}, …]`, sub
  items flattened. The dashboard offers these as shortcuts.
  """
  def site_menu_items(current_user) do
    items = Brando.admin_module(Menus).__menus__()
    items = if Brando.Authorization.enabled?(), do: filter_authorized(items, current_user), else: items
    flatten_links(items)
  end

  defp flatten_links(items) do
    Enum.flat_map(items, fn
      %{items: [_ | _] = children} -> flatten_links(children)
      %{url: url, name: name} = item when is_binary(url) -> [%{name: name, url: url, icon: item[:icon] || @fallback_icon}]
      _ -> []
    end)
  end

  # Tools for setting a site up rather than editing it. Without the
  # authorization engine only superusers see them; with it, the engine's
  # permissions decide (`filter_authorized/2`).
  defp developer_items(user, items) do
    if Brando.Authorization.enabled?() or match?(%{role: :superuser}, user), do: items, else: []
  end

  defp publishing_menu_item(%{delivery_mode: :static}) do
    %{name: gettext("Publishing"), url: "/admin/config/publishing", icon: "send"}
  end

  defp publishing_menu_item(_site), do: nil

  defp sites_menu_item(user) do
    if Brando.Authorization.enabled?() or (user && user.role == :superuser) do
      if Tenant.mode() == :multi, do: %{name: gettext("Sites"), url: "/admin/sites", icon: "panels-top-left"}
    end
  end

  # Without group authorization the log is for administrators; with it, the
  # `brando.activity.read` permission decides (`filter_authorized/2`).
  defp activity_menu_item(user) do
    if Brando.Authorization.enabled?() or match?(%{role: role} when role in [:admin, :superuser], user),
      do: %{name: gettext("Activity"), url: "/admin/config/activity", icon: "activity"}
  end

  # Without group authorization, for administrators; with it, the
  # `brando.webhooks.manage`, `brando.notifications.manage` or
  # `brando.mcp.manage` permission decides.
  defp integrations_menu_item(user) do
    if user && BrandoAdmin.Sites.IntegrationsLive.can_open?(user),
      do: %{name: gettext("Integrations"), url: "/admin/config/integrations", icon: "plug"}
  end

  defp environments_menu_item do
    if Tenant.enabled?(), do: %{name: gettext("Environments"), url: "/admin/config/environments", icon: "server"}
  end

  defp frontend_assets_menu_item(user) do
    if Brando.Authorization.enabled?() or (user && user.role == :superuser),
      do: %{name: gettext("Frontend assets"), url: "/admin/config/assets", icon: "package"}
  end

  defp shared_library_menu_item(%{role: role}) do
    if Tenant.mode() == :multi do
      name = if role == :superuser, do: gettext("Shared content library"), else: gettext("Site content library")
      %{name: name, url: "/admin/config/content/shared_library", icon: "library"}
    end
  end

  defp shared_library_menu_item(_user), do: nil

  defp filter_authorized(items, user) do
    Enum.flat_map(items, &authorized_item(&1, user))
  end

  defp authorized_item(item, user) do
    case item do
      %{items: children} when is_list(children) and children != [] ->
        case filter_authorized(children, user) do
          [] -> []
          children -> [%{item | items: children}]
        end

      %{url: url} when is_binary(url) ->
        if allowed_url?(user, url), do: [item], else: []

      _ ->
        []
    end
  end

  defp allowed_url?(user, url) do
    router = Brando.RuntimeConfig.web_module(Router)

    case Phoenix.Router.route_info(router, "GET", URI.parse(url).path, "localhost") do
      %{phoenix_live_view: {view, action, _, _}, path_params: params} ->
        {operation, resource} = BrandoAdmin.Authorization.requirement(view, params, action)

        scope =
          if resource in [:sites, :frontend_assets, :shared_library] or
               (resource == Brando.Users.User and Brando.Tenant.enabled?()),
             do: Brando.Authorization.Scope.installation(user),
             else: Brando.Authorization.Scope.current(user)

        Brando.Authorization.can?(scope, operation, resource)

      _ ->
        false
    end
  end
end
