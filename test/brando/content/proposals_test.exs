defmodule Brando.Content.ProposalsTest do
  use Brando.ConnCase, async: false
  alias Brando.Content.Block
  alias Brando.Content.Proposals

  alias Brando.Content.Proposals.{
    CreateEntry,
    InsertBlock,
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

    assert {revisions(c.identity), revisions(c.naming)} == {elem(revisions, 0) + 1, elem(revisions, 1) + 1}
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
end
