defmodule BrandoAdmin.Components.Content.ListSortHandleTest do
  # A sortable list's rows can be dragged only under a sort that shows their
  # stored order. Under any other sort the handle column is left out, and the
  # sort menu marks the order that allows dragging.
  use ExUnit.Case, async: true
  import Phoenix.LiveViewTest, only: [render_component: 2]

  alias BrandoAdmin.Components.Content.List
  alias BrandoAdmin.Components.Content.List.Row

  @by_title %{key: :default, label: "Title", order: "asc title"}
  @by_sequence %{key: :site_order, label: "Order", order: [{:asc, :sequence}, {:desc, :inserted_at}]}

  test "the handle column is only there under the stored order" do
    assert render_component(&Row.handle/1, active_sort: @by_sequence) =~ "sequence-handle"
    assert render_component(&Row.handle/1, active_sort: nil) =~ "sequence-handle"
    refute render_component(&Row.handle/1, active_sort: @by_title) =~ "seq"
  end

  test "the sort menu marks the order rows can be dragged in, when the list is sortable" do
    sorts = [@by_title, @by_sequence]
    opts = [active_sort: @by_title, sorts: sorts, schema: Brando.Pages.Page, on_update: "update_sort"]

    html = render_component(&List.sorts/1, [sortable?: true] ++ opts)
    assert [_] = Regex.scan(~r/class="sort-note"/, html)

    refute render_component(&List.sorts/1, [sortable?: false] ++ opts) =~ "sort-note"
  end
end
