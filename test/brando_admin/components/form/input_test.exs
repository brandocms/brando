defmodule BrandoAdmin.Components.Form.InputTest do
  use ExUnit.Case, async: false

  import Brando.Test.Support, only: [put_test_env: 2]
  import Ecto.Changeset, only: [cast: 3]
  import Phoenix.Component, only: [to_form: 2]
  import Phoenix.LiveViewTest, only: [render_component: 2]

  alias BrandoAdmin.Components.Form.Input

  defmodule TestEntry do
    use Ecto.Schema

    embedded_schema do
      field :title, :string
      field :body, :string
      field :meta_description, :string
    end
  end

  test "meta_description textarea renders AI action when model comes from app config" do
    put_test_env(Brando.AI,
      default_model: "openai:gpt-4o-mini",
      providers: [openai: [api_key: "test-openai-key"]]
    )

    form =
      %TestEntry{}
      |> cast(%{}, [:title, :meta_description])
      |> to_form(as: :page)

    html =
      render_component(&Input.textarea/1, %{
        field: form[:meta_description],
        label: "META description",
        target: "form-target",
        opts: [
          ai: [
            prompt: "Write a succinct meta description",
            context: [:title]
          ]
        ]
      })

    assert html =~ ~s(phx-click="ai_generate_input")
    assert html =~ ~s(phx-value-field_key="meta_description")
    assert html =~ ~s(phx-value-field_name="page[meta_description]")
  end

  test "meta_description textarea hides AI action when no model is available" do
    Application.put_env(:brando, Brando.AI, providers: [openai: [api_key: "test-openai-key"]])

    form =
      %TestEntry{}
      |> cast(%{}, [:title, :body, :meta_description])
      |> to_form(as: :page)

    html =
      render_component(&Input.textarea/1, %{
        field: form[:meta_description],
        label: "META description",
        target: "form-target",
        opts: [
          ai: [
            prompt: "Write a succinct meta description",
            context: [:title]
          ]
        ]
      })

    refute html =~ ~s(phx-click="ai_generate_input")
  end

  test "rich_text renders AI action when model comes from app config" do
    put_test_env(Brando.AI,
      default_model: "openai:gpt-4o-mini",
      providers: [openai: [api_key: "test-openai-key"]]
    )

    form =
      %TestEntry{}
      |> cast(%{}, [:title, :body, :meta_description])
      |> to_form(as: :page)

    html =
      render_component(&Input.rich_text/1, %{
        field: form[:body],
        label: "Body",
        target: "form-target",
        opts: [
          ai: [
            prompt: "Write body copy",
            context: [:title]
          ]
        ]
      })

    assert html =~ ~s(phx-click="ai_generate_input")
    assert html =~ ~s(phx-value-field_key="body")
    assert html =~ ~s(phx-value-field_name="page[body]")
  end

  test "text input renders the placeholder attribute" do
    form =
      %TestEntry{}
      |> cast(%{}, [:title])
      |> to_form(as: :page)

    html =
      render_component(&Input.text/1, %{
        field: form[:title],
        label: "Title",
        placeholder: "Enter a title"
      })

    assert html =~ ~s(placeholder="Enter a title")
  end
end
