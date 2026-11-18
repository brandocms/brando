defmodule E2eProject.GetEntrySelfLinkTest do
  # A project's blocks link to the project itself and load it with `get_entry`.
  # A form that renders only some of the entry's block fields leaves the others
  # to be rendered after a status change.
  use E2eProject.DataCase, async: false
  use Oban.Testing, repo: E2eProject.Repo

  alias E2eProject.Projects
  alias E2eProject.Projects.{Client, Project}

  @card ~S"""
  {% assign e = card.identifier | get_entry %}
  {% if e %}<div class="card">{{ e.title }}</div>{% else %}<div class="no-card"></div>{% endif %}
  """

  test "a form that renders some of the block fields leaves the others to be rendered for a status change" do
    Code.ensure_loaded!(Brando.RuntimeConfig.router_helpers())

    user =
      Repo.insert!(%Brando.Users.User{
        name: "Self link test",
        email: "self-link-test@example.test",
        password: "unused-in-test",
        role: :superuser,
        language: :en,
        config: %Brando.Users.UserConfig{}
      })

    client = Repo.insert!(%Client{name: "Self link", slug: "self-link-client", creator_id: user.id, language: :en})

    project =
      Repo.insert!(%Project{
        title: "Launch",
        slug: "self-link-project",
        introduction: "<p>Launch</p>",
        client_id: client.id,
        creator_id: user.id,
        language: :en,
        status: :draft
      })

    {:ok, identifier} = Brando.Content.create_identifier(Project, project)

    {:ok, module} =
      Brando.Content.create_module(
        %{
          name: "Self card",
          namespace: "projects",
          help_text: "help",
          class: "self-card",
          code: @card,
          vars: [%{type: :link, key: "card", label: "Card", link_type: :identifier, creator_id: user.id}]
        },
        :system
      )

    block =
      Repo.insert!(%Brando.Content.Block{
        type: :module,
        source: to_string(Project.IntroductionNotes),
        module_id: module.id,
        uid: Brando.Utils.generate_uid(),
        creator_id: user.id,
        vars: [
          %Brando.Content.Var{
            type: :link,
            key: "card",
            label: "Card",
            link_type: :identifier,
            identifier_id: identifier.id,
            creator_id: user.id
          }
        ]
      })

    Repo.insert!(%Project.IntroductionNotes{entry_id: project.id, block_id: block.id, sequence: 0})
    {:ok, _} = Brando.Content.Blocks.render_entry(Project, project.id)
    assert Repo.get!(Project, project.id).rendered_introduction_notes =~ ~s(class="no-card")

    # A form that holds the `blocks` field only renders that one
    {:ok, entry} = Brando.Query.get_entry(Project, project.id)

    # The jobs the save queues, run here
    Oban.Testing.with_testing_mode(:manual, fn ->
      {:ok, _} =
        entry
        |> Project.changeset(%{status: :published}, user)
        |> rendered_for_save([{:blocks, Project.Blocks, nil, []}])
        |> Projects.update_project(user)

      for worker <- [Brando.Worker.EntryCascade, Brando.Worker.EntryRenderer],
          %{args: args} <- all_enqueued(worker: worker),
          do: perform_job(worker, args)
    end)

    assert Repo.get!(Project, project.id).rendered_introduction_notes =~ ~s(<div class="card">Launch</div>)
  end

  # The form's inline render, as a save renders it: no block template fails here
  defp rendered_for_save(changeset, block_map) do
    {changeset, []} = BrandoAdmin.Components.Form.render_blocks_for_save(block_map, changeset)
    changeset
  end
end
