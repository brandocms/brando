defmodule Brando.AITest do
  use ExUnit.Case, async: false

  defmodule TraitConfiguredMetaSchema do
    def __traits__ do
      [
        {Brando.Trait.Meta,
         [
           ai: [
             meta_description: [prompt: "Trait configured meta prompt", context: [:title, :blocks]]
           ]
         ]}
      ]
    end
  end

  defmodule TraitUnconfiguredMetaSchema do
    def __traits__ do
      [
        {Brando.Trait.Meta, []}
      ]
    end
  end

  setup do
    original_brando_ai_cfg = Application.get_env(:brando, Brando.AI)
    original_req_llm_openai_key = Application.get_env(:req_llm, :openai_api_key)

    on_exit(fn ->
      restore_env(:brando, Brando.AI, original_brando_ai_cfg)
      restore_env(:req_llm, :openai_api_key, original_req_llm_openai_key)
    end)

    :ok
  end

  test "configured?/1 uses configured default model when field opts omit model" do
    Application.put_env(:brando, Brando.AI,
      default_model: "openai:gpt-4o-mini",
      providers: [openai: [api_key: "test-openai-key"]]
    )

    assert Brando.AI.configured?(prompt: "Generate a short summary")
  end

  test "configured?/1 falls back to req_llm provider key lookup" do
    Application.put_env(:brando, Brando.AI, default_model: "openai:gpt-4o-mini")
    Application.put_env(:req_llm, :openai_api_key, "test-openai-key-from-req-llm")

    assert Brando.AI.configured?(prompt: "Generate a short summary")
  end

  test "configured?/1 returns false when neither field opts nor config provides a model" do
    Application.put_env(:brando, Brando.AI, providers: [openai: [api_key: "test-openai-key"]])

    refute Brando.AI.configured?(prompt: "Generate a short summary")
  end

  test "field_ai_opts/2 returns trait-declared config for page meta fields" do
    meta_description_opts = Brando.AI.field_ai_opts(Brando.Pages.Page, :meta_description)
    meta_title_opts = Brando.AI.field_ai_opts(Brando.Pages.Page, :meta_title)

    assert meta_description_opts[:context] == [:title, :blocks, :language]
    assert meta_description_opts[:prompt] =~ "CMS language code"
    assert meta_description_opts[:prompt] =~ "140-155"

    assert meta_title_opts[:context] == [:title, :blocks, :language]
    assert meta_title_opts[:prompt] =~ "CMS language code"
    assert meta_title_opts[:prompt] =~ "50-60"
  end

  test "field_ai_opts/2 uses trait-declared ai config before app config fallbacks" do
    Application.put_env(:brando, Brando.AI,
      fields: [
        meta_description: [prompt: "General field prompt"]
      ]
    )

    assert Brando.AI.field_ai_opts(TraitConfiguredMetaSchema, :meta_description) == [
             prompt: "Trait configured meta prompt",
             context: [:title, :blocks]
           ]
  end

  test "field_ai_opts/2 uses generic fields fallback when trait has no ai config" do
    Application.put_env(:brando, Brando.AI,
      fields: [
        meta_description: [prompt: "General field prompt"]
      ]
    )

    assert Brando.AI.field_ai_opts(TraitUnconfiguredMetaSchema, :meta_description) == [
             prompt: "General field prompt"
           ]
  end

  test "field_ai_opts/1 uses generic fields fallback when no schema is provided" do
    Application.put_env(:brando, Brando.AI,
      fields: [
        meta_description: [prompt: "General field prompt"]
      ]
    )

    assert Brando.AI.field_ai_opts(:meta_description) == [prompt: "General field prompt"]
  end

  defp restore_env(app, key, nil), do: Application.delete_env(app, key)
  defp restore_env(app, key, value), do: Application.put_env(app, key, value)
end
