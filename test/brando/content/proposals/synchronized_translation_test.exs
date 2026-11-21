defmodule Brando.Content.Proposals.SynchronizedTranslationTest do
  # A synchronized translation follows its source: a proposal may fill in
  # its text with translate, and set the fields that are its language's own
  # (not text, not source-controlled). Every other operation on it is
  # refused, at prepare and again at approve and apply. Grouped: the
  # proposal tests take the proposal advisory locks.
  use Brando.ConnCase, async: true, group: :shared_locks

  import Ecto.Query, only: [from: 2]

  alias Brando.Content.Block
  alias Brando.Content.Proposals
  alias Brando.Content.Proposals.CopyBlock
  alias Brando.Content.Proposals.DeleteBlock
  alias Brando.Content.Proposals.InsertBlock
  alias Brando.Content.Proposals.MoveBlock
  alias Brando.Content.Proposals.SetBlockActive
  alias Brando.Content.Proposals.SetBlockDetails
  alias Brando.Content.Proposals.SetBlockMedia
  alias Brando.Content.Proposals.SetBlockSelection
  alias Brando.Content.Proposals.SetBlockTable
  alias Brando.Content.Proposals.SetBlockText
  alias Brando.Content.Proposals.SetBlockValues
  alias Brando.Content.Proposals.SetFields
  alias Brando.Content.Proposals.SetRefConfig
  alias Brando.Content.Var
  alias Brando.Factory
  alias Brando.Repo
  alias Brando.SyncTest
  alias Brando.SyncTest.Article
  alias Brando.Translations
  alias Brando.Translations.Member
  alias Brando.Utils

  setup do
    user = Factory.insert(:random_user)

    {:ok, module} =
      Brando.Content.create_module(
        Factory.params_for(:module,
          name: %{"en" => "Text"},
          namespace: %{"en" => "Content"},
          help_text: %{},
          code: "{% ref refs.body %}",
          refs: [
            %{name: "body", uid: Utils.generate_uid(), data: %{type: "text", data: %{text: "Default"}}},
            %{name: "photo", uid: Utils.generate_uid(), data: %{type: "picture", data: %{}}}
          ],
          vars: [%{key: "kicker", type: "string", label: "Kicker"}]
        ),
        user
      )

    {:ok, source} =
      SyncTest.create_article(
        %{title: "Tittel", slug: "tittel-#{System.unique_integer([:positive])}", language: "no", status: "published"},
        user
      )

    add_block(source, module, user, 0)
    add_block(source, module, user, 1)
    {:ok, target} = Translations.create_target(Article, source.id, :en, user)
    [first, second] = blocks(target)

    %{user: user, module: module, source: source, target: target, first: first, second: second}
  end

  defp add_block(article, module, user, sequence) do
    params = %{
      "uid" => Utils.generate_uid(),
      "type" => "module",
      "module_id" => module.id,
      "creator_id" => user.id,
      "source" => to_string(Article.Blocks),
      "refs" => [
        %{
          "uid" => Utils.generate_uid(),
          "name" => "body",
          "data" => %{"type" => "text", "data" => %{"text" => "<p>Tekst</p>"}}
        },
        %{"uid" => Utils.generate_uid(), "name" => "photo", "data" => %{"type" => "picture", "data" => %{}}}
      ]
    }

    block = %Block{} |> Block.recursive_block_changeset(params, user) |> Repo.insert!()
    Repo.insert!(%Var{key: "kicker", type: :string, value: "Stikk", label: %{"en" => "Kicker"}, block_id: block.id})
    struct(Article.Blocks, %{entry_id: article.id, block_id: block.id, sequence: sequence}) |> Repo.insert!()
    block
  end

  # The uids of an entry's top-level blocks, in order
  defp blocks(article) do
    Repo.all(
      from j in Article.Blocks,
        join: b in assoc(j, :block),
        where: j.entry_id == ^article.id,
        order_by: [asc: j.sequence, asc: j.id],
        select: b.uid
    )
  end

  defp problems(ops, user) do
    {:ok, proposal} = Proposals.prepare(ops, user)
    Enum.map(proposal.problems, &{Map.get(&1, :operation), &1.code, Map.get(&1, :key)})
  end

  defp refused(op, user), do: problems([op], user) == [{0, :follows_source, nil}]

  describe "fields" do
    test "text fields are refused, naming the field", c do
      op = %SetFields{target: {Article, c.target.id}, fields: %{"title" => "Title", "subtitle" => "Sub"}}

      assert problems([op], c.user) == [{0, :follows_source, "subtitle"}, {0, :follows_source, "title"}]
    end

    test "source-controlled fields, media, the parent and subforms are refused, naming the field", c do
      for field <- ["year", "cover_id", "parent_id", "items", "quotes"] do
        value = if field in ["items", "quotes"], do: [], else: nil
        op = %SetFields{target: {Article, c.target.id}, fields: %{field => value}}
        assert problems([op], c.user) == [{0, :follows_source, field}], field
      end
    end

    test "the language's own fields stay writable", c do
      op = %SetFields{
        target: {Article, c.target.id},
        fields: %{"slug" => "english-#{c.target.id}", "featured" => true, "status" => "draft"}
      }

      assert problems([op], c.user) == []
    end

    test "the language, its place in the group, is refused", c do
      op = %SetFields{target: {Article, c.target.id}, fields: %{"language" => "no"}}

      assert problems([op], c.user) == [{0, :follows_source, "language"}]
    end
  end

  describe "block operations" do
    test "insert_block", c do
      assert refused(%InsertBlock{target: {Article, c.target.id}, module: c.module.id}, c.user)
    end

    test "set_block_text", c do
      op = %SetBlockText{target: {Article, c.target.id}, block_uid: c.first, ref: "body", text: "<p>Text</p>"}
      assert refused(op, c.user)
    end

    test "set_block_values", c do
      op = %SetBlockValues{target: {Article, c.target.id}, block_uid: c.first, values: %{"kicker" => "Kicker"}}
      assert refused(op, c.user)
    end

    test "set_block_media", c do
      image = Factory.insert(:image)
      op = %SetBlockMedia{target: {Article, c.target.id}, block_uid: c.first, ref: "photo", asset: {:image, image.id}}
      assert refused(op, c.user)
    end

    test "set_ref_config", c do
      op = %SetRefConfig{target: {Article, c.target.id}, block_uid: c.first, ref: "photo", config: %{"lazyload" => true}}
      assert refused(op, c.user)
    end

    test "move_block", c do
      op = %MoveBlock{target: {Article, c.target.id}, block_uid: c.second, placement: {:before, c.first}}
      assert refused(op, c.user)
    end

    test "delete_block", c do
      assert refused(%DeleteBlock{target: {Article, c.target.id}, block_uid: c.first}, c.user)
    end

    test "set_block_active", c do
      assert refused(%SetBlockActive{target: {Article, c.target.id}, block_uid: c.first, active: false}, c.user)
    end

    test "set_block_details", c do
      op = %SetBlockDetails{target: {Article, c.target.id}, block_uid: c.first, anchor: "intro"}
      assert refused(op, c.user)
    end

    test "set_block_table", c do
      op = %SetBlockTable{target: {Article, c.target.id}, block_uid: c.first, rows: []}
      assert refused(op, c.user)
    end

    test "set_block_selection", c do
      op = %SetBlockSelection{target: {Article, c.target.id}, block_uid: c.first, identifiers: []}
      assert refused(op, c.user)
    end

    test "copy_block within the translation", c do
      assert refused(%CopyBlock{target: {Article, c.target.id}, block_uid: c.first}, c.user)
    end

    test "copy_block to the translation from another entry", c do
      [source_block | _] = blocks(c.source)

      op = %CopyBlock{
        target: {Article, c.source.id},
        block_uid: source_block,
        to_target: {Article, c.target.id}
      }

      assert refused(op, c.user)

      # The problem is the translation's, not the entry the block comes from
      {:ok, proposal} = Proposals.prepare([op], c.user)
      assert [%{target: target}] = proposal.problems
      assert target == {Article, c.target.id}
    end

    test "copy_block from the translation to another entry is not refused", c do
      op = %CopyBlock{target: {Article, c.target.id}, block_uid: c.first, to_target: {Article, c.source.id}}
      assert problems([op], c.user) == []
    end
  end

  describe "other entries" do
    test "the source and an independent translation are unaffected", c do
      {:ok, _} = Translations.make_independent(Article, c.target.id, c.user)

      ops = [
        %SetFields{target: {Article, c.source.id}, fields: %{"title" => "Ny tittel", "year" => 2020}},
        %SetFields{target: {Article, c.target.id}, fields: %{"title" => "New title", "year" => 2021}},
        %DeleteBlock{target: {Article, c.target.id}, block_uid: c.first}
      ]

      assert problems(ops, c.user) == []
    end
  end

  describe "a translation that became synchronized after the proposal was prepared" do
    setup c do
      {:ok, _} = Translations.make_independent(Article, c.target.id, c.user)
      {:ok, proposal} = Proposals.propose([%DeleteBlock{target: {Article, c.target.id}, block_uid: c.first}], c.user)
      assert proposal.problems == []
      %{proposal: proposal}
    end

    defp resynchronize(c) do
      {1, _} =
        Repo.update_all(
          from(m in Member, where: m.entry_type == ^to_string(Article) and m.entry_id == ^c.target.id),
          set: [synchronized: true]
        )
    end

    test "is refused at approve", c do
      resynchronize(c)

      assert {:error, _message} = Proposals.approve(c.proposal.id, c.proposal.version, c.user)
      assert {:ok, %{status: "pending", problems: [%{code: :follows_source}]}} = Proposals.get(c.proposal.id, c.user)
    end

    test "is refused at apply, and changes nothing", c do
      {:ok, _} = Proposals.approve(c.proposal.id, c.proposal.version, c.user)
      resynchronize(c)

      assert {:error, _message} = Proposals.apply(c.proposal.id, c.proposal.version, c.user)
      assert {:ok, %{status: "pending", problems: [%{code: :follows_source}]}} = Proposals.get(c.proposal.id, c.user)
      assert blocks(c.target) == [c.first, c.second]
    end
  end
end
