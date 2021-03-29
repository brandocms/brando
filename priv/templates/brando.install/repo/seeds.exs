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

post_cfg = %Brando.Type.ImageConfig{
  allowed_mimetypes: ["image/jpeg", "image/png", "image/gif"],
  default_size: "xlarge",
  random_filename: true,
  size_limit: 10_240_000,
  sizes: %{
    "large" => %{"quality" => 85, "size" => "1400"},
    "medium" => %{"quality" => 85, "size" => "1000"},
    "micro" => %{"crop" => false, "quality" => 10, "size" => "25"},
    "small" => %{"quality" => 85, "size" => "700"},
    "thumb" => %{"crop" => true, "quality" => 85, "size" => "150x150"},
    "xlarge" => %{"quality" => 85, "size" => "1900"}
  },
  upload_path: "images/site/posts"
}

ss_cfg = %Brando.Type.ImageConfig{
  allowed_mimetypes: ["image/jpeg", "image/png", "image/gif"],
  default_size: "xlarge",
  random_filename: true,
  size_limit: 10_240_000,
  sizes: %{
    "cropxlarge" => %{"crop" => true, "quality" => 80, "size" => "1140x600"},
    "large" => %{"quality" => 80, "size" => "1400"},
    "medium" => %{"quality" => 80, "size" => "900"},
    "micro" => %{"crop" => false, "quality" => 10, "size" => "25"},
    "small" => %{"quality" => 80, "size" => "300"},
    "test" => %{"quality" => 80, "size" => "900"},
    "thumb" => %{"crop" => true, "quality" => 80, "size" => "150x150"},
    "xlarge" => %{"quality" => 80, "size" => "2550"}
  },
  upload_path: "images/site/slideshows"
}

# insert admin user
password = Bcrypt.hash_pwd_salt("admin")

user = %Brando.Users.User{
  name: "Brando Admin",
  email: "admin@brandocms.com",
  password: password,
  avatar: nil,
  role: :superuser,
  language: "en"
}

user = <%= application_module %>.Repo.insert!(user)

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
  language: "en",
  sequence: 0,
  status: :published,
  template: nil,
  title: "Main menu"
}
|> <%= application_module %>.Repo.insert!()

example_module =
  %Brando.Villain.Module{
    class: "example",
    code:
      "<article b-tpl=\"example\">\n\t<div class=\"inner\">\n\t\t%{h1}\n        %{p}\n\t</div>\n</article>",
    help_text: "Used for the introduction page",
    multi: false,
    name: "Example module",
    namespace: "general",
    refs: [
      %{
        "data" => %{
          "data" => %{
            "class" => nil,
            "id" => nil,
            "level" => 1,
            "text" => "Heading"
          },
          "type" => "header"
        },
        "description" => "",
        "name" => "h1"
      },
      %{
        "data" => %{
          "data" => %{
            "extensions" => [],
            "text" => "Text",
            "type" => "paragraph"
          },
          "type" => "text"
        },
        "description" => "",
        "name" => "p"
      }
    ],
    sequence: 0,
    svg: nil,
    vars: %{},
    wrapper: nil
  }
  |> <%= application_module %>.Repo.insert!()

post_category = %Brando.ImageCategory{
  creator_id: user.id,
  name: "post",
  slug: "post",
  cfg: post_cfg
}

post_category = <%= application_module %>.Repo.insert!(post_category)

ss_category = %Brando.ImageCategory{
  cfg: ss_cfg,
  creator_id: user.id,
  name: "Slideshows",
  slug: "slideshows"
}

<%= application_module %>.Repo.insert!(ss_category)

post_series = %Brando.ImageSeries{
  creator_id: user.id,
  credits: nil,
  cfg: post_cfg,
  image_category_id: post_category.id,
  name: "post",
  sequence: 0,
  slug: "post"
}

<%= application_module %>.Repo.insert!(post_series)

page = %Brando.Pages.Page{
  creator_id: user.id,
  css_classes: nil,
  data: [
    %{
      "data" => %{
        "deleted_at" => nil,
        "id" => example_module.id,
        "multi" => false,
        "refs" => [
          %{
            "data" => %{
              "data" => %{
                "class" => nil,
                "id" => nil,
                "level" => 1,
                "text" => "Welcome to Brando!"
              },
              "type" => "header"
            },
            "description" => "",
            "name" => "h1"
          },
          %{
            "data" => %{
              "data" => %{
                "extensions" => [],
                "text" =>
                  "<p>Lorem ipsum dolor sit amet, consectetur adipiscing elit. Suspendisse varius auctor tellus ut hendrerit. Vivamus lectus libero, condimentum vitae tellus nec, vehicula iaculis nisi. Morbi at pulvinar neque, vitae maximus magna. Morbi bibendum pulvinar tellus, eu pellentesque arcu porta et. Pellentesque sagittis nisi a sem cursus, in fringilla metus tristique. Maecenas vel enim quis diam mollis viverra. Nulla pulvinar tristique erat nec rhoncus. Maecenas at nisl dignissim, rhoncus purus vitae, consequat diam. Curabitur sed sapien tempor, eleifend dolor cursus, rhoncus turpis. Vestibulum dolor eros, fermentum ac feugiat ut, interdum in nulla. Pellentesque faucibus, arcu eu gravida sollicitudin, massa lacus aliquam lorem, sed ultrices ligula mauris in velit. Fusce ac dolor facilisis lacus suscipit lobortis quis et leo. </p>",
                "type" => "paragraph"
              },
              "type" => "text"
            },
            "description" => "",
            "name" => "p"
          }
        ],
        "sequence" => 0,
        "vars" => %{}
      },
      "type" => "module",
      "uid" => "KMDHFWOUSTVCR"
    }
  ],
  deleted_at: nil,
  fragments: [],
  html:
    "<article b-tpl=\"example\">\n\t<div class=\"inner\">\n\t\t<h1>Welcome to Brando!</h1>\n        <p>Lorem ipsum dolor sit amet, consectetur adipiscing elit. Suspendisse varius auctor tellus ut hendrerit. Vivamus lectus libero, condimentum vitae tellus nec, vehicula iaculis nisi. Morbi at pulvinar neque, vitae maximus magna. Morbi bibendum pulvinar tellus, eu pellentesque arcu porta et. Pellentesque sagittis nisi a sem cursus, in fringilla metus tristique. Maecenas vel enim quis diam mollis viverra. Nulla pulvinar tristique erat nec rhoncus. Maecenas at nisl dignissim, rhoncus purus vitae, consequat diam. Curabitur sed sapien tempor, eleifend dolor cursus, rhoncus turpis. Vestibulum dolor eros, fermentum ac feugiat ut, interdum in nulla. Pellentesque faucibus, arcu eu gravida sollicitudin, massa lacus aliquam lorem, sed ultrices ligula mauris in velit. Fusce ac dolor facilisis lacus suscipit lobortis quis et leo. </p>\n\t</div>\n</article>",
  is_homepage: true,
  uri: "index",
  language: "en",
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
  language: "en",
  html: "<p>(c) BrandoCMS — all rights reserved</p>",
  data: [
    %{
      "data" => %{"text" => "(c) BrandoCMS — all rights reserved", "type" => "paragraph"},
      "type" => "text"
    }
  ],
  page_id: p1.id,
  creator_id: user.id
}

<%= application_module %>.Repo.insert!(footer_fragment)
