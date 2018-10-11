defmodule Brando.Meta.SchemaTest do
  use ExUnit.Case, async: true
  use Plug.Test

  @schema %{test: "test"}

  defmodule Meta do
    @moduledoc false
    use Brando.Meta.Schema,
      singular: "post",
      plural: "posts",
      repr: fn schema -> "#{schema.test}" end,
      hidden_fields: [:id],
      fields: [
        id: "ID",
        language: "Language"
      ]
  end

  test "__name__" do
    assert Meta.__name__(:singular) == "post"
    assert Meta.__name__(:plural) == "posts"
  end

  test "__repr__" do
    assert Meta.__repr__(@schema) == "test"
  end

  test "__keys__" do
    assert Meta.__keys__() == [:id, :language]
  end

  test "__hidden_fields__" do
    assert Meta.__hidden_fields__() == [:id]
  end
end
