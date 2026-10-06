defmodule Brando.Content.Identifier.SyncTest do
  use ExUnit.Case
  use Brando.ConnCase
  use BrandoIntegration.TestCase

  import Ecto.Query
  import ExUnit.CaptureIO

  alias Brando.BlueprintTest.Project
  alias Brando.Content.Identifier
  alias Brando.Content.Identifier.Sync
  alias Brando.Factory
  alias Brando.Pages.Page

  test "an entry that raises is skipped and reported, and the rest are synced" do
    # Loading a test Project for its identifier raises: its context module
    # (Brando.Projects) does not exist.
    project = Brando.Repo.insert!(%Project{title: "Broken", slug: "broken", language: :en})
    {:ok, _} = Brando.Content.create_identifier(Project, project)

    stale_page = Factory.insert(:page, title: "Fresh")
    {:ok, stale} = Brando.Content.create_identifier(Page, stale_page)
    stale |> Ecto.Changeset.change(title: "Stale") |> Brando.Repo.update!()

    missing_page = Factory.insert(:page)
    Brando.Repo.delete_all(from(i in Identifier, where: i.entry_id == ^missing_page.id and i.schema == ^Page))

    {result, output} = with_io(fn -> Sync.sync(modules: [Project, Page]) end)

    assert {:error, [{subject, %UndefinedFunctionError{}}]} = result
    assert subject =~ "Brando.BlueprintTest.Project ##{project.id}"
    assert output =~ "1 identifier(s) could not be synced"

    assert Brando.Repo.reload!(stale).title == "Fresh"
    assert {:ok, _} = Brando.Content.get_identifier(Page, missing_page)
  end

  test "returns :ok when every entry syncs" do
    page = Factory.insert(:page)

    assert {:ok, _output} = with_io(fn -> Sync.sync(modules: [Page]) end)
    assert {:ok, _} = Brando.Content.get_identifier(Page, page)
  end
end
