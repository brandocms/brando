defmodule Brando.GraphQL.Queries.ImageQueriesTest do
  use ExUnit.Case, async: true
  use Brando.ConnCase

  alias Brando.Factory

  setup do
    u1 = Factory.insert(:random_user)
    opts = [context: %{current_user: u1}]

    {:ok, %{user: u1, opts: opts}}
  end

  @image_categories_query """
  query {
    imageCategories {
      id
      imageSeriesCount
      imageSeries {
        id
        images {
          image {
            focal
            alt
            title
            thumb: url(size: "thumb")
            medium: url(size: "medium")
            xlarge: url(size: "xlarge")
          }
        }
      }
    }
  }
  """

  test "the whole thing", %{opts: opts} do
    c1 = Factory.insert(:image_category)
    s1 = Factory.insert(:image_series, image_category: c1)
    s2 = Factory.insert(:image_series, image_category: c1)
    _i = Factory.insert(:image, image_series: s1)

    assert Absinthe.run(
             @image_categories_query,
             Brando.Integration.TestSchema,
             opts
           ) ==
             {
               :ok,
               %{
                 data: %{
                   "imageCategories" => [
                     %{
                       "id" => to_string(c1.id),
                       "imageSeriesCount" => 2,
                       "imageSeries" => [
                         %{
                           "id" => to_string(s1.id),
                           "images" => [
                             %{
                               "image" => %{
                                 "alt" => nil,
                                 "focal" => %Brando.Images.Focal{x: 50, y: 50},
                                 "medium" => "/media/image/medium/1.jpg",
                                 "thumb" => "/media/image/thumb/1.jpg",
                                 "title" => "Title one",
                                 "xlarge" => "/media/image/xlarge/1.jpg"
                               }
                             }
                           ]
                         },
                         %{"id" => to_string(s2.id), "images" => []}
                       ]
                     }
                   ]
                 }
               }
             }
  end
end
