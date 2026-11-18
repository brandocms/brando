defmodule Brando.Doctor.Checks.VideoProviders do
  @moduledoc """
  The video provider problems `Brando.Videos.ProviderConfigCheck` logs at boot:
  partial credentials, credentials without a webhook secret, and a
  `default_video_upload_strategy` whose provider can't upload. Boot logs are
  rarely read, so Utilities lists them too, in the same words.
  """
  use Brando.Doctor.Check
  use Gettext, backend: Brando.Gettext

  alias Brando.Videos.ProviderConfigCheck

  @impl true
  def id, do: "video_providers"

  @impl true
  def label, do: dgettext("doctor", "Video providers")

  @impl true
  def run(_context) do
    case ProviderConfigCheck.problems() do
      [] ->
        ok(dgettext("doctor", "no configuration problems"))

      problems ->
        warning(
          dngettext(
            "doctor",
            "%{count} video provider problem: video uploads can fail",
            "%{count} video provider problems: video uploads can fail",
            length(problems)
          ),
          fix:
            dgettext(
              "doctor",
              "add what the details say is missing and restart, or change default_video_upload_strategy"
            ),
          items: problems
        )
    end
  end
end
