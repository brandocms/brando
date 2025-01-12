# Script for populating the database. You can run it as:
#
#     mix run priv/repo/seeds.exs
#
# Inside the script, you can read and write to any of your
# repositories directly:
#
#     E2eProject.Repo.insert!(%SomeSchema{})
#
# We recommend using the bang functions (`insert!`, `update!`
# and so on) as they will fail if something goes wrong.

# Add this at the top of the file
user = %Brando.Users.User{
  name: "Brando Admin",
  email: "admin@brandocms.com",
  password: Bcrypt.hash_pwd_salt("brandocms"),
  avatar: nil,
  role: :superuser,
  language: :en,
  config: %{
    prefers_reduced_motion: false,
    reset_password_on_first_login: false,
    show_mutation_notifications: true,
    content_language: :en
  }
} |> E2eProject.Repo.insert!()

languages = Brando.config(:languages) |> Enum.map(&String.to_existing_atom(&1[:value]))

# Create an identity for each language
for lang <- languages do
  %Brando.Sites.Identity{
    name: "Organization name",
    alternate_name: "Short form",
    email: "mail@domain.tld",
    phone: "+47 00 00 00 00",
    address: "Testveien 1",
    zipcode: "0000",
    city: "Oslo",
    country: "NO",
    title_prefix: "CompanyName | ",
    title: "Welcome!",
    title_postfix: "",
    logo: nil,
    language: lang
  } |> E2eProject.Repo.insert!()
end

# Create SEO entries for each language
for lang <- languages do
  %Brando.Sites.SEO{
    fallback_meta_title: "Welcome to our site",
    fallback_meta_description: "Default meta description for search engines",
    base_url: "https://example.com",
    robots: """
    User-agent: *
    Disallow: /admin/
    """,
    language: lang
  } |> E2eProject.Repo.insert!()
end

for lang <- languages do
  %Brando.Navigation.Menu{
    creator_id: user.id,
    items: [
      %Brando.Navigation.Item{
        key: "brando",
        status: :published,
        creator_id: user.id,
        link: %Brando.Content.Var{
          type: :link,
          link_type: :url,
          creator_id: user.id,
          link_text: "Brando CMS",
          link_target_blank: true,
          important: true,
          label: "Link",
          key: "link",
          value: "https://brandocms.com"
        }
      },
      %Brando.Navigation.Item{
        key: "documentation",
        status: :published,
        creator_id: user.id,
        link: %Brando.Content.Var{
          type: :link,
          link_type: :url,
          creator_id: user.id,
          link_text: "API Documentation",
          link_target_blank: true,
          important: true,
          label: "Link",
          key: "link",
          value: "https://hexdocs.pm/brando"
        }
      },
      %Brando.Navigation.Item{
        key: "guides",
        status: :published,
        creator_id: user.id,
        link: %Brando.Content.Var{
          type: :link,
          link_type: :url,
          creator_id: user.id,
          link_text: "Guides",
          link_target_blank: true,
          important: true,
          label: "Link",
          key: "link",
          value: "https://brandocms.com/guides"
        }
      }
    ],
    key: "main",
    language: lang,
    sequence: 0,
    status: :published,
    template: nil,
    title: "Main menu"
  }
  |> E2eProject.Repo.insert!()
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
  vars: []
}

m1 = E2eProject.Repo.insert!(example_module)

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
          source: Elixir.Brando.Pages.Page.Blocks,
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
    template: "default.html",
    title: "Index"
  }

  p1 = E2eProject.Repo.insert!(page)

  footer_fragment = %Brando.Pages.Fragment{
    parent_key: "partials",
    key: "footer",
    title: "Footer",
    language: lang,
    entry_blocks: [],
    page_id: p1.id,
    creator_id: user.id
  }

  E2eProject.Repo.insert!(footer_fragment)
end

# Create modules

%Brando.Content.Module{
   type: :liquid,
   name: %{"en" => "Heading", "no" => "Overskrift"},
   namespace: %{"en" => "01 HEADERS", "no" => "01 HEADINGER"},
   help_text: %{"en" => "Large text", "no" => "Stor tekst"},
   class: "header",
   code: "<article b-tpl=\"{{ block.class }}\">\n  <div class=\"inner\">\n    {% ref refs.h2 %}\n  </div>\n</article>",
   svg: nil,
   multi: false,
   datasource: false,
   datasource_module: nil,
   datasource_type: nil,
   datasource_query: nil,
   sequence: 0,
   deleted_at: nil,
   table_template_id: nil,
   table_template: nil,
   parent_id: nil,
   refs: [
     %Brando.Content.Module.Ref{
       name: "h2",
       description: nil,
       data: %Brando.Villain.Blocks.HeaderBlock{
         uid: "23JQYQHHdkMIXRzR7J2SQU",
         type: "header",
         active: true,
         collapsed: false,
         marked_as_deleted: false,
         data: %Brando.Villain.Blocks.HeaderBlock.Data{
           class: nil,
           text: "Text",
           level: 2,
           link: nil,
           placeholder: nil,
           id: nil,
           marked_as_deleted: false
         }
       },
       marked_as_deleted: false
     }
   ],
   vars: []
 } |> E2eProject.Repo.insert!()

 %Brando.Content.Module{
   type: :liquid,
   name: %{"en" => "Single Asset", "no" => "Enkelt bilde/video"},
   namespace: %{"en" => "02 MEDIA", "no" => "02 MEDIA"},
   help_text: %{"en" => "Full width image or video", "no" => "Fullbredde bilde eller video"},
   class: "asset",
   code: "<article b-tpl=\"asset\">\n  <div class=\"inner\">\n    {% ref refs.media %}\n  </div>\n</article>",
   svg: nil,
   multi: false,
   datasource: false,
   datasource_module: nil,
   datasource_type: nil,
   datasource_query: nil,
   sequence: 4,
   deleted_at: nil,
   table_template_id: nil,
   table_template: nil,
   parent_id: nil,
   refs: [
     %Brando.Content.Module.Ref{
       name: "media",
       description: nil,
       data: %Brando.Villain.Blocks.MediaBlock{
         uid: "23JQyqc9rQfBRqDcRLEn77",
         type: "media",
         active: true,
         collapsed: false,
         marked_as_deleted: false,
         data: %Brando.Villain.Blocks.MediaBlock.Data{
           available_blocks: ["picture", "video"],
           marked_as_deleted: false,
           template_picture: %Brando.Villain.Blocks.PictureBlock.Data{
             picture_class: nil,
             img_class: nil,
             link: nil,
             srcset: nil,
             media_queries: nil,
             title: nil,
             credits: nil,
             formats: [:original, :webp],
             alt: nil,
             path: nil,
             width: nil,
             height: nil,
             sizes: nil,
             cdn: false,
             lazyload: true,
             moonwalk: true,
             dominant_color: nil,
             placeholder: :dominant_color_faded,
             config_target: nil,
             fetchpriority: :auto,
             marked_as_deleted: false,
             focal: nil
           },
           template_video: %Brando.Villain.Blocks.VideoBlock.Data{
             url: nil,
             source: nil,
             remote_id: nil,
             poster: nil,
             width: nil,
             height: nil,
             autoplay: true,
             opacity: 0,
             preload: true,
             play_button: false,
             controls: false,
             cover: "false",
             thumbnail_url: nil,
             title: nil,
             aspect_ratio: nil,
             marked_as_deleted: false,
             cover_image: nil
           },
           template_gallery: nil,
           template_svg: nil
         }
       },
       marked_as_deleted: false
     }
   ],
   vars: [],
 } |> E2eProject.Repo.insert!()