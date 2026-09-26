defmodule Brando.Content.ProposalsTest do
  use Brando.ConnCase, async: false
  alias Brando.Content.Block
  alias Brando.Content.Proposals

  alias Brando.Content.Proposals.{
    Codec,
    CopyBlock,
    CreateEntry,
    DeleteBlock,
    InsertBlock,
    MoveBlock,
    Review,
    SetBlockActive,
    SetBlockDetails,
    SetBlockSelection,
    SetBlockTable,
    SetRefConfig,
    Preview,
    Receipt,
    SetBlockMedia,
    SetBlockText,
    SetBlockValues,
    SetFields
  }

  alias Brando.Content.Transfer.Catalog
  alias Brando.{Factory, Repo}
  alias Brando.Pages.Page
  alias Brando.Revisions.Revision
  alias Ecto.Changeset
  import Ecto.Query, only: [from: 2]

  import Brando.ProposalFixtures, only: [module!: 4]

  setup do
    Brando.ProposalFixtures.context()
  end

  defp approve_and_apply(proposal, user) do
    with {:ok, _} <- Proposals.approve(proposal.id, proposal.version, user),
         do: Proposals.apply(proposal.id, proposal.version, user)
  end

  defp load(page, user), do: Catalog.load!(Page, page.id, user)
  defp roots(page, user), do: Enum.map(load(page, user).entry_blocks, &{&1.id, &1.block.id, &1.block.uid})
  defp uids(page, user), do: Enum.map(load(page, user).entry_blocks, & &1.block.uid)
  defp block_count, do: Repo.aggregate(Block, :count)

  defp revisions(page),
    do: Repo.aggregate(from(r in Revision, where: r.entry_type == ^to_string(Page) and r.entry_id == ^page.id), :count)

  defp workflow(c) do
    [first | _] = uids(c.identity, c.user)

    [
      %CreateEntry{
        schema: Page,
        ref: :sommerro,
        fields: %{title: "Sommerro", uri: "sommerro", language: "en", template: "default.html"}
      },
      %InsertBlock{
        target: {Page, c.identity.id},
        module: c.case_module.id,
        placement: {:after, first},
        values: %{heading: "Identity case", wide: true},
        media: %{cover: {:image, c.image.id}}
      },
      %InsertBlock{
        target: {Page, c.naming.id},
        module: c.case_module.id,
        values: %{heading: "Naming case"},
        media: %{slot: {:video, c.video.id}}
      }
    ]
  end

  test "creates one draft and inserts a block into two saved entries, leaving their other blocks alone", c do
    before_identity = roots(c.identity, c.user)
    before_naming = roots(c.naming, c.user)
    blocks = block_count()
    revisions = {revisions(c.identity), revisions(c.naming)}

    assert {:ok, proposal} = Proposals.propose(workflow(c), c.user)
    assert proposal.problems == []

    assert %{creates: 1, updates: 2, inserted_blocks: 2, updated_blocks: 0, deletions: 0, live: live} =
             proposal.effects

    assert Enum.sort(live) == Enum.sort([{Page, c.identity.id}, {Page, c.naming.id}])

    # Review and preview materialize in memory only.
    assert {:ok, changesets} = Proposals.materialize(proposal, c.user)
    assert Changeset.get_change(changesets[{Page, c.identity.id}], :rendered_blocks) =~ "Identity case"
    assert block_count() == blocks
    assert roots(c.identity, c.user) == before_identity

    [_, identity_op, naming_op] = proposal.operations
    assert {:ok, %Receipt{} = receipt} = approve_and_apply(proposal, c.user)

    identity = load(c.identity, c.user)
    [first, inserted | rest] = identity.entry_blocks

    assert [{first.id, first.block.id, first.block.uid} | Enum.map(rest, &{&1.id, &1.block.id, &1.block.uid})] ==
             before_identity

    assert Enum.map(identity.entry_blocks, & &1.sequence) == [0, 1, 2, 3]
    assert inserted.block.uid == identity_op.uid
    assert inserted.block.module_id == c.case_module.id
    assert inserted.block.module_version == c.case_module.version
    assert Enum.find(inserted.block.refs, &(&1.name == "cover")).image_id == c.image.id
    assert Enum.find(inserted.block.vars, &(&1.key == "heading")).value == "Identity case"
    assert Enum.find(inserted.block.vars, &(&1.key == "wide")).value_boolean == true
    assert identity.rendered_blocks =~ "Identity case"
    assert identity.status == :published

    naming = load(c.naming, c.user)
    assert Enum.map(Enum.take(naming.entry_blocks, 3), &{&1.id, &1.block.id, &1.block.uid}) == before_naming
    appended = List.last(naming.entry_blocks).block
    assert appended.uid == naming_op.uid
    slot = Enum.find(appended.refs, &(&1.name == "slot"))
    assert slot.data.type == "video"
    assert slot.video_id == c.video.id

    created = Repo.get!(Page, receipt.mappings["created"]["sommerro"])
    assert created.status == :draft
    assert created.title == "Sommerro"

    # The pages had no revision: applying keeps one of how they were, for
    # undo, and the save adds its own.
    assert {revisions(c.identity), revisions(c.naming)} == {elem(revisions, 0) + 2, elem(revisions, 1) + 2}
    assert block_count() == blocks + 2
    assert receipt.mappings["effects"]["inserted_blocks"] == 2

    assert Map.keys(receipt.before) |> Enum.sort() ==
             Enum.sort(["Brando.Pages.Page:#{c.identity.id}", "Brando.Pages.Page:#{c.naming.id}"])

    # A second apply finds the receipt and writes nothing.
    assert {:ok, again} = Proposals.apply(proposal.id, proposal.version, c.user)
    assert again.id == receipt.id
    assert block_count() == blocks + 2
    assert Repo.aggregate(from(p in Page, where: p.uri == "sommerro"), :count) == 1
  end

  test "a media slot takes an image through its picture template", c do
    op = %InsertBlock{target: {Page, c.identity.id}, module: c.case_module.id, media: %{slot: {:image, c.image.id}}}
    assert {:ok, proposal} = Proposals.propose([op], c.user)
    assert {:ok, _} = approve_and_apply(proposal, c.user)

    slot =
      load(c.identity, c.user).entry_blocks |> List.last() |> then(& &1.block.refs) |> Enum.find(&(&1.name == "slot"))

    assert slot.data.type == "picture"
    assert slot.data.data.title == "Slot picture"
    assert slot.image_id == c.image.id
  end

  test "media and values on saved blocks and blocks inserted earlier in the proposal", c do
    [first | _] = uids(c.identity, c.user)
    uid = Brando.Utils.generate_uid()

    ops = [
      %InsertBlock{target: {Page, c.identity.id}, module: c.case_module.id, uid: uid, placement: {:before, first}},
      %SetBlockMedia{target: {Page, c.identity.id}, block_uid: uid, ref: :clip, asset: {:video, c.video.id}},
      %SetBlockValues{target: {Page, c.identity.id}, block_uid: uid, values: %{heading: "Set later"}},
      %SetFields{target: {Page, c.naming.id}, fields: %{title: "Naming, renamed"}}
    ]

    assert {:ok, proposal} = Proposals.propose(ops, c.user)
    assert proposal.problems == []
    assert proposal.effects.updated_blocks == 0
    assert {:ok, _} = approve_and_apply(proposal, c.user)

    [inserted | _] = load(c.identity, c.user).entry_blocks
    assert inserted.block.uid == uid
    assert Enum.find(inserted.block.refs, &(&1.name == "clip")).video_id == c.video.id
    assert Enum.find(inserted.block.vars, &(&1.key == "heading")).value == "Set later"
    assert Repo.get!(Page, c.naming.id).title == "Naming, renamed"

    # A saved block without the ref is reported, not changed.
    [saved | _] = uids(c.naming, c.user)
    op = %SetBlockMedia{target: {Page, c.naming.id}, block_uid: saved, ref: :cover, asset: {:image, c.image.id}}
    assert {:ok, proposal} = Proposals.propose([op], c.user)
    assert [%{code: :unknown_ref}] = proposal.problems
  end

  test "problems block the proposal and nothing is written", c do
    blocks = block_count()

    ops = [
      %InsertBlock{target: {Page, c.identity.id}, module: c.case_module.id, media: %{cover: {:video, c.video.id}}},
      %InsertBlock{target: {Page, c.identity.id}, module: c.case_module.id, media: %{clip: {:video, -1}}},
      %InsertBlock{target: {Page, c.identity.id}, module: c.case_module.id, values: %{missing: "x", wide: "yes"}},
      %InsertBlock{target: {Page, c.identity.id}, module: c.case_module.id, placement: {:after, "nope"}},
      %InsertBlock{target: {:new, "ghost"}, module: c.case_module.id},
      %InsertBlock{target: {Page, c.identity.id}, module: -1},
      %SetFields{target: {Page, c.naming.id}, fields: %{status: "draft", title: "x"}},
      %CreateEntry{
        schema: Page,
        ref: "case",
        fields: %{title: "Case", uri: "case", language: "en", template: "default.html"}
      },
      %InsertBlock{target: {Page, c.naming.id}, module: c.case_module.id, values: %{heading: {:new, "case"}}}
    ]

    assert {:ok, proposal} = Proposals.propose(ops, c.user)

    assert Enum.map(proposal.problems, &{&1.operation, &1.code}) == [
             {0, :wrong_media_type},
             {1, :missing_asset},
             {2, :unknown_var},
             {2, :unsupported_value},
             {3, :unknown_placement},
             {4, :unknown_target},
             {5, :unknown_module},
             {6, :protected_field},
             {8, :unsupported_value},
             {8, :draft_dependency}
           ]

    assert {:error, _} = approve_and_apply(proposal, c.user)
    assert block_count() == blocks
  end

  test "a URI in use is a problem, not silently renamed", c do
    ops = [%SetFields{target: {Page, c.naming.id}, fields: %{uri: "identity"}}]
    assert {:ok, proposal} = Proposals.propose(ops, c.user)
    assert [%{code: :taken, target: {Page, _}}] = proposal.problems
  end

  test "an invalid entry is a problem, found before anything is written", c do
    ops = [%CreateEntry{schema: Page, ref: "untitled", fields: %{uri: "untitled", language: "xx"}}]
    assert {:ok, proposal} = Proposals.propose(ops, c.user)
    assert [%{code: :invalid, target: {:new, "untitled"}}] = proposal.problems
  end

  test "an entry edited after prepare is refused on apply and on preview", c do
    ops = [%InsertBlock{target: {Page, c.identity.id}, module: c.case_module.id}]
    assert {:ok, proposal} = Proposals.propose(ops, c.user)
    blocks = block_count()

    Repo.get!(Page, c.identity.id) |> Changeset.change(title: "Edited meanwhile") |> Repo.update!()

    assert {:error, message} = approve_and_apply(proposal, c.user)
    assert message =~ "changed"
    assert {:error, _} = Preview.render(proposal, {Page, c.identity.id}, c.user)
    assert block_count() == blocks
    assert Repo.all(Receipt) == []
  end

  test "a module changed after prepare is refused", c do
    ops = [%InsertBlock{target: {Page, c.identity.id}, module: c.case_module.id}]
    assert {:ok, proposal} = Proposals.propose(ops, c.user)
    {:ok, _} = Brando.Content.update_module(c.case_module, %{code: "<div>changed</div>"}, c.user)
    assert Brando.Content.fetch_module(c.case_module.id).version == c.case_module.version + 1

    assert {:error, message} = approve_and_apply(proposal, c.user)
    assert message =~ "module"
  end

  test "a failure on a later entry rolls back the earlier ones", c do
    ops = [
      %InsertBlock{target: {Page, c.identity.id}, module: c.case_module.id},
      %SetFields{target: {Page, c.naming.id}, fields: %{uri: "naming-renamed"}}
    ]

    assert {:ok, proposal} = Proposals.propose(ops, c.user)
    assert proposal.problems == []
    blocks = block_count()
    revisions = revisions(c.identity)

    # Another entry takes the URI between review and apply. The naming entry
    # is saved after the identity entry, so the identity insert must roll back
    # rather than the URI being renamed on save.
    Factory.insert(:page, uri: "naming-renamed", language: :en, creator: c.user)

    assert {:error, message} = approve_and_apply(proposal, c.user)
    assert message =~ "already in use"
    assert Repo.get!(Page, c.naming.id).uri == "naming"
    assert block_count() == blocks
    assert revisions(c.identity) == revisions
    assert Repo.all(Receipt) == []
  end

  test "another user or a revoked grant cannot apply the proposal", c do
    ops = [%InsertBlock{target: {Page, c.identity.id}, module: c.case_module.id}]
    assert {:ok, proposal} = Proposals.propose(ops, c.user)
    other = Factory.insert(:random_user)
    assert {:error, message} = approve_and_apply(proposal, other)
    assert message =~ "another user"

    put_test_env(:authorization_mode, :groups)
    {:ok, _} = Brando.Authorization.Migration.run()
    alias Brando.Authorization.{Catalog, Groups, Scope}
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

    # Changing a published page also needs the publish grant.
    assert {:ok, %{problems: [%{code: :forbidden}]}} = Proposals.propose(ops, editor)
    Repo.get!(Page, c.identity.id) |> Changeset.change(status: :draft) |> Repo.update!()
    assert {:ok, proposal} = Proposals.propose(ops, editor)
    assert proposal.problems == []

    # Creating is outside the editor's grants.
    create = %CreateEntry{
      schema: Page,
      ref: "x",
      fields: %{title: "X", uri: "x", language: "en", template: "default.html"}
    }

    assert {:ok, %{problems: [%{code: :forbidden}]}} = Proposals.propose([create], editor)

    blocks = block_count()
    assert {:ok, :ok} = Groups.remove_member(scope, group.id, editor.id)
    assert {:error, _} = approve_and_apply(proposal, editor)
    assert block_count() == blocks
  end

  describe "stored proposals" do
    test "apply needs the actor's approval of that exact version", c do
      ops = [%InsertBlock{target: {Page, c.identity.id}, module: c.case_module.id}]
      assert {:ok, proposal} = Proposals.propose(ops, c.user, summary: "One case")
      assert proposal.status == "pending"
      assert proposal.version == 1
      blocks = block_count()

      assert {:error, message} = Proposals.apply(proposal.id, 1, c.user)
      assert message =~ "Approve"
      assert {:error, _} = Proposals.approve(proposal.id, 2, c.user)
      assert {:error, _} = Proposals.approve(proposal.id, 1, Factory.insert(:random_user))
      assert {:ok, %{status: "approved"}} = Proposals.approve(proposal.id, 1, c.user)
      assert {:error, _} = Proposals.approve(proposal.id, 1, c.user)
      assert block_count() == blocks

      assert {:ok, receipt} = Proposals.apply(proposal.id, 1, c.user)
      assert {:ok, %{status: "applied"}} = Proposals.get(proposal.id, c.user)
      assert {:ok, ^receipt} = Proposals.apply(proposal.id, 1, c.user)
      assert block_count() == blocks + 1
    end

    test "a refinement supersedes the previous version and its approval", c do
      ops = [%InsertBlock{target: {Page, c.identity.id}, module: c.case_module.id}]
      conversation = Ecto.UUID.generate()
      assert {:ok, first} = Proposals.propose(ops, c.user, conversation_id: conversation)
      assert {:ok, _} = Proposals.approve(first.id, 1, c.user)

      refined = [%InsertBlock{target: {Page, c.naming.id}, module: c.case_module.id, values: %{heading: "Refined"}}]
      assert {:ok, second} = Proposals.propose(refined, c.user, supersedes: first.id)
      assert second.version == 2
      assert second.conversation_id == conversation
      assert [%{version: 2}, %{version: 1, status: "superseded"}] = Proposals.list(conversation, c.user)

      assert {:error, message} = Proposals.apply(first.id, 1, c.user)
      assert message =~ "newer version"
      assert {:error, _} = Proposals.propose(refined, c.user, supersedes: first.id)

      assert {:ok, _} = Proposals.approve(second.id, 2, c.user)
      assert {:ok, _} = Proposals.apply(second.id, 2, c.user)

      assert List.last(load(c.naming, c.user).entry_blocks).block.vars
             |> Enum.find(&(&1.key == "heading"))
             |> Map.get(:value) == "Refined"

      assert length(load(c.identity, c.user).entry_blocks) == 3
    end

    test "expired and cancelled proposals cannot be approved", c do
      ops = [%InsertBlock{target: {Page, c.identity.id}, module: c.case_module.id}]
      assert {:ok, expired} = Proposals.propose(ops, c.user)

      Repo.get!(Proposals.Record, expired.id)
      |> Changeset.change(expires_at: DateTime.add(DateTime.utc_now(), -60))
      |> Repo.update!()

      assert {:error, message} = Proposals.approve(expired.id, 1, c.user)
      assert message =~ "expired"

      assert {:ok, cancelled} = Proposals.propose(ops, c.user)
      assert :ok = Proposals.cancel(cancelled.id, c.user)
      assert {:error, _} = Proposals.approve(cancelled.id, 1, c.user)
    end

    test "problems are stored with the proposal and block approval", c do
      ops = [%InsertBlock{target: {Page, c.identity.id}, module: c.case_module.id, media: %{cover: {:video, c.video.id}}}]
      assert {:ok, proposal} = Proposals.propose(ops, c.user)
      assert {:ok, stored} = Proposals.get(proposal.id, c.user)
      assert [%{code: :wrong_media_type, operation: 0}] = stored.problems
      assert {:error, _} = Proposals.approve(proposal.id, 1, c.user)
    end

    test "stored operations decode to the frozen operations", c do
      assert {:ok, proposal} = Proposals.propose(workflow(c), c.user)
      assert {:ok, stored} = Proposals.get(proposal.id, c.user)
      assert stored.operations == proposal.operations
      assert stored.fingerprints == proposal.fingerprints
      assert stored.module_versions == proposal.module_versions
      assert stored.effects == proposal.effects
    end
  end

  describe "text refs and select vars" do
    test "insert a block with text and replace the text of a saved block", c do
      [saved | _] = uids(c.naming, c.user)

      ops = [
        %InsertBlock{
          target: {Page, c.identity.id},
          module: c.text_module.id,
          texts: %{body: "<p>Written by the agent</p>"}
        },
        %SetBlockText{target: {Page, c.naming.id}, block_uid: saved, ref: :body, text: "<p>Rewritten</p>"}
      ]

      assert {:ok, proposal} = Proposals.propose(ops, c.user)
      assert proposal.problems == []
      assert proposal.effects.updated_blocks == 1
      assert {:ok, _} = approve_and_apply(proposal, c.user)

      assert List.last(load(c.identity, c.user).entry_blocks).block.refs |> hd() |> then(& &1.data.data.text) ==
               "<p>Written by the agent</p>"

      [first | _] = load(c.naming, c.user).entry_blocks
      assert first.block.uid == saved
      assert hd(first.block.refs).data.data.text == "<p>Rewritten</p>"
      assert Repo.get!(Page, c.naming.id).rendered_blocks =~ "Rewritten"
    end

    test "unsafe rich text and unknown text slots are problems", c do
      ops = [
        %InsertBlock{
          target: {Page, c.identity.id},
          module: c.text_module.id,
          texts: %{body: ~s{<p onclick="x()">Hi</p>}}
        },
        %InsertBlock{target: {Page, c.identity.id}, module: c.text_module.id, texts: %{missing: "Hi"}}
      ]

      assert {:ok, proposal} = Proposals.propose(ops, c.user)
      assert Enum.map(proposal.problems, &{&1.operation, &1.code}) == [{0, :unsafe_text}, {1, :unknown_ref}]
    end

    test "a select var takes one of its options", c do
      module =
        module!(c.user, "Choice", "<p>{{ tone }}</p>",
          vars: [
            %{
              type: "select",
              key: "tone",
              label: "Tone",
              value: "light",
              options: [%{label: "Light", value: "light"}, %{label: "Dark", value: "dark"}]
            }
          ]
        )

      ok = %InsertBlock{target: {Page, c.identity.id}, module: module.id, values: %{tone: "dark"}}
      bad = %InsertBlock{target: {Page, c.identity.id}, module: module.id, values: %{tone: "neon"}}
      assert {:ok, %{problems: []}} = Proposals.propose([ok], c.user)
      assert {:ok, %{problems: [%{code: :unsupported_value}]}} = Proposals.propose([bad], c.user)
    end
  end

  describe "preview" do
    test "renders the proposed page and its saved baseline without writing", c do
      assert {:ok, proposal} = Proposals.propose(workflow(c), c.user)
      blocks = block_count()
      target = {Page, c.identity.id}

      [_, identity_op, _] = proposal.operations

      assert {:ok, %{key: proposed_key, html: proposed}} =
               Preview.render(proposal, target, c.user, preview_target: :blocks)

      assert {:ok, %{key: before_key, html: before}} =
               Preview.render(proposal, target, c.user, version: :before, preview_target: :blocks)

      assert proposed_key != before_key
      assert proposed =~ "Identity case"
      # The block annotations locate the inserted block for highlighting.
      assert proposed =~ "<!-- [+:B<#{identity_op.uid}>] -->"
      assert proposed =~ c.image.sizes["xlarge"]
      assert before =~ "Identity 0"
      refute before =~ "Identity case"
      assert block_count() == blocks
      assert Repo.all(Receipt) == []

      assert {:error, :not_created} = Preview.render(proposal, {:new, "sommerro"}, c.user, version: :before)
      assert {:ok, %{html: created}} = Preview.render(proposal, {:new, "sommerro"}, c.user, preview_target: :blocks)
      assert created =~ "Sommerro"

      Preview.discard([proposed_key, before_key])
    end

    test "a content type without a preview target says so", c do
      ops = [%CreateEntry{schema: Brando.Pages.Fragment, ref: "f", fields: %{key: "f", parent_key: "p", language: "en"}}]
      assert {:ok, proposal} = Proposals.propose(ops, c.user)
      assert {:error, :no_preview_target} = Preview.render(proposal, {:new, "f"}, c.user)
    end
  end

  describe "child blocks" do
    setup c, do: Brando.ProposalFixtures.multi_context(c)

    defp multi(c), do: load(c.work, c.user).entry_blocks |> Enum.find(&(&1.block.uid == c.multi_uid)) |> Map.get(:block)
    defp child_uids(c), do: Enum.map(multi(c).children, & &1.uid)
    defp sizes(c), do: Enum.map(multi(c).children, &Enum.find_value(&1.vars, fn v -> v.key == "size" && v.value end))

    test "values, text and media of a multi module's entries", c do
      [alpha, beta, gamma] = c.child_uids
      target = {Page, c.work.id}

      ops = [
        %SetBlockValues{target: target, block_uid: beta, values: %{size: "50"}},
        %SetBlockText{target: target, block_uid: gamma, ref: :info, text: "<p>Gamma, rewritten</p>"},
        %SetBlockMedia{target: target, block_uid: gamma, ref: :clip, asset: {:video, c.video.id}}
      ]

      assert {:ok, proposal} = Proposals.propose(ops, c.user)
      assert proposal.problems == []
      assert %{updated_blocks: 2, moved_blocks: 0, deletions: 0} = proposal.effects

      [card] = Review.entries(proposal)

      assert [values, text, media] = card.changes
      assert values.block =~ "“Project” · 2 of 3 in “Projects”"
      assert [%{label: "Size", before: "Full (100)", value: "Half (50)"}] = values.values
      assert text.before == "Gamma"
      assert media.uid == gamma
      assert {:video, c.video.id} in Review.media([card])
      refute alpha in card.highlight

      assert {:ok, _} = approve_and_apply(proposal, c.user)
      assert sizes(c) == ["100", "50", "50"]
      assert child_uids(c) == c.child_uids

      [_, _, g] = multi(c).children
      assert Enum.find(g.refs, &(&1.name == "info")).data.data.text == "<p>Gamma, rewritten</p>"
      assert Enum.find(g.refs, &(&1.name == "clip")).video_id == c.video.id
      assert Repo.get!(Page, c.work.id).rendered_blocks =~ "Gamma, rewritten"
    end

    test "move, delete and insert entries; operations see the ones before them", c do
      [alpha, beta, gamma] = c.child_uids
      target = {Page, c.work.id}
      delta = Brando.Utils.generate_uid()
      blocks = block_count()

      ops = [
        %MoveBlock{target: target, block_uid: gamma, placement: {:before, alpha}},
        %DeleteBlock{target: target, block_uid: beta},
        %InsertBlock{
          target: target,
          module: c.project_module.id,
          parent: c.multi_uid,
          placement: {:after, gamma},
          uid: delta,
          values: %{size: "50"},
          texts: %{info: "<p>Delta</p>"}
        },
        %MoveBlock{target: target, block_uid: c.multi_uid, placement: {:before, c.intro_uid}}
      ]

      assert {:ok, proposal} = Proposals.propose(ops, c.user)
      assert proposal.problems == []
      assert %{inserted_blocks: 1, moved_blocks: 2, deletions: 1} = proposal.effects

      [card] = Review.entries(proposal)

      # Moves are shown as the order they leave each list in, where the first
      # move into that list is: the entries, then the root blocks.
      assert [order, delete, insert, root_order] = card.changes
      assert %{type: :order, parent: parent, items: items} = order
      assert parent =~ "Projects"
      assert Enum.map(items, & &1.uid) == [gamma, delta, alpha]
      assert Enum.map(items, &{&1.moved?, &1.new?}) == [{true, false}, {false, true}, {false, false}]
      assert [%{label: "Size", value: "Half (50)", changed?: true}] = Enum.at(items, 1).values
      assert [%{value: "Half (50)", changed?: false}] = hd(items).values
      assert gamma in card.highlight
      assert delete.type == :delete_block and delete.block =~ "Beta"
      assert insert.type == :insert_block and insert.placement.text =~ "After"
      assert %{type: :order, parent: nil, items: [%{uid: multi}, %{uid: intro}]} = root_order
      assert {multi, intro} == {c.multi_uid, c.intro_uid}

      assert {:ok, _} = approve_and_apply(proposal, c.user)

      assert uids(c.work, c.user) == [c.multi_uid, c.intro_uid]
      assert child_uids(c) == [gamma, delta, alpha]
      assert Enum.map(multi(c).children, & &1.sequence) == [0, 1, 2]
      assert Enum.map(multi(c).children, & &1.type) == [:module_entry, :module_entry, :module_entry]
      assert sizes(c) == ["50", "50", "100"]
      # The deleted entry is gone with its row; the new one is counted once.
      assert block_count() == blocks
      assert Repo.get!(Page, c.work.id).rendered_blocks =~ "Delta"
    end

    test "delete a root block and its children", c do
      target = {Page, c.work.id}
      ops = [%DeleteBlock{target: target, block_uid: c.multi_uid}]

      assert {:ok, proposal} = Proposals.propose(ops, c.user)
      assert proposal.problems == []
      assert %{deletions: 1} = proposal.effects
      assert [%{type: :delete_block, children: 3}] = hd(Review.entries(proposal)).changes

      assert {:ok, _} = approve_and_apply(proposal, c.user)
      assert uids(c.work, c.user) == [c.intro_uid]
      refute Repo.get!(Page, c.work.id).rendered_blocks =~ "Alpha"
    end

    test "structure problems", c do
      [alpha, beta, _gamma] = c.child_uids
      target = {Page, c.work.id}

      ops = [
        # Not an entry module of Projects.
        %InsertBlock{target: target, module: c.text_module.id, parent: c.multi_uid},
        # A Text block holds no children.
        %InsertBlock{target: target, module: c.project_module.id, parent: c.intro_uid},
        # An insert's anchor is a sibling; a move next to a root block goes to
        # the root, which does not take project entries; nothing moves next to
        # itself.
        %InsertBlock{target: target, module: c.project_module.id, parent: c.multi_uid, placement: {:after, c.intro_uid}},
        %MoveBlock{target: target, block_uid: alpha, placement: {:after, c.intro_uid}},
        %MoveBlock{target: target, block_uid: alpha, placement: {:after, alpha}},
        # A deleted block cannot be edited afterwards.
        %DeleteBlock{target: target, block_uid: beta},
        %SetBlockValues{target: target, block_uid: beta, values: %{size: "50"}},
        %DeleteBlock{target: target, block_uid: "nope"},
        # A uid in use cannot be given to a new block.
        %InsertBlock{target: target, module: c.project_module.id, parent: c.multi_uid, uid: alpha},
        %SetBlockValues{target: target, block_uid: alpha, values: %{size: "75"}}
      ]

      assert {:ok, proposal} = Proposals.propose(ops, c.user)

      assert Enum.map(proposal.problems, &{&1.operation, &1.code}) == [
               {0, :module_not_allowed},
               {1, :not_a_parent},
               {2, :unknown_placement},
               {3, :module_not_allowed},
               {4, :unknown_placement},
               {6, :unknown_block},
               {7, :unknown_block},
               {8, :duplicate_uid},
               {9, :unsupported_value}
             ]
    end

    test "new child operations survive storage", c do
      [alpha, beta, _] = c.child_uids
      target = {Page, c.work.id}

      ops = [
        %MoveBlock{target: target, block_uid: alpha, placement: :append},
        %DeleteBlock{target: target, block_uid: beta},
        %InsertBlock{target: target, module: c.project_module.id, parent: c.multi_uid}
      ]

      assert {:ok, proposal} = Proposals.propose(ops, c.user)
      assert {:ok, stored} = Proposals.get(proposal.id, c.user)
      assert stored.operations == proposal.operations
      assert stored.effects == proposal.effects
    end
  end

  describe "arranging across parents" do
    setup c do
      c = Brando.ProposalFixtures.multi_context(c)
      container = Brando.ProposalFixtures.root_block!(c, :container, nil, 2)
      other = Brando.ProposalFixtures.root_block!(c, :module, c.projects_module, 3)
      Map.merge(c, %{container_uid: container.uid, other_uid: other.uid})
    end

    defp block_row(uid), do: Repo.get_by!(Block, uid: uid)

    test "a block moves to another parent and back, keeping its row", c do
      [alpha, beta, gamma] = c.child_uids
      target = {Page, c.work.id}
      ids = Map.new([c.intro_uid, gamma], &{&1, block_row(&1).id})
      blocks = block_count()

      ops = [
        %MoveBlock{target: target, block_uid: c.intro_uid, placement: {:into, c.container_uid}},
        %MoveBlock{target: target, block_uid: gamma, placement: {:into, c.other_uid}}
      ]

      assert {:ok, proposal} = Proposals.propose(ops, c.user)
      assert proposal.problems == []
      assert %{moved_blocks: 2} = proposal.effects

      # Both lists a block leaves and joins are shown.
      [card] = Review.entries(proposal)
      parents = for %{type: :order, parent: parent} <- card.changes, do: parent
      assert length(parents) == 4
      assert nil in parents

      assert {:ok, _} = approve_and_apply(proposal, c.user)
      assert block_count() == blocks
      assert uids(c.work, c.user) == [c.multi_uid, c.container_uid, c.other_uid]
      assert block_row(c.intro_uid).id == ids[c.intro_uid]
      assert block_row(c.intro_uid).parent_id == block_row(c.container_uid).id
      assert block_row(gamma).id == ids[gamma]
      assert block_row(gamma).parent_id == block_row(c.other_uid).id
      assert child_uids(c) == [alpha, beta]

      # Back to the root, next to a root block: the row gets a join again.
      ops = [%MoveBlock{target: target, block_uid: c.intro_uid, placement: {:before, c.multi_uid}}]
      assert {:ok, proposal} = Proposals.propose(ops, c.user)
      assert proposal.problems == []
      assert {:ok, _} = approve_and_apply(proposal, c.user)

      assert uids(c.work, c.user) == [c.intro_uid, c.multi_uid, c.container_uid, c.other_uid]
      assert block_row(c.intro_uid).id == ids[c.intro_uid]
      assert is_nil(block_row(c.intro_uid).parent_id)
      assert block_count() == blocks
    end

    test "the new parent must take the module, and nothing moves into itself", c do
      [alpha | _] = c.child_uids
      target = {Page, c.work.id}

      ops = [
        # A project entry is not a module of the container.
        %MoveBlock{target: target, block_uid: alpha, placement: {:into, c.container_uid}},
        %MoveBlock{target: target, block_uid: c.multi_uid, placement: {:into, alpha}},
        %MoveBlock{target: target, block_uid: c.intro_uid, placement: {:into, c.intro_uid}},
        # Text blocks hold no children.
        %MoveBlock{target: target, block_uid: c.other_uid, placement: {:into, c.intro_uid}}
      ]

      assert {:ok, proposal} = Proposals.propose(ops, c.user)

      assert Enum.map(proposal.problems, &{&1.operation, &1.code}) == [
               {0, :module_not_allowed},
               {1, :unknown_placement},
               {2, :unknown_placement},
               {3, :not_a_parent}
             ]
    end

    test "a multi module is inserted at the root with its entries", c do
      target = {Page, c.work.id}
      uid = Brando.Utils.generate_uid()

      ops = [
        %InsertBlock{target: target, module: c.projects_module.id, uid: uid, placement: {:after, c.intro_uid}},
        %InsertBlock{target: target, module: c.project_module.id, parent: uid, texts: %{info: "<p>One</p>"}},
        %InsertBlock{
          target: target,
          module: c.project_module.id,
          parent: uid,
          values: %{size: "50"},
          texts: %{info: "<p>Two</p>"}
        }
      ]

      assert {:ok, proposal} = Proposals.propose(ops, c.user)
      assert proposal.problems == []
      assert {:ok, _} = approve_and_apply(proposal, c.user)

      [_, inserted | _] = load(c.work, c.user).entry_blocks
      assert inserted.block.uid == uid
      assert inserted.block.multi
      assert Enum.map(inserted.block.children, & &1.type) == [:module_entry, :module_entry]
      assert Repo.get!(Page, c.work.id).rendered_blocks =~ "Two"
    end
  end

  describe "switching blocks and refs, and every kind of variable" do
    setup c, do: Brando.ProposalFixtures.multi_context(c)

    test "a block and a ref are switched off and on", c do
      [alpha, beta, _] = c.child_uids
      target = {Page, c.work.id}

      ops = [
        %SetBlockActive{target: target, block_uid: beta, active: false},
        %SetBlockActive{target: target, block_uid: alpha, ref: "clip", active: false}
      ]

      assert {:ok, proposal} = Proposals.propose(ops, c.user)
      assert proposal.problems == []
      assert %{updated_blocks: 2} = proposal.effects

      [card] = Review.entries(proposal)
      assert [%{type: :block_active, active: false, ref: nil}, %{type: :block_active, ref: "clip"}] = card.changes

      assert {:ok, _} = approve_and_apply(proposal, c.user)
      [a, b, _] = multi(c).children
      refute b.active
      refute Enum.find(a.refs, &(&1.name == "clip")).active
      refute Repo.get!(Page, c.work.id).rendered_blocks =~ "Beta"

      ops = [
        %SetBlockActive{target: target, block_uid: beta, active: true},
        %SetBlockActive{target: target, block_uid: alpha, ref: "nope", active: true},
        %SetBlockActive{target: target, block_uid: "nope", active: true}
      ]

      assert {:ok, proposal} = Proposals.propose(ops, c.user)
      assert Enum.map(proposal.problems, &{&1.operation, &1.code}) == [{1, :unknown_ref}, {2, :unknown_block}]
    end

    test "colour, date, datetime, image and link variables", c do
      Brando.Content.create_identifier(Page, c.identity)

      module =
        module!(c.user, "Styled", "<p>{{ tint }}</p>",
          vars: [
            %{type: "color", key: "tint", label: "Tint"},
            %{type: "date", key: "day", label: "Day"},
            %{type: "datetime", key: "at", label: "At"},
            %{type: "image", key: "picture", label: "Picture"},
            %{type: "link", key: "to", label: "To"},
            %{type: "link", key: "url", label: "Url"}
          ]
        )

      target = {Page, c.work.id}
      uid = Brando.Utils.generate_uid()

      values = %{
        tint: "#1a2b3c",
        day: "2026-09-26",
        at: "2026-09-26T12:00:00Z",
        picture: {:image, c.image.id},
        to: {:entry, Page, c.identity.id},
        url: "https://example.com"
      }

      assert {:ok, proposal} =
               Proposals.propose([%InsertBlock{target: target, module: module.id, uid: uid, values: values}], c.user)

      assert proposal.problems == []

      [%{values: views}] = hd(Review.entries(proposal)).changes
      assert %{value: "Identity"} = Enum.find(views, &(&1.name == "to"))
      assert %{media: %{kind: :image}} = Enum.find(views, &(&1.name == "picture"))

      assert {:ok, _} = approve_and_apply(proposal, c.user)
      block = load(c.work, c.user).entry_blocks |> List.last() |> Map.get(:block)
      var = &Enum.find(block.vars, fn var -> var.key == &1 end)
      assert var.("tint").value == "#1a2b3c"
      assert var.("day").value == "2026-09-26"
      assert var.("picture").image_id == c.image.id
      assert var.("to").identifier.entry_id == c.identity.id
      assert var.("url").value == "https://example.com"

      bad = %{tint: "blue", day: "tomorrow", picture: {:video, c.video.id}, to: {:entry, Page, -1}}
      assert {:ok, proposal} = Proposals.propose([%InsertBlock{target: target, module: module.id, values: bad}], c.user)

      assert proposal.problems |> Enum.map(& &1.code) |> Enum.sort() ==
               Enum.sort([:unsupported_value, :unsupported_value, :wrong_media_type, :unknown_target])
    end
  end

  describe "copies, details, settings and every kind of ref" do
    setup c, do: Brando.ProposalFixtures.multi_context(c)

    test "a block is copied with everything below it", c do
      [alpha, _beta, gamma] = c.child_uids
      target = {Page, c.work.id}
      copy = Brando.Utils.generate_uid()
      blocks = block_count()

      ops = [
        %CopyBlock{target: target, block_uid: alpha, placement: {:after, gamma}, uid: copy},
        %CopyBlock{target: target, block_uid: c.multi_uid}
      ]

      assert {:ok, proposal} = Proposals.propose(ops, c.user)
      assert proposal.problems == []
      assert %{inserted_blocks: 2} = proposal.effects

      [card] = Review.entries(proposal)
      assert [%{type: :order, items: items}, %{type: :order, parent: nil}] = card.changes
      assert %{uid: ^copy, copy?: true, excerpt: "Alpha"} = List.last(items)

      # Review, preview and apply build the same tree.
      [%CopyBlock{uid: root_copy} | _] = Enum.reverse(proposal.operations)
      assert {:ok, _} = approve_and_apply(proposal, c.user)
      assert child_uids(c) == c.child_uids ++ [copy]
      # Alpha's copy, and the copy of Projects with its four entries — the
      # second copy sees the first.
      assert block_count() == blocks + 1 + 5

      [_, _, copied] = load(c.work, c.user).entry_blocks
      assert copied.block.uid == root_copy

      assert Enum.map(copied.block.children, & &1.uid) ==
               Enum.map(c.child_uids ++ [copy], &Proposals.BlockTree.copy_uid(root_copy, &1))

      assert Enum.find(List.last(multi(c).children).refs, &(&1.name == "info")).data.data.text == "<p>Alpha</p>"
    end

    test "a block's anchor and description, and its refs' settings", c do
      [alpha, beta, _] = c.child_uids
      target = {Page, c.work.id}

      ops = [
        %SetBlockDetails{target: target, block_uid: alpha, anchor: "alpha-case", description: "The first case"},
        %SetRefConfig{target: target, block_uid: alpha, ref: "clip", config: %{autoplay: true, loop: true}},
        %SetRefConfig{target: target, block_uid: beta, ref: "info", config: %{type: "lead"}}
      ]

      assert {:ok, proposal} = Proposals.propose(ops, c.user)
      assert proposal.problems == []

      [card] = Review.entries(proposal)
      assert [%{type: :block_details, settings: details}, %{type: :ref_config, settings: clip}, _] = card.changes
      assert Enum.any?(details, &match?(%{name: "anchor", value: "alpha-case"}, &1))
      assert Enum.any?(clip, &match?(%{name: "autoplay", before: nil, value: true}, &1))

      assert {:ok, _} = approve_and_apply(proposal, c.user)
      [a, b, _] = multi(c).children
      assert {a.anchor, a.description} == {"alpha-case", "The first case"}
      assert %{autoplay: true, loop: true} = Enum.find(a.refs, &(&1.name == "clip")).data.data
      assert Enum.find(b.refs, &(&1.name == "info")).data.data.type == :lead

      bad = [
        %SetBlockDetails{target: target, block_uid: alpha, anchor: "1 no"},
        %SetRefConfig{target: target, block_uid: alpha, ref: "clip", config: %{sizes: %{}}},
        %SetRefConfig{target: target, block_uid: beta, ref: "info", config: %{type: "shout"}},
        %SetRefConfig{target: target, block_uid: beta, ref: "nope", config: %{}}
      ]

      assert {:ok, proposal} = Proposals.propose(bad, c.user)

      assert Enum.map(proposal.problems, &{&1.operation, &1.code}) == [
               {0, :unsupported_value},
               {1, :unsupported_value},
               {2, :unsupported_value},
               {3, :unknown_ref}
             ]
    end

    test "galleries, files, svg, markdown and maps", c do
      file =
        Repo.insert!(%Brando.Files.File{
          title: "Brochure",
          filename: "brochure.pdf",
          filesize: 1,
          config_target: "default",
          creator_id: c.user.id
        })

      module =
        module!(c.user, "Everything", "<div>{% ref refs.gallery %}{% ref refs.doc %}{% ref refs.icon %}</div>",
          refs: [
            Brando.ProposalFixtures.ref("gallery", %{type: "gallery", data: %{}}),
            Brando.ProposalFixtures.ref("doc", %{type: "file", data: %{}}),
            Brando.ProposalFixtures.ref("icon", %{type: "svg", data: %{}}),
            Brando.ProposalFixtures.ref("notes", %{type: "markdown", data: %{}}),
            Brando.ProposalFixtures.ref("where", %{type: "map", data: %{}})
          ]
        )

      target = {Page, c.work.id}
      uid = Brando.Utils.generate_uid()
      svg = ~s(<svg viewBox="0 0 10 10"><circle cx="5" cy="5" r="4"/></svg>)

      insert = %InsertBlock{
        target: target,
        module: module.id,
        uid: uid,
        media: %{gallery: {:gallery, [{:image, c.image.id}, {:video, c.video.id}]}, doc: {:file, file.id}},
        texts: %{icon: svg, notes: "Some *notes*", where: "https://www.google.com/maps/embed?pb=1"},
        configs: %{gallery: %{display: "list"}, doc: %{label: "Download"}}
      }

      assert {:ok, proposal} = Proposals.propose([insert], c.user)
      assert proposal.problems == []
      assert {:ok, _} = approve_and_apply(proposal, c.user)

      block = load(c.work, c.user).entry_blocks |> List.last() |> Map.get(:block)
      ref = &Enum.find(block.refs, fn ref -> ref.name == &1 end)
      gallery = ref.("gallery").gallery
      assert Enum.map(gallery.gallery_objects, &{&1.image_id, &1.video_id}) == [{c.image.id, nil}, {nil, c.video.id}]
      assert ref.("gallery").data.data.display == :list
      assert {ref.("doc").file_id, ref.("doc").data.data.label} == {file.id, "Download"}
      assert ref.("icon").data.data.code == svg
      assert ref.("notes").data.data.text == "Some *notes*"
      assert ref.("where").data.data.embed_url =~ "google.com/maps"

      # A new gallery replaces the objects of the saved one.
      op = %SetBlockMedia{target: target, block_uid: uid, ref: :gallery, asset: {:gallery, [{:video, c.video.id}]}}
      assert {:ok, proposal} = Proposals.propose([op], c.user)
      assert {:ok, _} = approve_and_apply(proposal, c.user)
      block = load(c.work, c.user).entry_blocks |> List.last() |> Map.get(:block)
      regallery = Enum.find(block.refs, &(&1.name == "gallery")).gallery
      assert regallery.id == gallery.id
      assert Enum.map(regallery.gallery_objects, & &1.video_id) == [c.video.id]

      bad = %InsertBlock{
        target: target,
        module: module.id,
        media: %{doc: {:image, c.image.id}, gallery: {:gallery, [{:image, -1}]}},
        texts: %{icon: ~s{<svg onload="x()"></svg>}, where: "http://example.com"}
      }

      assert {:ok, proposal} = Proposals.propose([bad], c.user)

      assert proposal.problems |> Enum.map(& &1.code) |> Enum.sort() ==
               Enum.sort([:wrong_media_type, :missing_asset, :unsafe_text, :unsafe_text])
    end

    test "entry fields take media", c do
      ops = [%SetFields{target: {Page, c.work.id}, fields: %{meta_image_id: {:image, c.image.id}, meta_title: "Work"}}]
      assert {:ok, proposal} = Proposals.propose(ops, c.user)
      assert proposal.problems == []
      assert [%{type: :fields, fields: fields}] = hd(Review.entries(proposal)).changes
      assert Enum.any?(fields, &match?(%{media: %{kind: :image}}, &1))
      assert {:ok, _} = approve_and_apply(proposal, c.user)
      assert %{meta_image_id: id, meta_title: "Work"} = Repo.get!(Page, c.work.id)
      assert id == c.image.id

      ops = [%SetFields{target: {Page, c.work.id}, fields: %{meta_image_id: {:video, c.video.id}}}]
      assert {:ok, %{problems: [%{code: :wrong_media_type}]}} = Proposals.propose(ops, c.user)
    end

    test "a media swap shows what it replaces, and the order shows what will be", c do
      [alpha, _, gamma] = c.child_uids
      target = {Page, c.work.id}
      other = Factory.insert(:video)

      ops = [
        %SetBlockMedia{target: target, block_uid: alpha, ref: :clip, asset: {:video, other.id}},
        %MoveBlock{target: target, block_uid: alpha, placement: {:after, gamma}}
      ]

      assert {:ok, proposal} = Proposals.propose(ops, c.user)
      [card] = Review.entries(proposal)
      [swap, order] = card.changes
      assert swap.replaces == [%{ref: "clip", kind: :video, id: c.video.id}]
      assert swap.media == [%{ref: "clip", kind: :video, id: other.id}]
      assert %{uid: ^alpha, media: [%{id: id}]} = List.last(order.items)
      assert id == other.id
      assert {:video, c.video.id} in Review.media([card])
    end

    test "operations that change nothing are noted, not blocked", c do
      [alpha, beta, _] = c.child_uids
      target = {Page, c.work.id}

      ops = [
        %SetBlockActive{target: target, block_uid: alpha, active: true},
        %SetBlockValues{target: target, block_uid: beta, values: %{size: "100"}},
        %SetBlockText{target: target, block_uid: c.intro_uid, ref: :body, text: "<p>Work intro</p>"},
        %SetBlockValues{target: target, block_uid: alpha, values: %{size: "50"}}
      ]

      assert {:ok, proposal} = Proposals.propose(ops, c.user)
      assert proposal.problems == []
      assert [%{operation: 0}, %{operation: 1}, %{operation: 2}] = Proposals.notes(proposal)
    end
  end

  describe "tables, selections, links, copies to other entries and leaving out" do
    setup c, do: Brando.ProposalFixtures.multi_context(c)

    test "a table block's rows are replaced", c do
      template =
        Repo.insert!(%Brando.Content.TableTemplate{
          uid: Brando.Utils.generate_uid(),
          name: "Opening hours",
          vars: [
            %Brando.Content.Var{type: :string, key: "day", label: "Day", sequence: 0},
            %Brando.Content.Var{type: :boolean, key: "open", label: "Open", sequence: 1}
          ]
        })

      module = module!(c.user, "Hours", "<table></table>", table_template_id: template.id)
      target = {Page, c.work.id}
      uid = Brando.Utils.generate_uid()

      ops = [
        %InsertBlock{target: target, module: module.id, uid: uid},
        %SetBlockTable{target: target, block_uid: uid, rows: [%{day: "Monday", open: true}, %{day: "Sunday"}]}
      ]

      assert {:ok, proposal} = Proposals.propose(ops, c.user)
      assert proposal.problems == []
      assert [_, %{type: :block_table, rows: ["Monday · true", "Sunday"]}] = hd(Review.entries(proposal)).changes
      assert {:ok, _} = approve_and_apply(proposal, c.user)

      block = load(c.work, c.user).entry_blocks |> List.last() |> Map.get(:block)
      rows = Enum.map(block.table_rows, fn row -> Map.new(row.vars, &{&1.key, &1.value || &1.value_boolean}) end)
      assert rows == [%{"day" => "Monday", "open" => true}, %{"day" => "Sunday", "open" => false}]

      bad = [%SetBlockTable{target: target, block_uid: c.intro_uid, rows: [%{day: "x"}]}]
      assert {:ok, %{problems: [%{code: :unsupported_value}]}} = Proposals.propose(bad, c.user)

      bad = [%SetBlockTable{target: target, block_uid: uid, rows: [%{nope: 1}]}]
      assert {:ok, %{problems: [%{code: :unknown_var}]}} = Proposals.propose(bad, c.user)
    end

    test "a selection datasource block's entries are chosen from its options", c do
      module =
        module!(c.user, "Featured", "<div></div>",
          datasource: true,
          datasource_type: :selection,
          datasource_module: "Elixir.BrandoIntegration.ModuleWithDatasource",
          datasource_query: "chosen_pages"
        )

      {:ok, identity} = Brando.Content.create_identifier(Page, c.identity)
      {:ok, naming} = Brando.Content.create_identifier(Page, c.naming)

      target = {Page, c.work.id}
      uid = Brando.Utils.generate_uid()

      ok = [
        %InsertBlock{target: target, module: module.id, uid: uid},
        %SetBlockSelection{target: target, block_uid: uid, identifiers: [naming.id, identity.id]}
      ]

      assert {:ok, proposal} = Proposals.propose(ok, c.user)
      assert proposal.problems == []
      assert {:ok, changesets} = Proposals.materialize(proposal, c.user)

      block =
        changesets[target]
        |> Changeset.get_assoc(:entry_blocks)
        |> List.last()
        |> Changeset.get_assoc(:block)

      assert Enum.map(Changeset.get_assoc(block, :block_identifiers, :struct), &{&1.identifier_id, &1.sequence}) ==
               [{naming.id, 0}, {identity.id, 1}]

      bad = [
        %InsertBlock{target: target, module: module.id, uid: uid},
        %SetBlockSelection{target: target, block_uid: uid, identifiers: [-1]},
        %SetBlockSelection{target: target, block_uid: c.intro_uid, identifiers: [identity.id]}
      ]

      assert {:ok, proposal} = Proposals.propose(bad, c.user)
      assert Enum.map(proposal.problems, &{&1.operation, &1.code}) == [{1, :unsupported_value}, {2, :unsupported_value}]
    end

    test "a link to an entry becomes a link that follows it", c do
      Brando.Content.create_identifier(Page, c.identity)
      {:ok, identifier} = Brando.Content.get_identifier(Page, c.identity)
      text = ~s(<p>See <a href="entry:Brando.Pages.Page:#{c.identity.id}">Identity</a></p>)

      ops = [%SetBlockText{target: {Page, c.work.id}, block_uid: c.intro_uid, ref: :body, text: text}]
      assert {:ok, proposal} = Proposals.propose(ops, c.user)
      assert proposal.problems == []
      [%SetBlockText{text: resolved}] = proposal.operations
      assert resolved =~ ~s(data-identifier-id="#{identifier.id}")
      assert resolved =~ ~s(href="#{identifier.url}")

      broken = ~s(<p><a href="entry:Brando.Pages.Page:-1">Gone</a></p>)
      ops = [%SetBlockText{target: {Page, c.work.id}, block_uid: c.intro_uid, ref: :body, text: broken}]
      assert {:ok, proposal} = Proposals.propose(ops, c.user)
      assert :unknown_target in Enum.map(proposal.problems, & &1.code)
    end

    test "a saved block is copied to another entry", c do
      [alpha | _] = c.child_uids
      copy = Brando.Utils.generate_uid()
      [first | _] = uids(c.identity, c.user)

      ops = [
        %CopyBlock{target: {Page, c.work.id}, block_uid: c.multi_uid, to_target: {Page, c.identity.id}, uid: copy},
        %CopyBlock{
          target: {Page, c.work.id},
          block_uid: c.intro_uid,
          to_target: {Page, c.identity.id},
          placement: {:before, first}
        }
      ]

      assert {:ok, proposal} = Proposals.propose(ops, c.user)
      assert proposal.problems == []
      assert %{updates: 2, inserted_blocks: 2} = proposal.effects

      cards = Review.entries(proposal)
      work = Enum.find(cards, &(&1.target == {Page, c.work.id}))
      identity = Enum.find(cards, &(&1.target == {Page, c.identity.id}))
      assert [%{type: :copy_out}, %{type: :copy_out}] = work.changes
      assert [%{type: :order, items: items}] = identity.changes
      assert Enum.count(items, & &1.copy?) == 2

      assert {:ok, _} = approve_and_apply(proposal, c.user)
      [_intro_copy | rest] = load(c.identity, c.user).entry_blocks
      copied = List.last(rest).block
      assert copied.uid == copy
      assert copied.source == Page.Blocks
      assert Enum.map(copied.children, & &1.uid) == Enum.map(c.child_uids, &Proposals.BlockTree.copy_uid(copy, &1))
      assert uids(c.work, c.user) == [c.intro_uid, c.multi_uid]

      # Only saved blocks go to another entry.
      new_uid = Brando.Utils.generate_uid()

      ops = [
        %InsertBlock{target: {Page, c.work.id}, module: c.text_module.id, uid: new_uid},
        %CopyBlock{target: {Page, c.work.id}, block_uid: new_uid, to_target: {Page, c.identity.id}},
        %CopyBlock{target: {Page, c.work.id}, block_uid: alpha, to_target: {Page, c.identity.id}}
      ]

      assert {:ok, proposal} = Proposals.propose(ops, c.user)
      assert Enum.map(proposal.problems, &{&1.operation, &1.code}) == [{1, :unknown_block}, {2, :module_not_allowed}]
    end

    test "the reviewer leaves a change out, and a new version holds the rest", c do
      [alpha, beta, _] = c.child_uids
      target = {Page, c.work.id}

      ops = [
        %SetBlockValues{target: target, block_uid: alpha, values: %{size: "50"}},
        %SetBlockValues{target: target, block_uid: beta, values: %{size: "50"}}
      ]

      assert {:ok, proposal} = Proposals.propose(ops, c.user)
      assert [%{operations: [0]}, %{operations: [1]}] = hd(Review.entries(proposal)).changes

      assert {:ok, refined} = Proposals.leave_out(proposal.id, proposal.version, [0], c.user)
      assert refined.version == 2
      assert [%SetBlockValues{block_uid: ^beta}] = refined.operations
      assert {:ok, %{status: "superseded"}} = Proposals.get(proposal.id, c.user)

      assert {:error, _} = Proposals.leave_out(proposal.id, proposal.version, [1], c.user)
      assert {:error, message} = Proposals.leave_out(refined.id, refined.version, [0], c.user)
      assert message =~ "Discard"
    end
  end

  describe "publishing, undo, sharing and language versions" do
    setup c, do: Brando.ProposalFixtures.multi_context(c)

    test "the reviewer publishes a new entry as the proposal is applied", c do
      ops = [
        %CreateEntry{
          schema: Page,
          ref: "news",
          fields: %{title: "News", uri: "news", language: "en", template: "default.html"}
        }
      ]

      assert {:ok, proposal} = Proposals.propose(ops, c.user)
      assert {:ok, _} = Proposals.approve(proposal.id, proposal.version, c.user)
      assert {:ok, receipt} = Proposals.apply(proposal.id, proposal.version, c.user, publish: ["new:news"])
      assert receipt.mappings["published"] == ["new:news"]
      assert Repo.get!(Page, receipt.mappings["created"]["news"]).status == :published

      # A key the proposal does not name is refused, and nothing is saved.
      assert {:ok, proposal} =
               Proposals.propose([%{hd(ops) | ref: "other", fields: %{hd(ops).fields | uri: "other"}}], c.user)

      assert {:ok, _} = Proposals.approve(proposal.id, proposal.version, c.user)
      assert {:error, _} = Proposals.apply(proposal.id, proposal.version, c.user, publish: ["Brando.Pages.Page:-1"])
      refute Repo.get_by(Page, uri: "other")
    end

    test "undo puts every entry back and deletes new ones", c do
      [alpha, beta, gamma] = c.child_uids
      target = {Page, c.work.id}
      before = {uids(c.work, c.user), child_uids(c), sizes(c)}

      # The fixture page was never saved with a revision; applying makes one
      # of its state first.
      assert Brando.Revisions.get_active_revision(Page, c.work.id) == :error

      ops = [
        %SetBlockValues{target: target, block_uid: beta, values: %{size: "50"}},
        %MoveBlock{target: target, block_uid: gamma, placement: {:before, alpha}},
        %DeleteBlock{target: target, block_uid: alpha},
        %InsertBlock{target: target, module: c.text_module.id, texts: %{body: "<p>New</p>"}},
        %CreateEntry{
          schema: Page,
          ref: "news",
          fields: %{title: "News", uri: "news", language: "en", template: "default.html"}
        }
      ]

      assert {:ok, proposal} = Proposals.propose(ops, c.user)
      assert {:ok, receipt} = approve_and_apply(proposal, c.user)
      created = receipt.mappings["created"]["news"]
      refute {uids(c.work, c.user), child_uids(c), sizes(c)} == before

      assert {:ok, _} = Proposals.undo(proposal.id, c.user)
      assert {uids(c.work, c.user), child_uids(c), sizes(c)} == before
      assert Repo.get(Page, created) == nil or Repo.get(Page, created).deleted_at
      assert {:ok, %{status: "undone"}} = Proposals.get(proposal.id, c.user)
      assert {:error, message} = Proposals.undo(proposal.id, c.user)
      assert message =~ "already"
    end

    test "undo is refused when an entry changed after the proposal was applied", c do
      {:ok, _} = Brando.Revisions.create_revision(load(c.work, c.user), c.user)
      ops = [%SetFields{target: {Page, c.work.id}, fields: %{title: "Work, renamed"}}]
      assert {:ok, proposal} = Proposals.propose(ops, c.user)
      assert {:ok, _} = approve_and_apply(proposal, c.user)

      {:ok, _} = Brando.Pages.update_page(c.work.id, %{title: "Edited by hand"}, c.user)
      assert {:error, message} = Proposals.undo(proposal.id, c.user)
      assert message =~ "Edited by hand"
      assert Repo.get!(Page, c.work.id).title == "Edited by hand"
    end

    test "a colleague reviews a shared proposal and previews its pages", c do
      ops = [%SetBlockValues{target: {Page, c.work.id}, block_uid: hd(c.child_uids), values: %{size: "50"}}]
      assert {:ok, proposal} = Proposals.propose(ops, c.user)

      token = Proposals.share_token(proposal)
      assert {:ok, {id, version}} = Proposals.verify_share_token(token)
      assert {id, version} == {proposal.id, proposal.version}
      assert {:error, _} = Proposals.verify_share_token(token <> "x")

      colleague = Factory.insert(:random_user)
      assert {:ok, shared} = Proposals.get_shared(id, version, colleague)
      assert shared.operations == proposal.operations
      # Only the proposing user applies it.
      assert {:error, _} = Proposals.approve(id, version, colleague)

      assert {:ok, %{key: key, html: html}} =
               Preview.render(shared, {Page, c.work.id}, colleague, shared: true, preview_target: :blocks)

      assert html =~ "size-50"
      Preview.discard([key])

      assert {:ok, url, days} = Preview.share(proposal, {Page, c.work.id}, c.user, preview_target: :blocks)
      assert url =~ "/__p__/"
      assert days > 0
    end

    test "language versions are listed, and a synchronized source's translations follow on apply", c do
      alias Brando.SyncTest.Article

      {:ok, source} =
        Brando.SyncTest.create_article(%{title: "Tittel", slug: "tittel", language: "no", status: "published"}, c.user)

      {:ok, english} = Brando.Translations.create_target(Article, source.id, :en, c.user)

      assert {:source, [%{language: "en", id: id, synchronized: true}]} =
               Brando.Content.Proposals.Languages.versions(Repo.get!(Article, source.id))

      assert id == english.id

      ops = [%InsertBlock{target: {Article, source.id}, module: c.text_module.id, texts: %{body: "<p>Nytt avsnitt</p>"}}]
      assert {:ok, proposal} = Proposals.propose(ops, c.user)
      assert [%{languages: [%{language: "en", state: :follows}]}] = Review.entries(proposal)
      assert {:ok, _} = approve_and_apply(proposal, c.user)

      pending = Brando.Translations.get_pending_version(Article, english.id)
      assert pending
      assert Enum.any?(pending.work_items, &(&1.kind == :translate))
    end
  end

  describe "codec" do
    test "decodes move, delete and a child insert, and encodes them back" do
      target = %{"content_type" => "Brando.Pages.Page", "id" => 1}

      maps = [
        %{"op" => "move_block", "target" => target, "block_uid" => "a", "placement" => %{"after" => "b"}},
        %{"op" => "move_block", "target" => target, "block_uid" => "a", "placement" => "append"},
        %{"op" => "delete_block", "target" => target, "block_uid" => "a"},
        %{"op" => "insert_block", "target" => target, "module" => "local:3", "parent" => "p", "uid" => "n"},
        %{"op" => "move_block", "target" => target, "block_uid" => "a", "placement" => %{"into" => "p"}},
        %{"op" => "set_block_active", "target" => target, "block_uid" => "a", "ref" => "cover", "active" => false},
        %{
          "op" => "set_block_values",
          "target" => target,
          "block_uid" => "a",
          "values" => %{
            "to" => %{"content_type" => "Brando.Pages.Page", "id" => 2},
            "picture" => %{"asset" => "image1"},
            "clip" => %{"kind" => "video", "id" => 4}
          }
        }
      ]

      assert {:ok, [move, append, delete, insert, into, active, values]} =
               Codec.decode_all(maps, %{"image1" => {:image, 9}})

      assert %MoveBlock{target: {Page, 1}, block_uid: "a", placement: {:after, "b"}, field: "blocks"} = move
      assert append.placement == :append
      assert %DeleteBlock{block_uid: "a"} = delete
      assert %InsertBlock{parent: "p", uid: "n", placement: :append} = insert

      assert into.placement == {:into, "p"}
      assert %SetBlockActive{ref: "cover", active: false} = active
      assert values.values == %{"to" => {:entry, Page, 2}, "picture" => {:image, 9}, "clip" => {:video, 4}}

      for op <- [move, append, delete, insert, into, active, values],
          do: assert({:ok, ^op} = Codec.decode(Codec.encode(op)))

      # Only a move goes into a block; an insert names its parent.
      assert {:error, _} =
               Codec.decode(%{"op" => "insert_block", "target" => target, "module" => 3, "placement" => %{"into" => "p"}})

      assert {:error, _} = Codec.decode(%{"op" => "set_block_active", "target" => target, "block_uid" => "a"})

      more = [
        %{"op" => "copy_block", "target" => target, "block_uid" => "a", "placement" => %{"into" => "p"}, "uid" => "c"},
        %{"op" => "set_block_details", "target" => target, "block_uid" => "a", "anchor" => "x", "description" => ""},
        %{"op" => "set_ref_config", "target" => target, "block_uid" => "a", "ref" => "h", "config" => %{"level" => 2}},
        %{
          "op" => "set_block_media",
          "target" => target,
          "block_uid" => "a",
          "ref" => "g",
          "asset" => %{"gallery" => ["image1", %{"kind" => "video", "id" => 2}]}
        },
        %{
          "op" => "set_fields",
          "target" => target,
          "fields" => %{"meta_image_id" => "x", "cover_id" => %{"asset" => "image1"}}
        }
      ]

      assert {:ok, [copy, details, config, gallery, fields] = decoded} =
               Codec.decode_all(more, %{"image1" => {:image, 9}})

      assert %CopyBlock{uid: "c", placement: {:into, "p"}} = copy
      assert %SetBlockDetails{anchor: "x", description: ""} = details
      assert %SetRefConfig{ref: "h", config: %{"level" => 2}} = config
      assert gallery.asset == {:gallery, [{:image, 9}, {:video, 2}]}
      assert fields.fields == %{"meta_image_id" => "x", "cover_id" => {:image, 9}}
      for op <- decoded, do: assert({:ok, ^op} = Codec.decode(Codec.encode(op)))

      assert {:error, _} =
               Codec.decode(%{
                 "op" => "set_block_media",
                 "target" => target,
                 "block_uid" => "a",
                 "ref" => "g",
                 "asset" => %{"gallery" => [%{"kind" => "file", "id" => 1}]}
               })

      assert {:error, "Operation 0: " <> _} =
               Codec.decode_all([%{"op" => "move_block", "target" => target, "block_uid" => "a"}])

      assert {:error, _} = Codec.decode(%{"op" => "delete_block", "target" => target})
      assert {:error, _} = Codec.decode(%{"op" => "insert_block", "target" => target, "module" => 3, "parent" => 5})
    end
  end
end
