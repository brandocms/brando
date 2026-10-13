defmodule Brando.Migration.LegacyMediaRepairTest do
  use ExUnit.Case, async: true

  alias Brando.Migration.LegacyMediaRepair

  @index LegacyMediaRepair.index_images([
           {10, "images/site/posts/team.png"},
           {20, "images/site/posts/team.jpg"},
           {30, "images/site/logo.png"},
           {40, "images/site/posts/logo.svg"},
           {50, "images/site/posts/a.jpg"},
           {60, "images/site/posts/b.png"},
           {70, "images/site/posts/twin.jpg"},
           {80, "images/site/posts/twin.png"}
         ])

  defp resolve(path, sizes), do: LegacyMediaRepair.resolve_image(@index, %{"path" => path, "sizes" => sizes})

  test "an exact path wins over an image its sizes name by stem" do
    assert {:link_image, 20, "images/site/posts/team.jpg"} =
             resolve("/media/images/site/posts/team.jpg", %{"small" => "images/site/posts/small/team.jpg"})

    # An SVG's sizes name the file itself; dropping a folder names logo.png
    assert {:link_image, 40, _} = resolve("images/site/posts/logo.svg", %{"small" => "images/site/posts/logo.svg"})
  end

  test "a path that agrees with its sizes and has no row is made" do
    assert {:make_image, "images/site/posts/gone.jpg"} =
             resolve("/media/images/site/posts/gone.jpg", %{"small" => "/media/images/site/posts/small/gone.jpg"})
  end

  test "a stale path follows its sizes, and is not linked on its own" do
    # The sizes name b, which 0.53 displayed
    assert {:link_image, 60, _} = resolve("images/site/posts/a.jpg", %{"small" => "images/site/posts/small/b.jpg"})

    # The sizes name c, which has no row: a, live, is not linked in its place
    assert {:skip, "its path names images/site/posts/a.jpg and its sizes another image, which has no row"} =
             resolve("images/site/posts/a.jpg", %{"small" => "images/site/posts/small/c.jpg"})

    assert {:skip, "several images have the name its sizes give"} =
             resolve("images/site/posts/a.jpg", %{"small" => "images/site/posts/small/twin.jpg"})
  end
end
