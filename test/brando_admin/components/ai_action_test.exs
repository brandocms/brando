defmodule BrandoAdmin.Components.AIActionTest do
  use ExUnit.Case, async: true

  import Phoenix.Component, only: [sigil_H: 2]
  import Phoenix.LiveViewTest, only: [rendered_to_string: 1]

  alias BrandoAdmin.Components.AIAction

  defp find(html, selector), do: html |> Floki.parse_fragment!() |> Floki.find(selector)

  test "a button with the sparkles icon and the label" do
    assigns = %{}

    html =
      rendered_to_string(~H"""
      <AIAction.button phx-click="suggest_alt_text">Suggest alt text</AIAction.button>
      """)

    assert [{"button", attrs, _}] = find(html, "button.ai-action")
    assert {"type", "button"} in attrs
    assert {"phx-click", "suggest_alt_text"} in attrs
    assert find(html, "button.ai-action > [data-icon].lucide-sparkles") != []
    assert html =~ "Suggest alt text"
    assert find(html, "[aria-busy]") == []
  end

  test "a link when given an href" do
    assigns = %{}

    html =
      rendered_to_string(~H"""
      <AIAction.button href="/admin/assistant" target="_blank" rel="noopener">Build with AI</AIAction.button>
      """)

    assert [{"a", attrs, _}] = find(html, "a.ai-action")
    assert {"href", "/admin/assistant"} in attrs
    assert {"target", "_blank"} in attrs
  end

  test "sizes and the busy state are classes" do
    assigns = %{}

    html =
      rendered_to_string(~H"""
      <AIAction.button size={:compact}>A</AIAction.button>
      <AIAction.button size={:icon} aria-label="Generate with AI" />
      <AIAction.button busy disabled>C</AIAction.button>
      """)

    assert find(html, ".ai-action.is-compact") != []
    assert find(html, ".ai-action.is-icon[aria-label]") != []
    assert [{"button", attrs, _}] = find(html, ".ai-action.is-busy")
    assert {"aria-busy", "true"} in attrs
    assert {"disabled", "disabled"} in attrs
  end

  test "the primary variant fills the confirm step of a costed request" do
    assigns = %{}

    html =
      rendered_to_string(~H"""
      <AIAction.button variant={:primary} phx-click="describe">Describe 3 images</AIAction.button>
      <AIAction.button>Suggest alt text</AIAction.button>
      """)

    assert [{"button", _, _}] = find(html, "button.ai-action.is-primary")
    assert find(html, "button.ai-action.is-primary > [data-icon].lucide-sparkles") != []
    assert length(find(html, "button.ai-action")) == 2
  end
end
