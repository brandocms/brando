defmodule E2eProject.ContentTransferTest do
  use E2eProject.DataCase, async: false
  alias Brando.{Repo, Content}
  alias Brando.Content.Transfer
  alias E2eProject.Projects.{Project, Client, Category, ProjectCategory}

  test "whole project transfers related entries, owned category joins and gallery ownership, then recovers" do
    actor =
      Repo.insert!(%Brando.Users.User{
        name: "Transfer test",
        email: "transfer-test@brandocms.com",
        role: :superuser,
        password: "brandocms",
        language: :en
      })

    verify = fn condition, message -> assert condition, message end
    suffix = Ecto.UUID.generate()

    client =
      Client.changeset(
        %Client{},
        %{name: "Transfer client", slug: "client-" <> suffix, language: "en", status: "draft"},
        actor
      )
      |> Repo.insert!()

    category =
      Category.changeset(
        %Category{},
        %{title: "Transfer category", slug: "category-" <> suffix, language: "en", status: "draft"},
        actor
      )
      |> Repo.insert!()

    gallery =
      Brando.Galleries.Gallery.changeset(
        %Brando.Galleries.Gallery{},
        %{config_target: "default", gallery_objects: []},
        actor
      )
      |> Repo.insert!()

    project =
      Repo.insert!(%Project{
        title: "Whole project",
        slug: "project-" <> suffix,
        introduction: "<p>Authored introduction</p>",
        language: :en,
        status: :published,
        client_id: client.id,
        project_gallery_id: gallery.id,
        creator_id: actor.id
      })

    Repo.insert!(%ProjectCategory{project_id: project.id, category_id: category.id, sequence: 0})
    Enum.each([client, category, project], &Content.create_identifier(&1.__struct__, &1))
    identifier = Repo.get_by!(Brando.Content.Identifier, schema: Project, entry_id: project.id)
    selection_schema = Project.__schema__(:association, :related_entries).related
    Repo.insert!(struct(selection_schema, parent_id: project.id, identifier_id: identifier.id, sequence: 0))

    {:ok, exported} =
      Transfer.export(Enum.map([project, client, category], &%{schema: &1.__struct__, id: &1.id}), actor, media: false)

    {:ok, archive} = Transfer.read(exported.binary)

    targets =
      Map.new(archive.bundle["entries"], fn entry ->
        {entry["key"], %{"attributes" => %{"slug" => entry["data"]["attributes"]["slug"] <> "-copy"}}}
      end)

    {:ok, plan} = Transfer.preview(archive, targets, actor)
    verify.(plan.problems == [], inspect(plan.problems))
    gallery_count = Repo.aggregate(Brando.Galleries.Gallery, :count)
    {:ok, receipt} = Transfer.apply(plan, actor)
    id = receipt.after["#{Project}:#{project.id}"]["id"]
    copied = Transfer.EntryCodec.load!(Project, id, actor)
    verify.(copied.introduction == project.introduction, "Introduction missing")
    verify.(copied.client_id != client.id, "Client was not remapped")
    copied_identifier = Repo.get_by!(Brando.Content.Identifier, schema: Project, entry_id: copied.id)
    verify.(hd(copied.related_entries).identifier_id == copied_identifier.id, "The self-selection was not remapped")
    verify.(hd(copied.project_categories).category_id != category.id, "Owned category join was not remapped")
    verify.(copied.project_gallery_id != gallery.id, "Gallery was shared")
    verify.(Repo.aggregate(Brando.Galleries.Gallery, :count) == gallery_count + 1, "Unused gallery was inserted")
    verify.(Enum.all?(receipt.refresh, &(&1["status"] != "failed")), "Refresh failed: #{inspect(receipt.refresh)}")
    {:ok, _} = Transfer.restore(receipt.id, actor)
    verify.(is_nil(Repo.get(Project, id)), "Created entry was not removed")
    verify.(!is_nil(Repo.get(Project, project.id)), "Source entry was changed")
  end
end
