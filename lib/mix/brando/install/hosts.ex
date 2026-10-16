defmodule Mix.Brando.Install.Hosts do
  @moduledoc false

  # Labels of 1-63 letters, digits and inner hyphens.
  @label "[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?"
  @domain Regex.compile!("^(?:#{@label}\\.)+#{@label}$")
  @origin_host Regex.compile!("^(?:\\*\\.)?(?:#{@label}\\.)*#{@label}$")

  @doc """
  Resolves the production domain, staging host and extra trusted origins.

  Options are validated whether or not they are used. A missing `--domain`
  becomes the placeholder `<app>.com` unless `guided?`, when the domain,
  staging host and extra origins are asked for in that order.
  """
  def resolve(options, app_name, guided?) do
    with {:ok, domain} <- option(options[:domain], "--domain", &domain/1),
         {:ok, staging} <- option(options[:staging_domain], "--staging-domain", &domain/1),
         {:ok, origins} <- origins(List.wrap(options[:origin])) do
      hosts =
        if guided? && domain == nil do
          prompt(placeholder(app_name), staging, origins)
        else
          domain = domain || placeholder(app_name)
          hosts(domain, staging || "staging.#{domain}", origins, explicit?(options))
        end

      {:ok, Map.put(hosts, :placeholder?, hosts.domain == placeholder(app_name))}
    end
  end

  @doc "The `check_origin` list for the production endpoint, which staging also runs."
  def check_origin(hosts) do
    Enum.uniq(["//#{hosts.domain}", "//*.#{hosts.domain}", "//#{hosts.staging}" | hosts.origins])
  end

  @doc "A placeholder domain built from the application name."
  def placeholder(app_name), do: String.replace(to_string(app_name), "_", "-") <> ".com"

  @doc "Validates a host name: no scheme, port, path or wildcard."
  def domain(value) do
    host = value |> String.trim() |> String.downcase()

    if String.length(host) <= 253 and Regex.match?(@domain, host) do
      {:ok, host}
    else
      {:error, "must be a host name such as example.com, without a scheme, port or path; got: #{inspect(value)}"}
    end
  end

  @doc """
  Validates an origin in a form Phoenix's `check_origin` accepts: `//host`,
  `//*.host` or `https://host`, each with an optional port.
  """
  def origin(value) do
    trimmed = String.trim(value)

    with %{"scheme" => scheme, "host" => host, "port" => port} <-
           Regex.named_captures(~r{^(?:(?<scheme>[A-Za-z]+):)?//(?<host>[^/:?#]+)(?::(?<port>\d+))?$}, trimmed),
         scheme = String.downcase(scheme),
         true <- scheme in ["", "http", "https"],
         host = String.downcase(host),
         true <- Regex.match?(@origin_host, host),
         true <- port == "" or String.to_integer(port) in 1..65_535 do
      scheme = if scheme == "", do: "", else: scheme <> ":"
      port = if port == "", do: "", else: ":" <> port
      {:ok, "#{scheme}//#{host}#{port}"}
    else
      _ ->
        {:error,
         "must be an origin such as //example.com, //*.example.com or https://example.com:8443; got: #{inspect(value)}"}
    end
  end

  defp option(nil, _flag, _validate), do: {:ok, nil}

  defp option(value, flag, validate) do
    case validate.(value) do
      {:ok, value} -> {:ok, value}
      {:error, message} -> {:error, "#{flag} #{message}"}
    end
  end

  defp origins(values) do
    Enum.reduce_while(values, {:ok, []}, fn value, {:ok, acc} ->
      case option(value, "--origin", &origin/1) do
        {:ok, origin} -> {:cont, {:ok, acc ++ [origin]}}
        error -> {:halt, error}
      end
    end)
  end

  defp explicit?(options),
    do: options[:domain] != nil or options[:staging_domain] != nil or options[:origin] not in [nil, []]

  defp hosts(domain, staging, origins, explicit?),
    do: %{domain: domain, staging: staging, origins: origins, explicit?: explicit?}

  defp prompt(default_domain, staging, origins) do
    domain = ask("+ Production domain [#{default_domain}]", default_domain, &domain/1)
    staging = staging || ask("+ Staging host [staging.#{domain}]", "staging.#{domain}", &domain/1)
    origins = if origins == [], do: ask("+ Extra trusted origins, comma-separated []", "", &origin_list/1), else: origins
    hosts(domain, staging, origins, true)
  end

  defp origin_list(answer) do
    answer
    |> String.split(",", trim: true)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.reduce_while({:ok, []}, fn value, {:ok, acc} ->
      case origin(value) do
        {:ok, origin} -> {:cont, {:ok, acc ++ [origin]}}
        error -> {:halt, error}
      end
    end)
  end

  defp ask(question, default, validate) do
    answer =
      case Mix.Brando.prompt(question) do
        "" -> default
        answer -> answer
      end

    case validate.(answer) do
      {:ok, value} ->
        value

      {:error, message} ->
        Mix.shell().error("The answer #{message}")
        ask(question, default, validate)
    end
  end
end
