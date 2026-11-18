defmodule Brando.Pages.RestorePageFragmentsTest do
  # Restoring a page brings back the fragments trashed with it (#3621), in
  # one transaction with either authorization mode. The entries embedding
  # them render once it commits, as after the page's delete. Not async: the
  # failure is a constraint added to the fragments table, which locks it
  # until the test ends.
  use Brando.ConnCase

  alias Brando.Authorization.{Boundary, Migration}
  alias Brando.Factory
  alias Brando.Pages
  alias Brando.Pages.Fragment
  alias Brando.Pages.Page

  setup do
    put_test_env(:tenancy_mode, :none)
    Boundary.put_scope(nil)
    on_exit(fn -> Boundary.put_scope(nil) end)

    %{user: Factory.insert(:random_user, role: :superuser, config: %Brando.Users.UserConfig{})}
  end

  for mode <- [:legacy, :groups] do
    describe "with #{mode} authorization" do
      @describetag mode: mode

      setup %{mode: mode} do
        put_test_env(:authorization_mode, mode)
        if mode == :groups, do: {:ok, _} = Migration.run()
        :ok
      end

      test "the page comes back with its fragments, and their entries render once it commits", %{user: user} do
        %{page: page, header: header, footer: footer} = trashed_page!(user)
        entry = page!(user, %{title: "Embeds", uri: "embeds"})
        embed_fragment(entry, header, user)

        Oban.Testing.with_testing_mode(:manual, fn ->
          assert {:ok, queued_before_commit?} =
                   Brando.Repo.transaction(fn ->
                     assert {:ok, %Page{deleted_at: nil}} = Boundary.restore(user, reload(page))
                     render_queued?(entry)
                   end)

          refute queued_before_commit?
          assert render_queued?(entry)
        end)

        assert is_nil(reload(page).deleted_at)
        assert is_nil(reload(header).deleted_at)
        assert is_nil(reload(footer).deleted_at)
      end

      test "each restore of the page in one transaction renders the entries of its own fragments", %{user: user} do
        %{page: page, header: header} = trashed_page!(user)
        entry = page!(user, %{title: "Embeds", uri: "embeds"})
        embed_fragment(entry, header, user)
        other_entry = page!(user, %{title: "Embeds aside", uri: "embeds-aside"})

        Oban.Testing.with_testing_mode(:manual, fn ->
          {:ok, _} =
            Brando.Repo.transaction(fn ->
              {:ok, _} = Boundary.restore(user, reload(page))
              aside = fragment!(user, page, "aside")
              {:ok, _} = Pages.delete_page(page.id, user, fragments: :delete)
              # Embedded once in the trash: only the second restore renders it
              embed_fragment(other_entry, aside, user)
              {:ok, _} = Boundary.restore(user, reload(page))
            end)

          assert render_queued?(entry)
          assert render_queued?(other_entry)
        end)
      end

      test "deleting the page with its fragments renders their entries once it commits", %{user: user} do
        page = page!(user, %{title: "Page", uri: "page"})
        header = fragment!(user, page, "header")
        entry = page!(user, %{title: "Embeds", uri: "embeds"})
        embed_fragment(entry, header, user)

        Oban.Testing.with_testing_mode(:manual, fn ->
          assert {:ok, queued_before_commit?} =
                   Brando.Repo.transaction(fn ->
                     {:ok, _} = Pages.delete_page(page.id, user, fragments: :delete)
                     render_queued?(entry)
                   end)

          refute queued_before_commit?
          assert render_queued?(entry)
        end)
      end

      test "a fragment that can't be restored leaves the page and the others in the trash", %{user: user} do
        %{page: page, header: header, footer: footer} = trashed_page!(user)

        # The footer, restored after the page and the header, is refused
        Ecto.Adapters.SQL.query!(
          Brando.Repo.repo(),
          "ALTER TABLE pages_fragments ADD CONSTRAINT reject_restore_test CHECK (deleted_at IS NOT NULL OR key <> 'footer') NOT VALID"
        )

        assert_raise Ecto.ConstraintError, ~r/reject_restore_test/, fn -> Boundary.restore(user, reload(page)) end

        assert reload(page).deleted_at == page.deleted_at
        assert reload(header).deleted_at == page.deleted_at
        assert reload(footer).deleted_at == page.deleted_at
      end
    end
  end

  test "maintenance code restores the page with its fragments, all or nothing", %{user: user} do
    %{page: page, header: header, footer: footer} = trashed_page!(user)

    Ecto.Adapters.SQL.query!(
      Brando.Repo.repo(),
      "ALTER TABLE pages_fragments ADD CONSTRAINT reject_restore_test CHECK (deleted_at IS NOT NULL OR key <> 'footer') NOT VALID"
    )

    assert_raise Ecto.ConstraintError, fn -> Boundary.restore(:system, reload(page)) end
    assert reload(page).deleted_at == page.deleted_at
    assert reload(header).deleted_at == page.deleted_at

    Ecto.Adapters.SQL.query!(Brando.Repo.repo(), "ALTER TABLE pages_fragments DROP CONSTRAINT reject_restore_test")

    assert {:ok, _} = Boundary.restore(:system, reload(page))
    assert is_nil(reload(header).deleted_at)
    assert is_nil(reload(footer).deleted_at)
  end

  # A page in the trash with two fragments trashed with it, the header first
  defp trashed_page!(user) do
    page = page!(user, %{title: "Page", uri: "page"})
    header = fragment!(user, page, "header")
    footer = fragment!(user, page, "footer")
    {:ok, page} = Pages.delete_page(page.id, user, fragments: :delete)
    assert reload(header).deleted_at == page.deleted_at

    %{page: page, header: header, footer: footer}
  end

  defp page!(user, attrs) do
    params = Map.merge(%{language: "en", template: "default.html", status: :published}, attrs)
    {:ok, page} = Pages.create_page(params, user)
    page
  end

  defp fragment!(user, page, key) do
    Factory.insert(:fragment, creator: user, page_id: page.id, parent_key: "partials", key: key)
  end

  defp embed_fragment(entry, fragment, user) do
    block =
      %Brando.Content.Block{}
      |> Brando.Content.Block.recursive_block_changeset(
        %{
          "uid" => Brando.Utils.generate_uid(),
          "creator_id" => user.id,
          "source" => to_string(Page.Blocks),
          "type" => "fragment",
          "fragment_id" => fragment.id
        },
        user
      )
      |> Repo.insert!()

    Repo.insert!(%Page.Blocks{entry_id: entry.id, block_id: block.id, sequence: 0})
  end

  defp render_queued?(%Page{id: id}),
    do: Enum.any?(all_enqueued(worker: Brando.Worker.EntryRenderer), &(&1.args["entry_id"] == id))

  defp reload(%Fragment{id: id}), do: Repo.get!(Fragment, id)
  defp reload(%Page{id: id}), do: Repo.get!(Page, id)
end
