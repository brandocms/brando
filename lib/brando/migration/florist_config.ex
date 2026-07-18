defmodule Brando.Migration.FloristConfig do
  @moduledoc """
  Converts Brando's legacy Fabric deployment inputs into a reviewable Florist
  configuration without evaluating Python or copying secrets.

  The converter intentionally targets the deployment model implemented by the
  bundled `fabfile.py`: separate, single-release `prod` and `staging` targets
  using nginx and Docker-built OTP releases. Settings that cannot be inferred
  safely are reported as warnings and left for the operator to complete.
  """

  @required_settings ~w(PROJECT_MODULE PROJECT_NAME SSH_HOST SSH_PORT SSH_USER)
  @supported_targets [:prod, :staging]

  @type warning :: String.t()

  @doc """
  Generates `florist.config.exs` content from legacy `deployment.cfg` and
  `fabfile.py` contents.

  Password values are never copied into the generated configuration. The
  returned warnings identify required environment variables and any legacy
  expressions that could not be converted deterministically.
  """
  @spec generate(String.t(), String.t()) ::
          {:ok, String.t(), [warning()]} | {:error, String.t()}
  def generate(deployment_config, fabfile)
      when is_binary(deployment_config) and is_binary(fabfile) do
    with {:ok, settings} <- parse_deployment_config(deployment_config),
         :ok <- validate_required_settings(settings),
         :ok <- validate_project_module(settings["PROJECT_MODULE"]),
         {:ok, ssh_port} <- parse_ssh_port(settings["SSH_PORT"]),
         {:ok, target_names} <- find_targets(fabfile) do
      {targets, conversion_warnings} = build_targets(target_names, settings, ssh_port, fabfile)

      warnings =
        conversion_warnings
        |> Kernel.++(secret_warnings(settings, target_names))
        |> Kernel.++(deployment_warnings(fabfile, target_names))
        |> Enum.uniq()

      {:ok, render_config(settings, targets), warnings}
    end
  end

  defp parse_deployment_config(contents) do
    {_section, settings} =
      contents
      |> String.split(~r/\R/)
      |> Enum.reduce({nil, %{}}, fn line, {section, settings} ->
        parse_config_line(String.trim(line), section, settings)
      end)

    {:ok, settings}
  end

  defp parse_config_line("", section, settings), do: {section, settings}
  defp parse_config_line("#" <> _comment, section, settings), do: {section, settings}
  defp parse_config_line(";" <> _comment, section, settings), do: {section, settings}

  defp parse_config_line("[" <> rest, _section, settings) do
    {rest |> String.trim_trailing("]") |> String.trim() |> String.upcase(), settings}
  end

  defp parse_config_line(line, "DEPLOYMENT" = section, settings) do
    case String.split(line, "=", parts: 2) do
      [key, value] -> {section, Map.put(settings, key |> String.trim() |> String.upcase(), String.trim(value))}
      _other -> {section, settings}
    end
  end

  defp parse_config_line(_line, section, settings), do: {section, settings}

  defp validate_required_settings(settings) do
    missing = Enum.filter(@required_settings, &blank?(settings[&1]))

    case missing do
      [] -> :ok
      _missing -> {:error, "deployment.cfg is missing required DEPLOYMENT settings: #{Enum.join(missing, ", ")}"}
    end
  end

  defp validate_project_module(project_module) do
    valid? =
      project_module
      |> String.split(".")
      |> Enum.all?(&Regex.match?(~r/^[A-Z][A-Za-z0-9_]*$/, &1))

    if valid?,
      do: :ok,
      else: {:error, "PROJECT_MODULE must be a literal Elixir module name, got: #{inspect(project_module)}"}
  end

  defp parse_ssh_port(port) do
    case Integer.parse(port) do
      {value, ""} when value in 1..65_535 -> {:ok, value}
      _other -> {:error, "SSH_PORT must be an integer from 1 to 65535, got: #{inspect(port)}"}
    end
  end

  defp find_targets(fabfile) do
    targets = Enum.filter(@supported_targets, &target_defined?(fabfile, &1))

    if :prod in targets,
      do: {:ok, targets},
      else: {:error, "fabfile.py does not define the expected prod() deployment target"}
  end

  defp target_defined?(fabfile, target) do
    Regex.match?(~r/^def\s+#{target}\(\):/m, fabfile)
  end

  defp build_targets(target_names, settings, ssh_port, fabfile) do
    {group, warnings} = global_setting(fabfile, "project_group", "web")
    docker_host = blank_to_nil(settings["DOCKER_HOST"])

    Enum.map_reduce(target_names, warnings, fn target, warnings ->
      {target_config, target_warnings} =
        build_target(target, settings, ssh_port, fabfile, group, docker_host)

      {target_config, warnings ++ target_warnings}
    end)
  end

  defp build_target(target, settings, ssh_port, fabfile, group, docker_host) do
    defaults = target_defaults(target)
    glue_body = glue_target_body(fabfile, target)
    function_body = target_function_body(fabfile, target)

    {base_dir, warnings} = target_setting(glue_body, target, "project_base", defaults.base_dir, [])
    {process_name, warnings} = target_setting(glue_body, target, "process_name", defaults.process_name, warnings)
    {database_name, warnings} = target_setting(glue_body, target, "db_name", defaults.database_name, warnings)
    {database_user, warnings} = target_setting(glue_body, target, "db_user", defaults.database_user, warnings)

    {flavor, warnings} =
      atom_env_setting(function_body, target, "flavor", Atom.to_string(target), warnings)

    {mix_env, warnings} = atom_env_setting(function_body, target, "mix_env", "prod", warnings)
    {dockerfile, warnings} = env_setting(function_body, target, "dockerfile", "Dockerfile", warnings)
    {domain, ssl, redirect_http, warnings} = target_webserver(settings, target, warnings)

    target_config = %{
      name: target,
      flavor: flavor,
      mix_env: mix_env,
      base_dir: base_dir,
      process_name: process_name,
      ssh_host: settings["SSH_HOST"],
      ssh_port: ssh_port,
      ssh_user: settings["SSH_USER"],
      remote_user: "${PROJECT_NAME}",
      remote_group: group,
      database_name: database_name,
      database_user: database_user,
      pgbackup_enabled: target == :prod and String.contains?(fabfile, "def setup_pgbackup"),
      docker_host: docker_host,
      dockerfile: dockerfile,
      domain: domain,
      ssl: ssl,
      redirect_http: redirect_http,
      application_port: defaults.application_port,
      noindex: target == :staging
    }

    {target_config, warnings}
  end

  defp target_defaults(target) do
    target_name = Atom.to_string(target)

    %{
      base_dir: "/sites/#{target_name}",
      process_name: "${PROJECT_NAME}_#{target_name}",
      database_name: "${PROJECT_NAME}_#{target_name}",
      database_user: "${PROJECT_NAME}",
      application_port: legacy_application_port(target)
    }
  end

  defp legacy_application_port(:prod), do: 8055
  defp legacy_application_port(:staging), do: 8060

  defp global_setting(fabfile, key, fallback) do
    case python_key_expression(fabfile, key) do
      {:ok, expression} ->
        case parse_python_expression(expression) do
          {:ok, value} -> {value, []}
          :error -> {fallback, [conversion_warning(:global, key, expression, fallback)]}
        end

      :error ->
        {fallback, []}
    end
  end

  defp target_setting({:ok, body}, target, key, fallback, warnings) do
    case python_key_expression(body, key) do
      {:ok, expression} ->
        case parse_python_expression(expression) do
          {:ok, value} -> {value, warnings}
          :error -> {fallback, [conversion_warning(target, key, expression, fallback) | warnings]}
        end

      :error ->
        {fallback, warnings}
    end
  end

  defp target_setting(:error, _target, _key, fallback, warnings), do: {fallback, warnings}

  defp env_setting({:ok, body}, target, key, fallback, warnings) do
    case env_assignment(body, key) do
      {:ok, expression} ->
        case parse_python_expression(expression) do
          {:ok, value} -> {value, warnings}
          :error -> {fallback, [conversion_warning(target, "env.#{key}", expression, fallback) | warnings]}
        end

      :error ->
        {fallback, warnings}
    end
  end

  defp env_setting(:error, _target, _key, fallback, warnings), do: {fallback, warnings}

  defp atom_env_setting(body, target, key, fallback, warnings) do
    {value, warnings} = env_setting(body, target, key, fallback, warnings)

    if atom_literal?(value) do
      {value, warnings}
    else
      warning =
        "Could not render #{target} env.#{key} value #{inspect(value)} as an atom; using #{inspect(fallback)}."

      {fallback, [warning | warnings]}
    end
  end

  defp conversion_warning(target, key, expression, fallback) do
    "Could not convert #{target} #{key} expression #{inspect(expression)}; using #{inspect(fallback)}."
  end

  defp glue_target_body(fabfile, target) do
    regex = ~r/["']#{target}["']\s*:\s*\{(?<body>.*?)^\s*\}/ms

    case Regex.named_captures(regex, fabfile) do
      %{"body" => body} -> {:ok, body}
      _no_match -> :error
    end
  end

  defp target_function_body(fabfile, target) do
    regex = ~r/^def\s+#{target}\(\):(?<body>.*?)(?=^def\s|\z)/ms

    case Regex.named_captures(regex, fabfile) do
      %{"body" => body} -> {:ok, body}
      _no_match -> :error
    end
  end

  defp python_key_expression(body, key) do
    regex = ~r/["']#{Regex.escape(key)}["']\s*:\s*(?<expression>[^,\r\n}]+)/

    case Regex.named_captures(regex, body) do
      %{"expression" => expression} -> {:ok, String.trim(expression)}
      _no_match -> :error
    end
  end

  defp env_assignment(body, key) do
    regex = ~r/^\s*env\.#{Regex.escape(key)}\s*=\s*(?<expression>[^\r\n#]+)/m

    case Regex.named_captures(regex, body) do
      %{"expression" => expression} -> {:ok, String.trim(expression)}
      _no_match -> :error
    end
  end

  defp parse_python_expression("PROJECT_NAME"), do: {:ok, "${PROJECT_NAME}"}
  defp parse_python_expression("GLUE_SETTINGS['project_name']"), do: {:ok, "${PROJECT_NAME}"}
  defp parse_python_expression("GLUE_SETTINGS[\"project_name\"]"), do: {:ok, "${PROJECT_NAME}"}

  defp parse_python_expression(expression) do
    case parse_project_name_format(expression) do
      {:ok, _value} = parsed -> parsed
      :error -> parse_python_string(expression)
    end
  end

  defp parse_project_name_format(expression) do
    patterns = [
      ~r/^'(?<value>[^']*)'\s*%\s*PROJECT_NAME$/,
      ~r/^"(?<value>[^"]*)"\s*%\s*PROJECT_NAME$/
    ]

    Enum.find_value(patterns, :error, fn regex ->
      case Regex.named_captures(regex, expression) do
        %{"value" => value} -> {:ok, String.replace(value, "%s", "${PROJECT_NAME}")}
        _no_match -> false
      end
    end)
  end

  defp parse_python_string(expression) do
    patterns = [~r/^'(?<value>[^']*)'$/, ~r/^"(?<value>[^"]*)"$/]

    Enum.find_value(patterns, :error, fn regex ->
      case Regex.named_captures(regex, expression) do
        %{"value" => value} -> {:ok, value}
        _no_match -> false
      end
    end)
  end

  defp target_webserver(settings, target, warnings) do
    key = target |> Atom.to_string() |> String.upcase() |> Kernel.<>("_URL")

    case blank_to_nil(settings[key]) do
      nil ->
        warning = "No #{key} was found; set the #{target} webserver domain in florist.config.exs."
        {nil, :auto, true, [warning | warnings]}

      url ->
        parse_target_webserver_url(url, key, target, warnings)
    end
  end

  defp parse_target_webserver_url(url, key, target, warnings) do
    {normalized_url, warnings} = normalize_target_url(url, key, warnings)
    uri = URI.parse(normalized_url)

    if blank?(uri.host) do
      warning = "Could not derive the #{target} webserver domain from #{key}=#{inspect(url)}."
      {nil, :auto, true, [warning | warnings]}
    else
      warnings = warn_about_discarded_url_parts(uri, key, target, warnings)
      https? = uri.scheme == "https"
      {uri.host, if(https?, do: :auto, else: false), https?, warnings}
    end
  end

  defp normalize_target_url(url, key, warnings) do
    if String.contains?(url, "://") do
      {url, warnings}
    else
      {"https://#{url}", ["#{key} has no URL scheme; assuming HTTPS for the generated target." | warnings]}
    end
  end

  defp warn_about_discarded_url_parts(uri, key, target, warnings) do
    custom_port? = uri.port not in [nil, URI.default_port(uri.scheme)]
    path? = uri.path not in [nil, "", "/"]

    discarded_parts? =
      custom_port? or path? or not is_nil(uri.query) or not is_nil(uri.fragment) or not is_nil(uri.userinfo)

    if discarded_parts? do
      warning =
        "#{key} contains URL components beyond its scheme and host; only #{target} domain and SSL mode were converted."

      [warning | warnings]
    else
      warnings
    end
  end

  defp atom_literal?(value), do: Regex.match?(~r/^[a-z][a-z0-9_]*$/, value)

  defp secret_warnings(settings, targets) do
    variables = Enum.map_join(targets, ", ", &database_password_variable/1)

    [
      "Database passwords are intentionally not written to florist.config.exs; export #{variables} before using Florist."
    ]
    |> maybe_add_warning(not blank?(settings["SSH_PASS"]), fn ->
      "Legacy SSH_PASS was intentionally not copied; use an SSH agent or add an environment-backed `set :pass` manually."
    end)
  end

  defp deployment_warnings(fabfile, targets) do
    application_ports =
      Enum.map_join(targets, ", ", &"#{&1} #{legacy_application_port(&1)}")

    [
      "Florist keeps persistent media at `<base>/<project>/media` and links it into versioned releases; verify the legacy media location and protect its contents during the first cutover.",
      "Review legacy `etc/` systemd, nginx, logrotate, pgbackup, and cron configuration before running `florist bootstrap`.",
      "Generated application ports use Brando's bundled Fabric defaults (#{application_ports}); verify them against each `.envrc.<flavor>` and legacy nginx upstream."
    ]
    |> maybe_add_warning(String.contains?(fabfile, "def setup_rclone"), fn ->
      "Legacy rclone settings were not copied because the fabfile prompts for credentials and contains deployment-specific bucket paths; configure Florist's `rclone` block manually."
    end)
  end

  defp maybe_add_warning(warnings, true, warning), do: warnings ++ [warning.()]
  defp maybe_add_warning(warnings, false, _warning), do: warnings

  defp render_config(settings, targets) do
    rendered_targets = Enum.map_join(targets, "\n", &render_target/1)
    database_variables = Enum.map_join(targets, ", ", &database_password_variable(&1.name))

    """
    # Florist configuration generated by `mix brando.migrate54`.
    # Source: legacy deployment.cfg + fabfile.py. Review every value before use.
    # Database passwords: #{database_variables}
    # SSH authentication uses your agent unless you add an environment-backed pass.

    use Florist.DSL

    project_name #{inspect(settings["PROJECT_NAME"])}
    project_module #{settings["PROJECT_MODULE"]}

    #{rendered_targets}
    """
  end

  defp render_target(target) do
    """
    target :#{target.name} do
      set :flavor, :#{target.flavor}
      set :mix_env, :#{target.mix_env}
      set :description, #{inspect("Legacy Fabric #{target.name} deployment")}
      set :base_dir, #{inspect(target.base_dir)}
      set :process_name, #{inspect(target.process_name)}
      set :release_builder, :elixir

      ssh do
        set :host, #{inspect(target.ssh_host)}
        set :user, #{inspect(target.ssh_user)}
        set :port, #{target.ssh_port}
      end

      remote do
        set :user, #{inspect(target.remote_user)}
        set :group, #{inspect(target.remote_group)}
      end

      database do
        set :name, #{inspect(target.database_name)}
        set :user, #{inspect(target.database_user)}
        set :pgbackup_enabled, #{target.pgbackup_enabled}
        # Password: FLORIST_DB_PASSWORD_#{target.name |> Atom.to_string() |> String.upcase()}
      end

      docker do
    #{render_optional_setting(:host, target.docker_host, 4)}    set :dockerfile, #{inspect(target.dockerfile)}
      end

      deployment do
        set :type, :single
        # Florist uses :blue_port as the application port for :single deployments.
        set :blue_port, #{target.application_port}
      end

      webserver do
        set :type, :nginx
    #{render_domain(target.domain)}    set :ssl, #{inspect(target.ssl)}
        set :redirect_http, #{target.redirect_http}
        set :redirect_www, false
        set :noindex, #{target.noindex}
      end
    end
    """
  end

  defp render_optional_setting(_key, nil, _indent), do: ""

  defp render_optional_setting(key, value, indent) do
    "#{String.duplicate(" ", indent)}set #{inspect(key)}, #{inspect(value)}\n"
  end

  defp render_domain(nil), do: "    # TODO: set :domain for this target\n"
  defp render_domain(domain), do: "    set :domain, #{inspect(domain)}\n"

  defp database_password_variable(target) do
    "FLORIST_DB_PASSWORD_#{target |> Atom.to_string() |> String.upcase()}"
  end

  defp blank?(nil), do: true
  defp blank?(value) when is_binary(value), do: String.trim(value) == ""
  defp blank?(_value), do: false

  defp blank_to_nil(value), do: if(blank?(value), do: nil, else: value)
end
