defmodule Brando.Content.TransferContractsTest do
  use Brando.ConnCase, async: true

  alias Brando.Content.Transfer.Contracts
  alias Brando.Repo

  # A module stored without `multi` (NULL) and the same definition installed
  # elsewhere (multi false, the column default) must be one contract, or a
  # content import refuses the installed module as "incompatible settings".
  defp module!(multi) do
    Repo.insert!(%Brando.Content.Module{
      uid: Ecto.UUID.generate(),
      type: :liquid,
      name: %{"en" => "Campaign introduction"},
      namespace: %{"en" => "Content"},
      help_text: %{},
      class: "campaign-introduction",
      code: "{% ref refs.body %}",
      multi: multi,
      refs: [
        %Brando.Content.Ref{
          name: "body",
          uid: Brando.Utils.generate_uid(),
          data: %Brando.Villain.Blocks.TextBlock{type: "text", data: %Brando.Villain.Blocks.TextBlock.Data{text: ""}}
        }
      ],
      vars: []
    })
  end

  defp block, do: %{"refs" => [%{"name" => "body", "data" => %{"type" => "text"}}], "vars" => [], "table_rows" => []}

  test "an unset multi is the same contract as multi false" do
    source = module!(nil)
    installed = module!(false)

    assert Contracts.capture(source)["multi"] == false
    assert Contracts.normalized(source) == Contracts.normalized(installed)
    assert Contracts.check!(block(), Contracts.capture(source), installed) == :ok
  end

  test "a bundle exported with multi nil still matches an installed module" do
    old = Map.put(Contracts.capture(module!(nil)), "multi", nil)
    assert Contracts.check!(block(), old, module!(false)) == :ok
  end

  test "multi true is still a different contract" do
    assert_raise Brando.Content.Transfer.Error, ~r/multi/, fn ->
      Contracts.check!(block(), Contracts.capture(module!(nil)), module!(true))
    end
  end

  # A bundle exported before brando_225 names a rich_text var html
  test "a bundle with html vars matches a module with rich_text ones" do
    module = module!(false)
    Repo.insert!(%Brando.Content.Var{module_id: module.id, key: "intro", type: :rich_text, label: %{"en" => "Intro"}})
    module = Repo.preload(module, :vars, force: true)

    old = put_in(Contracts.capture(module), ["vars", "intro"], "html")
    assert old["vars"]["intro"] == "html"

    block = %{block() | "vars" => [%{"key" => "intro", "type" => "html", "value" => "<p>Intro</p>"}]}
    assert Contracts.check!(block, old, module) == :ok

    definition =
      update_in(Contracts.normalized(module), ["vars"], fn vars -> Enum.map(vars, &%{&1 | "type" => "html"}) end)

    assert Contracts.differences(%{"kind" => "module", "definition" => definition}, module) == []
    assert Contracts.same_definition?(module, definition)

    # A receipt's digest from before the rename names the var html
    blocks = [%{"block" => %{"vars" => [%{"key" => "intro", "type" => "rich_text"}], "children" => []}}]

    assert Contracts.with_html_vars(blocks) ==
             [%{"block" => %{"vars" => [%{"key" => "intro", "type" => "html"}], "children" => []}}]
  end
end
