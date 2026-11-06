defmodule Brando.Villain.VarKeyAtomsTest do
  # A var's key comes from stored content. Rendering a block makes no atom of
  # it: a template reads the keys it names, and those exist once it is compiled.
  use ExUnit.Case, async: true

  alias Brando.Content.Module
  alias Brando.Content.Var
  alias Brando.Villain.TemplateAdapter
  alias Brando.Villain.TemplateAdapter.Heex

  defp fresh, do: "zzvarkey#{System.unique_integer([:positive])}"

  defp atom?(string) do
    _ = String.to_existing_atom(string)
    true
  rescue
    ArgumentError -> false
  end

  defp var(key, value), do: %Var{type: :string, key: key, value: value}

  defp module(code, type) do
    %Module{id: System.unique_integer([:positive]), code: code, type: type, class: "c", refs: [], vars: []}
  end

  defp block(module, vars, rows \\ []) do
    %{
      uid: "u",
      type: :module,
      module_id: module.id,
      sequence: 0,
      active: true,
      collapsed: false,
      anchor: nil,
      description: nil,
      vars: vars,
      table_rows: rows
    }
  end

  defp row(vars), do: %{id: 7, sequence: 0, vars: vars}
  defp process(vars), do: Brando.Villain.Parser.process_vars(vars)

  describe "a HEEx module's block vars" do
    test "a key the template reads renders on the template's first render, however new" do
      key = fresh()
      refute atom?(key)
      module = module(~s(<p>{@#{key}}</p>), :heex)
      vars = [var(key, "shown")]

      html = Heex.render_module(module, block(module, vars), process(vars), %{}, %{})

      assert html =~ "<p>shown</p>"
    end

    test "a key the template does not read makes no atom" do
      key = fresh()
      module = module("<p>x</p>", :heex)
      vars = [var(key, "unread")]

      # Compiling the template makes atoms of its own, so count from a second render
      assert Heex.render_module(module, block(module, vars), process(vars), %{}, %{}) =~ "<p>x</p>"
      refute atom?(key)

      other = fresh()
      other_vars = [var(other, "unread")]
      before = :erlang.system_info(:atom_count)
      Heex.render_module(module, block(module, other_vars), process(other_vars), %{}, %{})

      assert :erlang.system_info(:atom_count) == before
      refute atom?(other)
    end

    test "put_vars leaves out what exists as no atom" do
      key = fresh()

      assert Heex.put_vars(%{a: 1}, %{key => "x", "title" => "t", already: "y"}) == %{a: 1, title: "t", already: "y"}
      refute atom?(key)
    end
  end

  describe "a HEEx module's table rows" do
    test "a key the template reads renders on its first render; one it does not makes no atom" do
      read = fresh()
      unread = fresh()
      refute atom?(read)
      code = ~s|<p :for={row <- @block.table_rows}>{row.#{read}} {row.id} {hd(row.vars).value}</p>|
      module = module(code, :heex)
      rows = [row([var(read, "cell"), var(unread, "other")])]

      html = Heex.render_module(module, block(module, [], rows), %{}, %{}, %{})

      assert html =~ "<p>cell 7 cell</p>"
      refute atom?(unread)
    end

    test "row fields win over a var of the same name" do
      code = ~s|<p :for={row <- @block.table_rows}>{row.id} {hd(row.vars).value}</p>|
      module = module(code, :heex)
      rows = [row([var("id", "from var"), var("vars", "other")])]

      assert Heex.render_module(module, block(module, [], rows), %{}, %{}, %{}) =~ "<p>7 from var</p>"
    end

    test "the rows of a child and a multi module's own" do
      read = fresh()
      module = module(~s|<i :for={row <- @block.table_rows}>{row.#{read}}</i>|, :heex)
      rows = [row([var(read, "cell")])]

      assert Heex.render_child_module(module, block(module, [], rows), %{}, %{}, %{}, 1, %{}) =~ "<i>cell</i>"

      read = fresh()
      module = module(~s|<i :for={row <- @block.table_rows}>{row.#{read}}</i>|, :heex)
      rows = [row([var(read, "cell")])]

      assert Heex.render_multi_module(module, block(module, [], rows), %{}, %{}, [], "", %{}) =~ "<i>cell</i>"
    end
  end

  describe "a Liquid module's table rows" do
    defp liquid(code, simple_block) do
      {:ok, template} = Liquex.parse(code)
      {rendered, _} = Liquex.render!(template, Liquex.Context.new(%{"block" => simple_block}))
      to_string(rendered)
    end

    test "make no atom, and read by key, by name and through where" do
      key = fresh()
      module = module("", :liquid)
      simple = TemplateAdapter.simple_block(module, block(module, [], [row([var(key, "cell")])]), escape: true)

      refute atom?(key)

      before = :erlang.system_info(:atom_count)
      other = fresh()
      TemplateAdapter.simple_block(module, block(module, [], [row([var(other, "cell")])]), escape: true)
      assert :erlang.system_info(:atom_count) == before

      assert liquid("{% for row in block.table_rows %}{{ row.#{key} }}{% endfor %}", simple) == "cell"
      assert liquid(~s({% for row in block.table_rows %}{{ row["#{key}"] }}{% endfor %}), simple) == "cell"

      assert liquid(
               ~s({% assign found = block.table_rows | where: "#{key}", "cell" %}{{ found | size }}),
               simple
             ) == "1"

      refute atom?(key)
    end

    test "row fields win over a var of the same name" do
      module = module("", :liquid)
      rows = [row([var("id", "from var"), var("vars", "other")])]
      simple = TemplateAdapter.simple_block(module, block(module, [], rows), escape: true)

      assert liquid("{% for row in block.table_rows %}{{ row.id }}/{{ row.vars[0].value }}{% endfor %}", simple) ==
               "7/from var"
    end
  end
end
