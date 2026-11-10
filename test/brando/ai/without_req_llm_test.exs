defmodule Brando.AI.WithoutReqLLMTest do
  # `req_llm` is an optional dependency. Brando's test build has it, so these
  # tests make `Brando.AI.available?/0` answer as it does in a site without
  # it: a node-wide switch, hence async: false. The compiled build without it
  # is checked by Brando.AI.OptionalDependencyTest and the consumer smoke.
  use Brando.LiveCase, async: false

  alias Brando.AI
  alias Brando.Doctor.Checks.Configuration
  alias BrandoAdmin.Components.Form.MetaDrawer
  alias Phoenix.LiveView.JS

  @available_key {Brando.AI, :req_llm_available?}

  setup do
    previous = :persistent_term.get(@available_key, nil)
    :persistent_term.put(@available_key, false)

    on_exit(fn ->
      if is_nil(previous),
        do: :persistent_term.erase(@available_key),
        else: :persistent_term.put(@available_key, previous)
    end)

    # A site configured for AI, as one that used it before req_llm became optional.
    put_test_env(Brando.AI,
      default_model: "openai:gpt-4o-mini",
      providers: [openai: [api_key: "test-openai-key"]],
      client: Brando.AI.Cassette
    )

    put_test_env(Brando.AI.Agent, model: "openai:gpt-4o-mini")
    :ok
  end

  test "AI is off whatever the config says, and requests return :disabled" do
    refute AI.available?()
    refute AI.enabled?()
    refute AI.configured?()
    refute AI.configured?(model: "openai:gpt-4o", api_key: "a-key")
    assert AI.request() == {:error, :disabled}
    assert AI.generate_text("Describe the lighthouse") == {:error, :disabled}
    refute AI.Agent.available?()
    refute Brando.Content.ModuleSketch.available?()
  end

  test "alt text is not drafted, before the image is read" do
    assert Brando.Images.AltText.describe(-1) == {:error, :disabled}
  end

  test "the model catalogue is not read: a model's prices are unknown" do
    assert {:ok, %{input_price: nil, output_price: nil, image_input?: nil}} = AI.model_info()
  end

  test "the AI settings that need req_llm are warned about at boot" do
    assert AI.settings() == ["Brando.AI models", "Brando.AI providers", "Brando.AI.Agent model"]
    assert [warning] = AI.dependency_warnings()
    assert warning =~ "Brando.AI models, Brando.AI providers, Brando.AI.Agent model set"
    assert warning =~ ~s|Add {:req_llm, "~> 1.29"} to deps in mix.exs|

    put_test_env(Brando.AI, enabled: false, default_model: "openai:gpt-4o-mini")
    assert AI.settings() == []
    assert AI.dependency_warnings() == []

    put_test_env(Brando.AI.Agent, [])

    # Site prompts carry their own model and key, under `prompts:` or `fields:`
    for key <- [:prompts, :fields] do
      put_test_env(Brando.AI, [{key, [alt: [model: "openai:gpt-4o", api_key: "a-key"]]}])
      assert AI.settings() == ["Brando.AI prompts"]
      assert [_warning] = AI.dependency_warnings()
    end

    # A provider key on Brando.AI itself
    put_test_env(Brando.AI, openai_api_key: "a-key")
    assert AI.settings() == ["Brando.AI providers"]

    put_test_env(Brando.AI, [])
    assert AI.dependency_warnings() == []

    # A provider key given to ReqLLM itself
    original = Application.fetch_env(:req_llm, :anthropic_api_key)
    Application.put_env(:req_llm, :anthropic_api_key, "a-key")

    on_exit(fn ->
      case original do
        {:ok, key} -> Application.put_env(:req_llm, :anthropic_api_key, key)
        :error -> Application.delete_env(:req_llm, :anthropic_api_key)
      end
    end)

    assert AI.settings() == ["req_llm API keys"]
  end

  test "the doctor warns about AI settings without req_llm, with the dependency to add" do
    assert {:warning, item, "AI configured without req_llm", fix} = Configuration.ai_dependency()
    assert item =~ "Brando.AI models"
    assert fix =~ ~s|add {:req_llm, "~> 1.29"} to deps in mix.exs and run mix deps.get|
    assert {:ok, _item, nil} = Configuration.assistant()

    assert {:ok, _item, nil} = Configuration.ai_dependency(false, [])
    assert {:ok, _item, nil} = Configuration.ai_dependency(true, ["Brando.AI models"])
  end

  test "the dependency Brando names is the one its mix.exs declares" do
    {:req_llm, requirement, opts} = List.keyfind(Mix.Project.config()[:deps], :req_llm, 0)
    assert AI.dependency() == {:req_llm, requirement}
    assert opts[:optional]
  end

  describe "the admin" do
    test "shows no AI actions on the meta fields" do
      html =
        render_component(&MetaDrawer.render/1, %{
          id: "meta-drawer",
          form: %Brando.Pages.Page{} |> Ecto.Changeset.change() |> Phoenix.Component.to_form(as: :page),
          blueprint: nil,
          form_cid: "form-target",
          form_id: "page_form",
          parent_uploads: %{},
          current_user: nil,
          close: %JS{}
        })

      refute html =~ "run_field_action"
    end

    test "hides Build with AI in the block editor", %{conn: conn} do
      page = Factory.insert(:page, title: "Empty page", uri: "empty-page", language: :en)
      {view, _html} = live_form(conn, "/admin/pages/update/#{page.id}")
      await_selector(view, ".blocks-welcome")
      refute has_element?(view, "[data-testid=build-with-ai]")
    end

    test "says on the assistant's screen that AI is not installed, with nothing to send", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/admin/assistant")
      assert has_element?(view, ".assistant-notice", "req_llm")
      assert has_element?(view, "#assistant-composer button[type=submit][disabled]")
    end

    test "leaves the assistant out of the menu", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/admin/pages")
      refute html =~ ~s(href="/admin/assistant")

      # With req_llm, the same settings put it there.
      :persistent_term.put(@available_key, true)
      {:ok, _view, html} = live(conn, "/admin/pages")
      assert html =~ ~s(href="/admin/assistant")
    end
  end
end
