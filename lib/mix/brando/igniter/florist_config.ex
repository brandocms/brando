if Code.ensure_loaded?(Igniter) do
  defmodule Mix.Brando.Igniter.FloristConfig do
    @doc "Requests recompilation when optional Igniter support is removed."
    def __mix_recompile__?, do: not Code.ensure_loaded?(Igniter)

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

    # Values Brando's install templates shipped and sites left in place.
    @placeholder_hosts ~w(somesite.com host.net)

    @type warning :: String.t()

    @doc """
    Generates `florist.config.exs` content from legacy `deployment.cfg` and
    `fabfile.py` contents.

    `files` maps project-relative paths to the contents of the other legacy
    deployment files, which fill what `deployment.cfg` leaves out:

      * a target's domain, when `<TARGET>_URL` is missing or still the install
        template's placeholder, from `.envrc.<flavor>` (`BRANDO_URL_HOST`) or
        the proxying `server_name` in `etc/nginx/<flavor>.conf`;
      * a target's application port from `PORT=` in
        `etc/supervisord/<flavor>.conf` or `etc/systemd/<flavor>.service`,
        checked against the `etc/nginx/<flavor>.conf` upstream;
      * the process manager (`etc/supervisord/` or `etc/systemd/`), which the
        warnings name.

    Password values are never copied into the generated configuration. The
    returned warnings identify required environment variables and any legacy
    expressions that could not be converted deterministically.
    """
    @spec generate(String.t(), String.t(), %{optional(String.t()) => String.t()}) ::
            {:ok, String.t(), [warning()]} | {:error, String.t()}
    def generate(deployment_config, fabfile, files \\ %{})
        when is_binary(deployment_config) and is_binary(fabfile) and is_map(files) do
      with {:ok, settings} <- parse_deployment_config(deployment_config),
           :ok <- validate_required_settings(settings),
           :ok <- validate_project_module(settings["PROJECT_MODULE"]),
           {:ok, ssh_port} <- parse_ssh_port(settings["SSH_PORT"]),
           {:ok, target_names} <- find_targets(fabfile) do
        {targets, conversion_warnings} = build_targets(target_names, settings, ssh_port, fabfile, files)

        warnings =
          conversion_warnings
          |> Kernel.++(secret_warnings(settings, target_names))
          |> Kernel.++(deployment_warnings(fabfile, targets, files))
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

    defp build_targets(target_names, settings, ssh_port, fabfile, files) do
      {group, warnings} = global_setting(fabfile, "project_group", "web")
      docker_host = blank_to_nil(settings["DOCKER_HOST"])

      Enum.map_reduce(target_names, warnings, fn target, warnings ->
        {target_config, target_warnings} =
          build_target(target, settings, ssh_port, fabfile, group, docker_host, files)

        {target_config, warnings ++ target_warnings}
      end)
    end

    defp build_target(target, settings, ssh_port, fabfile, group, docker_host, files) do
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
      legacy_files = flavor_files(files, flavor, target)
      {domain, ssl, redirect_http, warnings} = target_webserver(settings, target, legacy_files, warnings)
      {application_port, port_source, warnings} = application_port(target, legacy_files, warnings)

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
        application_port: application_port,
        port_source: port_source,
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
        database_user: "${PROJECT_NAME}"
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

    defp target_webserver(settings, target, legacy_files, warnings) do
      key = target |> Atom.to_string() |> String.upcase() |> Kernel.<>("_URL")
      {configured, warnings} = configured_webserver(settings[key], key, target, warnings)

      case configured || inferred_webserver(legacy_files) do
        {host, ssl, redirect_http} ->
          {host, ssl, redirect_http, warnings}

        {host, ssl, redirect_http, source} ->
          {host, ssl, redirect_http, ["Took the #{target} domain #{host} from #{source}; verify it." | warnings]}

        nil ->
          warning = "No #{key} was found; set the #{target} webserver domain in florist.config.exs."
          {nil, :auto, true, [warning | warnings]}
      end
    end

    # `<TARGET>_URL` from deployment.cfg, unless it is missing or a placeholder.
    defp configured_webserver(url, key, target, warnings) do
      with url when is_binary(url) <- blank_to_nil(url),
           {host, ssl, redirect_http, warnings} when is_binary(host) <-
             parse_target_webserver_url(url, key, target, warnings) do
        if placeholder_host?(host),
          do: {nil, ["#{key} = #{url} is the install template's placeholder, not the #{target} domain." | warnings]},
          else: {{host, ssl, redirect_http}, warnings}
      else
        nil -> {nil, warnings}
        {nil, _ssl, _redirect_http, warnings} -> {nil, warnings}
      end
    end

    defp inferred_webserver(legacy_files) do
      envrc_webserver(legacy_files.envrc) || nginx_webserver(legacy_files.nginx)
    end

    defp envrc_webserver(nil), do: nil

    defp envrc_webserver({path, content}) do
      with host when is_binary(host) <- last_export(content, "BRANDO_URL_HOST"),
           false <- placeholder_host?(host) do
        https? = last_export(content, "BRANDO_URL_PORT") == "443" or last_export(content, "BRANDO_URL_SCHEME") == "https"
        {host, if(https?, do: :auto, else: false), https?, "#{path} (BRANDO_URL_HOST)"}
      else
        _ -> nil
      end
    end

    defp last_export(content, variable) do
      case Regex.scan(~r/^[ \t]*export[ \t]+#{variable}=["']?([^"'\s#]+)/m, content) do
        [] -> nil
        matches -> matches |> List.last() |> List.last()
      end
    end

    # The domain of the server block that proxies to the application, preferring
    # one that serves HTTPS over a plain-HTTP block for the same upstream.
    defp nginx_webserver(nil), do: nil

    defp nginx_webserver({path, content}) do
      servers =
        content
        |> strip_comments()
        |> nginx_server_blocks()
        |> Enum.filter(&String.contains?(&1, "proxy_pass"))
        |> Enum.map(&{server_names(&1), Regex.match?(~r/\blisten\s+[^;]*\b443\b/, &1)})
        |> Enum.reject(&match?({[], _https?}, &1))

      case Enum.find(servers, &elem(&1, 1)) || List.first(servers) do
        {[host | _], https?} -> {host, if(https?, do: :auto, else: false), https?, "#{path} (server_name)"}
        nil -> nil
      end
    end

    defp strip_comments(content), do: Regex.replace(~r/#[^\n]*/, content, "")

    defp nginx_server_blocks(content) do
      ~r/\bserver\s*\{/
      |> Regex.scan(content, return: :index)
      |> Enum.map(fn [{start, length}] -> block_body(content, start + length) end)
    end

    # The text from `offset` up to the brace that closes the block opened just before it.
    defp block_body(content, offset) do
      content
      |> binary_part(offset, byte_size(content) - offset)
      |> String.graphemes()
      |> Enum.reduce_while({1, []}, fn
        "}", {1, acc} -> {:halt, {0, acc}}
        "}", {depth, acc} -> {:cont, {depth - 1, ["}" | acc]}}
        "{", {depth, acc} -> {:cont, {depth + 1, ["{" | acc]}}
        char, {depth, acc} -> {:cont, {depth, [char | acc]}}
      end)
      |> elem(1)
      |> Enum.reverse()
      |> Enum.join()
    end

    defp server_names(server) do
      ~r/\bserver_name\s+([^;{}]+)/
      |> Regex.scan(server, capture: :all_but_first)
      |> Enum.flat_map(fn [names] -> String.split(names) end)
      |> Enum.reject(&(&1 == "_" or String.contains?(&1, "*") or placeholder_host?(&1)))
    end

    defp placeholder_host?(host), do: host in @placeholder_hosts or String.contains?(host, "byXX")

    # The port the process manager starts the release on, checked against the
    # port nginx proxies to.
    defp application_port(target, legacy_files, warnings) do
      manager_port = find_port(legacy_files.manager, ~r/\bPORT=["']?(\d+)/)

      upstream_port =
        find_port(legacy_files.nginx, ~r/\bupstream\s+\S+\s*\{[^}]*?\bserver\s+(?:127\.0\.0\.1|localhost|\[::1\]):(\d+)/)

      case {manager_port, upstream_port} do
        {nil, nil} ->
          {legacy_application_port(target), :default, warnings}

        {{port, source}, nil} ->
          {port, source, warnings}

        {nil, {port, source}} ->
          {port, source, warnings}

        {{port, source}, {port, _upstream}} ->
          {port, source, warnings}

        {{port, source}, {other, upstream}} ->
          warning =
            "#{source} starts #{target} on port #{port}, but #{upstream} proxies to #{other}; using #{port}."

          {port, source, [warning | warnings]}
      end
    end

    defp find_port(nil, _regex), do: nil

    defp find_port({path, content}, regex) do
      case Regex.run(regex, strip_comments(content), capture: :all_but_first) do
        [port] -> {String.to_integer(port), path}
        nil -> nil
      end
    end

    # The legacy files for a target, found by its flavor (`etc/nginx/prod.conf`)
    # or, failing that, its name.
    defp flavor_files(files, flavor, target) do
      names = Enum.uniq([flavor, Atom.to_string(target)])
      find = fn paths -> Enum.find_value(paths, &(files[&1] && {&1, files[&1]})) end

      %{
        envrc: find.(Enum.map(names, &".envrc.#{&1}")),
        nginx: find.(Enum.map(names, &"etc/nginx/#{&1}.conf")),
        manager: find.(Enum.map(names, &"etc/supervisord/#{&1}.conf") ++ Enum.map(names, &"etc/systemd/#{&1}.service"))
      }
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

    defp deployment_warnings(fabfile, targets, files) do
      defaulted = Enum.filter(targets, &(&1.port_source == :default))
      application_ports = Enum.map_join(defaulted, ", ", &"#{&1.name} #{&1.application_port}")

      [
        "Florist keeps persistent media at `<base>/<project>/media` and links it into versioned releases; verify the legacy media location and protect its contents during the first cutover.",
        process_manager_warning(files)
      ]
      |> maybe_add_warning(defaulted != [], fn ->
        "Generated application ports use Brando's bundled Fabric defaults (#{application_ports}); no `etc/supervisord`, `etc/systemd` or nginx upstream named them. Verify them against the server."
      end)
      |> maybe_add_warning(String.contains?(fabfile, "def setup_rclone"), fn ->
        "Legacy rclone settings were not copied because the fabfile prompts for credentials and contains deployment-specific bucket paths; configure Florist's `rclone` block manually."
      end)
    end

    defp process_manager_warning(files) do
      paths = Map.keys(files)

      case {Enum.any?(paths, &String.starts_with?(&1, "etc/supervisord/")),
            Enum.any?(paths, &String.starts_with?(&1, "etc/systemd/"))} do
        {true, _systemd?} ->
          "The legacy deployment runs under supervisord (`etc/supervisord/`), and Florist runs the release as a systemd service. Stop and disable the supervisord program on the server at cutover so both don't claim the port, and review the legacy nginx, logrotate, pgbackup and cron configuration before running `florist bootstrap`."

        {false, true} ->
          "The legacy deployment runs under systemd (`etc/systemd/`). Florist writes its own systemd unit; review the legacy unit, nginx, logrotate, pgbackup and cron configuration before running `florist bootstrap`."

        {false, false} ->
          "Review legacy `etc/` process manager (systemd or supervisord), nginx, logrotate, pgbackup, and cron configuration before running `florist bootstrap`."
      end
    end

    defp maybe_add_warning(warnings, true, warning), do: warnings ++ [warning.()]
    defp maybe_add_warning(warnings, false, _warning), do: warnings

    defp render_config(settings, targets) do
      rendered_targets = Enum.map_join(targets, "\n", &render_target/1)
      database_variables = Enum.map_join(targets, ", ", &database_password_variable(&1.name))

      """
      # Florist configuration generated by `mix brando.migrate55`.
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
else
  defmodule Mix.Brando.Igniter.FloristConfig do
    @moduledoc false
    # Revisit this source when the optional dependency becomes available.
    def __mix_recompile__?, do: Code.ensure_loaded?(Igniter)
  end
end
