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
          vars: opts[:vars] || []
        ),
        user
      )

    module
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
