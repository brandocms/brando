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

  defmodule TestPlayback do
    use Ecto.Schema

    embedded_schema do
      field :autoplay, :boolean
      field :controls, :boolean
    end
  end

  describe "override_toggle_group/1" do
    # A block form round-trips through params, so `field.value` arrives as the
    # string the hidden input submitted rather than the changeset's boolean.
    # Strict `== true` drew an inherited `autoplay: true` as off, and the first
    # click then wrote `false` because `toggle_override` negates the changeset's
    # real value.
    # `field.value` is only a string when the cast records no change, i.e. when
    # the stored value already equals what the form submits — which is every
    # block that already carries its module template's settings.
    setup do
      form =
        %TestPlayback{autoplay: true, controls: false}
        |> cast(%{"autoplay" => "true", "controls" => "false"}, [:autoplay, :controls])
        |> to_form(as: :block_data)

      assert form[:autoplay].value == "true", "setup must produce a string value"

      %{form: form}
    end

    test "a true that came back as a string still renders the toggle on", %{form: form} do
      html = render_group([{form[:autoplay], "Autoplay", nil}])

      assert html =~ "override-toggle-btn active"
      assert html =~ ~s(value="true")
    end

    test "a false matching the record's value is not treated as an override", %{form: form} do
      html = render_group([{form[:controls], "Controls", nil}])

      refute html =~ "active"
      refute html =~ "override-reset-inline"
      refute html =~ "override-reset-all"
    end

    test "a false against a record that has the setting on is an override", %{form: form} do
      html = render_group([{form[:controls], "Controls", true}])

      assert html =~ "override-reset-inline"
      assert html =~ "override-reset-all"
    end

    defp render_group(fields) do
      render_component(&Input.override_toggle_group/1, %{
        label: "Video playback",
        target: "block-target",
        fields: fields
      })
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

  test "password confirmation accepts the HTML-safe labels produced by Blueprint forms" do
    form = to_form(%{"password" => nil, "password_confirmation" => nil}, as: :user)

    for label <- ["Password", Phoenix.HTML.raw("Password")] do
      html =
        render_component(&Input.password/1, %{
          field: form[:password],
          label: label,
          opts: [confirmation: true]
        })

      assert html =~ "Password [confirm]"
      assert html =~ ~s(for="user_password_confirmation")
      assert html =~ ~s(name="user[password_confirmation]")
    end
  end
end
