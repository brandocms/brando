defmodule Brando.Doctor.Checks.Configuration do
  @moduledoc """
  Required configuration: the endpoint's URL, the mailer and its sender, the
  media CDN settings when a CDN is enabled, and the Assistant's model and key
  when the Assistant is configured.
  """
  use Brando.Doctor.Check
  use Gettext, backend: Brando.Gettext

  alias Brando.Doctor.Result

  @cdn_contexts [Brando.Images, Brando.Files]

  @impl true
  def id, do: "configuration"

  @impl true
  def label, do: dgettext("doctor", "Configuration")

  @impl true
  def run(_context) do
    evaluate([endpoint_url(), mailer()] ++ Enum.map(@cdn_contexts, &cdn/1) ++ [assistant()])
  end

  @doc """
  Turns findings into a result. Each finding is `{status, item, problem}`:
  the status of one setting, the line `--verbose` shows for it, and the
  short problem for the summary (nil when it is fine).
  """
  def evaluate(findings) do
    items = Enum.map(findings, &elem(&1, 1))
    problems = Enum.filter(findings, &(elem(&1, 0) in [:warning, :error]))
    status = findings |> Enum.map(&elem(&1, 0)) |> Enum.reduce(:ok, &Result.worst/2)

    case problems do
      [] ->
        ok(dgettext("doctor", "URL, mailer and media settings in place"), items: items)

      problems ->
        summary = Enum.map_join(problems, ", ", &elem(&1, 2))
        fix = dgettext("doctor", "see the guides for email, CDN delivery and the content assistant")
        apply(Result, status, [summary, [fix: fix, items: items]])
    end
  end

  @doc """
  The site's URL from the endpoint, or nil when the endpoint is not running
  or has no URL.
  """
  def site_url do
    Brando.endpoint().url()
  rescue
    # The endpoint's config table is not there until it starts
    ArgumentError -> nil
  end

  @doc "The endpoint URL as a finding (see `evaluate/1`)."
  def endpoint_url do
    url = site_url()
    host = url && URI.parse(url).host

    cond do
      host in [nil, ""] ->
        {:error, dgettext("doctor", "Endpoint URL: not set"), dgettext("doctor", "no endpoint URL")}

      host == "localhost" and Brando.env() == :prod ->
        {:warning, dgettext("doctor", "Endpoint URL: %{url}", url: url), dgettext("doctor", "endpoint URL is localhost")}

      true ->
        {:ok, dgettext("doctor", "Endpoint URL: %{url}", url: url), nil}
    end
  end

  @doc "The mailer and its sender as a finding (see `evaluate/1`)."
  def mailer do
    mailer = Brando.Mailer.mailer()
    from = Brando.Mailer.sender()[:from]

    cond do
      is_nil(mailer) ->
        {:warning, dgettext("doctor", "Mailer: not set"), dgettext("doctor", "no mailer")}

      not Code.ensure_loaded?(mailer) ->
        {:error, dgettext("doctor", "Mailer: %{mailer} does not exist", mailer: inspect(mailer)),
         dgettext("doctor", "mailer module missing")}

      is_nil(from) ->
        {:warning, dgettext("doctor", "Mailer: %{mailer}, no sender", mailer: inspect(mailer)),
         dgettext("doctor", "no sender address")}

      true ->
        {:ok, dgettext("doctor", "Mailer: %{mailer}, from %{from}", mailer: inspect(mailer), from: format_from(from)),
         nil}
    end
  end

  defp format_from({name, address}), do: "#{name} <#{address}>"
  defp format_from(address), do: to_string(address)

  @doc "The CDN settings of a media context as a finding (see `evaluate/1`)."
  def cdn(context) do
    name = context |> Module.split() |> List.last()

    if Brando.CDN.enabled?(context) do
      config = Brando.config(context, :cdn)

      missing =
        [bucket: blank?(config_value(config, :bucket)), media_url: blank?(config_value(config, :media_url))]
        |> Enum.filter(&elem(&1, 1))
        |> Enum.map(&to_string(elem(&1, 0)))
        |> Kernel.++(missing_s3(config_value(config, :s3)))

      if missing == [] do
        {:ok, dgettext("doctor", "%{context} CDN: %{bucket}", context: name, bucket: config_value(config, :bucket)), nil}
      else
        list = Enum.join(missing, ", ")

        {:error, dgettext("doctor", "%{context} CDN: missing %{settings}", context: name, settings: list),
         dgettext("doctor", "%{context} CDN incomplete", context: name)}
      end
    else
      {:ok, dgettext("doctor", "%{context} CDN: off", context: name), nil}
    end
  end

  defp missing_s3(:default) do
    case Brando.config(Brando.CDN.S3Config) do
      nil -> ["Brando.CDN.S3Config"]
      s3 -> missing_s3(s3)
    end
  end

  defp missing_s3(nil), do: ["s3"]

  defp missing_s3(s3) do
    for key <- [:access_key_id, :secret_access_key, :host], blank?(config_value(s3, key)), do: "s3.#{key}"
  end

  defp config_value(config, key) when is_map(config), do: Map.get(config, key)
  defp config_value(config, key) when is_list(config), do: Keyword.get(config, key)
  defp config_value(_config, _key), do: nil

  defp blank?(value), do: value in [nil, ""]

  @doc "The Assistant's model and key as a finding (see `evaluate/1`)."
  def assistant do
    agent = Application.get_env(:brando, Brando.AI.Agent, [])

    cond do
      not Brando.AI.enabled?() ->
        {:ok, dgettext("doctor", "Assistant: AI turned off"), nil}

      is_nil(agent[:model]) ->
        {:ok, dgettext("doctor", "Assistant: not configured"), nil}

      Brando.AI.Agent.available?() ->
        {:ok, dgettext("doctor", "Assistant: %{model}", model: agent[:model]), nil}

      true ->
        {:warning, dgettext("doctor", "Assistant: %{model} has no API key", model: agent[:model]),
         dgettext("doctor", "no API key for the Assistant")}
    end
  end
end
