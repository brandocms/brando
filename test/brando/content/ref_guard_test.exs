defmodule Brando.Content.RefGuardTest do
  # What a block save may change in the block's refs
  # (`Brando.Content.RefGuard`): a ref's type follows its module, and only a
  # superuser changes the markup of an HTML or SVG ref. Editors fill in an
  # HTML ref's parameter values.
  use ExUnit.Case, async: false
  use Brando.ConnCase

  alias Brando.Content.Block
  alias Brando.Factory
  alias Brando.ProposalFixtures
  alias Brando.Repo
  alias Brando.Utils
  alias Brando.Villain.Blocks.HtmlBlock
  alias Brando.Villain.Blocks.MediaBlock
  alias Brando.Villain.Blocks.SvgBlock
  alias Brando.Villain.Blocks.TextBlock
  alias Ecto.Changeset

  @template ~s(<div data-checkin="{{ checkin_id }}"></div>)
  @svg ~s(<svg viewBox="0 0 1 1"><rect width="1" height="1"/></svg>)

  setup do
    superuser = Factory.insert(:random_user)
    editor = Factory.insert(:random_user, role: :editor)

    module =
      ProposalFixtures.module!(
        superuser,
        "Checkin",
        "<div>{% ref refs.body %}{% ref refs.embed %}{% ref refs.logo %}{% ref refs.media %}</div>",
        refs: [
          ProposalFixtures.ref("body", %{type: "text", data: %{text: "<p>Body</p>"}}),
          ProposalFixtures.ref("embed", %{
            type: "html",
            data: %{text: @template, params: [%{key: "checkin_id", label: "Checkin ID", type: "id"}]}
          }),
          ProposalFixtures.ref("logo", %{type: "svg", data: %{code: @svg}}),
          ProposalFixtures.ref("media", %{
            type: "media",
            data: %{available_blocks: ["picture", "svg"], template_svg: %{code: @svg}}
          })
        ]
      )

    %{superuser: superuser, editor: editor, module: module}
  end

  defp insert_block!(c) do
    %Block{}
    |> Block.recursive_block_changeset(
      %{
        "uid" => Utils.generate_uid(),
        "type" => "module",
        "module_id" => c.module.id,
        "refs" => module_ref_params(c.module)
      },
      c.superuser
    )
    |> Repo.insert!()
    |> Repo.preload([:refs, :vars, :table_rows, :block_identifiers, :children])
  end

  defp module_ref_params(module) do
    module.refs
    |> Enum.with_index()
    |> Map.new(fn {ref, index} ->
      {to_string(index),
       %{
         "uid" => Utils.generate_uid(),
         "name" => ref.name,
         "data" => data_params(ref.data)
       }}
    end)
  end

  defp data_params(%{} = struct) when is_struct(struct) do
    struct
    |> Map.from_struct()
    |> Map.delete(:__meta__)
    |> Map.new(fn {key, value} -> {to_string(key), data_params(value)} end)
  end

  defp data_params(list) when is_list(list), do: Enum.map(list, &data_params/1)
  defp data_params(value), do: value

  defp ref(block, name), do: Enum.find(block.refs, &(&1.name == name))

  # A keystroke that sends `data` for the ref `name`
  defp save(block, name, data, user) do
    ref = ref(block, name)
    params = %{"refs" => %{"0" => %{"id" => to_string(ref.id), "data" => data}}}
    Block.block_changeset(block, params, user.id)
  end

  defp saved_ref(changeset, name) do
    changeset |> Changeset.apply_changes() |> Map.get(:refs) |> Enum.find(&(&1.name == name))
  end

  describe "a ref's type" do
    test "an editor cannot turn a text ref into an HTML ref", c do
      block = insert_block!(c)
      payload = %{"type" => "html", "data" => %{"text" => "<i>raw</i>"}}

      changeset = save(block, "body", payload, c.editor)

      assert %TextBlock{data: %{text: "<p>Body</p>"}} = saved_ref(changeset, "body").data
    end

    test "nor can a superuser: the type follows the module", c do
      block = insert_block!(c)
      payload = %{"type" => "html", "data" => %{"text" => "<i>raw</i>"}}

      changeset = save(block, "body", payload, c.superuser)

      assert %TextBlock{} = saved_ref(changeset, "body").data
    end

    test "a saved ref keeps its name, so it cannot take another ref's place", c do
      block = insert_block!(c)
      embed = ref(block, "embed")

      params = %{"refs" => %{"0" => %{"id" => to_string(embed.id), "name" => "body"}}}
      changeset = Block.block_changeset(block, params, c.editor.id)

      refute Enum.any?(Changeset.apply_changes(changeset).refs, &match?(%{name: "body", data: %HtmlBlock{}}, &1))
    end

    test "a media slot takes a type its module lists", c do
      block = insert_block!(c)

      changeset = save(block, "media", %{"type" => "picture", "data" => %{}}, c.editor)
      assert %Brando.Villain.Blocks.PictureBlock{} = saved_ref(changeset, "media").data

      changeset = save(block, "media", %{"type" => "video", "data" => %{}}, c.editor)
      assert %MediaBlock{} = saved_ref(changeset, "media").data
    end

    test "a new ref the module does not define holds no markup for an editor", c do
      block = insert_block!(c)

      params = %{
        "refs" => %{
          "0" => %{
            "uid" => "planted1",
            "name" => "planted",
            "data" => %{"type" => "html", "data" => %{"text" => "<i>x</i>"}}
          }
        }
      }

      changeset = Block.block_changeset(block, params, c.editor.id)
      planted = changeset |> Changeset.get_change(:refs) |> Enum.find(&(Changeset.get_field(&1, :name) == "planted"))

      assert planted.action == :ignore
    end
  end

  describe "an HTML ref" do
    test "an editor fills in a value", c do
      block = insert_block!(c)

      changeset = save(block, "embed", %{"data" => %{"values" => %{"checkin_id" => "abc-123"}}}, c.editor)

      assert changeset.valid?

      assert %HtmlBlock{data: %{text: @template, values: %{"checkin_id" => "abc-123"}}} =
               saved_ref(changeset, "embed").data
    end

    test "an editor's invalid value is refused", c do
      block = insert_block!(c)

      changeset = save(block, "embed", %{"data" => %{"values" => %{"checkin_id" => "a b"}}}, c.editor)

      refute changeset.valid?
    end

    test "an editor's markup and parameters are put back, the value kept", c do
      block = insert_block!(c)

      data = %{
        "text" => "<b>{{ checkin_id }}</b>",
        "params" => %{"0" => %{"key" => "checkin_id", "label" => "X", "type" => "text"}},
        "values" => %{"checkin_id" => "abc"}
      }

      changeset = save(block, "embed", %{"data" => data}, c.editor)

      assert changeset.valid?
      saved = saved_ref(changeset, "embed").data.data
      assert saved.text == @template
      assert [%{key: "checkin_id", label: "Checkin ID", type: :id}] = saved.params
      assert saved.values == %{"checkin_id" => "abc"}
    end

    test "a value valid only for the editor's own parameter type is refused", c do
      block = insert_block!(c)

      data = %{
        "params" => %{"0" => %{"key" => "checkin_id", "label" => "Checkin ID", "type" => "text"}},
        "values" => %{"checkin_id" => "not an id"}
      }

      changeset = save(block, "embed", %{"data" => data}, c.editor)

      refute changeset.valid?
      assert saved_ref(changeset, "embed").data.data.params |> hd() |> Map.get(:type) == :id
    end

    test "a superuser changes the markup and parameters", c do
      block = insert_block!(c)

      data = %{
        "text" => "<b>{{ name }}</b>",
        "params" => %{"0" => %{"key" => "name", "label" => "Name", "type" => "text"}}
      }

      changeset = save(block, "embed", %{"data" => data}, c.superuser)

      assert changeset.valid?
      saved = saved_ref(changeset, "embed").data.data
      assert saved.text == "<b>{{ name }}</b>"
      assert [%{key: "name", type: :text}] = saved.params
    end

    test "a new block's HTML ref takes the module's markup for an editor", c do
      params = %{
        "uid" => Utils.generate_uid(),
        "type" => "module",
        "module_id" => c.module.id,
        "refs" => %{
          "0" => %{
            "uid" => Utils.generate_uid(),
            "name" => "embed",
            "data" => %{"type" => "html", "data" => %{"text" => "<i>x</i>", "values" => %{"checkin_id" => "a1"}}}
          }
        }
      }

      changeset = Block.recursive_block_changeset(%Block{}, params, c.editor.id)

      saved = saved_ref(changeset, "embed").data.data
      assert saved.text == @template
      assert saved.values == %{"checkin_id" => "a1"}
    end

    test "a copy of a saved block keeps the markup a superuser gave it", c do
      block = insert_block!(c)
      custom = "<span>{{ checkin_id }}</span>"

      block
      |> Block.block_changeset(
        %{"refs" => %{"0" => %{"id" => to_string(ref(block, "embed").id), "data" => %{"data" => %{"text" => custom}}}}},
        c.superuser.id
      )
      |> Repo.update!()

      params = %{
        "uid" => Utils.generate_uid(),
        "type" => "module",
        "module_id" => c.module.id,
        "refs" => %{
          "0" => %{
            "uid" => Utils.generate_uid(),
            "name" => "embed",
            "data" => %{
              "type" => "html",
              "data" => %{
                "text" => custom,
                "params" => %{"0" => %{"key" => "checkin_id", "label" => "Checkin ID", "type" => "id"}}
              }
            }
          }
        }
      }

      changeset = Block.recursive_block_changeset(%Block{}, params, c.editor.id)

      assert saved_ref(changeset, "embed").data.data.text == custom
    end
  end

  describe "content transfer" do
    # Transferred blocks are cast by `Transfer.field_changeset/3` with the
    # importing user, like an editor's save
    defp transfer(c, user) do
      page = Factory.insert(:page, creator: c.superuser) |> Repo.preload(entry_blocks: :block)

      block = %{
        "uid" => Utils.generate_uid(),
        "type" => "module",
        "module_id" => c.module.id,
        "refs" => %{
          "0" => %{
            "uid" => Utils.generate_uid(),
            "name" => "embed",
            "data" => %{"type" => "html", "data" => %{"text" => "<i>imported</i>", "values" => %{"checkin_id" => "x1"}}}
          },
          "1" => %{
            "uid" => Utils.generate_uid(),
            "name" => "body",
            "data" => %{"type" => "svg", "data" => %{"code" => "<svg/>"}}
          }
        }
      }

      changeset =
        Brando.Content.Transfer.field_changeset(page, %{"entry_blocks" => [%{"sequence" => 0, "block" => block}]}, user)

      [entry_block] = Changeset.apply_changes(changeset).entry_blocks
      Map.new(entry_block.block.refs, &{&1.name, &1.data})
    end

    test "an editor's import takes the module's markup and types", c do
      refs = transfer(c, c.editor)

      assert %HtmlBlock{data: %{text: @template, values: %{"checkin_id" => "x1"}}} = refs["embed"]
      assert %TextBlock{data: %{text: "<p>Body</p>"}} = refs["body"]
    end

    test "a superuser's import keeps its markup, but not a changed type", c do
      refs = transfer(c, c.superuser)

      assert %HtmlBlock{data: %{text: "<i>imported</i>"}} = refs["embed"]
      assert %TextBlock{} = refs["body"]
    end
  end

  describe "an SVG ref" do
    test "an editor's code is put back", c do
      block = insert_block!(c)

      changeset = save(block, "logo", %{"data" => %{"code" => "<svg><a/></svg>", "class" => "x"}}, c.editor)

      assert %SvgBlock{data: %{code: @svg, class: nil}} = saved_ref(changeset, "logo").data
    end

    test "a superuser changes the code", c do
      block = insert_block!(c)

      changeset = save(block, "logo", %{"data" => %{"code" => "<svg><g/></svg>"}}, c.superuser)

      assert %SvgBlock{data: %{code: "<svg><g/></svg>"}} = saved_ref(changeset, "logo").data
    end

    test "an editor turns a media slot into an SVG with the slot's own template", c do
      block = insert_block!(c)

      changeset = save(block, "media", %{"type" => "svg", "data" => %{"code" => "<svg><a/></svg>"}}, c.editor)

      assert %SvgBlock{data: %{code: @svg}} = saved_ref(changeset, "media").data
    end

    test "an editor cannot change a media slot's SVG template", c do
      block = insert_block!(c)

      changeset = save(block, "media", %{"data" => %{"template_svg" => %{"code" => "<svg><a/></svg>"}}}, c.editor)

      assert %MediaBlock{data: %{template_svg: %{code: @svg}}} = saved_ref(changeset, "media").data
    end
  end
end
