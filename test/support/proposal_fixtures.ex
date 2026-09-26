defmodule Brando.ProposalFixtures do
  @moduledoc false
  alias Brando.Content.Block
  alias Brando.{Factory, Repo}
  alias Brando.Pages.Page

  # A user, an image, a video, a Text module (text ref `body`), a Case module
  # (picture `cover`, video `clip`, media `slot`, vars `heading` and `wide`),
  # and two published pages with three Text blocks each.
  def context do
    user = Factory.insert(:random_user)
    image = Factory.insert(:image, creator_id: user.id)
    video = Factory.insert(:video)

    text_module =
      module!(user, "Text", "<p>{{ heading }}</p>{% ref refs.body %}",
        refs: [ref("body", %{type: "text", data: %{text: "Default body"}})]
      )

    case_module =
      module!(
        user,
        "Case",
        ~s(<div class="case">{{ heading }}{% ref refs.cover %}{% ref refs.clip %}{% ref refs.slot %}</div>),
        refs: [
          ref("cover", %{type: "picture", data: %{}}),
          ref("clip", %{type: "video", data: %{}}),
          ref("slot", %{
            type: "media",
            data: %{
              available_blocks: ["picture", "video"],
              template_picture: %{title: "Slot picture"},
              template_video: %{}
            }
          })
        ],
        vars: [
          %{type: "string", key: "heading", label: "Heading", value: "Default heading"},
          %{type: "boolean", key: "wide", label: "Wide", value_boolean: false}
        ]
      )

    identity = page!(user, "Identity", text_module)
    naming = page!(user, "Naming", text_module)

    %{
      user: user,
      image: image,
      video: video,
      text_module: text_module,
      case_module: case_module,
      identity: identity,
      naming: naming
    }
  end

  def ref(name, data), do: %{name: name, uid: Brando.Utils.generate_uid(), data: data}

  def module!(user, name, code, opts) do
    {:ok, module} =
      Brando.Content.create_module(
        Factory.params_for(:module,
          name: %{"en" => name},
          namespace: %{"en" => "Content"},
          help_text: %{"en" => "Help"},
          code: code,
          refs: opts[:refs] || [],
          vars: opts[:vars] || [],
          multi: opts[:multi] || false,
          parent_id: opts[:parent_id]
        ),
        user
      )

    module
  end

  # A "Projects" multi module whose entry module "Project" has a `size`
  # select (50/100), a `clip` video and an `info` text, and a page "Work"
  # with a Text block and a Projects block holding three projects: sizes
  # 100, 100 and 50, the first showing `c.video`.
  def multi_context(c) do
    projects =
      module!(c.user, "Projects", ~s(<section class="projects">{{ content }}</section>), multi: true)

    project =
      module!(
        c.user,
        "Project",
        ~s(<article class="project size-{{ size }}">{% ref refs.info %}{% ref refs.clip %}</article>),
        parent_id: projects.id,
        refs: [ref("info", %{type: "text", data: %{text: "Info"}}), ref("clip", %{type: "video", data: %{}})],
        vars: [
          %{
            type: "select",
            key: "size",
            label: "Size",
            value: "100",
            options: [%{label: "Half", value: "50"}, %{label: "Full", value: "100"}]
          }
        ]
      )

    page = Factory.insert(:page, creator: c.user, title: "Work", uri: "work")
    text = insert_block!(c.user, c.text_module, :module, nil, [body_ref("<p>Work intro</p>")], [])
    multi = insert_block!(c.user, projects, :module, nil, [], [])

    children =
      [{"Alpha", "100", c.video.id}, {"Beta", "100", nil}, {"Gamma", "50", nil}]
      |> Enum.with_index()
      |> Enum.map(fn {{name, size, video_id}, n} ->
        refs = [
          %{"uid" => Brando.Utils.generate_uid(), "name" => "info", "data" => text_data("<p>#{name}</p>")},
          %{
            "uid" => Brando.Utils.generate_uid(),
            "name" => "clip",
            "data" => %{"type" => "video", "data" => %{}},
            "video_id" => video_id
          }
        ]

        vars = [
          %{
            "type" => "select",
            "key" => "size",
            "label" => "Size",
            "value" => size,
            "options" => [
              %{"label" => "Half", "value" => "50"},
              %{"label" => "Full", "value" => "100"}
            ]
          }
        ]

        insert_block!(c.user, project, :module_entry, multi.id, refs, vars, n)
      end)

    for {block, n} <- Enum.with_index([text, multi]),
        do: struct(Page.Blocks, %{entry_id: page.id, block_id: block.id, sequence: n}) |> Repo.insert!()

    Map.merge(c, %{
      projects_module: projects,
      project_module: project,
      work: page,
      intro_uid: text.uid,
      multi_uid: multi.uid,
      child_uids: Enum.map(children, & &1.uid)
    })
  end

  defp body_ref(text), do: %{"uid" => Brando.Utils.generate_uid(), "name" => "body", "data" => text_data(text)}
  defp text_data(text), do: %{"type" => "text", "data" => %{"text" => text}}

  defp insert_block!(user, module, type, parent_id, refs, vars, sequence \\ 0) do
    %Block{}
    |> Block.recursive_block_changeset(
      %{
        "uid" => Brando.Utils.generate_uid(),
        "type" => to_string(type),
        "module_id" => module.id,
        "multi" => module.multi || false,
        "parent_id" => parent_id,
        "sequence" => sequence,
        "creator_id" => user.id,
        "source" => to_string(Page.Blocks),
        "refs" => refs,
        "vars" => vars
      },
      user
    )
    |> Repo.insert!()
  end

  def page!(user, title, module) do
    page = Factory.insert(:page, creator: user, title: title, uri: String.downcase(title))

    for n <- 0..2 do
      block =
        %Block{}
        |> Block.recursive_block_changeset(
          %{
            "uid" => Brando.Utils.generate_uid(),
            "type" => "module",
            "module_id" => module.id,
            "creator_id" => user.id,
            "source" => to_string(Page.Blocks),
            "refs" => [
              %{
                "uid" => Brando.Utils.generate_uid(),
                "name" => "body",
                "data" => %{"type" => "text", "data" => %{"text" => "<p>#{title} #{n}</p>"}}
              }
            ]
          },
          user
        )
        |> Repo.insert!()

      struct(Page.Blocks, %{entry_id: page.id, block_id: block.id, sequence: n}) |> Repo.insert!()
    end

    page
  end
end
