defmodule Brando.Videos.Uploaders.ReqOptions do
  @moduledoc """
  The one owner of the video providers' `:req_options` precedence rule.

  Mux, Bunny and Cloudflare build genuinely different requests — Basic auth vs
  an `AccessKey` header vs a Bearer token, two URL shapes, and two different
  answers to missing credentials — so their `api_request` functions are not one
  function with cosmetic differences and are not collapsed here.

  What *was* byte-identical across all three, and therefore what could drift in
  one of them without anyone noticing, is this merge. That is what this module
  owns.
  """

  @doc """
  Puts `provider`'s configured `:req_options` **underneath** `built_opts`.

  Built values win. The other direction lets a `:req_options` entry silently
  replace the authorization header, the URL or the method — a config seam that
  can unset credentials is a config seam that will. What the seam is *for* is
  the transport: a test points it at a `Req.Test` stub so the request a provider
  builds can be asserted without a network (see
  `test/brando/videos/provider_client_test.exs`), and nothing about that needs
  the power to rewrite the request itself.

  Reads `nil` as absent as well as unset: `Application.put_env(key, nil)` is not
  the same as not setting it, and a config-restore helper that stores `nil`
  otherwise beats the `[]` default.
  """
  def merge(provider, built_opts) do
    configured =
      :brando
      |> Application.get_env(provider, [])
      |> Keyword.get(:req_options)

    Keyword.merge(configured || [], built_opts)
  end
end
