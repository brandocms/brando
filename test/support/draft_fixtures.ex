defmodule Brando.DraftFixtures do
  @moduledoc false
  def payload do
    var = %{"key" => "title", "type" => "string", "value" => "Original", "creator_id" => nil, "sequence" => 0}

    block = %{
      "uid" => "one",
      "sequence" => 0,
      "vars" => [var, %{var | "key" => "subtitle", "value" => "Subtitle"}],
      "refs" => [
        %{"name" => "text", "sequence" => 0, "data" => %{"type" => "text", "data" => %{"text" => "Body"}}},
        %{
          "name" => "gallery",
          "sequence" => 0,
          "gallery_id" => 12,
          "data" => %{"type" => "gallery", "data" => %{"gallery_object_overrides" => []}}
        }
      ],
      "children" => [%{"uid" => "child-one", "sequence" => 0, "vars" => [var]}, %{"uid" => "child-two", "sequence" => 0}],
      "block_identifiers" => [%{"identifier_id" => 1, "sequence" => 0}, %{"identifier_id" => 2, "sequence" => 0}],
      "table_rows" => [%{"id" => 1, "sequence" => 0, "vars" => [var]}, %{"id" => 2, "sequence" => 0}]
    }

    %{
      "main" => %{"title" => "Saved entry", "sequence" => 8, "image_id" => 10},
      "blocks" => %{"blocks" => [%{"sequence" => 0, "block" => block}, %{"sequence" => 0, "block" => %{"uid" => "two"}}]},
      "transformers" => %{"items" => [%{"id" => 3, "title" => "One"}, %{"id" => 4, "title" => "Two"}]},
      "modules" => %{"local:1" => %{"version" => 1}}
    }
  end

  def initialized(payload) do
    initialize = fn recurse, value ->
      cond do
        is_list(value) ->
          value
          |> Enum.with_index()
          |> Enum.map(fn {row, index} ->
            row = if is_map(row) && Map.has_key?(row, "sequence"), do: Map.put(row, "sequence", index), else: row
            recurse.(recurse, row)
          end)

        is_map(value) ->
          value = if Map.has_key?(value, "creator_id"), do: Map.put(value, "creator_id", 7), else: value
          Map.new(value, fn {key, child} -> {key, recurse.(recurse, child)} end)

        true ->
          value
      end
    end

    initialize.(initialize, payload)
    |> put_in(
      ["blocks", "blocks", Access.at(0), "block", "refs", Access.at(1), "data", "data", "gallery_object_overrides"],
      [
        %{"object_id" => "595", "object_type" => "image", "title" => nil, "use_default_title" => true},
        %{"object_id" => "596", "object_type" => "video", "muted" => nil, "use_default_muted" => true}
      ]
    )
  end
end
