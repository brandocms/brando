defmodule BrandoWeb.Admin.Menu do
  import Brando.Gettext

  def get_menu do
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
                text: gettext("Identity"),
                url: "/admin/config/identity"
              },
              %{
                text: gettext("SEO"),
                url: "/admin/config/seo"
              },
              %{
                text: gettext("Global variables"),
                url: "/admin/config/globals"
              },
              %{
                text: gettext("Planned publishing"),
                url: "/admin/config/planned-publishing"
              },
              %{
                text: gettext("Cache"),
                url: "/admin/config/cache"
              },
              %{
                text: gettext("Content modules"),
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
        items: [
          %{
            name: gettext("Pages & Sections"),
            url: "/admin/pages"
          }
        ]
      }
    ]
  end
end
