defmodule BrandoAdmin.EmptyVarPickTest do
  # A link or image var saved empty, given an entry or an image in the
  # editor: the save renders what was picked.
  use Brando.LiveCase

  import Brando.EditSessionEditors

  alias Brando.Content.Block
  alias Brando.Pages.Page

  # The vars in the block form's params, in their order: `project`, `photo`
  @vars ["entry_block", "block", "vars"]

  setup %{current_user: user} do
    module =
      Brando.ProposalFixtures.module!(
        user,
        "Card",
        ~s({% if project.identifier %}<a class="card">{{ project.identifier.title }}</a>{% endif %}) <>
          ~s({% if photo %}<i class="photo"></i>{% endif %}),
        vars: [
          %{key: "project", type: "link", label: "Project", link_type: "identifier"},
          %{key: "photo", type: "image", label: "Photo"}
        ]
      )

    page = Factory.insert(:page, creator: user, title: "Cards", uri: "cards")
    other = Factory.insert(:page, creator: user, title: "Linked page", uri: "linked")
    {:ok, identifier} = Brando.Content.create_identifier(Page, other)

    block =
      %Block{}
      |> Block.recursive_block_changeset(
        %{
          "uid" => Brando.Utils.generate_uid(),
          "type" => "module",
          "module_id" => module.id,
          "creator_id" => user.id,
          "source" => to_string(Page.Blocks),
          "vars" => [
            %{
              "key" => "project",
              "type" => "link",
              "label" => "Project",
              "link_type" => "identifier",
              "sequence" => 0,
              "link_identifier_schemas" => ["Brando.Pages.Page"]
            },
            %{"key" => "photo", "type" => "image", "label" => "Photo", "sequence" => 1}
          ]
        },
        user
      )
      |> Repo.insert!()

    struct(Page.Blocks, %{entry_id: page.id, block_id: block.id, sequence: 0}) |> Repo.insert!()
    image = Factory.insert(:image, creator_id: user.id)

    %{page: page, uid: block.uid, identifier: identifier, image: image}
  end

  test "an entry picked for an empty link var is in the saved render", c do
    view = open(c.conn, c.page)
    set(view, c.uid, @vars ++ ["0", "identifier_id"], to_string(c.identifier.id))
    save(view)

    assert rendered(c.page) =~ ~s(<a class="card">Linked page</a>)
  end

  test "an image picked for an empty image var is in the saved render", c do
    view = open(c.conn, c.page)
    # What the var's input sends its block once an image is picked (`RenderVar.on_change/2`)
    block = %Phoenix.LiveComponent.CID{cid: cid_of(view, "#entry_block_form-#{c.uid}")}
    data = %{image: c.image, image_id: c.image.id}

    Phoenix.LiveView.send_update(view.pid, block,
      event: "update_block_var",
      var_key: "photo",
      var_type: :image,
      data: data
    )

    render(view)
    save(view)

    assert rendered(c.page) =~ ~s(<i class="photo"></i>)
  end

  defp open(conn, page) do
    {view, _html} = live_form(conn, "/admin/pages/update/#{page.id}")
    await_selector(view, "[data-block-uid]")
    view
  end

  # A save is two submits: the first collects the blocks, the second writes
  defp save(view) do
    view |> form("#page_form_form") |> render_submit()
    assert_push_event(view, "b:submit", %{}, 5_000)
    view |> form("#page_form_form") |> render_submit()
  end

  defp rendered(page), do: Repo.get!(Page, page.id).rendered_blocks
end
