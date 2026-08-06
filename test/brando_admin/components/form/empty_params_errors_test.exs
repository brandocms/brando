defmodule BrandoAdmin.Components.Form.EmptyParamsErrorsTest do
  # Phase 3 / F in the form audit.
  #
  # `assign_form/1`, `assign_refreshed_form/1` and `refresh_entry` all forced
  # `Map.put(:action, :validate)` onto a changeset built from EMPTY params. The
  # audit's claim was that it achieves nothing, and this pins why: both error
  # gates in `Form` route through `Phoenix.Component.used_input?/1`, which reads
  # `form.params` and nothing else. A form whose params are `%{}` has no used
  # input, so it cannot surface an error — with or without an action.
  #
  # There is no e2e coverage of validation-error display, so this test is what
  # makes dropping the forced action safe.
  use ExUnit.Case, async: false
  use Brando.ConnCase

  import Phoenix.Component, only: [to_form: 1]

  alias Brando.Factory
  alias Brando.Pages.Page
  alias Ecto.Changeset
  alias Phoenix.Component

  setup do
    {:ok, user: Factory.insert(:random_user)}
  end

  defp empty_params_form(ctx) do
    # A blank page fails its required validations, so the changeset genuinely
    # carries errors — the question is only whether the form surfaces them.
    to_form(Page.changeset(%Page{}, %{}, ctx.user))
  end

  test "an empty-params changeset does have errors to surface", ctx do
    changeset = Page.changeset(%Page{}, %{}, ctx.user)

    refute changeset.valid?
    refute changeset.errors == []
  end

  test "no field of an empty-params form counts as used input", ctx do
    form = empty_params_form(ctx)

    assert form.params == %{}

    for field <- [:title, :slug, :status, :language] do
      refute Phoenix.Component.used_input?(form[field]),
             "#{field} must not count as used input on an empty-params form"
    end
  end

  test "and so the error gate stays shut regardless of the changeset action", ctx do
    with_action = %{Page.changeset(%Page{}, %{}, ctx.user) | action: :validate}
    without_action = Page.changeset(%Page{}, %{}, ctx.user)

    for changeset <- [with_action, without_action] do
      form = to_form(changeset)

      assert Enum.filter([form[:title], form[:slug]], &Phoenix.Component.used_input?/1) == []
    end
  end

  test "a field the user DID touch still surfaces its error", ctx do
    # The control: this is the case the forced action looked like it existed
    # for. It works off `params`, so the real validate path is unaffected.
    changeset =
      %Page{}
      |> Page.changeset(%{"title" => ""}, ctx.user)
      |> Map.put(:action, :validate)

    form = to_form(changeset)

    assert Phoenix.Component.used_input?(form[:title])
    refute form[:title].errors == []
    refute Phoenix.Component.used_input?(form[:slug])
  end

  defp bare_socket(ctx, entry) do
    %Phoenix.LiveView.Socket{}
    |> Component.assign(:entry, entry)
    |> Component.assign(:schema, Page)
    |> Component.assign(:current_user, ctx.user)
  end

  test "assign_refreshed_form/1 builds a form with empty params", ctx do
    page = Factory.insert(:page, creator: ctx.user)
    socket = BrandoAdmin.Components.Form.assign_refreshed_form(bare_socket(ctx, page))

    assert socket.assigns.form.params == %{}
    assert %Changeset{} = socket.assigns.form.source
    refute Phoenix.Component.used_input?(socket.assigns.form[:title])
  end

  # The assertions above hold with or without the forced action, so on their own
  # they would pass against the pre-fix code. These two are the ones that fail if
  # `Map.put(:action, :validate)` comes back — they are the point of the file.
  test "assign_refreshed_form/1 leaves the changeset action unset", ctx do
    page = Factory.insert(:page, creator: ctx.user)
    socket = BrandoAdmin.Components.Form.assign_refreshed_form(bare_socket(ctx, page))

    assert socket.assigns.form.source.action == nil
  end

  test "assign_form/1 leaves the changeset action unset", ctx do
    page = Factory.insert(:page, creator: ctx.user)
    socket = BrandoAdmin.Components.Form.assign_form(bare_socket(ctx, page))

    assert socket.assigns.form.source.action == nil
    assert socket.assigns.form.params == %{}
  end
end
