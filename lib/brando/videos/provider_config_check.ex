defmodule Brando.Videos.ProviderConfigCheck do
  @moduledoc """
  Reports misconfigured video providers at boot.

  ## Why this exists

  The three provider clients raise on missing credentials, on the stated grounds
  that *"missing credentials are a deploy-time configuration error, not a
  runtime condition"*. That was only half true. The check lived in
  `api_request`, so it fired at file-pick time — the latest possible moment,
  with an editor's unsaved work in the blast radius. `Brando.Uploads`'
  pre-flight validation fixed the *damage* (the pick is now rejected cleanly
  instead of killing the LiveView), but not the *timing*: a misconfigured deploy
  was still discovered by the first person who tried to upload a video.

  This is the part that makes the rationale literally true. A bad deploy says so
  at boot, in the logs, next to everything else that starts up.

  ## Why it logs rather than raises

  Refusing to boot would turn a misconfiguration into an outage, and would break
  every environment that legitimately has no provider credentials — dev, test,
  CI, and any site whose video fields are unused or `:local`. The failure this
  guards is already non-destructive: `validate_provider_video_intake/2` rejects
  the pick with a message. What was missing was *visibility*, and that is what
  this adds.

  Sites that want the strict reading can opt in:

      config :brando, :strict_video_provider_config, true

  which raises at boot instead. That is off by default because it changes
  whether an application starts, which is not a default anyone should inherit
  silently.

  ## What counts as a problem

  Deliberately narrow, because a check that cries wolf gets ignored:

    * **The default strategy is a provider that is not configured.** The site
      has said this is how videos upload, so it has to work.
    * **Partial credentials.** Some of a provider's credential keys are set and
      others are not. This cannot be intentional — nobody sets `MUX_TOKEN_ID`
      and deliberately omits `MUX_TOKEN_SECRET`.
    * **Usable credentials, no webhook secret.** Uploads start and never
      complete, and the upload control silently does not render
      (`Brando.Videos.upload_available?/1` requires it).

  A provider with *no* configuration at all is not a problem. That is what every
  site not using that provider looks like.
  """

  alias Brando.Videos.Uploaders.Bunny
  alias Brando.Videos.Uploaders.Cloudflare
  alias Brando.Videos.Uploaders.Mux

  require Logger

  @providers [
    {:mux, Mux, [:access_token_id, :access_token_secret]},
    {:bunny, Bunny, [:api_key]},
    {:cloudflare, Cloudflare, [:account_id, :api_token]}
  ]

  @doc """
  Logs any provider configuration problems, or raises when strict mode is on.

  Called from `Brando.Supervisor.init/1`. Returns `:ok` regardless, so a
  misconfigured provider never prevents boot unless the site asked for that.
  """
  def run do
    case problems() do
      [] ->
        :ok

      problems ->
        if Application.get_env(:brando, :strict_video_provider_config, false) do
          raise """
          Video provider configuration is incomplete:

          #{Enum.map_join(problems, "\n", &"  * #{&1}")}

          This raises because `config :brando, :strict_video_provider_config` is
          true. Unset it to log these instead of refusing to boot.
          """
        end

        Enum.each(problems, &Logger.error("==> Video provider config: #{&1}"))
        :ok
    end
  end

  @doc """
  The configuration problems, as human-readable sentences.

  Pure with respect to everything but the application environment, so it can be
  asserted directly rather than through the log.
  """
  def problems do
    Enum.flat_map(@providers, &provider_problems/1) ++ default_strategy_problems()
  end

  defp provider_problems({name, module, credential_keys}) do
    cfg = Brando.Videos.provider_config(module)
    present = Enum.filter(credential_keys, &present?(cfg[&1]))

    cond do
      # Nothing configured — this provider is simply not in use.
      present == [] ->
        []

      not module.configured?() ->
        missing = credential_keys -- present

        [
          "#{name} has #{inspect(present)} configured but #{inspect(missing)} missing or empty. " <>
            "Provider calls will raise; uploads are rejected before they start."
        ]

      not present?(webhook_secret(name, cfg)) ->
        [
          "#{name} has credentials but no #{webhook_key(name)}. Uploads will start and never " <>
            "complete, and the upload control will not render."
        ]

      true ->
        []
    end
  end

  # Bunny accepts its read-only API key in place of a webhook secret.
  defp webhook_secret(:bunny, cfg), do: cfg[:webhook_secret] || cfg[:read_only_api_key]
  defp webhook_secret(_name, cfg), do: cfg[:webhook_secret]

  defp webhook_key(:bunny), do: "webhook_secret (or read_only_api_key)"
  defp webhook_key(_name), do: "webhook_secret"

  defp default_strategy_problems do
    strategy = Brando.default_video_upload_strategy()

    case Enum.find(@providers, fn {name, _, _} -> name == strategy end) do
      nil ->
        []

      {name, module, _keys} ->
        if module.configured?() do
          []
        else
          [
            "default_video_upload_strategy is #{inspect(name)}, but #{name} has no usable " <>
              "credentials. Every video field without its own strategy is unusable."
          ]
        end
    end
  end

  defp present?(value), do: not is_nil(value) and value != ""
end
