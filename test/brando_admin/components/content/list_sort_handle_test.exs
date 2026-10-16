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

  describe "the sort shown for the URL" do
    test "is the one it names, or the one with its order, or the first" do
      sorts = [@by_title, @by_sequence]
      assert List.active_sort(sorts, %{}) == @by_title
      assert List.active_sort(sorts, %{"sort" => "site_order"}) == @by_sequence
      assert List.active_sort(sorts, %{"order" => "asc sequence, desc inserted_at"}) == @by_sequence
      assert List.active_sort(sorts, %{"order" => %{"asc" => "title"}}) == @by_title
      assert List.active_sort([], %{"order" => "asc title"}) == nil
    end

    # A menu link carries the listing's `query.order`, which need not be a sort
    test "is the URL's own order when no sort has it, and allows dragging by sequence" do
      sort = List.active_sort([@by_title], %{"order" => "asc sequence, desc inserted_at"})
      assert sort.label == "Manual order"
      assert Row.ordered_by_sequence?(sort)
      assert render_component(&Row.handle/1, active_sort: sort) =~ "sequence-handle"

      assert %{label: "Custom order"} = List.active_sort([@by_title], %{"order" => "desc inserted_at"})
    end
  end

  test "the sort menu marks the order rows can be dragged in, when the list is sortable" do
    sorts = [@by_title, @by_sequence]
    opts = [active_sort: @by_title, sorts: sorts, schema: Brando.Pages.Page, on_update: "update_sort"]

    html = render_component(&List.sorts/1, [sortable?: true] ++ opts)
    assert [_] = Regex.scan(~r/<small>/, html)
    assert html =~ "Rows can be dragged in this order"
    # The current sort is the selected row
    assert [_] = Regex.scan(~r/is-selected/, html)

    refute render_component(&List.sorts/1, [sortable?: false] ++ opts) =~ "<small>"
  end
end
