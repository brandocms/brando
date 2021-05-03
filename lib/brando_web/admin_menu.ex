defmodule BrandoWeb.Admin.Menu do
  def get_menu do
    [
      %{
        name: "System",
        items: [
          %{
            name: "Dashboard",
            url: "/admin"
          },
          %{
            name: "Configuration",
            url: nil,
            items: [
              %{
                text: "Identity",
                url: "/admin/config/identity"
              },
              %{
                text: "SEO",
                url: "/admin/config/seo"
              },
              %{
                text: "Global variables",
                url: "/admin/config/globals"
              },
              %{
                text: "Planned publishing",
                url: "/admin/config/planned-publishing"
              },
              %{
                text: "Cache",
                url: "/admin/config/cache"
              },
              %{
                text: "Content modules",
                url: "/admin/config/modules"
              }
            ]
          },
          %{
            name: "Navigation",
            url: "/admin/navigation"
          },
          %{
            name: "Users",
            url: "/admin/users"
          },
          %{
            name: "Image Library",
            url: "/admin/images"
          },
          %{
            name: "File Library",
            url: "/admin/files"
          }
        ]
      },
      %{
        name: "Content",
        items: [
          %{
            name: "Pages & Sections",
            url: "/admin/pages"
          }
        ]
      }
    ]
  end
end
