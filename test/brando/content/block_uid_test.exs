defmodule Brando.Content.BlockUidTest do
  # A block uid is written into marker comments on edit-mode pages, so its shape
  # is what keeps it from changing the page's structure. The markup below would
  # only set document.title.
  use Brando.ConnCase, async: false

  alias Brando.Authorization.{Catalog, Groups, Migration, Scope}
  alias Brando.Content.Block
  alias Brando.Content.Proposals
  alias Brando.Content.Proposals.{BlockTree, CopyBlock, InsertBlock, Preview, Record}
  alias Brando.{Factory, FrontendEdit, FrontendEditFixtures, Repo}
  alias Brando.Pages.Page
  alias Ecto.Changeset
  import Ecto.Query, only: [from: 2]

  @breakout "x>] --><script>document.title='MARKER'</script><!-- [+:B<y"
  @liquid "{{ 7777 | plus: 1 }}"
  @bad_uids [
    @breakout,
    @liquid,
    "{% if true %}x{% endif %}",
    "[$ content $]",
    "",
    "has space",
    "line\n",
    "closes--",
    "trailing-",
    String.duplicate("a", 256)
  ]

  defp block_changeset(attrs, user) do
    base = %{
      "type" => "container",
      "creator_id" => user.id,
      "source" => to_string(Page.Blocks)
    }

    Block.block_changeset(%Block{}, Map.merge(base, attrs), user)
  end

  defp groups_editor(c) do
    put_test_env(:authorization_mode, :groups)
    {:ok, _} = Migration.run()
    editor = Factory.insert(:random_user, role: :user)
    scope = Scope.standalone(c.user)

    grants = [
      Catalog.get(:read, Page).key,
      Catalog.get(:update, Page).key,
      Catalog.get(:read, Brando.Content.Module).key,
      "brando.admin.access"
    ]

    {:ok, group} = Groups.create(scope, %{name: "Proposal editors"}, grants)
    {:ok, :ok} = Groups.add_member(scope, group.id, editor.id)
    Repo.get!(Page, c.identity.id) |> Changeset.change(status: :draft) |> Repo.update!()
    editor
  end

  describe "valid_uid?/1" do
    test "admits generated and derived uids" do
      generated = Brando.Utils.generate_uid()

      for uid <- [
            generated,
            BlockTree.copy_uid(generated, "original"),
            generated <> "-kept",
            generated <> "-kept-2",
            generated <> "-kept-kept-12",
            "snake_case_uid"
          ] do
        assert Block.valid_uid?(uid), "expected #{uid} to be valid"
      end
    end

    test "refuses anything else" do
      for uid <- @bad_uids, do: refute(Block.valid_uid?(uid), "expected #{inspect(uid)} to be refused")
      refute Block.valid_uid?(nil)
      refute Block.valid_uid?(123)
    end
  end

  describe "the block changeset" do
    setup do
      %{user: Factory.insert(:random_user)}
    end

    test "refuses a badly shaped uid", %{user: user} do
      for uid <- @bad_uids do
        refute block_changeset(%{"uid" => uid}, user).valid?, "expected #{inspect(uid)} to be refused"
      end
    end

    test "admits a recovery copy's uid", %{user: user} do
      assert block_changeset(%{"uid" => Brando.Utils.generate_uid() <> "-kept-2"}, user).valid?
    end

    test "a row stored with a bad uid can still be edited", %{user: user} do
      block = %Block{uid: @breakout, type: :container, creator_id: user.id}
      assert Block.block_changeset(block, %{"uid" => @breakout, "description" => "Edited"}, user).valid?
    end
  end

  describe "proposals" do
    setup do
      Brando.ProposalFixtures.context()
    end

    for mode <- [:legacy, :groups] do
      @mode mode

      test "#{mode}: insert_block and copy_block report a bad uid, a good one passes", c do
        actor = if @mode == :groups, do: groups_editor(c), else: c.user
        target = {Page, c.identity.id}
        [existing | _] = Enum.map(Brando.Content.Transfer.Catalog.load!(Page, c.identity.id, actor).entry_blocks, & &1.block.uid)
        before = Repo.aggregate(Block, :count)

        for uid <- [@breakout, @liquid, "closes--"] do
          ops = [
            %InsertBlock{target: target, module: c.text_module.id, uid: uid},
            %CopyBlock{target: target, block_uid: existing, placement: :append, uid: uid}
          ]

          assert {:ok, proposal} = Proposals.propose(ops, actor)
          assert Enum.map(proposal.problems, &{&1.operation, &1.code}) == [{0, :invalid_uid}, {1, :invalid_uid}]
          assert {:error, _} = Proposals.approve(proposal.id, proposal.version, actor)
        end

        assert Repo.aggregate(Block, :count) == before

        uid = Brando.Utils.generate_uid()
        insert = %InsertBlock{target: target, module: c.text_module.id, uid: uid}
        copy = %CopyBlock{target: target, block_uid: existing, placement: :append, uid: uid <> "-copy"}
        assert {:ok, %{problems: []} = proposal} = Proposals.propose([insert, copy], actor)
        assert {:ok, _} = Proposals.approve(proposal.id, proposal.version, actor)
        assert {:ok, _} = Proposals.apply(proposal.id, proposal.version, actor)
        assert Repo.get_by(Block, uid: uid)
        assert Repo.get_by(Block, uid: uid <> "-copy")
      end
    end

    test "a copy to another entry reports a bad uid", c do
      [existing | _] = Enum.map(Brando.Content.Transfer.Catalog.load!(Page, c.identity.id, c.user).entry_blocks, & &1.block.uid)
      other = Factory.insert(:page, creator: c.user)

      op = %CopyBlock{
        target: {Page, c.identity.id},
        block_uid: existing,
        to_target: {Page, other.id},
        placement: :append,
        uid: @breakout
      }

      assert {:ok, proposal} = Proposals.propose([op], c.user)
      assert Enum.map(proposal.problems, & &1.code) == [:invalid_uid]
    end

    test "a ref uid chosen for a new block is held to the same shape", c do
      op = %InsertBlock{
        target: {Page, c.identity.id},
        module: c.text_module.id,
        ref_uids: %{"body" => @breakout}
      }

      assert {:ok, proposal} = Proposals.propose([op], c.user)
      assert Enum.map(proposal.problems, & &1.code) == [:invalid_uid]
    end

    test "a proposal stored before the check is refused at approve, apply and preview", c do
      op = %InsertBlock{target: {Page, c.identity.id}, module: c.text_module.id, uid: @breakout}
      assert {:ok, proposal} = Proposals.propose([op], c.user)
      assert [%{code: :invalid_uid}] = proposal.problems

      clear = fn extra ->
        Repo.update_all(from(r in Record, where: r.id == ^proposal.id), set: [problems: []] ++ extra)
      end

      clear.([])
      assert {:error, _} = Proposals.approve(proposal.id, proposal.version, c.user)

      clear.([])
      assert {:ok, stored} = Proposals.get(proposal.id, c.user)
      assert {:error, :problems} = Preview.render(stored, {Page, c.identity.id}, c.user, preview_target: :blocks)

      clear.(status: "approved", approved_at: DateTime.utc_now())
      assert {:error, _} = Proposals.apply(proposal.id, proposal.version, c.user)
      refute Repo.get_by(Block, uid: @breakout)
    end
  end

  describe "duplicating" do
    test "a block stored with a bad uid gives the copy a good one" do
      user = Factory.insert(:random_user)
      %{intro: intro} = FrontendEditFixtures.page_with_blocks(user)
      {1, _} = Repo.update_all(from(b in Block, where: b.id == ^intro.id), set: [uid: @breakout])
      stored = Block |> Repo.get!(intro.id) |> Repo.preload([:vars, :refs, :table_rows, :block_identifiers, :children])

      copy =
        stored
        |> Changeset.change()
        |> Brando.Content.Blocks.duplicate_block(user_id: user.id)
        |> Changeset.apply_changes()

      assert Block.valid_uid?(copy.uid)
    end
  end

  describe "an edit-mode render" do
    setup do
      user = Factory.insert(:random_user, role: :superuser)
      on_exit(fn -> FrontendEdit.deactivate() end)
      Map.put(FrontendEditFixtures.page_with_blocks(user), :user, user)
    end

    defp store_uid!(block, uid) do
      {1, _} = Repo.update_all(from(b in Block, where: b.id == ^block.id), set: [uid: uid])
    end

    defp edit_mode_html(page), do: FrontendEdit.with_active(fn -> FrontendEdit.rendered_html(page, :blocks) end)

    for {name, uid} <- [{"comment terminator", @breakout}, {"Liquid", @liquid}, {"marker terminator", "closes--"}] do
      @uid uid

      test "a stored uid with a #{name} leaves no marker or element", %{page: page, intro: intro, container: container, child: child} do
        store_uid!(intro, "1" <> @uid)
        store_uid!(container, "2" <> @uid)
        store_uid!(child, "3" <> @uid)

        html = edit_mode_html(page)
        parsed = LazyHTML.from_fragment(html)

        assert LazyHTML.query(parsed, "script") |> Enum.to_list() == []
        refute html =~ "MARKER"
        refute html =~ "7778"
        refute html =~ "[+:B<"
        refute html =~ "[+:C<"

        # The content itself still renders.
        assert html =~ "Hello from the intro"
        assert html =~ "Inside the section"
      end
    end

    test "a bad uid drops only its own markers", %{page: page, intro: intro, container: container, child: child} do
      store_uid!(intro, @breakout)
      html = edit_mode_html(page)

      refute html =~ "MARKER"
      assert html =~ "<!-- [+:B<#{container.uid}>] -->"
      assert html =~ "<!-- [+:C<#{container.uid}>] -->"
      assert html =~ "<!-- [+:B<#{child.uid}>] -->"
    end

    test "generated and derived uids keep their markers", %{page: page, intro: intro} do
      uid = Brando.Utils.generate_uid() <> "-kept-2"
      store_uid!(intro, uid)
      assert edit_mode_html(page) =~ "<!-- [+:B<#{uid}>] -->"
    end
  end
end
