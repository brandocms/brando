if Code.ensure_loaded?(Igniter) do
  defmodule Mix.Brando.Igniter.Install.Toolchain do
    @doc "Requests recompilation when optional Igniter support is removed."
    def __mix_recompile__?, do: not Code.ensure_loaded?(Igniter)

    @moduledoc false

    alias Brando.Utils
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
    pin is written only when the running Erlang and Elixir are the installs
    asdf or mise name as the pin does: a shim stops at a pinned version it has
    not installed under that name. It is also left out when the application or
    a folder above it, below the home folder, pins a toolchain. Otherwise a
    notice suggests the file.

    `igniter.assigns[:brando_toolchain]` may give `:running` (`%{"erlang" =>
    root, "elixir" => root}`), `:data_dirs` (version managers' data folders)
    and `:parents` (folders to look in) in place of the running system's.
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
      data_dirs = Map.get_lazy(overrides, :data_dirs, &data_dirs/0)

      cond do
        own = Enum.find(@toolchain_files, &Igniter.exists?(igniter, &1)) ->
          "the application pins its toolchain in #{own}"

        parent = Enum.find_value(Map.get_lazy(overrides, :parents, &parents/0), &pinned_in/1) ->
          "#{parent} pins a toolchain for the folders below it"

        not pinned_install?(pins, running, data_dirs) ->
          "this install does not run the Erlang #{pins["erlang"]} and Elixir #{pins["elixir"]} that asdf or mise installed under those names " <>
            "(it runs Erlang from #{running["erlang"]} and Elixir from #{running["elixir"]}), " <>
            "and with the pin, asdf or mise would stop the install's own `mix` tasks in the application until they are installed under those names"

        true ->
          nil
      end
    end

    @doc """
    Whether the running Erlang and Elixir (`running`, their root folders) are
    the installs one version manager has under the names `pins` gives, in
    `installs/<tool>/<name>` of one of `data_dirs` (mise's and asdf's), so its
    shims run them with the pin written. Any doubt is a no.
    """
    def pinned_install?(pins, running \\ running(), data_dirs \\ data_dirs()) do
      Enum.any?(data_dirs, fn dir ->
        Enum.all?(~w(erlang elixir), fn tool ->
          install = Path.join([dir, "installs", tool, pins[tool]])
          File.dir?(install) and Utils.real_path(install) == Utils.real_path(running[tool])
        end)
      end)
    end

    defp pinned_in(dir) do
      Enum.find_value(@toolchain_files, fn file ->
        path = Path.join(dir, file)
        if File.regular?(path), do: path
      end)
    end

    @doc """
    The folders above the application at `cwd`, up to the user's `home`
    folder, whose own `.tool-versions` holds the global versions the pin is
    meant to replace. Both are compared as real paths: `File.cwd!/0` gives
    one, and a home folder may be a symlink.
    """
    def parents(cwd \\ File.cwd!(), home \\ System.user_home()) do
      home = home && Utils.real_path(home)

      cwd
      |> Utils.real_path()
      |> Path.split()
      |> Enum.drop(-1)
      |> Enum.scan(&Path.join(&2, &1))
      |> Enum.reject(&(&1 == "/" or (home != nil and (home == &1 or String.starts_with?(home, &1 <> "/")))))
    end

    # The running Erlang's and Elixir's root folders.
    defp running do
      %{
        "erlang" => to_string(:code.root_dir()),
        "elixir" => :code.lib_dir(:elixir) |> Path.join("../..") |> Path.expand()
      }
    end

    # Where mise and asdf keep their installs, under installs/<tool>/<name>.
    defp data_dirs do
      mise = System.get_env("MISE_DATA_DIR") || Path.join(System.get_env("XDG_DATA_HOME") || "~/.local/share", "mise")
      asdf = System.get_env("ASDF_DATA_DIR") || "~/.asdf"
      Enum.map([mise, asdf], &Path.expand/1)
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
