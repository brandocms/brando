defmodule Brando.VillainTest do
  defmodule OtherParser do
    @behaviour Brando.Villain.Parser

    def text(%{"text" => _, "type" => _}) do
      "other parser"
    end

    def map(_), do: nil
    def blockquote(_), do: nil
    def columns(_), do: nil
    def divider(_), do: nil
    def header(_), do: nil
    def image(_), do: nil
    def list(_), do: nil
    def slideshow(_), do: nil
    def video(_), do: nil
  end

  use Brando.ConnCase
  use ExUnit.Case, async: true
  alias Brando.Factory

  @parser_mod Brando.Villain.Parser.Default

  setup do
    user = Factory.insert(:user)
    category = Factory.insert(:image_category, creator: user)
    series = Factory.insert(:image_series, creator: user, image_category: category)
    {:ok, %{user: user, category: category, series: series}}
  end

  test "parse" do
    assert Brando.Villain.parse("", @parser_mod) == ""
    assert Brando.Villain.parse(nil, @parser_mod) == ""

    assert Brando.Villain.parse(
             ~s([{"type":"columns","data":[{"class":"col-md-6 six","data":[]},{"class":"col-md-6 six","data":[{"type":"markdown","data":{"text":"Markdown"}}]}]}]),
             @parser_mod
           ) ==
             "<div class=\"row\"><div class=\"col-md-6 six\"></div><div class=\"col-md-6 six\"><p>Markdown</p>\n</div></div>"

    assert Brando.Villain.parse(
             [
               %{
                 "type" => "text",
                 "data" => %{"text" => "**Some** text here.", "type" => "paragraph"}
               }
             ],
             @parser_mod
           ) == "<p><strong>Some</strong> text here.</p>\n"

    assert_raise FunctionClauseError, fn ->
      Brando.Villain.parse(%{"text" => "**Some** text here.", "type" => "paragraph"}, @parser_mod) ==
        ""
    end

    assert Brando.Villain.parse(
             [
               %{
                 "type" => "text",
                 "data" => %{"text" => "**Some** text here.", "type" => "paragraph"}
               }
             ],
             Brando.VillainTest.OtherParser
           ) == "other parser"

    assert_raise UndefinedFunctionError, fn ->
      Brando.Villain.parse(
        [
          %{"type" => "text", "data" => %{"text" => "**Some** text here.", "type" => "paragraph"}}
        ],
        Brando.VillainTest.NoneParser
      ) == "other parser"
    end
  end

  test "map_images", %{series: series, user: user} do
    Ecto.Changeset.change(%Brando.Image{
      image_series_id: series.id,
      creator_id: user.id,
      image: %Brando.Type.Image{
        credits: "Credits",
        optimized: false,
        path: "image/1.jpg",
        sizes: %{
          large: "image/large/1.jpg",
          medium: "image/medium/1.jpg",
          small: "image/small/1.jpg",
          thumb: "image/thumb/1.jpg",
          xlarge: "image/xlarge/1.jpg"
        },
        title: "Title one"
      }
    })
    |> Brando.repo().insert!

    images = Brando.repo().all(Brando.Image)

    assert Brando.Villain.map_images(images) ==
             [
               %{
                 credits: "Credits",
                 sizes: %{
                   "large" => "/media/image/large/1.jpg",
                   "medium" => "/media/image/medium/1.jpg",
                   "small" => "/media/image/small/1.jpg",
                   "thumb" => "/media/image/thumb/1.jpg",
                   "xlarge" => "/media/image/xlarge/1.jpg"
                 },
                 src: "/media/image/1.jpg",
                 thumb: "/media/image/thumb/1.jpg",
                 title: "Title one"
               }
             ]
  end
end
