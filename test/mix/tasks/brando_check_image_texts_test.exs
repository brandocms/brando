defmodule Mix.Tasks.Brando.Check.ImageTextsTest do
  use ExUnit.Case, async: false
  use Brando.ConnCase

  alias Brando.Factory
  alias Mix.Tasks.Brando.Check.ImageTexts

  test "lists module templates that print an image's texts without a language" do
    user = Factory.insert(:random_user)

    {:ok, _} =
      Brando.Content.create_module(
        Factory.params_for(:module, %{
          name: %{"en" => "Cover caption"},
          code: "<figure>{% picture entry.cover %}\n<figcaption>{{ entry.cover.title }}</figcaption></figure>"
        }),
        user
      )

    {:ok, _} =
      Brando.Content.create_module(
        Factory.params_for(:module, %{name: %{"en" => "Already fine"}, code: "{{ entry.cover.alt | i18n }}"}),
        user
      )

    findings = ImageTexts.scan([])

    assert [%{kind: "Module", name: "Cover caption", line: 2, text: "{{ entry.cover.title }}"}] =
             Enum.filter(findings, &(&1.name in ["Cover caption", "Already fine"]))
  end
end
