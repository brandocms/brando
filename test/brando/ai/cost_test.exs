defmodule Brando.AI.CostTest do
  use ExUnit.Case, async: false

  alias Brando.AI.Cost

  setup do
    previous = Application.get_env(:brando, Brando.AI)

    on_exit(fn ->
      if previous, do: Application.put_env(:brando, Brando.AI, previous), else: Application.delete_env(:brando, Brando.AI)
    end)
  end

  defp model(spec), do: Application.put_env(:brando, Brando.AI, default_model: spec)

  test "counts image tokens with each provider's formula" do
    assert Cost.image_tokens(%{provider: :anthropic}, 750, 500) == 500
    # Anthropic fits 1568px on the long edge first.
    assert Cost.image_tokens(%{provider: :anthropic}, 3136, 1568) == Cost.image_tokens(%{provider: :anthropic}, 1568, 784)
    # gpt-4o: 85 + 170 per 512px tile; a 512px image is one tile.
    assert Cost.image_tokens(%{provider: :openai, model_id: "gpt-4o"}, 512, 384) == 255
    assert Cost.image_tokens(%{provider: :openai, model_id: "gpt-4o-mini"}, 512, 384) == 2833 + 5667
    # Patch models: 32px patches times the model's factor.
    assert Cost.image_tokens(%{provider: :openai, model_id: "gpt-4.1-mini"}, 512, 384) == ceil(16 * 12 * 1.62)
    assert Cost.image_tokens(%{provider: :google}, 300, 300) == 258
    assert Cost.image_tokens(%{provider: :someone_else}, 512, 512) == 1500
  end

  test "estimates a batch from the configured model's catalogue prices" do
    model("openai:gpt-4o")

    assert {:ok, %{spec: "openai:gpt-4o", count: 2, total: total, per_image: per_image}} =
             Cost.images([{512, 384}, {512, 384}])

    # (255 image + 150 prompt) × $2.50/M + 60 reply × $10/M, per image.
    assert_in_delta per_image, (405 * 2.5 + 60 * 10) / 1_000_000, 1.0e-9
    assert_in_delta total, 2 * per_image, 1.0e-9
  end

  test "refuses a model that cannot read images" do
    model("openai:gpt-3.5-turbo")
    assert Cost.images([{512, 384}]) == {:error, :no_image_input}
  end

  test "a model outside the catalogue is unknown, not refused" do
    model("anthropic:claude-imaginary-9")
    assert Cost.images([{512, 384}]) == {:error, :unknown_model}
  end

  test "formats small amounts without rounding them to nothing" do
    assert Cost.format(0.0013) == "$0.0013"
    assert Cost.format(0.00397) == "$0.0040"
    assert Cost.format(0.126) == "$0.13"
    assert Cost.format(12.5) == "$12.50"
  end
end
