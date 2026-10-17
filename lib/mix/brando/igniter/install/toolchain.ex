if Code.ensure_loaded?(Igniter) do
  defmodule Mix.Brando.Igniter.Install.Toolchain do
    @doc "Requests recompilation when optional Igniter support is removed."
    def __mix_recompile__?, do: not Code.ensure_loaded?(Igniter)

    @moduledoc false

    alias Mix.Brando.Igniter.Files
    alias Mix.Brando.Install.Templates

    # Files that pin a toolchain for asdf, mise, nvm or Node version managers.
    # A .tool-versions would override what they pin.
    @toolchain_files ~w(
      .tool-versions .mise.toml mise.toml mise.local.toml .mise.local.toml .mise/config.toml
      .config/mise.toml .config/mise/config.toml .nvmrc .node-version
    )

    @doc """
    Pins the toolchain Brando is tested with in a new application's
    `.tool-versions`, so a plain `mix` or `pnpm` there uses it.

    Igniter runs the install's follow-up tasks (`brando.install.secrets`,
    `deps.get`) as `mix` in the application once the files are written, so the
    pin is written only when the running Erlang and Elixir are the pinned ones:
    asdf refuses a pinned version it has not installed. It is also left out
    when the application or a folder above it, below the home folder, pins a
    toolchain. Otherwise a notice suggests the file.

    `igniter.assigns[:brando_toolchain]` may give `:running` (`%{"erlang" =>
    version, "elixir" => version}`) and `:parents` (folders to look in) in
    place of the running system's.
    """
    def plan(igniter, fresh?)
    def plan(igniter, false), do: igniter

    def plan(igniter, true) do
      contents = Templates.contents(:copy, "tool-versions")
      pins = pins(contents)

      case reason(igniter, pins) do
        nil ->
          igniter
          |> Files.create(".tool-versions", contents)
          |> Igniter.add_notice("""
          .tool-versions pins Erlang #{pins["erlang"]}, Elixir #{pins["elixir"]}, Node.js #{pins["nodejs"]} and pnpm #{pins["pnpm"]}.
          Run `mise install` (or `asdf install`) for the Node.js and pnpm it names.
          """)

        reason ->
          Igniter.add_notice(igniter, """
          No .tool-versions was written: #{reason}. Brando is tested with:

          #{contents |> String.split("\n", trim: true) |> Enum.map_join("\n", &("  " <> &1))}

          To pin those, write them to .tool-versions and run `mise install` (or `asdf install`).
          """)
      end
    end

    defp reason(igniter, pins) do
      overrides = Map.get(igniter.assigns, :brando_toolchain, %{})
      running = Map.get_lazy(overrides, :running, &running/0)

      cond do
        own = Enum.find(@toolchain_files, &Igniter.exists?(igniter, &1)) ->
          "the application pins its toolchain in #{own}"

        parent = Enum.find_value(Map.get_lazy(overrides, :parents, &parents/0), &pinned_in/1) ->
          "#{parent} pins a toolchain for the folders below it"

        different = Enum.find(~w(erlang elixir), &(running[&1] != pins[&1])) ->
          "this install runs #{different} #{running[different]}, not #{pins[different]}, and asdf would stop the install's own `mix` tasks in the application until that is installed"

        true ->
          nil
      end
    end

    defp pinned_in(dir) do
      Enum.find_value(@toolchain_files, fn file ->
        path = Path.join(dir, file)
        if File.regular?(path), do: path
      end)
    end

    # The folders above the application, up to its user's home folder, whose
    # own .tool-versions holds the global versions the pin is meant to replace.
    defp parents do
      home = System.user_home()

      File.cwd!()
      |> Path.expand()
      |> Path.split()
      |> Enum.drop(-1)
      |> Enum.scan(&Path.join(&2, &1))
      |> Enum.reject(&(&1 == "/" or (home != nil and (home == &1 or String.starts_with?(home, &1 <> "/")))))
    end

    defp running do
      otp = to_string(:erlang.system_info(:otp_release))

      erlang =
        case File.read(Path.join([to_string(:code.root_dir()), "releases", otp, "OTP_VERSION"])) do
          {:ok, version} -> String.trim(version)
          {:error, _} -> otp
        end

      %{"erlang" => erlang, "elixir" => "#{System.version()}-otp-#{System.build_info()[:otp_release]}"}
    end

    defp pins(contents) do
      for line <- String.split(contents, "\n", trim: true), into: %{} do
        [tool, version] = String.split(line)
        {tool, version}
      end
    end
  end
else
  defmodule Mix.Brando.Igniter.Install.Toolchain do
    @moduledoc false
    # Revisit this source when the optional dependency becomes available.
    def __mix_recompile__?, do: Code.ensure_loaded?(Igniter)
  end
end
