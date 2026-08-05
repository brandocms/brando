defmodule BrandoAdmin.Components.Form.Block.ConfigEventUidTest do
  # Regression coverage for C6 — the seven block config handlers rebuilt the
  # block form with `uid = nil` on ROOT blocks.
  #
  # Each handler read `Changeset.get_field(changeset, :uid)`, but for a root the
  # changeset is the *entry_block* changeset, whose schema has no `:uid` field —
  # the block (and its uid) lives on the nested `:block` assoc. `get_field/2`
  # returns its default for an unknown field, so the read silently yielded nil
  # and the rebuilt form got the id `"entry_block_form-"`.
  #
  # That id is load-bearing, not cosmetic: the BlockField JS hook keys its
  # sessionStorage recovery snapshot on `entry_block_form-${uid}`
  # (`assets/src/hooks/BlockField/index.js`), so a block whose form id lost its
  # uid can no longer be recovered after the LiveView process dies. The DOM node
  # is also re-created, since the id changed.
  #
  # Child blocks were unaffected — their changeset *is* the block changeset.
  use ExUnit.Case, async: false
  use Brando.ConnCase

  alias Brando.Factory
  alias BrandoAdmin.Components.Form.Block
  alias BrandoAdmin.Components.Form.Block.Events
  alias BrandoAdmin.Components.Form.BlockField
  alias Ecto.Changeset

  defp create_module(user) do
    {:ok, module} =
      Brando.Content.create_module(
        %{
          name: %{"en" => "Refs and vars"},
          namespace: %{"en" => "test"},
          help_text: %{"en" => "help"},
          class: "refsandvars",
          code: "<div>{% ref refs.header %}{% ref refs.body %}{{ title }}{{ subtitle }}</div>",
          refs: [
            %{
              name: "header",
              uid: "refheader1",
              description: "header ref",
              data: %{type: "text", data: %{text: "Default header", type: "paragraph"}}
            },
            %{
              name: "body",
              uid: "refbody001",
              description: "body ref",
              data: %{type: "text", data: %{text: "Default body", type: "paragraph"}}
            }
          ],
          vars: [
            %{
              type: :string,
              label: "Title",
              key: "title",
              value: "Default title",
              placement: :content,
              width: :full
            },
            %{
              type: :string,
              label: "Subtitle",
              key: "subtitle",
              value: "Default subtitle",
              placement: :content,
              width: :full
            }
          ]
        },
        user
      )

    module
  end

  defp child_changeset(module, user) do
    BlockField.build_block(module.id, user.id, nil, "Elixir.Brando.Pages.Page.Blocks", :module)
  end

  defp root_changeset(module, user) do
    %Brando.Pages.Page.Blocks{}
    |> Changeset.change()
    |> Changeset.put_assoc(:block, child_changeset(module, user))
  end

  defp base_changeset(:root, module, user), do: root_changeset(module, user)
  defp base_changeset(_child, module, user), do: child_changeset(module, user)

  defp uid_of(changeset, :root),
    do: changeset |> Changeset.get_assoc(:block) |> Changeset.get_field(:uid)

  defp uid_of(changeset, _child), do: Changeset.get_field(changeset, :uid)

  defp socket_for(changeset, belongs_to, module) do
    uid = uid_of(changeset, belongs_to)

    %Phoenix.LiveView.Socket{}
    |> Phoenix.Component.assign(:form, Block.build_form_from_changeset(changeset, uid, belongs_to))
    |> Phoenix.Component.assign(:belongs_to, belongs_to)
    |> Phoenix.Component.assign(:module_id, module.id)
    |> Phoenix.Component.assign(:uid, uid)
    |> Phoenix.Component.assign(:form_id, "page_form")
    |> Phoenix.Component.assign(:block_field, "blocks")
  end

  defp expected_form_id(uid, :root), do: "entry_block_form-#{uid}"
  defp expected_form_id(uid, _child), do: "child_block_form-#{uid}"

  defp vars_of(socket, :root) do
    socket.assigns.form.source
    |> Changeset.get_assoc(:block)
    |> Changeset.get_assoc(:vars)
  end

  defp vars_of(socket, _child), do: Changeset.get_assoc(socket.assigns.form.source, :vars)

  # Every handler that rebuilds the form via `Block.build_form_from_changeset/3`.
  @handlers [
    {"fetch_missing_refs", %{}},
    {"reset_ref", %{"id" => "header"}},
    {"reset_refs", %{}},
    {"fetch_missing_vars", %{}},
    {"reset_vars", %{}},
    {"reset_var", %{"id" => "title"}},
    {"delete_var", %{"id" => "title"}}
  ]

  for belongs_to <- [:root, :child] do
    describe "block config handlers keep the form uid (#{belongs_to} block)" do
      setup do
        user = Factory.insert(:random_user)
        module = create_module(user)
        {:ok, user: user, module: module}
      end

      for {event, params} <- @handlers do
        test "#{event} rebuilds the form with the block uid", %{user: user, module: module} do
          belongs_to = unquote(belongs_to)
          event = unquote(event)
          params = unquote(Macro.escape(params))

          changeset = base_changeset(belongs_to, module, user)
          uid = uid_of(changeset, belongs_to)

          # Guard the premise: the fixture really does carry a uid, so a nil in
          # the rebuilt id can only come from the handler.
          assert is_binary(uid) and uid != ""

          socket = socket_for(changeset, belongs_to, module)
          assert {:halt, socket} = Events.handle_block_event(event, params, socket)

          assert socket.assigns.form.id == expected_form_id(uid, belongs_to)
          refute socket.assigns.form.id in ["entry_block_form-", "child_block_form-"]
        end
      end

      # The var reset handlers rebuild each var from the module default via a
      # plain map. That map was hand-pruned of `Var`'s associations, and the
      # list never grew the `:video` and `:gallery` relations added later — so
      # both arrived at `put_assoc/3` as `%Ecto.Association.NotLoaded{}`, which
      # raises `UndefinedFunctionError` on `__changeset__/0` and kills the
      # editor LiveView. Every var type hit it, video/gallery vars included.
      test "reset_vars carries media vars without a NotLoaded assoc", %{
        user: user,
        module: module
      } do
        belongs_to = unquote(belongs_to)

        {:ok, module} =
          Brando.Content.update_module(
            module,
            %{
              vars:
                Enum.map(module.vars, fn var ->
                  var |> Map.from_struct() |> Map.put(:type, :video)
                end)
            },
            user
          )

        changeset = base_changeset(belongs_to, module, user)
        socket = socket_for(changeset, belongs_to, module)

        assert {:halt, socket} = Events.handle_block_event("reset_vars", %{}, socket)

        vars = vars_of(socket, belongs_to)
        keys = vars |> Enum.map(&Changeset.get_field(&1, :key)) |> Enum.sort()

        assert keys == ["subtitle", "title"]
        assert Enum.all?(vars, &(Changeset.get_field(&1, :type) == :video))
      end
    end
  end
end
