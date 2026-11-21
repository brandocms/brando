defmodule BrandoAdmin.Components.Form.RefusedAndRepeatedSavesTest do
  @moduledoc """
  What the Form does with a save it refuses or repeats (#3773). These drive
  `handle_event/3` on a hand-built socket, as `SubmitProcessingFlagTest`
  does: the save collects its rows in a first round-trip, and what matters
  here is the changeset the second one builds.
  """

  use ExUnit.Case, async: false
  use Brando.ConnCase

  import ExUnit.CaptureLog, only: [with_log: 1]

  alias BrandoAdmin.Components.Form
  alias Phoenix.Component

  setup do
    user = Brando.Factory.insert(:random_user, role: :superuser)
    palette = Brando.Factory.insert(:palette, creator: user, status: :published, colors: [Brando.Factory.build(:color)])
    {:ok, user: user, palette: palette}
  end

  defp palette_socket(ctx, overrides) do
    %Phoenix.LiveView.Socket{}
    |> Component.assign(:id, "palette_form")
    |> Component.assign(:schema, Brando.Content.Palette)
    |> Component.assign(:singular, "palette")
    |> Component.assign(:context, Brando.Content)
    |> Component.assign(:entry, ctx.palette)
    |> Component.assign(:entry_id, ctx.palette.id)
    |> Component.assign(:current_user, ctx.user)
    |> Component.assign(:form_blueprint, Brando.Content.Palette.__form__(:default))
    |> Component.assign(:form, Phoenix.Component.to_form(Ecto.Changeset.change(ctx.palette)))
    |> Component.assign(:has_blocks?, false)
    |> Component.assign(:has_transformers?, false)
    |> Component.assign(:all_transformers_received?, true)
    |> Component.assign(:transformer_changesets, %{})
    |> Component.assign(:processing, true)
    |> Component.assign(:save_redirect_target, :self)
    |> Component.assign(:live_preview_active?, false)
    |> Component.assign(:fields_demanding_live_preview_reassign, [])
    |> then(fn socket ->
      Enum.reduce(overrides, socket, fn {k, v}, acc -> Component.assign(acc, k, v) end)
    end)
  end

  defp color_params(palette, name) do
    [color] = palette.colors
    %{"0" => %{"name" => name, "key" => color.key, "hex_value" => color.hex_value}}
  end

  describe "a kept field and an invalid row" do
    # Another editor's save replaced `instructions` after the browser drew
    # the form it sends (`_form_rev` older than the take): the form keeps
    # its own value for it (`stale_relations/2`, `keep_field/3`). A color
    # row in the same save has no name, which the row refuses.
    test "the save is refused, with the row's error, and the entry is left as it was", ctx do
      socket = palette_socket(ctx, taken_relations: %{instructions: 10})

      params = %{
        "_form_rev" => "1",
        "palette" => %{
          "name" => ctx.palette.name,
          "instructions" => "From the old form",
          "colors" => color_params(ctx.palette, "")
        }
      }

      {{:noreply, socket}, _log} = with_log(fn -> Form.handle_event("save", params, socket) end)

      refute socket.assigns.processing
      changeset = socket.assigns.form.source
      refute changeset.valid?
      assert [row] = changeset |> Ecto.Changeset.get_change(:colors) |> Enum.reject(&(&1.action == :replace))
      refute row.valid?
      assert Keyword.has_key?(row.errors, :name)
      # The kept field is the form's, not the old form's
      assert Ecto.Changeset.get_field(changeset, :instructions) == ctx.palette.instructions

      saved = Brando.Repo.get!(Brando.Content.Palette, ctx.palette.id)
      assert Enum.map(saved.colors, & &1.name) == Enum.map(ctx.palette.colors, & &1.name)
    end
  end
end
