defmodule Brando.Content.StaleBlocksTest do
  use ExUnit.Case, async: false
  use Brando.ConnCase

  import Brando.Test.Support, only: [put_test_env: 2]
  import Ecto.Query

  alias Brando.Content.Block
  alias Brando.Content.Blocks
  alias Brando.Content.Module
  alias Brando.Content.StaleBlocks
  alias Brando.Content.Var
  alias Brando.Factory
  alias Brando.Pages.Page
  alias Brando.ProposalFixtures
  alias Brando.Repo

  # A slider module on version 3. Version 1 had a `link` variable and a
  # `title` text reference; version 3 has `cta` (link), `caption` (text),
  # `label` (string), `size` (select) and a `body` picture reference.
  setup do
    user = Factory.insert(:random_user)

    module =
      ProposalFixtures.module!(user, "Kulturslider", "<div>{{ caption }}{% ref refs.body %}</div>",
        refs: [ProposalFixtures.ref("body", %{type: "picture", data: %{}})],
        vars: [
          %{type: "link", key: "cta", label: "Call to action"},
          %{type: "text", key: "caption", label: "Caption"},
          %{type: "string", key: "label", label: "Label", value: "Default label"},
          %{
            type: "select",
            key: "size",
            label: "Size",
            value: "small",
            options: [%{label: "Small", value: "small"}, %{label: "Large", value: "large"}]
          }
        ]
      )

    module = module |> Ecto.Changeset.change(version: 3) |> Repo.update!()
    %{user: user, module: module}
  end

  # A page with one block on version 1 of the module, holding `vars` and
  # `refs` as given plus everything version 3 defines.
  defp page_with_block(c, vars, refs, title \\ "Sommerro") do
    page = Factory.insert(:page, creator: c.user, title: title, uri: "p#{System.unique_integer([:positive])}")
    block = insert_block!(c, page, vars, refs)
    {page, block}
  end

  defp insert_block!(c, page, vars, refs, sequence \\ 0) do
    defined_vars = [
      %{"type" => "link", "key" => "cta", "label" => "Call to action"},
      %{"type" => "text", "key" => "caption", "label" => "Caption"},
      %{"type" => "string", "key" => "label", "label" => "Label", "value" => "Default label"},
      %{"type" => "select", "key" => "size", "label" => "Size", "value" => "small"}
    ]

    defined_vars = Enum.reject(defined_vars, fn var -> Enum.any?(vars, &(&1["key"] == var["key"])) end)

    defined_refs =
      if Enum.any?(refs, &(&1["name"] == "body")),
        do: [],
        else: [%{"uid" => Brando.Utils.generate_uid(), "name" => "body", "data" => %{"type" => "picture", "data" => %{}}}]

    block =
      %Block{}
      |> Block.recursive_block_changeset(
        %{
          "uid" => Brando.Utils.generate_uid(),
          "type" => "module",
          "module_id" => c.module.id,
          "creator_id" => c.user.id,
          "source" => to_string(Page.Blocks),
          "vars" => Enum.with_index(vars ++ defined_vars, &Map.put(&1, "sequence", &2)),
          "refs" => Enum.with_index(refs ++ defined_refs, &Map.put(&1, "sequence", &2))
        },
        c.user
      )
      |> Repo.insert!()
      |> Ecto.Changeset.change(module_version: 1)
      |> Repo.update!()

    struct(Page.Blocks, %{entry_id: page.id, block_id: block.id, sequence: sequence}) |> Repo.insert!()
    block
  end

  defp link_var(text \\ "Les mer", url \\ "https://by.no/kultur"),
    do: %{"type" => "link", "key" => "link", "label" => "Link", "value" => url, "link_text" => text}

  defp text_ref(name, text),
    do: %{
      "uid" => Brando.Utils.generate_uid(),
      "name" => name,
      "data" => %{"type" => "text", "data" => %{"text" => text}}
    }

  defp vars(block), do: Repo.all(from(v in Var, where: v.block_id == ^block.id, order_by: v.key))
  defp var(block, key), do: Enum.find(vars(block), &(&1.key == key))
  defp refs(block), do: Repo.all(from(r in Brando.Content.Ref, where: r.block_id == ^block.id))
  defp version(block), do: Repo.get!(Block, block.id).module_version

  defp report!(c) do
    {:ok, report} = StaleBlocks.report(c.module, c.user)
    report
  end

  defp revisions(page),
    do: Repo.all(from(r in Brando.Revisions.Revision, where: r.entry_id == ^page.id, order_by: r.revision))

  describe "the case from `by`" do
    test "a block on version 1 with a `link` var the module dropped: refresh leaves it, resolve drops it", c do
      {_page, block} = page_with_block(c, [link_var()], [])

      Blocks.refresh_module_in_blocks(c.module.id)
      assert version(block) == 1
      assert block.id in Blocks.list_stale_block_ids(c.module)
      assert %{status: :warning, fix: fix} = Brando.Doctor.Checks.Modules.run(Brando.Doctor.Context.new())
      assert fix =~ "mix brando.modules resolve"

      assert {:ok, %{stamped: [id]}} = StaleBlocks.apply(c.module, %{{:var, "link"} => :drop}, c.user)
      assert id == block.id
      assert version(block) == 3
      assert var(block, "link") == nil
      assert Blocks.list_stale_block_ids(c.module) == []
      assert %{status: :ok} = Brando.Doctor.Checks.Modules.run(Brando.Doctor.Context.new())
    end
  end

  describe "report/2" do
    test "lists each block's entry, versions and leftovers with their values", c do
      {page, block} = page_with_block(c, [link_var()], [text_ref("title", "<p>Kultur i <b>by</b></p>")])

      report = report!(c)
      assert report.version == 3
      assert [stale] = report.blocks
      assert stale.id == block.id
      assert stale.module_version == 1
      assert [%{label: "Sommerro", schema: Page, id: page_id, url: url}] = stale.entries
      assert page_id == page.id
      assert url =~ "/admin"

      assert [ref, link] = stale.leftovers
      assert %{kind: :ref, key: "title", type: "text", reason: :undefined, preview: "Kultur i by"} = ref
      assert %{kind: :var, key: "link", type: :link, reason: :undefined, preview: "Les mer → https://by.no/kultur"} = link
    end

    test "a ref whose type the module changed is a leftover, and so is a block that only needs a re-sync", c do
      {_page, retyped} = page_with_block(c, [], [text_ref("body", "Was text")])
      {_page, current} = page_with_block(c, [], [], "Clean")

      report = report!(c)
      by_id = Map.new(report.blocks, &{&1.id, &1})

      assert [%{key: "body", reason: :retyped, type: "text", defined_type: "picture"}] = by_id[retyped.id].leftovers
      assert by_id[current.id].leftovers == []
      assert by_id[current.id].problems == []
    end

    test "groups leftovers by key, with the targets they could move to", c do
      page_with_block(c, [link_var()], [])
      page_with_block(c, [link_var("Billetter", "https://by.no/billetter")], [], "Other")

      assert [group] = report!(c).groups
      assert %{kind: :var, key: "link", types: [:link], blocks: [_, _]} = group
      targets = Map.new(group.targets, &{&1.key, &1})
      assert %{ok?: true, reason: nil} = targets["cta"]
      assert %{ok?: false, reason: reason} = targets["label"]
      assert reason =~ "cannot become"
    end
  end

  describe "apply/4" do
    test "maps a var onto a renamed one of the same type, moving its value", c do
      {_page, block} = page_with_block(c, [link_var()], [])

      plan = StaleBlocks.plan(report!(c), %{{:var, "link"} => {:map, "cta"}})
      assert plan.refused == []
      assert plan.stamped == [block.id]

      assert {:ok, _} = StaleBlocks.apply(c.module, %{{:var, "link"} => {:map, "cta"}}, c.user, expect: plan.fingerprint)

      assert %Var{type: :link, value: "https://by.no/kultur", link_text: "Les mer", label: %{"en" => "Call to action"}} =
               var(block, "cta")

      assert var(block, "link") == nil
      assert version(block) == 3
    end

    test "says what a mapping replaces when the target already holds a value", c do
      {_page, block} =
        page_with_block(
          c,
          [link_var(), %{"type" => "link", "key" => "cta", "label" => "CTA", "value" => "https://other"}],
          []
        )

      plan = StaleBlocks.plan(report!(c), %{{:var, "link"} => {:map, "cta"}})
      assert [%{replaces: "https://other", lost: nil}] = plan.changes
      assert {:ok, _} = StaleBlocks.apply(c.module, %{{:var, "link"} => {:map, "cta"}}, c.user)
      assert [%Var{value: "https://by.no/kultur"}] = Enum.filter(vars(block), &(&1.key == "cta"))
    end

    test "converts a string var into a text or HTML one, and refuses what would lose content", c do
      {_page, block} =
        page_with_block(c, [%{"type" => "string", "key" => "subtitle", "label" => "S", "value" => "A & B"}], [])

      assert {:ok, _} = StaleBlocks.apply(c.module, %{{:var, "subtitle"} => {:map, "caption"}}, c.user)
      assert %Var{type: :text, value: "A & B"} = var(block, "caption")
      assert version(block) == 3
    end

    test "a string or text var moved onto an HTML one is escaped into a paragraph", c do
      Repo.insert!(%Var{module_id: c.module.id, key: "lead", type: :html, label: %{"en" => "Lead"}})

      {_page, block} =
        page_with_block(c, [%{"type" => "text", "key" => "intro", "label" => "I", "value" => "A < B\nC"}], [])

      assert {:ok, _} = StaleBlocks.apply(c.module, %{{:var, "intro"} => {:map, "lead"}}, c.user)
      assert %Var{type: :html, value: "<p>A &lt; B<br>C</p>"} = var(block, "lead")
      assert version(block) == 3
    end

    test "refuses incompatible mappings with a reason, and changes nothing", c do
      {_page, block} =
        page_with_block(
          c,
          [
            link_var(),
            %{"type" => "text", "key" => "lines", "label" => "L", "value" => "one\ntwo"},
            %{"type" => "string", "key" => "kind", "label" => "K", "value" => "medium"}
          ],
          []
        )

      resolutions = %{
        {:var, "link"} => {:map, "label"},
        {:var, "lines"} => {:map, "label"},
        {:var, "kind"} => {:map, "size"}
      }

      plan = StaleBlocks.plan(report!(c), resolutions)
      reasons = Map.new(plan.refused, &{&1.key, &1.reason})
      assert reasons["link"] =~ "a link variable cannot become a string variable"
      assert reasons["lines"] =~ "more than one line"
      # string → select is not a conversion either
      assert reasons["kind"] =~ "cannot become"

      assert {:error, message} = StaleBlocks.apply(c.module, resolutions, c.user)
      assert message =~ "link"
      assert var(block, "link")
      assert version(block) == 1
    end

    test "a select value must be one of the target's options", c do
      {_page, block} =
        page_with_block(c, [%{"type" => "select", "key" => "width", "label" => "W", "value" => "huge"}], [])

      plan = StaleBlocks.plan(report!(c), %{{:var, "width"} => {:map, "size"}})
      assert [%{reason: reason}] = plan.refused
      assert reason =~ "“huge” is not one of its options"

      Repo.update_all(from(v in Var, where: v.block_id == ^block.id and v.key == "width"), set: [value: "large"])
      assert {:ok, _} = StaleBlocks.apply(c.module, %{{:var, "width"} => {:map, "size"}}, c.user)
      assert [%Var{value: "large"}] = Enum.filter(vars(block), &(&1.key == "size"))
    end

    test "maps a ref onto a defined ref of a compatible type, moving its content; refuses another type", c do
      module =
        c.module
        |> Repo.preload(:refs)
        |> then(fn module ->
          Repo.insert!(%Brando.Content.Ref{
            module_id: module.id,
            name: "intro",
            uid: Brando.Utils.generate_uid(),
            data: %Brando.Villain.Blocks.TextBlock{
              type: "text",
              data: %Brando.Villain.Blocks.TextBlock.Data{text: "Default"}
            }
          })

          module
        end)

      c = %{c | module: module}
      {_page, block} = page_with_block(c, [], [text_ref("title", "<p>Moved</p>")])

      plan = StaleBlocks.plan(report!(c), %{{:ref, "title"} => {:map, "body"}})
      assert [%{reason: reason}] = plan.refused
      assert reason =~ "a picture reference cannot hold the content of a text reference"

      assert {:ok, _} = StaleBlocks.apply(c.module, %{{:ref, "title"} => {:map, "intro"}}, c.user)
      intro = Enum.find(refs(block), &(&1.name == "intro"))
      assert intro.data.data.text == "<p>Moved</p>"
      refute Enum.any?(refs(block), &(&1.name == "title"))
      assert version(block) == 3
    end

    test "dropping a retyped ref lets the re-sync put the module's own back", c do
      {_page, block} = page_with_block(c, [], [text_ref("body", "Was text")])

      assert {:ok, %{stamped: [_]}} = StaleBlocks.apply(c.module, %{{:ref, "body"} => :drop}, c.user)
      assert [body] = Enum.filter(refs(block), &(&1.name == "body"))
      assert %Brando.Villain.Blocks.PictureBlock{} = body.data
      assert version(block) == 3
    end

    test "resolves a leftover in every block at once, with a per-block exception", c do
      {_page, one} = page_with_block(c, [link_var()], [])
      {_page, two} = page_with_block(c, [link_var("Billetter")], [], "Other")
      {_page, three} = page_with_block(c, [link_var("Kart")], [], "Third")

      resolutions = %{{:var, "link"} => :drop, {two.id, :var, "link"} => {:map, "cta"}, {three.id, :var, "link"} => :keep}
      plan = StaleBlocks.plan(report!(c), resolutions)
      assert Enum.sort(plan.changed) == Enum.sort([one.id, two.id])
      assert plan.remaining == [three.id]
      assert [%{block_id: lost_in, lost: "Les mer → https://by.no/kultur"}] = Enum.filter(plan.changes, & &1.lost)
      assert lost_in == one.id

      assert {:ok, result} = StaleBlocks.apply(c.module, resolutions, c.user)
      assert Enum.sort(result.stamped) == Enum.sort([one.id, two.id])
      assert var(one, "link") == nil
      assert var(two, "cta").link_text == "Billetter"
      assert var(three, "link")
      assert version(three) == 1
      assert Blocks.list_stale_block_ids(c.module) == [three.id]
    end

    test "a block that only needs a re-sync is stamped", c do
      {_page, block} = page_with_block(c, [], [])
      assert {:ok, %{stamped: [_]}} = StaleBlocks.apply(c.module, %{}, c.user)
      assert version(block) == 3
    end

    test "is refused when the blocks changed after the plan was reviewed", c do
      {_page, block} = page_with_block(c, [link_var()], [])
      plan = StaleBlocks.plan(report!(c), %{{:var, "link"} => :drop})

      Repo.update_all(from(v in Var, where: v.block_id == ^block.id and v.key == "link"), set: [link_text: "Changed"])

      assert {:error, message} =
               StaleBlocks.apply(c.module, %{{:var, "link"} => :drop}, c.user, expect: plan.fingerprint)

      assert message =~ "changed after you reviewed"
      assert var(block, "link")
    end

    test "stores a revision of each entry before and after, and records the change in Activity", c do
      {page, _block} = page_with_block(c, [link_var()], [])
      before = revisions(page)

      assert {:ok, _} = StaleBlocks.apply(c.module, %{{:var, "link"} => :drop}, c.user)

      assert [first, second] = revisions(page) -- before
      refute first.active
      assert first.description =~ "Before resolving blocks on older versions of Kulturslider"
      assert second.active

      # the first revision still holds the dropped var, so History can bring it back
      {:ok, {_, {_, restored}}} = Brando.Revisions.get_revision(Page, page.id, first.revision)
      [entry_block] = restored.entry_blocks
      assert Enum.any?(entry_block.block.vars, &(&1.key == "link"))

      event = Repo.one!(from(e in Brando.Activity.Event, where: e.schema == ^to_string(Page) and e.entry_id == ^page.id))
      assert event.action == :updated
      assert event.user_id == c.user.id
      assert %{"module" => "Kulturslider", "dropped" => ["var:link"], "blocks" => [_]} = event.details["stale_blocks"]

      module_events =
        Repo.all(from(e in Brando.Activity.Event, where: e.schema == ^to_string(Module) and e.entry_id == ^c.module.id))

      assert Enum.any?(module_events, &match?(%{"stale_blocks" => %{"dropped" => ["var:link"]}}, &1.details))
    end

    test "needs the right to update the module and every entry it changes", c do
      {_page, block} = page_with_block(c, [link_var()], [])
      put_test_env(:authorization_mode, :groups)
      alias Brando.Authorization.{Catalog, Groups, Migration, Scope}
      owner = Factory.insert(:random_user, role: :superuser)
      assert {:ok, _} = Migration.run()
      scope = Scope.standalone(owner)

      module_only = Factory.insert(:random_user, role: :user, config: %Brando.Users.UserConfig{})
      grants = [Catalog.get(:update, Module).key, Catalog.get(:read, Module).key, "brando.admin.access"]
      assert {:ok, group} = Groups.create(scope, %{name: "Module editors"}, grants)
      assert {:ok, :ok} = Groups.add_member(scope, group.id, module_only.id)

      nobody = Factory.insert(:random_user, role: :user, config: %Brando.Users.UserConfig{})

      assert {:error, message} = StaleBlocks.apply(c.module, %{{:var, "link"} => :drop}, nobody)
      assert message =~ "permission to change this module"

      assert {:error, message} = StaleBlocks.apply(c.module, %{{:var, "link"} => :drop}, module_only)
      assert message =~ "permission to change Sommerro"

      assert var(block, "link")
      assert {:ok, _} = StaleBlocks.apply(c.module, %{{:var, "link"} => :drop}, owner)
      assert var(block, "link") == nil
    end
  end

  describe "mix brando.modules" do
    # What the task says, info and errors, through `Mix.Shell.Process`: the
    # shell is global, and capturing IO depends on what other tests set it to.
    defp run_task(args) do
      previous = Mix.shell()
      Mix.shell(Mix.Shell.Process)
      Mix.Task.reenable("brando.modules")

      try do
        Mix.Tasks.Brando.Modules.run(args)
        shell_output()
      after
        Mix.shell(previous)
      end
    end

    defp shell_output(acc \\ "") do
      receive do
        {:mix_shell, _level, [message]} -> shell_output(acc <> message <> "\n")
      after
        0 -> acc
      end
    end

    test "resolve lists the blocks and leftovers without changing anything", c do
      {_page, block} = page_with_block(c, [link_var()], [text_ref("title", "Gammel tittel")])
      args = ["resolve", "--uid", c.module.uid, "--user", to_string(c.user.id)]

      output = run_task(args)
      assert output =~ "Kulturslider (#{c.module.uid}) is on version 3; 1 blocks are behind."
      assert output =~ "Block ##{block.id} on version 1: Sommerro (Page, en)"
      assert output =~ ~s|var link (link): "Les mer → https://by.no/kultur"|
      assert output =~ ~s|ref title (text): "Gammel tittel"|
      assert output =~ "var link in 1 blocks; can map to: cta (link)"

      output = run_task(args ++ ["--drop", "link"])
      assert output =~ "→ drop"
      assert output =~ "Dry run: nothing changed"
      assert var(block, "link")
      assert version(block) == 1
    end

    test "resolve --apply drops and maps, then the block is current", c do
      module =
        Repo.insert!(%Brando.Content.Ref{
          module_id: c.module.id,
          name: "intro",
          uid: Brando.Utils.generate_uid(),
          data: %Brando.Villain.Blocks.TextBlock{
            type: "text",
            data: %Brando.Villain.Blocks.TextBlock.Data{text: "Default"}
          }
        })

      assert module
      {_page, block} = page_with_block(c, [link_var()], [text_ref("title", "Gammel tittel")])

      args = [
        "resolve",
        "--uid",
        c.module.uid,
        "--user",
        to_string(c.user.id),
        "--drop",
        "var:link",
        "--map",
        "title=intro"
      ]

      output = run_task(args ++ ["--apply"])
      assert output =~ "Resolved 1 blocks; 1 are now on version 3, 0 remain."
      assert var(block, "link") == nil
      assert Enum.find(refs(block), &(&1.name == "intro")).data.data.text == "Gammel tittel"
      assert version(block) == 3
    end

    test "resolve --apply refuses an incompatible mapping and changes nothing", c do
      {_page, block} = page_with_block(c, [link_var()], [])
      args = ["resolve", "--uid", c.module.uid, "--user", to_string(c.user.id), "--map", "link=label", "--apply"]

      assert_raise Mix.Error, ~r/Nothing was changed/, fn -> run_task(args) end
      assert shell_output() =~ "Variable link → label: a link variable cannot become a string variable."
      assert var(block, "link")
    end

    test "refresh says what keeps blocks stale and where to resolve them", c do
      page_with_block(c, [link_var()], [])

      output = run_task(["refresh", "--uid", c.module.uid, "--user", to_string(c.user.id)])
      assert output =~ "1 stale blocks remain"
      assert output =~ "They hold refs or vars the module no longer defines: var link (1 blocks)."
      assert output =~ "mix brando.modules resolve --uid #{c.module.uid} --user ID"
      assert output =~ "/admin/config/content/modules/update/#{c.module.id}/stale-blocks"
    end
  end

  describe "tenancy" do
    test "lists and resolves only the selected environment's blocks", c do
      {_page, public_block} = page_with_block(c, [link_var()], [])
      put_test_env(:tenancy_mode, :multi)
      prefix = "tenant_stale_staging"
      Ecto.Adapters.SQL.query!(Repo.repo(), ~s(CREATE SCHEMA "#{prefix}"))

      for table <- ~w(content_modules content_refs content_vars content_blocks) do
        Ecto.Adapters.SQL.query!(
          Repo.repo(),
          ~s|CREATE TABLE "#{prefix}"."#{table}" (LIKE public."#{table}" INCLUDING ALL)|
        )
      end

      Brando.Tenant.with_prefix(prefix, fn ->
        module =
          Repo.insert!(%Module{
            uid: c.module.uid,
            name: %{"en" => "Kulturslider"},
            namespace: %{"en" => "x"},
            help_text: %{"en" => "h"},
            class: "c",
            code: "c",
            version: 2
          })

        block =
          Repo.insert!(%Block{
            uid: "loose",
            type: :module,
            module_id: module.id,
            module_version: 1,
            creator_id: c.user.id
          })

        Repo.insert!(%Var{block_id: block.id, key: "link", type: :link, label: %{"en" => "Link"}, value: "https://x"})

        assert {:ok, %{blocks: [%{id: id, leftovers: [%{key: "link"}]}]}} = StaleBlocks.report(c.module.uid, c.user)
        assert id == block.id
        assert {:ok, %{stamped: [_]}} = StaleBlocks.apply(c.module.uid, %{{:var, "link"} => :drop}, c.user)
        assert Repo.get!(Block, block.id).module_version == 2
      end)

      put_test_env(:tenancy_mode, :none)
      assert var(public_block, "link")
      assert version(public_block) == 1
    end
  end
end
