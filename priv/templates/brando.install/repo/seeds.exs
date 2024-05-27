# Script for populating the database. You can run it as:
#
#     mix run priv/repo/seeds.exs
#
# Inside the script, you can read and write to any of your
# repositories directly:
#
#     <%= application_module %>.Repo.insert!(%SomeSchema{})
#
# We recommend using the bang functions (`insert!`, `update!`
# and so on) as they will fail if something goes wrong.

user = <%= application_module %>.Repo.get_by!(Brando.Users.User, id: 1)
languages = Brando.config(:languages) |> Enum.map(&String.to_existing_atom(&1[:value]))

for lang <- languages do
  %Brando.Navigation.Menu{
    creator_id: user.id,
    items: [
      %Brando.Navigation.Item{
        items: [],
        key: "brando",
        open_in_new_window: true,
        status: :published,
        title: "Brando CMS",
        url: "https://brandocms.com"
      },
      %Brando.Navigation.Item{
        items: [],
        key: "documentation",
        open_in_new_window: true,
        status: :published,
        title: "API Documentation",
        url: "https://hexdocs.pm/brando"
      },
      %Brando.Navigation.Item{
        items: [],
        key: "guides",
        open_in_new_window: true,
        status: :published,
        title: "Guides",
        url: "https://brandocms.com/guides"
      }
    ],
    key: "main",
    language: lang,
    sequence: 0,
    status: :published,
    template: nil,
    title: "Main menu"
  }
  |> <%= application_module %>.Repo.insert!()
end

example_module = %Brando.Content.Module{
  class: "example",
  code:
    "<article b-tpl=\"example\">\n\t<div class=\"inner\">\n\t\t{% ref refs.h1 %}\n        {% ref refs.p %}\n\t</div>\n</article>",
  help_text: "Used for the introduction page",
  name: "Example module",
  namespace: "general",
  refs: [
    %Brando.Content.Module.Ref{
      data: %Brando.Villain.Blocks.HeaderBlock{
        data: %Brando.Villain.Blocks.HeaderBlock.Data{
          class: nil,
          id: nil,
          level: 1,
          text: "Heading"
        },
        type: "header"
      },
      description: "",
      name: "h1"
    },
    %Brando.Content.Module.Ref{
      data: %Brando.Villain.Blocks.TextBlock{
        data: %Brando.Villain.Blocks.TextBlock.Data{
          extensions: [],
          text: "Text",
          type: "paragraph"
        },
        type: "text"
      },
      description: "",
      name: "p"
    }
  ],
  sequence: 0,
  svg: nil,
  vars: [],
  wrapper: nil
}

m1 = <%= application_module %>.Repo.insert!(example_module)

for lang <- languages do
  page = %Brando.Pages.Page{
    creator_id: user.id,
    css_classes: nil,
    entry_blocks: [
      %Brando.Pages.Page.Blocks{
        block: %Brando.Content.Block{
          type: :module,
          uid: Brando.Utils.generate_uid(),
          module_id: m1.id,
          multi: false,
          refs: [
            %Brando.Content.Module.Ref{
              data: %Brando.Villain.Blocks.HeaderBlock{
                data: %Brando.Villain.Blocks.HeaderBlock.Data{
                  class: nil,
                  id: nil,
                  level: 1,
                  text: "Welcome to Brando!"
                },
                type: "header",
                uid: Brando.Utils.generate_uid()
              },
              description: "",
              name: "h1"
            },
            %Brando.Content.Module.Ref{
              data: %Brando.Villain.Blocks.TextBlock{
                data: %Brando.Villain.Blocks.TextBlock.Data{
                  extensions: [],
                  text:
                    "<p>Lorem ipsum dolor sit amet, consectetur adipiscing elit. Suspendisse varius auctor tellus ut hendrerit. Vivamus lectus libero, condimentum vitae tellus nec, vehicula iaculis nisi. Morbi at pulvinar neque, vitae maximus magna. Morbi bibendum pulvinar tellus, eu pellentesque arcu porta et. Pellentesque sagittis nisi a sem cursus, in fringilla metus tristique. Maecenas vel enim quis diam mollis viverra. Nulla pulvinar tristique erat nec rhoncus. Maecenas at nisl dignissim, rhoncus purus vitae, consequat diam. Curabitur sed sapien tempor, eleifend dolor cursus, rhoncus turpis. Vestibulum dolor eros, fermentum ac feugiat ut, interdum in nulla. Pellentesque faucibus, arcu eu gravida sollicitudin, massa lacus aliquam lorem, sed ultrices ligula mauris in velit. Fusce ac dolor facilisis lacus suscipit lobortis quis et leo. </p>",
                  type: "paragraph"
                },
                type: "text",
                uid: Brando.Utils.generate_uid()
              },
              description: "",
              name: "p"
            }
          ],
          sequence: 0,
          vars: []
        },
        sequence: 0
      }
    ],
    deleted_at: nil,
    fragments: [],
    is_homepage: true,
    uri: "index",
    language: lang,
    meta_description: nil,
    meta_image: nil,
    parent_id: nil,
    sequence: 0,
    status: :published,
    title: "Index"
  }

  p1 = <%= application_module %>.Repo.insert!(page)

  footer_fragment = %Brando.Pages.Fragment{
    parent_key: "partials",
    key: "footer",
    title: "Footer",
    language: lang,
    entry_blocks: [],
    page_id: p1.id,
    creator_id: user.id
  }

  <%= application_module %>.Repo.insert!(footer_fragment)
end
