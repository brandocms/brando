defmodule BrandoAdmin.Menu do
  @moduledoc """
      import MyAppAdmin.Gettext

      menus do
        menu_item t("Projects") do
          menu_subitem t("Projects"), "/admin/projects/projects"
          menu_subitem t("Categories"), "/admin/projects/categories"
          menu_subitem MyApp.Project.Something
        end

        menu_item MyApp.Team.Member
      end
  """

  use Gettext, backend: Brando.Gettext

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

  @doc """
  Generate a menu item from blueprint schema
  """
  defmacro menu_item(schema) do
    do_menu_item(schema)
  end

  @doc """
  Add custom URL to menu
  """
  defmacro menu_item(name, do: block) do
    do_menu_item(name, do: block)
  end

  defmacro menu_item(name, url) do
    do_menu_item(name, url)
  end

  defp do_menu_item(schema) do
    quote location: :keep,
          generated: true,
          bind_quoted: [schema: schema] do
      domain = schema.__naming__().domain
      snake_domain = Macro.underscore(domain)
      schema_name = schema.__naming__().schema
      plural = schema.__naming__().plural
      msgid = Brando.Utils.humanize(plural, :downcase)

      url_base = "/admin/#{snake_domain}/#{plural}"
      default_listing = Enum.find(schema.__listings__(), &(&1.name == :default))

      if !default_listing do
        raise Brando.Exception.BlueprintError,
          message: "Missing default listing for menu_item `#{inspect(schema)}`"
      end

      query_params =
        default_listing.query
        |> BrandoAdmin.Menu.strip_preloads()
        |> BrandoAdmin.Menu.encode_advanced_order()
        |> Plug.Conn.Query.encode()
        |> String.replace("%3A", ":")
        |> String.replace("%5B", "[")
        |> String.replace("%5D", "]")

      url = Enum.join([url_base, query_params], "?")
      gettext_domain = String.downcase("#{domain}_#{schema_name}")

      Module.put_attribute(__MODULE__, :menus, %{
        name: {:translate, gettext_domain, msgid},
        url: url
      })
    end
  end

  defp do_menu_item(name, do: block) do
    quote location: :keep,
          generated: true do
      var!(b_menu_subitems) = []
      subitems = unquote(block)

      Module.put_attribute(__MODULE__, :menus, %{
        name: unquote(name),
        items: Enum.reverse(subitems),
        url: nil
      })
    end
  end

  defp do_menu_item(name, url) do
    quote location: :keep,
          generated: true,
          bind_quoted: [name: name, url: url] do
      Module.put_attribute(__MODULE__, :menus, %{name: name, url: url})
    end
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
    do_menu_subitem(schema)
  end

  defmacro menu_subitem(name, url) do
    do_menu_subitem(name, url)
  end

  defp do_menu_subitem(schema) do
    quote location: :keep,
          generated: true,
          bind_quoted: [schema: schema] do
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

      query_params =
        default_listing.query
        |> BrandoAdmin.Menu.strip_preloads()
        |> BrandoAdmin.Menu.encode_advanced_order()
        |> Plug.Conn.Query.encode()
        |> String.replace("%3A", ":")
        |> String.replace("%5B", "[")
        |> String.replace("%5D", "]")

      url = Enum.join([url_base, query_params], "?")
      gettext_domain = String.downcase("#{domain}_#{schema_name}")

      var!(b_menu_subitems) = [
        %{name: {:translate, gettext_domain, msgid}, url: url} | var!(b_menu_subitems)
      ]
    end
  end

  defp do_menu_subitem(name, url) do
    quote location: :keep,
          generated: true do
      var!(b_menu_subitems) = [%{name: unquote(name), url: unquote(url)} | var!(b_menu_subitems)]
    end
  end

  defmacro t(msgid) do
    quote do
      dgettext("menus", unquote(msgid))
    end
  end

  def get_menu do
    content_menus = Brando.admin_module(Menus).__menus__()

    [
      %{
        name: gettext("System"),
        items: [
          %{
            name: gettext("Dashboard"),
            url: "/admin"
          },
          %{
            name: gettext("Configuration"),
            url: nil,
            items: [
              %{
                name: gettext("Navigation"),
                url: "/admin/config/navigation/menus"
              },
              %{
                name: gettext("Identity"),
                url: "/admin/config/identity"
              },
              %{
                name: gettext("SEO"),
                url: "/admin/config/seo"
              },
              %{
                name: gettext("Globals"),
                url: "/admin/config/global_sets"
              },
              %{
                name: gettext("Scheduled publishing"),
                url: "/admin/config/scheduled_publishing"
              },
              %{
                name: gettext("Cache"),
                url: "/admin/config/cache"
              },
              %{
                name: gettext("Utilities"),
                url: "/admin/config/utils"
              },
              %{
                name: gettext("Block modules"),
                url: "/admin/config/content/modules"
              },
              %{
                name: gettext("Block module sets"),
                url: "/admin/config/content/module_sets"
              },
              %{
                name: gettext("Containers"),
                url: "/admin/config/content/containers"
              },
              %{
                name: gettext("Table Templates"),
                url: "/admin/config/content/table_templates"
              },
              %{
                name: gettext("Templates"),
                url: "/admin/config/content/templates"
              },
              %{
                name: gettext("Palettes"),
                url: "/admin/config/content/palettes"
              }
            ]
          },
          %{
            name: gettext("Assets"),
            url: nil,
            items: [
              %{
                name: gettext("Images"),
                url: "/admin/assets/images"
              },
              %{
                name: gettext("Files"),
                url: "/admin/assets/files"
              },
              %{
                name: gettext("Videos"),
                url: "/admin/assets/videos"
              }
            ]
          },
          %{
            name: gettext("Users"),
            url: "/admin/users"
          }
        ]
      },
      %{
        name: gettext("Content"),
        items:
          [
            %{
              name: gettext("Pages & Sections"),
              url: "/admin/pages"
            },
            %{
              name: gettext("Globals"),
              url: "/admin/globals"
            }
          ] ++ content_menus
      }
    ]
  end
end
