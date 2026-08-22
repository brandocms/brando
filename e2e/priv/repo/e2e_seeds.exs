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
user =
  %Brando.Users.User{
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
  }
  |> E2eProject.Repo.insert!()

# Second superuser for multi-user collaboration specs (two browser contexts
# editing the same entry — block sync filters out same-user broadcasts)
%Brando.Users.User{
  name: "Second Editor",
  email: "editor@brandocms.com",
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
}
|> E2eProject.Repo.insert!()

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
  }
  |> E2eProject.Repo.insert!()
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
  }
  |> E2eProject.Repo.insert!()
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
          placement: :content,
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
          placement: :content,
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
          placement: :content,
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
    %Brando.Content.Ref{
      uid: Brando.Utils.generate_uid(),
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
    %Brando.Content.Ref{
      uid: Brando.Utils.generate_uid(),
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
            %Brando.Content.Ref{
              uid: Brando.Utils.generate_uid(),
              data: %Brando.Villain.Blocks.HeaderBlock{
                data: %Brando.Villain.Blocks.HeaderBlock.Data{
                  class: nil,
                  id: nil,
                  level: 1,
                  text: "Welcome to Brando!"
                },
                type: "header"
              },
              description: "",
              name: "h1"
            },
            %Brando.Content.Ref{
              uid: Brando.Utils.generate_uid(),
              data: %Brando.Villain.Blocks.TextBlock{
                data: %Brando.Villain.Blocks.TextBlock.Data{
                  extensions: [],
                  text:
                    "<p>Lorem ipsum dolor sit amet, consectetur adipiscing elit. Suspendisse varius auctor tellus ut hendrerit. Vivamus lectus libero, condimentum vitae tellus nec, vehicula iaculis nisi. Morbi at pulvinar neque, vitae maximus magna. Morbi bibendum pulvinar tellus, eu pellentesque arcu porta et. Pellentesque sagittis nisi a sem cursus, in fringilla metus tristique. Maecenas vel enim quis diam mollis viverra. Nulla pulvinar tristique erat nec rhoncus. Maecenas at nisl dignissim, rhoncus purus vitae, consequat diam. Curabitur sed sapien tempor, eleifend dolor cursus, rhoncus turpis. Vestibulum dolor eros, fermentum ac feugiat ut, interdum in nulla. Pellentesque faucibus, arcu eu gravida sollicitudin, massa lacus aliquam lorem, sed ultrices ligula mauris in velit. Fusce ac dolor facilisis lacus suscipit lobortis quis et leo. </p>",
                  type: "paragraph"
                },
                type: "text"
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
    breadcrumbs: [],
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
    %Brando.Content.Ref{
      name: "h2",
      description: nil,
      uid: Brando.Utils.generate_uid(),
      data: %Brando.Villain.Blocks.HeaderBlock{
        type: "header",
        data: %Brando.Villain.Blocks.HeaderBlock.Data{
          class: nil,
          text: "Text",
          level: 2,
          link: nil,
          placeholder: nil,
          id: nil
        }
      }
    }
  ],
  vars: []
}
|> E2eProject.Repo.insert!()

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
    %Brando.Content.Ref{
      name: "media",
      description: nil,
      uid: Brando.Utils.generate_uid(),
      data: %Brando.Villain.Blocks.MediaBlock{
        type: "media",
        data: %Brando.Villain.Blocks.MediaBlock.Data{
          available_blocks: ["picture", "video"],
          template_picture: %Brando.Villain.Blocks.PictureBlock.Data{
            picture_class: nil,
            img_class: nil,
            link: nil,
            srcset: nil,
            media_queries: nil,
            title: nil,
            credits: nil,
            alt: nil,
            lazyload: true,
            moonwalk: true,
            placeholder: :dominant_color_faded,
            fetchpriority: :auto
          },
          template_video: %Brando.Villain.Blocks.VideoBlock.Data{
            title: nil,
            poster: nil,
            autoplay: true,
            opacity: 0,
            preload: true,
            play_button: false,
            controls: false,
            cover: "false",
            aspect_ratio: nil,
            cover_image: nil
          },
          template_gallery: nil,
          template_svg: nil
        }
      }
    }
  ],
  vars: [
    %Brando.Content.Var{
      type: :string,
      label: "String label",
      key: "string_label",
      placement: :content,
      value: "test value for string label"
    }
  ]
}
|> E2eProject.Repo.insert!()

# Create test projects for datasource selection and their identifiers
project1 =
  %E2eProject.Projects.Project{
    title: "Test Project Alpha",
    slug: "test-project-alpha",
    status: :published,
    language: :en,
    creator_id: user.id
  }
  |> E2eProject.Repo.insert!()

Brando.Content.create_identifier(E2eProject.Projects.Project, project1)

project2 =
  %E2eProject.Projects.Project{
    title: "Test Project Beta",
    slug: "test-project-beta",
    status: :published,
    language: :en,
    creator_id: user.id
  }
  |> E2eProject.Repo.insert!()

Brando.Content.create_identifier(E2eProject.Projects.Project, project2)

project3 =
  %E2eProject.Projects.Project{
    title: "Test Project Gamma",
    slug: "test-project-gamma",
    status: :published,
    language: :en,
    creator_id: user.id
  }
  |> E2eProject.Repo.insert!()

Brando.Content.create_identifier(E2eProject.Projects.Project, project3)

# Create table template for testing table rows
table_template =
  %Brando.Content.TableTemplate{
    name: "Person Table",
    creator_id: user.id,
    vars: [
      %Brando.Content.Var{
        type: :string,
        label: "Name",
        key: "name",
        placement: :content,
        sequence: 0,
        width: :half,
        creator_id: user.id
      },
      %Brando.Content.Var{
        type: :string,
        label: "Role",
        key: "role",
        placement: :config,
        sequence: 1,
        width: :half,
        creator_id: user.id
      }
    ]
  }
  |> E2eProject.Repo.insert!()

# Create module with table template
%Brando.Content.Module{
  type: :liquid,
  name: %{"en" => "Person List", "no" => "Personliste"},
  namespace: %{"en" => "04 TABLES", "no" => "04 TABELLER"},
  help_text: %{"en" => "A table with person data", "no" => "En tabell med persondata"},
  class: "person-list",
  code:
    "<section b-tpl=\"person-list\">\n  <div class=\"inner\">\n    <table>\n      {% for row in block.table_rows %}\n        <tr>\n          <td>{{ row.name }}</td>\n          <td>{{ row.role }}</td>\n        </tr>\n      {% endfor %}\n    </table>\n  </div>\n</section>",
  svg: nil,
  multi: false,
  datasource: false,
  datasource_module: nil,
  datasource_type: nil,
  datasource_query: nil,
  sequence: 11,
  deleted_at: nil,
  table_template_id: table_template.id,
  parent_id: nil,
  refs: [],
  vars: []
}
|> E2eProject.Repo.insert!()

# Create module with datasource (selection type)
%Brando.Content.Module{
  type: :liquid,
  name: %{"en" => "Featured Projects", "no" => "Utvalgte prosjekter"},
  namespace: %{"en" => "03 DATASOURCE", "no" => "03 DATAKILDE"},
  help_text: %{"en" => "Select featured projects", "no" => "Velg utvalgte prosjekter"},
  class: "featured-projects",
  code:
    "<section b-tpl=\"featured-projects\">\n  <div class=\"inner\">\n    {% for entry in entries %}\n      <div class=\"project\">{{ entry.title }}</div>\n    {% endfor %}\n  </div>\n</section>",
  svg: nil,
  multi: false,
  datasource: true,
  datasource_module: "Elixir.E2eProject.Projects.Project",
  datasource_type: :selection,
  datasource_query: "featured",
  sequence: 10,
  deleted_at: nil,
  table_template_id: nil,
  parent_id: nil,
  refs: [],
  vars: []
}
|> E2eProject.Repo.insert!()

# ============================================================================
# LIVE PREVIEW TEST MODULES
# ============================================================================

# Module 1: Single Image with Caption (picture ref + vars)
%Brando.Content.Module{
  type: :liquid,
  name: %{"en" => "Single Image with Caption", "no" => "Enkelt bilde med bildetekst"},
  namespace: %{"en" => "05 LIVE PREVIEW TEST", "no" => "05 LIVE PREVIEW TEST"},
  help_text: %{
    "en" => "Picture ref with caption variable",
    "no" => "Bilderef med bildetekstvariabel"
  },
  class: "single-image-caption",
  code: """
  <figure b-tpl="single-image" {% if show_border %}data-border="true"{% endif %}>
    {% ref refs.image %}
    <figcaption>{{ caption }}</figcaption>
  </figure>
  """,
  svg: nil,
  multi: false,
  datasource: false,
  sequence: 20,
  deleted_at: nil,
  table_template_id: nil,
  parent_id: nil,
  refs: [
    %Brando.Content.Ref{
      name: "image",
      description: "Main image",
      uid: Brando.Utils.generate_uid(),
      data: %Brando.Villain.Blocks.PictureBlock{
        type: "picture",
        data: %Brando.Villain.Blocks.PictureBlock.Data{
          title: nil,
          credits: nil,
          alt: nil,
          picture_class: nil,
          img_class: nil,
          link: nil,
          srcset: nil,
          media_queries: nil,
          lazyload: true,
          moonwalk: false,
          placeholder: :dominant_color_faded,
          fetchpriority: :auto
        }
      }
    }
  ],
  vars: [
    %Brando.Content.Var{
      type: :string,
      label: "Caption",
      key: "caption",
      placement: :content,
      value: "Default caption text",
      sequence: 0,
      width: :full
    },
    %Brando.Content.Var{
      type: :boolean,
      label: "Show border",
      key: "show_border",
      placement: :content,
      value_boolean: false,
      sequence: 1,
      width: :half
    }
  ]
}
|> E2eProject.Repo.insert!()

# Module 2: Gallery with Controls (gallery ref + vars)
%Brando.Content.Module{
  type: :liquid,
  name: %{"en" => "Gallery with Controls", "no" => "Galleri med kontroller"},
  namespace: %{"en" => "05 LIVE PREVIEW TEST", "no" => "05 LIVE PREVIEW TEST"},
  help_text: %{
    "en" => "Gallery ref with layout and stagger variables",
    "no" => "Galleriref med layout og stagger variabler"
  },
  class: "gallery-controls",
  code: """
  <section b-tpl="gallery-controls" data-layout="{{ layout }}" {% if stagger %}data-stagger="true"{% endif %}>
    <h2 class="gallery-title">{{ title }}</h2>
    {% ref refs.gallery %}
  </section>
  """,
  svg: nil,
  multi: false,
  datasource: false,
  sequence: 21,
  deleted_at: nil,
  table_template_id: nil,
  parent_id: nil,
  refs: [
    %Brando.Content.Ref{
      name: "gallery",
      description: "Image gallery",
      uid: Brando.Utils.generate_uid(),
      data: %Brando.Villain.Blocks.GalleryBlock{
        type: "gallery",
        data: %Brando.Villain.Blocks.GalleryBlock.Data{
          class: nil,
          lightbox: false,
          placeholder: :dominant_color_faded,
          display: :grid,
          type: :gallery,
          formats: [:original]
        }
      }
    }
  ],
  vars: [
    %Brando.Content.Var{
      type: :string,
      label: "Title",
      key: "title",
      placement: :content,
      value: "Gallery Title",
      sequence: 0,
      width: :full
    },
    %Brando.Content.Var{
      type: :select,
      label: "Layout",
      key: "layout",
      placement: :content,
      value: "grid",
      sequence: 1,
      width: :half,
      options: [
        %Brando.Content.Var.Option{label: "Grid", value: "grid"},
        %Brando.Content.Var.Option{label: "List", value: "list"},
        %Brando.Content.Var.Option{label: "Masonry", value: "masonry"}
      ]
    },
    %Brando.Content.Var{
      type: :boolean,
      label: "Stagger animation",
      key: "stagger",
      placement: :content,
      value_boolean: false,
      sequence: 2,
      width: :half
    }
  ]
}
|> E2eProject.Repo.insert!()

# Module 3: Styled Header (header ref + vars)
%Brando.Content.Module{
  type: :liquid,
  name: %{"en" => "Styled Header", "no" => "Stilisert overskrift"},
  namespace: %{"en" => "05 LIVE PREVIEW TEST", "no" => "05 LIVE PREVIEW TEST"},
  help_text: %{
    "en" => "Header ref with color and alignment variables",
    "no" => "Overskriftref med farge og justeringsvariabler"
  },
  class: "styled-header",
  code: """
  <header b-tpl="styled-header" style="color: {{ text_color }}; text-align: {{ alignment }}">
    {% ref refs.h1 %}
  </header>
  """,
  svg: nil,
  multi: false,
  datasource: false,
  sequence: 22,
  deleted_at: nil,
  table_template_id: nil,
  parent_id: nil,
  refs: [
    %Brando.Content.Ref{
      name: "h1",
      description: "Main heading",
      uid: Brando.Utils.generate_uid(),
      data: %Brando.Villain.Blocks.HeaderBlock{
        type: "header",
        data: %Brando.Villain.Blocks.HeaderBlock.Data{
          class: nil,
          text: "Header Text",
          level: 1,
          link: nil,
          placeholder: nil,
          id: nil
        }
      }
    }
  ],
  vars: [
    %Brando.Content.Var{
      type: :color,
      label: "Text color",
      key: "text_color",
      placement: :content,
      value: "#333333",
      sequence: 0,
      width: :half,
      color_picker: true,
      color_opacity: false
    },
    %Brando.Content.Var{
      type: :select,
      label: "Alignment",
      key: "alignment",
      placement: :content,
      value: "left",
      sequence: 1,
      width: :half,
      options: [
        %Brando.Content.Var.Option{label: "Left", value: "left"},
        %Brando.Content.Var.Option{label: "Center", value: "center"},
        %Brando.Content.Var.Option{label: "Right", value: "right"}
      ]
    }
  ]
}
|> E2eProject.Repo.insert!()

# Module 4: Rich Text Article (text ref + vars)
%Brando.Content.Module{
  type: :liquid,
  name: %{"en" => "Rich Text Article", "no" => "Rik tekstartikkel"},
  namespace: %{"en" => "05 LIVE PREVIEW TEST", "no" => "05 LIVE PREVIEW TEST"},
  help_text: %{
    "en" => "Text ref with intro and show_intro variables",
    "no" => "Tekstref med intro og show_intro variabler"
  },
  class: "rich-text-article",
  code: """
  <article b-tpl="rich-text">
    {% if show_intro %}<div class="intro">{{ intro }}</div>{% endif %}
    {% ref refs.content %}
  </article>
  """,
  svg: nil,
  multi: false,
  datasource: false,
  sequence: 23,
  deleted_at: nil,
  table_template_id: nil,
  parent_id: nil,
  refs: [
    %Brando.Content.Ref{
      name: "content",
      description: "Main content",
      uid: Brando.Utils.generate_uid(),
      data: %Brando.Villain.Blocks.TextBlock{
        type: "text",
        data: %Brando.Villain.Blocks.TextBlock.Data{
          text: "<p>Article content goes here</p>",
          type: "paragraph",
          extensions: []
        }
      }
    }
  ],
  vars: [
    %Brando.Content.Var{
      type: :html,
      label: "Intro text",
      key: "intro",
      placement: :content,
      value: "<p>Introduction paragraph</p>",
      sequence: 0,
      width: :full
    },
    %Brando.Content.Var{
      type: :boolean,
      label: "Show intro",
      key: "show_intro",
      placement: :content,
      value_boolean: true,
      sequence: 1,
      width: :half
    }
  ]
}
|> E2eProject.Repo.insert!()

# Module 5: Video Player (video ref + vars)
%Brando.Content.Module{
  type: :liquid,
  name: %{"en" => "Video Player", "no" => "Videospiller"},
  namespace: %{"en" => "05 LIVE PREVIEW TEST", "no" => "05 LIVE PREVIEW TEST"},
  help_text: %{
    "en" => "Video ref with autoplay and controls variables",
    "no" => "Videoref med autoplay og kontrollvariabler"
  },
  class: "video-player",
  code: """
  <div b-tpl="video-player" data-autoplay="{{ autoplay }}" data-controls="{{ show_controls }}">
    {% ref refs.video %}
  </div>
  """,
  svg: nil,
  multi: false,
  datasource: false,
  sequence: 24,
  deleted_at: nil,
  table_template_id: nil,
  parent_id: nil,
  refs: [
    %Brando.Content.Ref{
      name: "video",
      description: "Video content",
      uid: Brando.Utils.generate_uid(),
      data: %Brando.Villain.Blocks.VideoBlock{
        type: "video",
        data: %Brando.Villain.Blocks.VideoBlock.Data{
          title: nil,
          poster: nil,
          autoplay: false,
          opacity: 0,
          preload: true,
          play_button: true,
          controls: true,
          cover: "false",
          aspect_ratio: nil
        }
      }
    }
  ],
  vars: [
    %Brando.Content.Var{
      type: :boolean,
      label: "Autoplay",
      key: "autoplay",
      placement: :content,
      value_boolean: false,
      sequence: 0,
      width: :half
    },
    %Brando.Content.Var{
      type: :boolean,
      label: "Show controls",
      key: "show_controls",
      placement: :content,
      value_boolean: true,
      sequence: 1,
      width: :half
    }
  ]
}
|> E2eProject.Repo.insert!()

# Module 6: Morph Preservation Test (hardcoded video + iframe + editable label)
# Used to verify that skipFromChildren preserves video/iframe DOM elements during morphdom updates
%Brando.Content.Module{
  type: :liquid,
  name: %{"en" => "Morph Preservation", "no" => "Morph-bevaring"},
  namespace: %{"en" => "05 LIVE PREVIEW TEST", "no" => "05 LIVE PREVIEW TEST"},
  help_text: %{
    "en" => "Tests that morphdom preserves video and iframe elements",
    "no" => "Tester at morphdom bevarer video- og iframe-elementer"
  },
  class: "morph-preservation",
  code: """
  <div b-tpl="morph-preservation">
    <div class="video-wrapper" data-smart-video data-src="https://example.com/test-video.m3u8">
      <video data-video width="640" height="360" preload="none">
        <source src="https://example.com/test-video.m3u8" type="application/x-mpegURL" />
      </video>
    </div>
    <iframe class="embed-frame" src="https://example.com/embed" width="560" height="315" frameborder="0"></iframe>
    <p class="morph-label">{{ label }}</p>
  </div>
  """,
  svg: nil,
  multi: false,
  datasource: false,
  sequence: 25,
  deleted_at: nil,
  table_template_id: nil,
  parent_id: nil,
  refs: [],
  vars: [
    %Brando.Content.Var{
      type: :string,
      label: "Label",
      key: "label",
      placement: :content,
      value: "Initial label",
      sequence: 0,
      width: :full
    }
  ]
}
|> E2eProject.Repo.insert!()

# Module 7: Map Embed (map ref) — regression coverage for the map block's
# out-of-band embed_url commit (update_ref_data + propagate)
%Brando.Content.Module{
  type: :liquid,
  name: %{"en" => "Map Embed", "no" => "Kartinnbygging"},
  namespace: %{"en" => "05 LIVE PREVIEW TEST", "no" => "05 LIVE PREVIEW TEST"},
  help_text: %{
    "en" => "Map ref for embed URL persistence tests",
    "no" => "Kartref for testing av embed-URL-persistens"
  },
  class: "map-embed",
  code: """
  <div b-tpl="map-embed">
    {% ref refs.map %}
  </div>
  """,
  svg: nil,
  multi: false,
  datasource: false,
  sequence: 26,
  deleted_at: nil,
  table_template_id: nil,
  parent_id: nil,
  refs: [
    %Brando.Content.Ref{
      name: "map",
      description: "Map content",
      uid: Brando.Utils.generate_uid(),
      data: %Brando.Villain.Blocks.MapBlock{
        type: "map",
        data: %Brando.Villain.Blocks.MapBlock.Data{}
      }
    }
  ],
  vars: []
}
|> E2eProject.Repo.insert!()

# Module 8: HEEx parity — exercises the block editor preview, published live
# preview, vars, parsed refs, headless refs, system assigns, routes and video.
%Brando.Content.Module{
  type: :heex,
  name: %{"en" => "HEEx Parity", "no" => "HEEx-paritet"},
  namespace: %{"en" => "05 LIVE PREVIEW TEST", "no" => "05 LIVE PREVIEW TEST"},
  help_text: %{
    "en" => "HEEx module rendering parity coverage",
    "no" => "Dekning for HEEx-modulrendering"
  },
  class: "heex-parity",
  code: """
  <article
    b-tpl="heex-parity"
    data-language={@language}
    data-identity={@identity.name}
  >
    <h2 class="heex-headline">{@headline}</h2>
    <p :if={@show_entry_title} class="heex-entry-title">{@entry.title}</p>
    <span class="heex-ref-type">{@refs["body"].data.type}</span>
    <.ref block={@block} ref={:body} />
    <.ref block={@block} ref={:headless_title} headless :let={data}>
      <span class="heex-headless-title">{data.text}</span>
    </.ref>
    <span class="heex-route">
      <.route helper={:page_path} action={:show} args={["about/team"]} />
    </span>
    <span class="heex-translation">
      <.t language={@language} translations={%{"en" => "Translated", "no" => "Oversatt"}} />
    </span>
    <.video src="https://cdn.example/video.mp4" opts={[controls: true]} />
  </article>
  """,
  svg: nil,
  multi: false,
  datasource: false,
  sequence: 27,
  deleted_at: nil,
  table_template_id: nil,
  parent_id: nil,
  refs: [
    %Brando.Content.Ref{
      name: "body",
      description: "Body",
      uid: Brando.Utils.generate_uid(),
      data: %Brando.Villain.Blocks.TextBlock{
        type: "text",
        data: %Brando.Villain.Blocks.TextBlock.Data{
          text: "<p>HEEx body</p>",
          type: :paragraph,
          extensions: []
        }
      }
    },
    %Brando.Content.Ref{
      name: "headless_title",
      description: "Headless title",
      uid: Brando.Utils.generate_uid(),
      data: %Brando.Villain.Blocks.HeaderBlock{
        type: "header",
        data: %Brando.Villain.Blocks.HeaderBlock.Data{
          text: "Headless title",
          level: 3
        }
      }
    }
  ],
  vars: [
    %Brando.Content.Var{
      type: :string,
      label: "Headline",
      key: "headline",
      placement: :content,
      value: "HEEx headline",
      sequence: 0,
      width: :full
    },
    %Brando.Content.Var{
      type: :boolean,
      label: "Show entry title",
      key: "show_entry_title",
      placement: :content,
      value_boolean: true,
      sequence: 1,
      width: :half
    }
  ]
}
|> E2eProject.Repo.insert!()

# ============================================================================
# COPY/PASTE TEST MODULES
# ============================================================================

# Multi module (parent) — "Team Section" that holds "Team Member" entries
team_section =
  %Brando.Content.Module{
    type: :liquid,
    name: %{"en" => "Team Section", "no" => "Teamblokk"},
    namespace: %{"en" => "06 COPY PASTE TEST", "no" => "06 COPY PASTE TEST"},
    help_text: %{"en" => "Multi block for team members", "no" => "Multiblokk for teammedlemmer"},
    class: "team-section",
    code: """
    <section b-tpl="team-section">
      <div class="inner">
        {{ content }}
      </div>
    </section>
    """,
    svg: nil,
    multi: true,
    datasource: false,
    sequence: 30,
    deleted_at: nil,
    table_template_id: nil,
    parent_id: nil,
    refs: [],
    vars: [
      %Brando.Content.Var{
        type: :string,
        label: "Section title",
        key: "section_title",
        placement: :content,
        value: "Our Team",
        sequence: 0,
        width: :full
      }
    ]
  }
  |> E2eProject.Repo.insert!()

# Multi module (child) — "Team Member" entry
%Brando.Content.Module{
  type: :liquid,
  name: %{"en" => "Team Member", "no" => "Teammedlem"},
  namespace: %{"en" => "06 COPY PASTE TEST", "no" => "06 COPY PASTE TEST"},
  help_text: %{"en" => "A single team member", "no" => "Enkelt teammedlem"},
  class: "team-member",
  code: "<div b-tpl=\"team-member\">\n  <h3>{{ member_name }}</h3>\n  <p>{{ member_role }}</p>\n</div>",
  svg: nil,
  multi: false,
  datasource: false,
  sequence: 31,
  deleted_at: nil,
  table_template_id: nil,
  parent_id: team_section.id,
  refs: [],
  vars: [
    %Brando.Content.Var{
      type: :string,
      label: "Name",
      key: "member_name",
      placement: :content,
      value: "John Doe",
      sequence: 0,
      width: :half
    },
    %Brando.Content.Var{
      type: :string,
      label: "Role",
      key: "member_role",
      placement: :content,
      value: "Developer",
      sequence: 1,
      width: :half
    }
  ]
}
|> E2eProject.Repo.insert!()

# Multi module (child) — "Team Lead", an entry template that is ITSELF flagged
# multi. Mirrors real projects where an entry template was created from the
# multi form and inherited `multi: true`; the block built from it then carries
# multi=true even though it never takes children of its own.
%Brando.Content.Module{
  type: :liquid,
  name: %{"en" => "Team Lead", "no" => "Teamleder"},
  namespace: %{"en" => "06 COPY PASTE TEST", "no" => "06 COPY PASTE TEST"},
  help_text: %{"en" => "A team lead entry", "no" => "En teamleder"},
  class: "team-lead",
  code: "<div b-tpl=\"team-lead\">\n  <h3>{{ lead_name }}</h3>\n</div>",
  svg: nil,
  multi: true,
  datasource: false,
  sequence: 32,
  deleted_at: nil,
  table_template_id: nil,
  parent_id: team_section.id,
  refs: [],
  vars: [
    %Brando.Content.Var{
      type: :string,
      label: "Lead name",
      key: "lead_name",
      placement: :content,
      value: "Jane Doe",
      sequence: 0,
      width: :full
    }
  ]
}
|> E2eProject.Repo.insert!()

# Multi module (parent) + child that mirrors a real project's "media object":
# the child carries BOTH a `{% ref %}` media ref and a `{% headless_ref %}` text
# ref, and falls back to entry content pulled through a link var's identifier
# when either ref is switched off. This is the shape that exercises
# `refs.<name>.active` from a module template.
fallback_group =
  %Brando.Content.Module{
    type: :liquid,
    name: %{"en" => "Fallback Group", "no" => "Fallbackgruppe"},
    namespace: %{"en" => "08 REF FALLBACK TEST", "no" => "08 REF FALLBACK TEST"},
    help_text: %{"en" => "Multi block of media objects", "no" => "Multiblokk med mediaobjekter"},
    class: "fallback-group",
    code: """
    <section b-tpl="fallback-group">
      {{ content }}
    </section>
    """,
    svg: nil,
    multi: true,
    datasource: false,
    sequence: 40,
    deleted_at: nil,
    table_template_id: nil,
    parent_id: nil,
    refs: [],
    vars: []
  }
  |> E2eProject.Repo.insert!()

%Brando.Content.Module{
  type: :liquid,
  name: %{"en" => "Fallback Object", "no" => "Fallbackobjekt"},
  namespace: %{"en" => "08 REF FALLBACK TEST", "no" => "08 REF FALLBACK TEST"},
  help_text: %{"en" => "Media + text refs with fallbacks", "no" => "Media- og tekstref med fallback"},
  class: "fallback-object",
  # Flagged multi even though it is an entry template that never takes children
  # — the shape real projects produce when the template is created from the
  # multi form. It makes the block render through `Parser.module/2`'s multi
  # clause instead of `render_child_module/7`, which is worth covering here
  # since this module is the one with refs and a `get_entry` fallback.
  code: """
  {% if project and project.identifier %}
    {% assign e = project.identifier | get_entry %}
  {% endif %}
  <article b-tpl="fallback-object" data-entry-id="{{ e.id }}">
    <div class="media">
      {% ref refs.media %}
      {% hide %}
      {% if refs.media.active == false %}
        {% if e %}
          <div class="entry-fallback">{{ e.title }}</div>
        {% else %}
          <div class="media-fallback">FALLBACK MEDIA</div>
        {% endif %}
      {% endif %}
      {% endhide %}
    </div>
    {% headless_ref refs.text %}
    {% if refs.text.active %}
      <div class="text">{{ refs.text.data.data.text }}</div>
    {% else %}
      <div class="text-fallback">FALLBACK TEXT</div>
    {% endif %}
  </article>
  """,
  svg: nil,
  multi: true,
  datasource: false,
  sequence: 41,
  deleted_at: nil,
  table_template_id: nil,
  parent_id: fallback_group.id,
  refs: [
    %Brando.Content.Ref{
      name: "media",
      description: "Media",
      uid: Brando.Utils.generate_uid(),
      data: %Brando.Villain.Blocks.PictureBlock{
        type: "picture",
        data: %Brando.Villain.Blocks.PictureBlock.Data{
          title: nil,
          credits: nil,
          alt: nil,
          picture_class: nil,
          img_class: nil,
          link: nil,
          srcset: nil,
          media_queries: nil,
          lazyload: true,
          moonwalk: false,
          placeholder: :dominant_color_faded,
          fetchpriority: :auto
        }
      }
    },
    %Brando.Content.Ref{
      name: "text",
      description: "Caption",
      uid: Brando.Utils.generate_uid(),
      data: %Brando.Villain.Blocks.TextBlock{
        type: "text",
        data: %Brando.Villain.Blocks.TextBlock.Data{
          text: "Caption body",
          type: "paragraph",
          extensions: nil
        }
      }
    }
  ],
  vars: [
    %Brando.Content.Var{
      type: :link,
      label: "Project",
      key: "project",
      placement: :content,
      link_type: :identifier,
      link_allow_custom_text: true,
      sequence: 0,
      width: :full
    }
  ]
}
|> E2eProject.Repo.insert!()

# Module with image and file vars for upload testing
%Brando.Content.Module{
  type: :liquid,
  name: %{"en" => "Image and File Vars", "no" => "Bilde- og filvariabler"},
  namespace: %{"en" => "07 VAR UPLOAD TEST", "no" => "07 VAR UPLOAD TEST"},
  help_text: %{
    "en" => "Module with image and file variable types",
    "no" => "Modul med bilde- og filvariabler"
  },
  class: "image-file-vars",
  code: """
  <div b-tpl="image-file-vars">
    {% if my_image %}<img src="{{ my_image | media_url }}" />{% endif %}
    {% if my_file %}<a href="{{ my_file | media_url }}">Download</a>{% endif %}
  </div>
  """,
  svg: nil,
  multi: false,
  datasource: false,
  sequence: 40,
  deleted_at: nil,
  table_template_id: nil,
  parent_id: nil,
  refs: [],
  vars: [
    %Brando.Content.Var{
      type: :image,
      label: "My image",
      key: "my_image",
      placement: :content,
      sequence: 0,
      width: :half,
      creator_id: user.id
    },
    %Brando.Content.Var{
      type: :file,
      label: "My file",
      key: "my_file",
      placement: :content,
      sequence: 1,
      width: :half,
      creator_id: user.id
    },
    %Brando.Content.Var{
      type: :string,
      label: "Notes",
      key: "var_notes",
      placement: :content,
      value: "",
      sequence: 2,
      width: :full,
      creator_id: user.id
    }
  ]
}
|> E2eProject.Repo.insert!()

# Module carrying both config- and hidden-placement vars alongside a content
# var. Config vars only have inputs while the config modal is open, so this is
# what pins the rule that a closed modal must still round-trip their identity —
# without it, `cast_assoc(:vars)` sees a shorter list and deletes them.
%Brando.Content.Module{
  type: :liquid,
  name: %{"en" => "Config Vars", "no" => "Konfigvariabler"},
  namespace: %{"en" => "08 CONFIG VAR TEST", "no" => "08 CONFIG VAR TEST"},
  help_text: %{
    "en" => "Module with content, config and hidden placement vars",
    "no" => "Modul med innholds-, konfig- og skjulte variabler"
  },
  class: "config-vars",
  code: """
  <div b-tpl="config-vars" data-tracking="{{ tracking_id }}">
    <span class="body-text">{{ body_text }}</span>
    <span class="config-note">{{ config_note }}</span>
  </div>
  """,
  svg: nil,
  multi: false,
  datasource: false,
  sequence: 41,
  deleted_at: nil,
  table_template_id: nil,
  parent_id: nil,
  refs: [],
  vars: [
    %Brando.Content.Var{
      type: :string,
      label: "Body text",
      key: "body_text",
      placement: :content,
      value: "Body default",
      sequence: 0,
      width: :full,
      creator_id: user.id
    },
    %Brando.Content.Var{
      type: :string,
      label: "Config note",
      key: "config_note",
      placement: :config,
      value: "Config default",
      sequence: 1,
      width: :full,
      creator_id: user.id
    },
    %Brando.Content.Var{
      type: :string,
      label: "Tracking id",
      key: "tracking_id",
      placement: :hidden,
      value: "trk-000",
      sequence: 2,
      width: :full,
      creator_id: user.id
    }
  ]
}
|> E2eProject.Repo.insert!()

# Gallery for gallery listing/editing tests
%Brando.Galleries.Gallery{
  config_target: "gallery:E2eProject.Projects.Project:project_gallery",
  gallery_objects: []
}
|> E2eProject.Repo.insert!()

%Brando.Galleries.Gallery{
  config_target: "test_gallery",
  gallery_objects: []
}
|> E2eProject.Repo.insert!()

# Video for gallery video selection tests
%Brando.Videos.Video{
  title: "Test Video",
  type: :youtube,
  config_target: "default",
  source_url: "https://www.youtube.com/watch?v=dQw4w9WgXcQ",
  remote_id: "dQw4w9WgXcQ",
  width: 1920,
  height: 1080,
  aspect_ratio: "1920/1080",
  status: :ready,
  creator_id: user.id
}
|> E2eProject.Repo.insert!()
