defmodule Brando.VillainTest do
  defmodule OtherParser do
    @behaviour Brando.Villain.Parser

    def text(%{"text" => _, "type" => _}, _), do: "other parser"
    def datatable(_, _), do: nil
    def datasource(_, _), do: nil
    def markdown(_, _), do: nil
    def html(_, _), do: nil
    def svg(_, _), do: nil
    def map(_, _), do: nil
    def blockquote(_, _), do: nil
    def columns(_, _), do: nil
    def divider(_, _), do: nil
    def header(_, _), do: nil
    def image(_, _), do: nil
    def list(_, _), do: nil
    def slideshow(_, _), do: nil
    def video(_, _), do: nil
    def template(_, _), do: nil
    def comment(_, _), do: nil
  end

  use Brando.ConnCase
  use ExUnit.Case
  alias Brando.Factory

  setup_all do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Brando.repo())
    # we are setting :auto here so that the data persists for all tests,
    # normally (with :shared mode) every process runs in a transaction
    # and rolls back when it exits. setup_all runs in a distinct process
    # from each test so the data doesn't exist for each test.
    Ecto.Adapters.SQL.Sandbox.mode(Brando.repo(), :auto)

    user = Factory.insert(:random_user)
    category = Factory.insert(:image_category, creator: user)
    series = Factory.insert(:image_series, creator: user, image_category: category)
    image = Factory.insert(:image, creator: user, image_series: series)

    on_exit(fn ->
      # this callback needs to checkout its own connection since it
      # runs in its own process
      :ok = Ecto.Adapters.SQL.Sandbox.checkout(Brando.repo())
      Ecto.Adapters.SQL.Sandbox.mode(Brando.repo(), :auto)

      Brando.repo().delete(image)
      Brando.repo().delete(series)
      Brando.repo().delete(category)
      Brando.repo().delete(user)
      :ok
    end)

    {:ok, %{user: user, category: category, series: series, image: image}}
  end

  test "parse" do
    Application.put_env(:brando, Brando.Villain, parser: Brando.Villain.ParserTest.Parser)

    assert Brando.Villain.parse("") == ""
    assert Brando.Villain.parse(nil) == ""

    assert Brando.Villain.parse(
             ~s([{"type":"columns","data":[{"class":"col-md-6 six","data":[]},{"class":"col-md-6 six","data":[{"type":"markdown","data":{"text":"Markdown"}}]}]}])
           ) ==
             "<div class=\"row\"><div class=\"col-md-6 six\"></div><div class=\"col-md-6 six\"><p>Markdown</p>\n</div></div>"

    assert Brando.Villain.parse([
             %{
               "type" => "text",
               "data" => %{"text" => "**Some** text here.", "type" => "paragraph"}
             }
           ]) == "<p><strong>Some</strong> text here.</p>\n"

    assert_raise FunctionClauseError, fn ->
      Brando.Villain.parse(%{"text" => "**Some** text here.", "type" => "paragraph"}) ==
        ""
    end
  end

  test "list_villains" do
    assert Brando.Villain.list_villains() == [
             {Brando.Pages.Page, [{:villain, :data, :html}]},
             {Brando.Pages.PageFragment, [{:villain, :data, :html}]},
             {Brando.Pages.Page, [{:villain, :data, :html}]},
             {Brando.Pages.PageFragment, [{:villain, :data, :html}]}
           ]
  end

  test "map_images", %{image: image} do
    mapped_images =
      [image]
      |> Brando.Villain.map_images()
      |> Enum.map(&Map.delete(&1, :inserted_at))

    assert mapped_images ==
             [
               %{
                 credits: "Credits",
                 height: nil,
                 sizes: %{
                   "large" => "/media/image/large/1.jpg",
                   "medium" => "/media/image/medium/1.jpg",
                   "small" => "/media/image/small/1.jpg",
                   "thumb" => "/media/image/thumb/1.jpg",
                   "xlarge" => "/media/image/xlarge/1.jpg"
                 },
                 src: "/media/image/1.jpg",
                 thumb: "/media/image/thumb/1.jpg",
                 title: "Title one",
                 width: nil
               }
             ]
  end

  test "search_villains_for_text" do
    pf1 =
      Factory.insert(:page_fragment, %{
        data: [
          %{
            "type" => "text",
            "data" => %{"text" => "**Some** text here.", "type" => "paragraph"}
          }
        ]
      })

    _pf2 = Factory.insert(:page_fragment, %{data: []})
    _pf3 = Factory.insert(:page_fragment, %{data: []})

    pf4 =
      Factory.insert(:page_fragment, %{
        data: [
          %{
            "type" => "text",
            "data" => %{"text" => "**Some** text here.", "type" => "paragraph"}
          }
        ]
      })

    resulting_ids =
      Brando.Villain.search_villains_for_text(
        Brando.Pages.PageFragment,
        :data,
        "text"
      )

    assert resulting_ids === [pf1.id, pf4.id]
  end

  test "search_villains_for_regex" do
    pf1 =
      Factory.insert(:page_fragment, %{
        data: [
          %{
            "type" => "text",
            "data" => %{"text" => "**Some** ${GLOBAL:old} here.", "type" => "paragraph"}
          }
        ]
      })

    _pf2 = Factory.insert(:page_fragment, %{data: []})
    _pf3 = Factory.insert(:page_fragment, %{data: []})

    pf4 =
      Factory.insert(:page_fragment, %{
        data: [
          %{
            "type" => "text",
            "data" => %{"text" => "**Some** ${GLOBAL:really_old} here.", "type" => "paragraph"}
          }
        ]
      })

    resulting_ids =
      Brando.Villain.search_villains_for_regex(
        Brando.Pages.PageFragment,
        :data,
        "\\${GLOBAL:(\\w+)}"
      )

    assert resulting_ids === [pf1.id, pf4.id]
  end
end
