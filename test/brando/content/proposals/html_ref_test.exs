defmodule Brando.Content.Proposals.HtmlRefTest do
  # A proposal fills in an HTML ref's parameter values, checked against
  # their types, and never writes its markup.
  use Brando.ConnCase, async: false

  alias Brando.Content.Proposals
  alias Brando.Content.Proposals.InsertBlock
  alias Brando.Content.Proposals.SetBlockText
  alias Brando.Content.Proposals.SetRefConfig
  alias Brando.Content.Proposals.Tools
  alias Brando.Content.Proposals.Tools.Context
  alias Brando.Content.Transfer.Catalog
  alias Brando.Pages.Page

  import Brando.ProposalFixtures, only: [module!: 4, ref: 2]

  @template ~s(<div data-checkin="{{ checkin_id }}"></div>)

  setup do
    c = Brando.ProposalFixtures.context()

    module =
      module!(c.user, "Checkin", "{% ref refs.embed %}",
        refs: [
          ref("embed", %{
            type: "html",
            data: %{text: @template, params: [%{key: "checkin_id", label: "Checkin ID", type: "id"}]}
          })
        ]
      )

    Map.put(c, :checkin, module)
  end

  defp approve_and_apply(proposal, user) do
    with {:ok, _} <- Proposals.approve(proposal.id, proposal.version, user),
         do: Proposals.apply(proposal.id, proposal.version, user)
  end

  defp embed(c) do
    block = Catalog.load!(Page, c.identity.id, c.user).entry_blocks |> List.last() |> Map.get(:block)
    {block, Enum.find(block.refs, &(&1.name == "embed")).data.data}
  end

  test "describe_module lists the parameters", c do
    context = %Context{actor: c.user, conversation_id: Ecto.UUID.generate(), attachments: %{}}
    {:ok, contract} = Tools.call("describe_module", %{"module" => "local:#{c.checkin.id}"}, context)

    assert [%{name: "embed", settings: [%{key: :values, params: [%{key: "checkin_id", type: "id"}]}]} = slot] =
             contract.slots

    assert slot.settable =~ "set_ref_config"
  end

  test "an insert fills in a value and keeps the module's markup", c do
    uid = Brando.Utils.generate_uid()

    insert = %InsertBlock{
      target: {Page, c.identity.id},
      module: c.checkin.id,
      uid: uid,
      configs: %{"embed" => %{"values" => %{"checkin_id" => "abc-123"}}}
    }

    assert {:ok, proposal} = Proposals.propose([insert], c.user)
    assert proposal.problems == []
    assert {:ok, _} = approve_and_apply(proposal, c.user)

    {_block, data} = embed(c)
    assert data.text == @template
    assert data.values == %{"checkin_id" => "abc-123"}

    op = %SetRefConfig{
      target: {Page, c.identity.id},
      block_uid: uid,
      ref: "embed",
      config: %{"values" => %{"checkin_id" => "x9"}}
    }

    assert {:ok, proposal} = Proposals.propose([op], c.user)
    assert proposal.problems == []
    assert {:ok, _} = approve_and_apply(proposal, c.user)
    assert {_, %{values: %{"checkin_id" => "x9"}, text: @template}} = embed(c)
  end

  test "a value invalid for its type or an unknown parameter is a problem", c do
    for values <- [%{"checkin_id" => ~s(" onload="x)}, %{"other" => "x"}] do
      insert = %InsertBlock{
        target: {Page, c.identity.id},
        module: c.checkin.id,
        configs: %{"embed" => %{"values" => values}}
      }

      assert {:ok, proposal} = Proposals.propose([insert], c.user)
      assert Enum.map(proposal.problems, & &1.code) == [:unsupported_value]
    end
  end

  test "markup is not a text a proposal sets", c do
    insert = %InsertBlock{target: {Page, c.identity.id}, module: c.checkin.id, texts: %{"embed" => "<p>Safe</p>"}}
    assert {:ok, proposal} = Proposals.propose([insert], c.user)
    assert Enum.map(proposal.problems, & &1.code) == [:unsupported_value]

    uid = Brando.Utils.generate_uid()
    insert = %InsertBlock{target: {Page, c.identity.id}, module: c.checkin.id, uid: uid}
    assert {:ok, proposal} = Proposals.propose([insert], c.user)
    assert {:ok, _} = approve_and_apply(proposal, c.user)

    op = %SetBlockText{target: {Page, c.identity.id}, block_uid: uid, ref: "embed", text: "<p>Safe</p>"}
    assert {:ok, proposal} = Proposals.propose([op], c.user)
    assert Enum.map(proposal.problems, & &1.code) == [:unsupported_value]
  end
end
