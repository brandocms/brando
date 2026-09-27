defmodule Brando.Blueprint.DraftRequiredTest do
  use ExUnit.Case, async: true

  defmodule Post do
    @moduledoc false
    use Brando.Blueprint,
      application: "Brando",
      domain: "DraftRequiredTest",
      schema: "Post",
      singular: "post",
      plural: "posts",
      gettext_module: Brando.Gettext

    identifier "{{ entry.title }}"

    attributes do
      # A plain status field: the Status trait's protocol is consolidated
      # before test modules compile.
      attribute :status, :enum, values: [:draft, :published]
      attribute :title, :string, required: true
      attribute :body, :text, required: true
    end
  end

  defp errors(params) do
    %Post{}
    |> Post.changeset(params, %{id: 1})
    |> Map.fetch!(:errors)
    |> Keyword.keys()
    |> Enum.sort()
  end

  test "a draft needs the fields its identifier shows, and nothing else" do
    assert errors(%{status: :draft}) == [:title]
    assert errors(%{status: :draft, title: "Half done"}) == []
  end

  test "anything but a draft needs every required field" do
    assert errors(%{status: :published}) == [:body, :title]
  end

  test "the identifier's fields are known by name" do
    assert Post.__identifier_fields__() == ["title"]
  end
end
