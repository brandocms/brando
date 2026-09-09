defmodule E2eProject.RichTextIdentifierTest do
  use E2eProject.DataCase, async: false
  use Oban.Testing, repo: E2eProject.Repo
  alias Brando.Content.{Block, Ref}
  alias Brando.Villain.Blocks.TextBlock
  alias E2eProject.Projects.{Client, Project}

  test "a normal destination update rewrites refs and ordinary rich-text owners and invalidates their cache" do
    Code.ensure_loaded!(Brando.RuntimeConfig.router_helpers())

    user =
      Repo.insert!(%Brando.Users.User{
        name: "Rich text test",
        email: "rich-text-test@example.test",
        password: "unused-in-test",
        role: :superuser,
        language: :en,
        config: %Brando.Users.UserConfig{}
      })

    client = Repo.insert!(%Client{name: "Editor test", slug: "editor-test-client", creator_id: user.id, language: :en})

    destination =
      Repo.insert!(%Project{
        title: "Destination",
        slug: "editor-test-destination",
        introduction: "<p>Destination</p>",
        client_id: client.id,
        creator_id: user.id,
        language: :en,
        status: :published
      })

    {:ok, identifier} = Brando.Content.create_identifier(Project, destination)

    html =
      "<p><a data-identifier-id='#{identifier.id}' class='action-button extra' href='#{identifier.url}'>Our wording &amp; more</a></p>"

    owner =
      Repo.insert!(%Project{
        title: "Owner",
        slug: "editor-test-owner",
        introduction: html,
        client_id: client.id,
        creator_id: user.id,
        language: :en
      })

    block =
      Repo.insert!(%Block{
        type: :module,
        uid: Brando.Utils.generate_uid(),
        refs: [
          %Ref{
            name: "text",
            uid: Brando.Utils.generate_uid(),
            data: %TextBlock{type: "text", data: %TextBlock.Data{text: html}}
          }
        ]
      })

    assert block.id in Brando.Content.Blocks.list_block_ids_with_identifier_in_refs(identifier.id)
    key = {:single, Project.__schema__(:source), "rich-text-test", owner.id}
    Cachex.put(:query, key, owner)

    Oban.Testing.with_testing_mode(:manual, fn ->
      assert {:ok, _} = E2eProject.Projects.update_project(destination, %{slug: "editor-test-renamed"}, user)
      rewritten = Repo.get!(Project, owner.id).introduction
      assert rewritten =~ ~s(href="/project/editor-test-renamed")
      assert rewritten =~ "Our wording &amp; more"
      refute rewritten =~ "editor-test-destination"
      assert {:ok, nil} = Cachex.get(:query, key)

      assert_enqueued(
        worker: Brando.Worker.EntryRenderer,
        args: %{schema: "Elixir.E2eProject.Projects.Project", entry_id: owner.id}
      )

      ref = Repo.get_by!(Ref, block_id: block.id)
      assert ref.data.data.text =~ ~s(href="/project/editor-test-renamed")
    end)
  end
end
