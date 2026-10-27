defmodule Mix.Brando.Install.Hosts do
  @moduledoc false

  # Labels of 1-63 letters, digits and inner hyphens.
  @label "[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?"
  # The last label of a domain is not all digits, which rules out IP addresses.
  @domain Regex.compile!("^(?:#{@label}\\.)+(?!\\d+$)#{@label}$")
  # A wildcard covers subdomains of a name with at least two labels, not a TLD.
  @origin_host Regex.compile!("^(?:\\*\\.(?:#{@label}\\.)+|(?:#{@label}\\.)*)#{@label}$")

  @doc """
  Resolves the production domain, staging host and extra trusted origins.

  Options are validated whether or not they are used. A missing `--domain`
  becomes the placeholder `<app>.com`, flagged `placeholder?`, unless `guided`
  is `:hosts` or `:all`: then the domain and staging host are asked for, and
  with `:all` the extra origins too. An empty answer to the domain question
  keeps the placeholder.
  """
  def resolve(options, app_name, guided) do
    with {:ok, domain} <- option(options[:domain], "--domain", &domain/1),
         {:ok, staging} <- option(options[:staging_domain], "--staging-domain", &domain/1),
         {:ok, origins} <- origins(List.wrap(options[:origin])) do
      if guided in [:hosts, :all] && domain == nil do
        {:ok, prompt(placeholder(app_name), staging, origins, guided == :all)}
      else
        placeholder? = domain == nil
        domain = domain || placeholder(app_name)
        {:ok, hosts(domain, staging || "staging.#{domain}", origins, explicit?(options), placeholder?)}
      end
    end
  end

  @doc """
  The `check_origin` list for the production endpoint, which staging also runs:
  the domain with its `www.` host (or, for a `www.` domain, the name without
  it), the staging host and the extra origins. No wildcard is added, so a page
  on another subdomain (a forgotten DNS record, a hosted service) cannot open a
  socket with a visitor's or an editor's cookies; `--origin '//*.example.com'`
  trusts them all on purpose.
  """
  def check_origin(hosts) do
    Enum.uniq(["//#{hosts.domain}" | www_pair(hosts.domain)] ++ ["//#{hosts.staging}" | hosts.origins])
  end

  # The other name of the domain a visitor may type. A `www.` domain's apex
  # needs two labels of its own: `www.com` has none to add.
  defp www_pair("www." <> apex), do: if(String.contains?(apex, "."), do: ["//#{apex}"], else: [])
  defp www_pair(domain), do: ["//www.#{domain}"]

  @doc "A placeholder domain built from the application name."
  def placeholder(app_name), do: String.replace(to_string(app_name), "_", "-") <> ".com"

  @doc "Validates a host name: no scheme, port, path, wildcard or IP address."
  def domain(value) do
    host = value |> String.trim() |> String.downcase()

    if String.length(host) <= 253 and Regex.match?(@domain, host) do
      {:ok, host}
    else
      {:error,
       "must be a host name such as example.com, without a scheme, port or path, and not an IP address; got: #{inspect(value)}"}
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

  defp hosts(domain, staging, origins, explicit?, placeholder?),
    do: %{domain: domain, staging: staging, origins: origins, explicit?: explicit?, placeholder?: placeholder?}

  defp prompt(default_domain, staging, origins, origins?) do
    # An empty answer keeps the placeholder, which writes no check_origin.
    {domain, placeholder?} =
      case ask("+ Production domain [#{default_domain}]", nil, &domain/1) do
        nil -> {default_domain, true}
        domain -> {domain, false}
      end

    staging = staging || ask("+ Staging host [staging.#{domain}]", "staging.#{domain}", &domain/1)

    origins =
      if origins == [] and origins?,
        do: ask("+ Extra trusted origins, comma-separated []", "", &origin_list/1),
        else: origins

    hosts(domain, staging, origins, true, placeholder?)
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

  # An empty answer takes the default, or nil when there is none.
  defp ask(question, default, validate) do
    with answer when answer != "" <- Mix.Brando.prompt(question),
         {:ok, value} <- validate.(answer) do
      value
    else
      "" when is_nil(default) ->
        nil

      "" ->
        {:ok, value} = validate.(default)
        value

      {:error, message} ->
        Mix.shell().error("The answer #{message}")
        ask(question, default, validate)
    end
  end
end
