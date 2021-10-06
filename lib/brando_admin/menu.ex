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

  require Brando.Gettext

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

  def translate_menu(%{name: msgid, items: items} = menu)
      when is_nil(items) or length(items) == 0 do
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
      snake_domain = domain |> Recase.to_snake()
      schema_name = schema.__naming__().schema
      plural = schema.__naming__().plural
      msgid = plural

      url_base = "/admin/#{snake_domain}/#{plural}"
      default_listing = Enum.find(schema.__listings__, &(&1.name == :default))

      if !default_listing do
        raise Brando.Exception.BlueprintError,
          message: "Missing default listing for menu_subitem `#{inspect(schema)}`"
      end

      query_params =
        default_listing.query
        |> BrandoAdmin.Menu.strip_preloads()
        |> Plug.Conn.Query.encode()
        |> String.replace("%3A", ":")
        |> String.replace("%5B", "[")
        |> String.replace("%5D", "]")

      url = Enum.join([url_base, query_params], "?")
      gettext_domain = String.downcase("#{domain}_#{schema_name}_naming")

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
    Map.drop(query, [:preload])
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
      snake_domain = domain |> Recase.to_snake()
      schema_name = schema.__naming__().schema
      plural = schema.__naming__().plural
      msgid = plural

      url_base = "/admin/#{snake_domain}/#{plural}"
      default_listing = Enum.find(schema.__listings__, &(&1.name == :default))

      if !default_listing do
        raise Brando.Exception.BlueprintError,
          message: "Missing default listing for menu_subitem `#{inspect(schema)}`"
      end

      query_params =
        default_listing.query
        |> BrandoAdmin.Menu.strip_preloads()
        |> Plug.Conn.Query.encode()
        |> String.replace("%3A", ":")
        |> String.replace("%5B", "[")
        |> String.replace("%5D", "]")

      url = Enum.join([url_base, query_params], "?")
      gettext_domain = String.downcase("#{domain}_#{schema_name}_naming")

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
        name: Brando.Gettext.gettext("System"),
        items: [
          %{
            name: Brando.Gettext.gettext("Dashboard"),
            url: "/admin"
          },
          %{
            name: Brando.Gettext.gettext("Configuration"),
            url: nil,
            items: [
              %{
                name: Brando.Gettext.gettext("Navigation"),
                url: "/admin/config/navigation/menus"
              },
              %{
                name: Brando.Gettext.gettext("Identity"),
                url: "/admin/config/identity"
              },
              %{
                name: Brando.Gettext.gettext("SEO"),
                url: "/admin/config/seo"
              },
              %{
                name: Brando.Gettext.gettext("Globals"),
                url: "/admin/config/global_sets"
              },
              %{
                name: Brando.Gettext.gettext("Scheduled publishing"),
                url: "/admin/config/scheduled_publishing"
              },
              %{
                name: Brando.Gettext.gettext("Cache"),
                url: "/admin/config/cache"
              },
              %{
                name: Brando.Gettext.gettext("Block modules"),
                url: "/admin/config/content/modules"
              },
              %{
                name: Brando.Gettext.gettext("Templates"),
                url: "/admin/config/content/templates"
              },
              %{
                name: Brando.Gettext.gettext("Palettes"),
                url: "/admin/config/content/palettes"
              }
            ]
          },
          %{
            name: Brando.Gettext.gettext("Assets"),
            url: nil,
            items: [
              %{
                name: Brando.Gettext.gettext("Files"),
                url: "/admin/assets/files"
              },
              %{
                name: Brando.Gettext.gettext("Images"),
                url: "/admin/assets/images"
              },
              %{
                name: Brando.Gettext.gettext("Videos"),
                url: "/admin/assets/videos"
              }
            ]
          },
          %{
            name: Brando.Gettext.gettext("Users"),
            url: "/admin/users"
          }
        ]
      },
      %{
        name: Brando.Gettext.gettext("Content"),
        items:
          [
            %{
              name: Brando.Gettext.gettext("Pages & Sections"),
              url: "/admin/pages"
            }
          ] ++ content_menus
      }
    ]
  end
end
