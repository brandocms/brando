defmodule BrandoAdmin.Components.Form.FunctionInputTest do
  @moduledoc """
  A blueprint input can be a function component
  (`input :size, &MyAdmin.size_picker/1`). `Primitives.input/1` used to put the
  function itself in the wrapper's `data-component` attribute, which raised.
  """
  use ExUnit.Case, async: true

  import Phoenix.Component
  import Phoenix.LiveViewTest, only: [render_component: 2]

  alias BrandoAdmin.Components.Form.Primitives

  def picker(assigns) do
    ~H"""
    <span class="picker">{@field.name}</span>
    """
  end

  test "renders a function component input, named in data-component" do
    form =
      %Brando.Pages.Page{}
      |> Ecto.Changeset.change()
      |> to_form(as: :page)

    html =
      render_component(&Primitives.input/1, %{
        field: form[:title],
        label: "Title",
        instructions: nil,
        placeholder: nil,
        opts: [],
        type: &__MODULE__.picker/1,
        current_user: nil
      })

    assert html =~ ~s(<span class="picker">page[title]</span>)
    assert html =~ ~s(data-component="#{inspect(__MODULE__)}.picker/1")
  end
end
