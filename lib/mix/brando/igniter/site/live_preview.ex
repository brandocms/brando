if Code.ensure_loaded?(Igniter) do
  defmodule Mix.Brando.Igniter.Site.LivePreview do
    @doc "Requests recompilation when optional Igniter support is removed."
    def __mix_recompile__?, do: not Code.ensure_loaded?(Igniter)

    @moduledoc false

    alias Igniter.Code.Function, as: CodeFunction
    alias Igniter.Project.Module, as: ProjectModule
    alias Mix.Brando.Igniter.Files
    alias Mix.Brando.Igniter.Template
    alias Rewrite.Source

    @template "live_preview.ex"

    @doc """
    Gives CMS pages a live preview: a `preview_target` for `Brando.Pages.Page`
    in the application's LivePreview module that renders with the CMS layout
    and templates.

    A missing module, or the bare one `brando.install` writes, becomes the
    template. A module that already previews pages is kept as it is; any
    other gets a notice with the target to add.
    """
    def plan(igniter, project) do
      module = Module.concat(project.web_module, LivePreview)

      case render(igniter, project) do
        {:ok, igniter, generated} -> place(igniter, module, generated)
        {:error, igniter} -> igniter
      end
    end

    defp place(igniter, module, generated) do
      case ProjectModule.find_module(igniter, module) do
        {:ok, {igniter, source, zipper}} -> update(igniter, module, source, zipper, generated)
        {:error, igniter} -> Files.create(igniter, "lib/#{Macro.underscore(module)}.ex", generated)
      end
    end

    defp update(igniter, module, source, zipper, generated) do
      path = Source.get(source, :path)

      cond do
        previews_pages?(zipper) ->
          igniter

        same_code?(Source.get(source, :content), bare(module)) ->
          Igniter.update_file(igniter, path, &Source.update(&1, :content, generated))

        true ->
          notice(igniter, path, generated)
      end
    end

    @doc "The LivePreview module `brando.install` writes, without targets."
    def bare(module) do
      """
      defmodule #{inspect(module)} do
        use Brando.LivePreview
      end
      """
    end

    defp render(igniter, project) do
      case Template.render(igniter, "brando.gen.site", @template, web_module: inspect(project.web_module)) do
        {:ok, igniter, contents} -> {:ok, igniter, contents}
        {:error, message} -> {:error, Igniter.add_issue(igniter, message)}
      end
    end

    # Any preview_target whose schema is Page or ends in Pages.Page.
    defp previews_pages?(zipper) do
      match?(
        {:ok, _},
        CodeFunction.move_to_function_call(zipper, :preview_target, 2, fn call ->
          case CodeFunction.move_to_nth_argument(call, 0) do
            {:ok, %{node: {:__aliases__, _, segments}}} -> page_alias?(segments)
            _ -> false
          end
        end)
      )
    end

    defp page_alias?(segments), do: segments == [:Page] or Enum.take(segments, -2) == [:Pages, :Page]

    defp notice(igniter, path, generated) do
      Igniter.add_notice(igniter, """
      #{path} is customized and has no preview target for Brando.Pages.Page, so it was left
      unchanged. For a live preview of CMS pages, add the target from the generated module:

      #{generated}
      """)
    end

    defp same_code?(left, right) do
      with {:ok, left} <- Sourceror.parse_string(left),
           {:ok, right} <- Sourceror.parse_string(right) do
        Sourceror.strip_meta(left) == Sourceror.strip_meta(right)
      else
        _ -> false
      end
    end
  end
else
  defmodule Mix.Brando.Igniter.Site.LivePreview do
    @moduledoc false
    # Revisit this source when the optional dependency becomes available.
    def __mix_recompile__?, do: Code.ensure_loaded?(Igniter)
  end
end
