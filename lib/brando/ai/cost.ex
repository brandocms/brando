defmodule Brando.AI.Cost do
  @moduledoc """
  Estimates what a batch of AI requests will cost before it is sent.

  Prices come from ReqLLM's model catalogue (`Brando.AI.model_info/1`). Image
  input is counted with each provider's published formula for the size the
  image is actually sent at; unknown providers get a cautious flat figure.
  These are estimates for an editor deciding whether to go ahead — the
  provider's own bill is what counts, and prices change.
  """

  # Tokens for the instructions around each image, and for a one-sentence reply.
  @prompt_tokens 150
  @reply_tokens 60
  # When a provider's image formula is unknown.
  @fallback_image_tokens 1_500

  @doc """
  Estimated cost in USD of describing images of the given `{width, height}`
  sizes, one request each, with the model `ai_opts` resolve to.
  """
  @spec images([{pos_integer(), pos_integer()}], keyword()) ::
          {:ok, %{total: float(), per_image: float(), spec: String.t(), count: non_neg_integer()}}
          | {:error, :no_image_input | :unknown_price | term()}
  def images(dimensions, ai_opts \\ []) do
    with {:ok, info} <- Brando.AI.model_info(ai_opts),
         :ok <- check(info) do
      totals =
        Enum.map(dimensions, fn {width, height} ->
          input = image_tokens(info, width, height) + @prompt_tokens
          (input * info.input_price + @reply_tokens * info.output_price) / 1_000_000
        end)

      count = length(totals)
      total = Enum.sum(totals)

      {:ok,
       %{
         total: total,
         per_image: if(count > 0, do: total / count, else: 0.0),
         spec: info.spec,
         count: count
       }}
    end
  end

  @doc """
  Input tokens a provider charges for one image of `width` × `height`,
  after its own resizing.
  """
  @spec image_tokens(map(), pos_integer(), pos_integer()) :: pos_integer()
  def image_tokens(%{provider: :anthropic}, width, height) do
    # Scaled to fit 1568px on the long edge; tokens ≈ pixels / 750.
    {w, h} = fit(width, height, 1568)
    ceil(w * h / 750)
  end

  def image_tokens(%{provider: provider} = info, width, height) when provider in [:openai, :azure] do
    id = to_string(info.model_id)

    cond do
      # Patch-based models: 32px patches, capped at 1536, times a model factor.
      patch_multiplier(id) ->
        patches = min(ceil(width / 32) * ceil(height / 32), 1536)
        ceil(patches * patch_multiplier(id))

      # gpt-4o-mini prices images like gpt-4o by charging far more tokens.
      String.contains?(id, "4o-mini") ->
        2833 + 5667 * tiles(width, height)

      true ->
        85 + 170 * tiles(width, height)
    end
  end

  def image_tokens(%{provider: provider}, width, height) when provider in [:google, :google_vertex] do
    # 258 tokens per image up to 384px, else per 768px tile.
    if width <= 384 and height <= 384, do: 258, else: 258 * ceil(width / 768) * ceil(height / 768)
  end

  def image_tokens(_info, _width, _height), do: @fallback_image_tokens

  @doc "A cost in USD for display, to the cent; under a cent reads as such, not as zero."
  @spec format(float()) :: String.t()
  def format(usd) when usd < 0.01, do: "< $0.01"
  def format(usd), do: "$" <> :erlang.float_to_binary(usd, decimals: 2)

  defp check(%{image_input?: false}), do: {:error, :no_image_input}
  defp check(%{input_price: input, output_price: output}) when is_number(input) and is_number(output), do: :ok
  defp check(_info), do: {:error, :unknown_price}

  # OpenAI's high-detail tiling: fit 2048, shortest side down to 768, 512px tiles.
  defp tiles(width, height) do
    {w, h} = fit(width, height, 2048)
    scale = min(1.0, 768 / min(w, h))
    ceil(w * scale / 512) * ceil(h * scale / 512)
  end

  defp patch_multiplier(id) do
    cond do
      String.contains?(id, "nano") -> 2.46
      String.contains?(id, "4.1-mini") or String.contains?(id, "gpt-5-mini") -> 1.62
      String.contains?(id, "o4-mini") -> 1.72
      true -> nil
    end
  end

  defp fit(width, height, max) do
    scale = min(1.0, max / max(width, height))
    {max(round(width * scale), 1), max(round(height * scale), 1)}
  end
end
