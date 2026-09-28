defmodule Brando.Translations.EditCheckTest do
  use ExUnit.Case, async: false

  alias Brando.Translations.EditCheck

  setup do
    original = Application.get_env(:brando, Brando.AI)

    Application.put_env(:brando, Brando.AI,
      models: [default: "openai:gpt-4o-mini", evaluate: "typesafe:jev-1.13.0"],
      providers: [typesafe: [api_key: "test-typesafe-key"]]
    )

    on_exit(fn ->
      if original, do: Application.put_env(:brando, Brando.AI, original), else: Application.delete_env(:brando, Brando.AI)
    end)
  end

  @ai_opts [req_http_options: [plug: {Req.Test, __MODULE__}], max_retries: 0]

  defp stub_answers(kind, confidence, retranslate) do
    test = self()

    Req.Test.stub(__MODULE__, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      send(test, {:request, conn.request_path, Jason.decode!(body)})

      Req.Test.json(conn, %{
        "model" => "jev-1.13.0",
        "answers" => %{
          "kind" => %{
            "type" => "choice",
            "choice" => kind,
            "probabilities" => %{kind => confidence},
            "confidence" => confidence
          },
          "retranslate" => %{"type" => "noul", "noul" => retranslate}
        },
        "usage" => %{"input_tokens" => 120, "output_tokens" => 0}
      })
    end)
  end

  describe "Brando.AI.evaluate/3" do
    test "asks the :evaluate model and returns its answers and version" do
      stub_answers("correction", 0.9, 0.1)

      assert {:ok, %{answers: answers, model: "jev-1.13.0", provider: :typesafe}} =
               Brando.AI.evaluate(%{text: "Hei"}, EditCheck.questions(), @ai_opts)

      assert answers["kind"]["choice"] == "correction"
      assert answers["retranslate"]["probability"] == 0.1

      assert_received {:request, "/v1/systemone", body}
      assert body["model"] == "jev-1.13.0"
      assert body["questions"]["retranslate"]["type"] == "noul"
      assert Map.keys(body["questions"]["kind"]["criteria"]) == ~w(content correction meaning rewording)
    end

    test "does not fall back to the generative default model" do
      Application.put_env(:brando, Brando.AI, models: [default: "openai:gpt-4o-mini"])

      refute Brando.AI.evaluation_configured?()
      assert {:error, :missing_model} = Brando.AI.evaluate("x", EditCheck.questions())
    end
  end

  describe "precheck/2" do
    test "settles what code can compute without the model" do
      assert {:ok, %{verdict: :minor, reason: :unchanged}} =
               EditCheck.precheck("Velkommen  til oss", "Velkommen til oss\n")

      assert {:ok, %{verdict: :review, reason: :markup}} =
               EditCheck.precheck("<p>Velkommen til oss</p>", "<p>Velkommen til <strong>oss</strong></p>")

      assert {:ok, %{verdict: :review, reason: :numbers}} =
               EditCheck.precheck("Åpent fra kl. 10", "Åpent fra kl. 11")

      assert :ask = EditCheck.precheck("Velkomen til oss", "Velkommen til oss")
    end
  end

  describe "check/3" do
    test "calls a confident correction minor" do
      stub_answers("correction", 0.93, 0.05)

      assert {:ok, %{verdict: :minor, reason: :model, kind: "correction", model: "jev-1.13.0"}} =
               EditCheck.check("Velkomen til oss", "Velkommen til oss", language: "no", ai_opts: @ai_opts)

      assert_received {:request, _, %{"state" => state}}
      assert state == %{"before" => "Velkomen til oss", "after" => "Velkommen til oss", "language" => "Norsk"}
    end

    test "sends anything less than a confident, safe correction to review" do
      for {kind, confidence, retranslate} <- [
            {"correction", 0.6, 0.05},
            {"correction", 0.95, 0.4},
            {"rewording", 0.95, 0.05},
            {"meaning", 0.99, 0.9}
          ] do
        stub_answers(kind, confidence, retranslate)

        assert {:ok, %{verdict: :review, kind: ^kind}} =
                 EditCheck.check("Vi har åpent i dag", "Vi har stengt i dag", ai_opts: @ai_opts)
      end
    end

    test "passes model errors through" do
      Req.Test.stub(__MODULE__, &Plug.Conn.send_resp(&1, 500, "{}"))

      assert {:error, _} = EditCheck.check("Hei der", "Hei dere", ai_opts: @ai_opts)
    end
  end
end
