defmodule Brando.Content.VarGuardTest do
  # A var's type, key and options come from its definition, whatever a block
  # save sends; a saved block's module changes only for a superuser, and then
  # holds what the block has; and whatever is stored prints inert in Liquid.
  # The payloads would each only set the page's title.
  use ExUnit.Case, async: false
  use Brando.ConnCase

  alias Brando.Content.Block
  alias Brando.Content.Var
  alias Brando.Content.VarGuard
  alias Brando.Factory
  alias Brando.ProposalFixtures
  alias Brando.Repo
  alias Brando.Utils
  alias Ecto.Changeset

  @payloads "test/fixtures/editor_sinks/payloads.json" |> File.read!() |> Jason.decode!()
  @handler @payloads["handler"]
  @crafted_types ~w(color select datetime date rich_text html boolean bogus)
  @options [%{label: "Small", value: "small"}, %{label: "Large", value: "large"}]

  defmodule Parser do
    @moduledoc false
    use Brando.Villain.Parser
  end

  setup do
    preserve_cache(:globals)
    superuser = Factory.insert(:random_user)
    editor = Factory.insert(:random_user, role: :editor)

    {:ok, template} =
      Brando.Content.create_table_template(
        %{
          name: "Rows",
          vars: [
            %{key: "cell", label: "Cell", type: :string, creator_id: superuser.id},
            %{key: "size", label: "Size", type: :select, options: @options, creator_id: superuser.id}
          ]
        },
        superuser
      )

    module =
      ProposalFixtures.module!(superuser, "Vars", "<p>{{ title }}|{{ body }}|{{ size }}|{{ tint }}|{{ day }}|{{ at }}</p>",
        table_template_id: template.id,
        vars: [
          %{type: "string", key: "title", label: "Title"},
          %{type: "rich_text", key: "body", label: "Body"},
          %{type: "select", key: "size", label: "Size", value: "small", options: @options},
          %{type: "color", key: "tint", label: "Tint"},
          %{type: "date", key: "day", label: "Day"},
          %{type: "datetime", key: "at", label: "At"}
        ]
      )

    module = Repo.preload(module, :vars)
    %{superuser: superuser, editor: editor, module: module}
  end

  defp new_block_params(c, extra) do
    Map.merge(
      %{"uid" => Utils.generate_uid(), "type" => "module", "module_id" => c.module.id, "source" => "Elixir.Brando.Pages.Page.Blocks"},
      extra
    )
  end

  defp var_params(var) do
    var
    |> Map.take([:type, :key, :label, :value])
    |> Map.new(fn {key, value} -> {to_string(key), value} end)
    |> Map.update!("type", &to_string/1)
    |> Map.put("options", Enum.map(var.options, &%{"label" => &1.label, "value" => &1.value}))
  end

  defp insert_block!(c) do
    vars = c.module.vars |> Enum.with_index() |> Map.new(fn {var, i} -> {to_string(i), var_params(var)} end)
    row = %{"vars" => %{"0" => %{"key" => "cell", "label" => "Cell", "value" => "One"}}}

    %Block{}
    |> Block.recursive_block_changeset(new_block_params(c, %{"vars" => vars, "table_rows" => %{"0" => row}}), c.superuser)
    |> Repo.insert!()
    |> Repo.preload([:refs, :vars, :block_identifiers, :children, table_rows: :vars])
  end

  defp var(block, key), do: Enum.find(block.vars, &(&1.key == key))

  defp edit(block, key, fields, user) do
    params = Map.put(fields, "id", to_string(var(block, key).id))
    Block.block_changeset(block, %{"vars" => %{"0" => params}}, user.id)
  end

  defp var_change(changeset, key) do
    changeset |> Changeset.get_assoc(:vars) |> Enum.find(&(Changeset.get_field(&1, :key) == key))
  end

  defp new_var(block_params, c, fields, user \\ nil) do
    %Block{}
    |> Block.block_changeset(Map.put(new_block_params(c, block_params), "vars", %{"0" => fields}), (user || c.editor).id)
    |> Changeset.get_assoc(:vars)
  end

  defp active(html) do
    doc = html |> IO.iodata_to_binary() |> LazyHTML.from_fragment()
    doc |> LazyHTML.query("[onerror],[onclick],[onload],script") |> Enum.count()
  end

  describe "a saved var" do
    for type <- @crafted_types do
      test "keeps its type when a save sends #{type}", c do
        block = insert_block!(c)
        changeset = edit(block, "title", %{"type" => unquote(type), "value" => "Text"}, c.editor)

        assert changeset.valid?
        var = var_change(changeset, "title")
        assert Changeset.get_field(var, :type) == :string
        assert Changeset.get_field(var, :value) == "Text"
      end
    end

    test "keeps its key", c do
      block = insert_block!(c)
      changeset = edit(block, "title", %{"key" => "renamed", "value" => "Text"}, c.editor)
      assert %{changes: %{value: "Text"} = changes} = var_change(changeset, "title")
      refute Map.has_key?(changes, :key)
    end

    test "a form reads the held field, not what was sent", c do
      block = insert_block!(c)
      var = block |> edit("title", %{"type" => "color", "key" => "renamed"}, c.editor) |> var_change("title")
      refute Map.has_key?(var.params, "type")
      refute Map.has_key?(var.params, "key")
    end

    test "a rich text var relabelled as a string is still sanitized", c do
      block = insert_block!(c)
      refute edit(block, "body", %{"type" => "string", "value" => @handler}, c.editor).valid?
    end

    test "a table row's var keeps its type and key", c do
      block = insert_block!(c)
      [%{vars: [cell]} = row] = block.table_rows

      params = %{
        "table_rows" => %{
          "0" => %{
            "id" => to_string(row.id),
            "vars" => %{"0" => %{"id" => to_string(cell.id), "type" => "rich_text", "key" => "x", "value" => "Two"}}
          }
        }
      }

      changeset = Block.block_changeset(block, params, c.editor.id)
      assert changeset.valid?
      [row_change] = Changeset.get_assoc(changeset, :table_rows)
      assert [%{changes: changes}] = Changeset.get_assoc(row_change, :vars)
      assert Map.take(changes, [:type, :key, :value]) == %{value: "Two"}
    end

    test "cannot be pointed at a module, which would make it part of the definition", c do
      block = insert_block!(c)
      var = block |> edit("title", %{"module_id" => to_string(c.module.id)}, c.editor) |> var_change("title")
      refute Map.has_key?(var.changes, :module_id)
    end
  end

  describe "a new var" do
    for type <- @crafted_types do
      test "takes its definition's type over #{type}", c do
        assert [var] =
                 new_var(%{}, c, %{"key" => "title", "label" => "Title", "type" => unquote(type), "value" => "Text"})

        assert Changeset.get_field(var, :type) == :string
        assert var.valid?
      end
    end

    test "is left out when its key has no definition", c do
      assert [] = new_var(%{}, c, %{"key" => "planted", "label" => "Planted", "type" => "color", "value" => @handler})
    end

    test "is left out on a block with no module", c do
      assert [] = new_var(%{"module_id" => nil}, c, %{"key" => "title", "label" => "Title", "value" => "Text"})
    end

    test "a value under a key of another type is checked for that type", c do
      assert [var] = new_var(%{}, c, %{"key" => "body", "label" => "Body", "type" => "string", "value" => @handler})
      refute var.valid?
    end

    test "gets its options from the definition, not the request", c do
      fields = %{
        "key" => "size",
        "label" => "Size",
        "type" => "select",
        "value" => "small",
        "options" => %{"0" => %{"label" => "Crafted", "value" => @handler}}
      }

      assert [var] = new_var(%{}, c, fields)
      assert var.valid?
      assert Enum.map(Changeset.get_embed(var, :options, :struct), & &1.value) == ["small", "large"]
    end

    test "a new table row's vars take the template's types and refuse other keys", c do
      params =
        new_block_params(c, %{
          "table_rows" => %{
            "0" => %{
              "vars" => %{
                "0" => %{"key" => "cell", "label" => "Cell", "type" => "color", "value" => @handler},
                "1" => %{"key" => "planted", "label" => "Planted", "value" => "x"}
              }
            }
          }
        })

      changeset = Block.block_changeset(%Block{}, params, c.editor.id)
      [row] = Changeset.get_assoc(changeset, :table_rows)
      assert [cell] = Changeset.get_assoc(row, :vars)
      assert Changeset.get_field(cell, :type) == :string
      assert changeset.valid?
    end

    test "its owner comes from the block, not the request", c do
      fields = %{"key" => "title", "label" => "Title", "module_id" => to_string(c.module.id)}
      assert [var] = new_var(%{}, c, fields)
      refute Map.has_key?(var.changes, :module_id)
    end
  end

  describe "a value" do
    for {key, valid} <- [
          {"tint", "#ff0000"},
          {"tint", "rgb(0 0 0 / 50%)"},
          {"size", "large"},
          {"day", "2026-11-01"},
          {"at", "2026-11-01T10:00:00.000Z"},
          {"at", "2026-11-01 10:00:00"},
          {"size", ""}
        ] do
      test "#{key} takes #{inspect(valid)}", c do
        block = insert_block!(c)
        assert edit(block, unquote(key), %{"value" => unquote(valid)}, c.editor).valid?
        assert [%{valid?: true}] = new_var(%{}, c, %{"key" => unquote(key), "label" => "L", "value" => unquote(valid)})
      end
    end

    for key <- ~w(tint size day at) do
      test "#{key} refuses a crafted one, saved or new", c do
        block = insert_block!(c)
        refute edit(block, unquote(key), %{"value" => @handler}, c.editor).valid?
        assert [%{valid?: false}] = new_var(%{}, c, %{"key" => unquote(key), "label" => "L", "value" => @handler})
      end
    end

    test "a select refuses a value with a matching crafted option", c do
      block = insert_block!(c)
      options = %{"0" => %{"label" => "Crafted", "value" => @handler}}
      refute edit(block, "size", %{"value" => @handler, "options" => options}, c.editor).valid?
    end

    test "Var.changeset checks dates, datetimes and select options", c do
      base = %{key: "k", label: "K", creator_id: c.superuser.id}

      for {type, value} <- [{:date, @handler}, {:datetime, @handler}, {:select, @handler}, {:color, @handler}] do
        refute Var.changeset(%Var{}, Map.merge(base, %{type: type, value: value}), c.superuser).valid?
      end

      assert Var.changeset(%Var{}, Map.merge(base, %{type: :date, value: "2026-11-01"}), c.superuser).valid?
    end

    test "a stored one the save leaves alone does not stop it", c do
      block = insert_block!(c)
      size = var(block, "size")
      size |> Changeset.change(value: @handler) |> Repo.update!()
      block = Repo.preload(block, [:vars], force: true)

      assert edit(block, "title", %{"value" => "Text"}, c.editor).valid?
    end

    test "a definition's default is not taken for a crafted value", c do
      {:ok, module} =
        Brando.Content.create_module(
          Factory.params_for(:module, vars: [%{type: "select", key: "theme", label: "Theme", options: []}]),
          c.superuser
        )

      module.vars |> hd() |> Changeset.change(value: "dark") |> Repo.update!()
      Brando.Cache.Query.evict({:ok, module})

      params = %{"module_id" => module.id}
      assert [%{valid?: true}] = new_var(params, c, %{"key" => "theme", "label" => "Theme", "value" => "dark"})
    end
  end

  describe "the Liquid render" do
    for type <- [:color, :select, :datetime, :date, :text, :string] do
      test "a stored #{type} value prints inert, by key and in table rows", c do
        key = "v"
        var = %Var{type: unquote(type), key: key, label: %{"en" => key}, value: @handler}
        row = %Brando.Content.TableRow{vars: [var]}

        {:ok, module} =
          Brando.Content.create_module(
            Factory.params_for(:module, %{
              type: :liquid,
              code: "<p>{{ v }}</p>{% for row in table_rows %}{{ row.v }}{% for c in row.vars %}{{ c.value }}{% endfor %}{% endfor %}"
            }),
            c.superuser
          )

        block = %{
          block: %Block{type: :module, module_id: module.id, uid: Utils.generate_uid(), vars: [var], table_rows: [row], refs: []}
        }

        html = Brando.Villain.parse([block], %Brando.Pages.Page{})
        assert active(html) == 0
        assert IO.iodata_to_binary(html) =~ "&lt;"
      end
    end

    test "a color prints as it is", c do
      {:ok, module} = Brando.Content.create_module(Factory.params_for(:module, %{type: :liquid, code: "{{ v }}"}), c.superuser)

      for value <- ["#ff00aa", "rgb(0 0 0 / 50%)", "oklch(50% 0.1 200)"] do
        var = %Var{type: :color, key: "v", label: %{"en" => "v"}, value: value}
        block = %{block: %Block{type: :module, module_id: module.id, uid: Utils.generate_uid(), vars: [var], refs: []}}
        assert [block] |> Brando.Villain.parse(%Brando.Pages.Page{}) |> IO.iodata_to_binary() =~ value
      end
    end

    test "rich text still prints as markup", c do
      {:ok, module} = Brando.Content.create_module(Factory.params_for(:module, %{type: :liquid, code: "{{ v }}"}), c.superuser)
      var = %Var{type: :rich_text, key: "v", label: %{"en" => "v"}, value: "<p>Hi</p>"}
      block = %{block: %Block{type: :module, module_id: module.id, uid: Utils.generate_uid(), vars: [var], refs: []}}
      assert [block] |> Brando.Villain.parse(%Brando.Pages.Page{}) |> IO.iodata_to_binary() =~ "<p>Hi</p>"
    end

    test "globals of every text type print inert in Liquid, and raw for HEEx" do
      sets =
        for type <- [:select, :color, :datetime, :date, :link, :string], into: %{} do
          {to_string(type), %{type: type, value: @handler}}
        end

      context = Brando.Villain.add_to_context(Liquex.Context.new(%{}), "globals", %{"set" => sets})
      escaped = Liquex.Context.fetch(context, "globals") |> then(fn {:ok, globals} -> globals["set"] end)

      for {_type, value} <- escaped do
        refute value =~ "<"
      end

      assert Brando.Villain.raw_context(context, "globals")["set"]["select"] == @handler
    end

    test "an input ref prints its value as text" do
      assert Parser.input(%{value: @handler}, %{}) == Brando.Villain.Parser.escape_var_value(@handler)
    end
  end

  describe "a saved block's module" do
    setup c do
      target =
        ProposalFixtures.module!(c.superuser, "Target", "<div>{% ref refs.embed %}{% ref refs.media %}</div>",
          refs: [
            ProposalFixtures.ref("embed", %{type: "html", data: %{text: "<b>template</b>", params: []}}),
            ProposalFixtures.ref("media", %{type: "media", data: %{available_blocks: ["picture"]}})
          ],
          vars: [%{type: "rich_text", key: "title", label: "Title"}, %{type: "color", key: "size", label: "Size"}]
        )

      %{target: target}
    end

    # The first save of the attack: a ref of a harmless type under a name the
    # block's module does not define and the target's does.
    defp planted!(c, name) do
      block = insert_block!(c)

      params = %{
        "refs" => %{
          "0" => %{"uid" => Utils.generate_uid(), "name" => name, "data" => %{"type" => "input", "data" => %{"value" => @handler}}}
        }
      }

      block |> Block.block_changeset(params, c.editor.id) |> Repo.update!() |> Repo.preload(:refs, force: true)
    end

    defp move(block, target, refs_params, user) do
      params = %{"module_id" => to_string(target.id)}
      params = if refs_params, do: Map.put(params, "refs", refs_params), else: params
      Block.block_changeset(block, params, user)
    end

    defp id_only(ref), do: %{"0" => %{"id" => to_string(ref.id)}}
    defp edited(ref), do: %{"0" => %{"id" => to_string(ref.id), "description" => "Edited"}}

    for mode <- [:legacy, :groups], name <- ["embed", "media"], form <- [:no_refs, :id_only, :edited] do
      test "stays for a non-superuser in #{mode} mode: #{name} slot, #{form}", c do
        put_test_env(:authorization_mode, unquote(mode))
        block = planted!(c, unquote(name))
        ref = hd(block.refs)

        refs =
          case unquote(form) do
            :no_refs -> nil
            :id_only -> id_only(ref)
            :edited -> edited(ref)
          end

        changeset = move(block, c.target, refs, c.editor.id)
        refute Changeset.changed?(changeset, :module_id)
      end
    end

    test "stays for a non-superuser when only its origin changes", c do
      block = planted!(c, "embed")
      changeset = Block.block_changeset(block, %{"module_origin" => "shared"}, c.editor.id)
      refute Changeset.changed?(changeset, :module_origin)
    end

    for {name, type} <- [{"embed", "html"}, {"media", "media"}], form <- [:no_refs, :id_only, :edited] do
      test "a superuser's change holds a saved #{name} ref to the definition: #{form}", c do
        block = planted!(c, unquote(name))
        ref = hd(block.refs)

        refs =
          case unquote(form) do
            :no_refs -> nil
            :id_only -> id_only(ref)
            :edited -> edited(ref)
          end

        changeset = move(block, c.target, refs, :system)
        assert changeset.valid?
        assert Changeset.get_change(changeset, :module_id) == c.target.id
        saved = changeset |> Repo.update!() |> Repo.preload(:refs, force: true)
        moved = Enum.find(saved.refs, &(&1.name == unquote(name)))
        assert moved.data.type == unquote(type)
        refute inspect(moved.data) =~ "onerror"
      end
    end

    test "a superuser's change of origin holds saved refs too", c do
      block = planted!(c, "embed")
      changeset = Block.block_changeset(block, %{"module_origin" => "shared"}, :system)
      assert Changeset.get_change(changeset, :module_origin) == :shared
      assert [%{action: :update} | _] = Changeset.get_assoc(changeset, :refs)
    end

    test "a superuser's change retypes saved vars and empties them", c do
      block = insert_block!(c)
      var(block, "title") |> Changeset.change(value: "Plain <b>") |> Repo.update!()
      block = Repo.preload(block, :vars, force: true)

      changeset = move(block, c.target, nil, :system)
      assert changeset.valid?
      saved = changeset |> Repo.update!() |> Repo.preload(:vars, force: true)

      assert %{type: :rich_text, value: nil} = var(saved, "title")
      assert %{type: :color, value: nil, options: []} = var(saved, "size")
      # A var the module does not define lies dormant
      assert %{type: :rich_text} = var(saved, "body")
    end
  end

  describe "ordinary editing" do
    test "a new block from the module saves its vars and table row", c do
      block = insert_block!(c)
      assert var(block, "size").value == "small"
      assert Enum.map(var(block, "size").options, & &1.value) == ["small", "large"]
      assert [%{vars: [%{key: "cell", value: "One", type: :string}]}] = block.table_rows
      assert Enum.sort(Enum.map(block.vars, & &1.type)) == Enum.sort([:string, :rich_text, :select, :color, :date, :datetime])
    end

    test "a duplicate saves, with a stored value it could not carry left empty", c do
      block = insert_block!(c)
      var(block, "size") |> Changeset.change(value: @handler) |> Repo.update!()
      var(block, "tint") |> Changeset.change(value: @handler) |> Repo.update!()
      var(block, "title") |> Changeset.change(value: "Keep") |> Repo.update!()
      block = Repo.preload(block, [:vars], force: true)

      copy = block |> Changeset.change() |> Brando.Content.Blocks.duplicate_block(user_id: c.editor.id)
      params = Brando.Drafts.Params.snapshot(Changeset.apply_changes(copy))
      recast = Block.block_changeset(%Block{}, Map.put(params, "uid", Utils.generate_uid()), c.editor.id)

      assert recast.valid?
      assert %{value: "Keep"} = recast |> Changeset.apply_changes() |> var("title")
      assert %{value: nil} = recast |> Changeset.apply_changes() |> var("size")
      assert %{value: nil} = recast |> Changeset.apply_changes() |> var("tint")
    end

    test "a stale var keeps its saved type and key on an unrelated edit", c do
      block = insert_block!(c)

      %Var{}
      |> Var.changeset(%{key: "dropped", label: "Dropped", type: :string, value: "Kept", block_id: block.id}, c.superuser)
      |> Repo.insert!()

      block = Repo.preload(block, [:vars], force: true)
      assert edit(block, "dropped", %{"value" => "Edited"}, c.editor).valid?
    end

    test "global_values/2 lets through values only" do
      var = %Var{id: 1, type: :string, key: "a"}
      kept = %Var{id: 2, type: :string, key: "b"}

      params = %{
        "id" => "9",
        "key" => "renamed",
        "sort_var_ids" => ["0"],
        "vars" => %{
          "0" => %{"id" => "1", "value" => "New", "type" => "rich_text", "key" => "x", "options" => %{}},
          "1" => %{"key" => "planted", "value" => "x"}
        }
      }

      assert VarGuard.global_values(%{id: 9, vars: [var, kept]}, params) == %{
               "id" => 9,
               "vars" => %{"0" => %{"id" => 1, "value" => "New"}, "1" => %{"id" => 2}}
             }
    end
  end
end
