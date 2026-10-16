if Code.ensure_loaded?(Igniter) do
  defmodule Mix.Brando.Igniter.Install.PhoenixStatic do
    @doc "Requests recompilation when optional Igniter support is removed."
    def __mix_recompile__?, do: not Code.ensure_loaded?(Igniter)

    @moduledoc false

    alias Igniter.Code.Function, as: CodeFunction
    alias Igniter.Project.Module, as: ProjectModule
    alias Mix.Brando.Install.Templates
    alias Sourceror.Zipper

    # SHA-256 of the files `mix phx.new` writes to priv/static, the same from
    # phx_new 1.7.21 to 1.8.13. Only a file still exactly as phx.new wrote it
    # is removed or moved.
    @robots "priv/static/robots.txt"
    @robots_sha256 "f994bfae2c1db1221ac049f1097776b444048e0b0a7705d33ea511b610bed115"
    @favicon "priv/static/favicon.ico"
    @favicon_sha256 "01723aeae3ce3b5195a8f42e3eb6e9018a8c08b7acda4ed382b31341811f0a8a"
    @logo "priv/static/images/logo.svg"
    @logo_sha256 "a730517dbca12868ac89a0711edfef20cb65e2801d1ac7063338d04a98457f0f"

    @public_favicon "assets/frontend/public/favicon.ico"
    @public_logo "assets/frontend/public/images/logo.svg"

    @doc """
    Takes the favicon and logo `mix phx.new` writes out of `priv/static`.

    Brando's Docker build makes `priv/static` from the two Vite builds only, so
    a file there works in development and is missing from the release. The
    favicon is removed: Brando writes its own to `assets/frontend/public`.
    The logo moves to `assets/frontend/public/images/logo.svg`, or is removed
    when the site already has a file there. A file the frontend build copied
    from `assets/frontend/public` is left alone, and any other file is kept,
    with a notice.
    """
    def plan(igniter) do
      igniter
      |> favicon()
      |> logo()
    end

    @doc """
    Removes the `priv/static/robots.txt` `mix phx.new` writes, and `robots.txt`
    from `static_paths/0` in the web module, so `BrandoWeb.SEOController`
    answers `/robots.txt` in development as it does in the release. A changed
    file is kept, with a notice.
    """
    def robots(igniter, project) do
      case read(igniter, @robots) do
        {igniter, nil} ->
          igniter

        {igniter, contents} ->
          if sha256(contents) == @robots_sha256 do
            igniter
            |> Igniter.rm(@robots)
            |> drop_static_path(project.web_module)
          else
            Igniter.add_notice(igniter, """
            #{@robots} is not the file mix phx.new writes, so it was kept. BrandoWeb.SEOController answers
            /robots.txt from the SEO settings in the admin, but in development Plug.Static serves this file
            first, and the release does not have it (the Docker build leaves priv/static out). Move its rules
            to the SEO settings, delete it, and remove robots.txt from static_paths/0 in #{inspect(project.web_module)}.
            """)
          end
      end
    end

    defp favicon(igniter) do
      case read(igniter, @favicon) do
        {igniter, nil} ->
          igniter

        {igniter, contents} ->
          {igniter, public} = read(igniter, @public_favicon)

          cond do
            sha256(contents) == @favicon_sha256 ->
              Igniter.rm(igniter, @favicon)

            contents in [public, Templates.contents(:copy, @public_favicon)] ->
              igniter

            true ->
              Igniter.add_notice(igniter, """
              #{@favicon} is not the file mix phx.new writes, so it was kept. The release does not have it:
              the Docker build makes priv/static from the Vite builds. To ship it, move it to #{@public_favicon},
              which the frontend build copies to priv/static.
              """)
          end
      end
    end

    defp logo(igniter) do
      case read(igniter, @logo) do
        {igniter, nil} ->
          igniter

        {igniter, contents} ->
          {igniter, public} = read(igniter, @public_logo)

          cond do
            contents == public -> igniter
            sha256(contents) != @logo_sha256 -> logo_notice(igniter, public)
            public -> Igniter.rm(igniter, @logo)
            true -> Igniter.move_file(igniter, @logo, @public_logo)
          end
      end
    end

    defp logo_notice(igniter, public) do
      move =
        if public,
          do: "Compare it with #{@public_logo}, which the frontend build copies over it, and delete it.",
          else: "To ship it, move it to #{@public_logo}, which the frontend build copies to priv/static."

      Igniter.add_notice(igniter, """
      #{@logo} is not the file mix phx.new writes, so it was kept. The release does not have it:
      the Docker build makes priv/static from the Vite builds. #{move}
      """)
    end

    defp drop_static_path(igniter, web_module) do
      case ProjectModule.find_and_update_module(igniter, web_module, &without_robots/1) do
        {:ok, igniter} -> igniter
        {:error, igniter} -> igniter
      end
    end

    # phx.new writes `def static_paths, do: ~w(assets fonts images favicon.ico robots.txt)`;
    # a list of strings is read too.
    defp without_robots(zipper) do
      case CodeFunction.move_to_def(zipper, :static_paths, 0) do
        {:ok, body} -> {:ok, Zipper.update(body, &Macro.prewalk(&1, fn node -> drop_robots(node) end))}
        :error -> {:ok, zipper}
      end
    end

    defp drop_robots({:sigil_w, meta, [{:<<>>, string_meta, [words]}, modifiers]} = node) when is_binary(words) do
      if "robots.txt" in String.split(words) do
        words = words |> String.split() |> List.delete("robots.txt") |> Enum.join(" ")
        {:sigil_w, meta, [{:<<>>, string_meta, [words]}, modifiers]}
      else
        node
      end
    end

    defp drop_robots(list) when is_list(list), do: Enum.reject(list, &match?({:__block__, _, ["robots.txt"]}, &1))
    defp drop_robots(node), do: node

    defp read(igniter, path) do
      if Igniter.exists?(igniter, path) do
        igniter = Igniter.include_existing_file(igniter, path)
        {igniter, igniter.rewrite |> Rewrite.source!(path) |> Rewrite.Source.get(:content)}
      else
        {igniter, nil}
      end
    end

    defp sha256(contents), do: :sha256 |> :crypto.hash(contents) |> Base.encode16(case: :lower)
  end
else
  defmodule Mix.Brando.Igniter.Install.PhoenixStatic do
    @moduledoc false
    # Revisit this source when the optional dependency becomes available.
    def __mix_recompile__?, do: Code.ensure_loaded?(Igniter)
  end
end
