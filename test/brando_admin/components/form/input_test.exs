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

  defmodule TestMarkets do
    use Ecto.Schema

    embedded_schema do
      field :area_served, Brando.Type.StringList, default: []
    end
  end

  defmodule TestI18n do
    use Ecto.Schema

    embedded_schema do
      field :position, :map
    end
  end

  describe "i18n_text/1" do
    # Blueprint labels can arrive HTML-safe; interpolating one into an
    # aria-label crashed the whole form.
    test "renders with an HTML-safe label, its text in each tab's aria-label" do
      form = %TestI18n{} |> cast(%{"position" => %{"en" => "Designer"}}, [:position]) |> to_form(as: :employee)

      html = render_component(&Input.i18n_text/1, field: form[:position], label: {:safe, "Position"}, opts: [])

      assert html =~ ~s(value="Designer")
      assert html =~ ~r/aria-label="Position \(/
    end
  end

  describe "radios/1" do
    test "options may come from a function given the form, as a select's can" do
      form = %TestEntry{} |> cast(%{"title" => "m"}, [:title]) |> to_form(as: :entry)

      options = fn %Phoenix.HTML.Form{} = given, opts ->
        assert given.name == "entry"
        assert Keyword.has_key?(opts, :options)
        [%{label: "Small", value: "s"}, %{label: "Medium", value: "m"}]
      end

      html = render_component(&Input.radios/1, field: form[:title], label: "Size", opts: [options: options])

      assert html =~ "Small"
      assert html =~ ~r/value="m"[^>]*checked/
    end
  end

  describe "checkbox/1" do
    test "has one presence slot, the field label's, so its id is unique" do
      form = %TestEntry{} |> cast(%{}, [:title]) |> to_form(as: :entry)

      html = render_component(&Input.checkbox/1, field: form[:title], label: "Confirmed", opts: [])

      assert length(Regex.scan(~r/id="entry_title-field-presence"/, html)) == 1
    end
  end

  describe "input/1 with type :string_list" do
    defp markets_form(params) do
      %TestMarkets{}
      |> cast(params, [:area_served])
      |> to_form(as: :config)
    end

    test "renders one text input per value plus a trailing empty one" do
      form = markets_form(%{"area_served" => ["Norway", "Europe"]})
      html = render_component(&Input.input/1, type: :string_list, field: form[:area_served])

      assert html =~ ~s(name="config[area_served][]")
      assert html =~ ~s(id="config_area_served_0")
      assert html =~ ~s(value="Norway")
      assert html =~ ~s(value="Europe")
      assert html =~ ~s(id="config_area_served_2")
      assert length(Regex.scan(~r/<input/, html)) == 3
    end

    test "a legacy comma string renders as rows" do
      form = markets_form(%{"area_served" => "Norway, Europe"})
      html = render_component(&Input.input/1, type: :string_list, field: form[:area_served])
      assert html =~ ~s(value="Norway")
      assert html =~ ~s(value="Europe")
    end

    test "an empty list renders only the empty row" do
      form = markets_form(%{})
      html = render_component(&Input.input/1, type: :string_list, field: form[:area_served])
      assert length(Regex.scan(~r/<input/, html)) == 1
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

  describe "AI" do
    # `ai:` on a Blueprint input runs as the action :generate
    defp generate_action do
      Brando.Blueprint.Forms.AIAction.generate([prompt: "Write a succinct meta description", context: [:title]], :ai)
    end

    defp render_input(fun, field, assigns) do
      form = %TestEntry{} |> cast(%{}, [:title, :body, :meta_description]) |> to_form(as: :page)
      render_component(fun, Map.merge(%{field: form[field], label: "Label", target: "form-target", opts: []}, assigns))
    end

    test "an input's Generate is an action whose result is a suggestion, not a button that writes the field" do
      put_test_env(Brando.AI, default_model: "openai:gpt-4o-mini", providers: [openai: [api_key: "test-openai-key"]])

      for fun <- [&Input.textarea/1, &Input.text/1] do
        html = render_input(fun, :meta_description, %{ai_actions: [generate_action()], form_id: "page_form"})

        assert html =~ ~s(phx-click="run_field_action")
        assert html =~ ~s(phx-value-action="generate")
        assert html =~ "Generate"
        assert html =~ ~s(data-testid="field-ai-suggestion")
        refute html =~ "ai_generate_input"
        refute html =~ "ai-generate-button"
      end
    end

    test "offers no action when no model is available" do
      put_test_env(Brando.AI, providers: [openai: [api_key: "test-openai-key"]])

      html = render_input(&Input.textarea/1, :meta_description, %{ai_actions: [generate_action()], form_id: "page_form"})

      refute html =~ "run_field_action"
    end

    test "Write with AI is on in an entry form's rich text whenever AI is configured" do
      put_test_env(Brando.AI, default_model: "openai:gpt-4o-mini", providers: [openai: [api_key: "test-openai-key"]])

      html = render_input(&Input.rich_text/1, :body, %{form_id: "page_form"})

      assert html =~ ~s(data-tiptap-ai="true")
      assert html =~ ~s(data-tiptap-field="body")
      assert html =~ ~s(name="page[body]")
    end

    test "Write with AI is off with write_with_ai: false, outside an entry form and without AI" do
      put_test_env(Brando.AI, default_model: "openai:gpt-4o-mini", providers: [openai: [api_key: "test-openai-key"]])

      assert render_input(&Input.rich_text/1, :body, %{form_id: "page_form", opts: [write_with_ai: false]}) =~
               ~s(data-tiptap-ai="false")

      assert render_input(&Input.rich_text/1, :body, %{}) =~ ~s(data-tiptap-ai="false")

      put_test_env(Brando.AI, enabled: false, default_model: "openai:gpt-4o-mini")
      assert render_input(&Input.rich_text/1, :body, %{form_id: "page_form"}) =~ ~s(data-tiptap-ai="false")
    end
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

  test "password inputs never render the stored value, only what was typed" do
    stored = %Brando.Users.User{password: "$2b$12$storedhashstoredhash"}

    untouched = stored |> Ecto.Changeset.change() |> to_form(as: :user)

    html =
      render_component(&Input.password/1, %{field: untouched[:password], label: "Password", opts: [confirmation: true]})

    refute html =~ "storedhash"

    typed =
      stored
      |> cast(%{"password" => "typed-pass", "password_confirmation" => "typed-conf"}, [:password])
      |> to_form(as: :user)

    html = render_component(&Input.password/1, %{field: typed[:password], label: "Password", opts: [confirmation: true]})

    assert html =~ ~s(value="typed-pass")
    assert html =~ ~s(value="typed-conf")
  end
end
