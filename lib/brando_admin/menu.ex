defmodule BrandoAdmin.Menu do
  import Brando.Gettext

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
        Enum.reverse(@menus)
      end
    end
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
      plural = schema.__naming__().plural
      url_base = "/admin/#{plural}"
      default_listing = Enum.find(schema.__listings__, &(&1.name == :default))

      if !default_listing do
        raise Brando.Exception.BlueprintError,
          message: "Missing default listing for menu_item `#{inspect(schema)}`"
      end

      query_params =
        default_listing.query
        |> BrandoAdmin.Menu.strip_preloads()
        |> URI.encode_query()
        |> String.replace("%3A", ":")

      url = Enum.join([url_base, query_params], "?")

      Module.put_attribute(__MODULE__, :menus, %{name: String.capitalize(plural), url: url})
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

  defmacro menu_subitem(name, url) do
    do_menu_subitem(name, url)
  end

  defp do_menu_subitem(name, url) do
    quote location: :keep,
          generated: true do
      var!(b_menu_subitems) = [%{name: unquote(name), url: unquote(url)} | var!(b_menu_subitems)]
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
                name: gettext("Identity"),
                url: "/admin/config/identity"
              },
              %{
                name: gettext("SEO"),
                url: "/admin/config/seo"
              },
              %{
                name: gettext("Global variables"),
                url: "/admin/config/globals"
              },
              %{
                name: gettext("Planned publishing"),
                url: "/admin/config/planned-publishing"
              },
              %{
                name: gettext("Cache"),
                url: "/admin/config/cache"
              },
              %{
                name: gettext("Content modules"),
                url: "/admin/config/modules"
              }
            ]
          },
          %{
            name: gettext("Navigation"),
            url: "/admin/navigation"
          },
          %{
            name: gettext("Users"),
            url: "/admin/users"
          },
          %{
            name: gettext("Image Library"),
            url: "/admin/images"
          },
          %{
            name: gettext("File Library"),
            url: "/admin/files"
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
            }
          ] ++ content_menus
      }
    ]
  end
end
