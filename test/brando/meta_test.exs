defmodule Brando.Meta.ModelTest do
  use ExUnit.Case, async: true
  use Plug.Test

  @model %{test: "test"}

  defmodule Meta do
    @moduledoc false
    use Brando.Meta.Model, [
      singular: "post",
      plural: "posts",
      repr: fn (model) -> "#{model.test}" end,
      hidden_fields: [:id],
      fields: [
        id: "ID",
        language: "Language"
      ]
    ]

  end

  test "__name__" do
    assert Meta.__name__(:singular) == "post"
    assert Meta.__name__(:plural) == "posts"
  end

  test "__repr__" do
    assert Meta.__repr__(@model) == "test"
  end

  test "__keys__" do
    assert Meta.__keys__ == [:id, :language]
  end

  test "__hidden_fields__" do
    assert Meta.__hidden_fields__ == [:id]
  end
end
