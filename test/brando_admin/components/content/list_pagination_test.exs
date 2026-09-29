defmodule BrandoAdmin.Components.Content.ListPaginationTest do
  use ExUnit.Case, async: true

  alias BrandoAdmin.Components.Content.List

  describe "page_window/2" do
    test "offers every page when there are few" do
      assert List.page_window(1, 1) == [1]
      assert List.page_window(3, 7) == [1, 2, 3, 4, 5, 6, 7]
    end

    test "keeps the first, the last and two pages on each side of the current one" do
      assert List.page_window(1, 41) == [1, 2, 3, :gap, 41]
      assert List.page_window(20, 41) == [1, :gap, 18, 19, 20, 21, 22, :gap, 41]
      assert List.page_window(41, 41) == [1, :gap, 39, 40, 41]
    end

    test "shows a single skipped page instead of a gap" do
      assert List.page_window(5, 41) == [1, 2, 3, 4, 5, 6, 7, :gap, 41]
      assert List.page_window(4, 8) == [1, 2, 3, 4, 5, 6, 7, 8]
    end
  end
end
