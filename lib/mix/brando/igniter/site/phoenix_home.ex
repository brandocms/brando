if Code.ensure_loaded?(Igniter) do
  defmodule Mix.Brando.Igniter.Site.PhoenixHome do
    @doc "Requests recompilation when optional Igniter support is removed."
    def __mix_recompile__?, do: not Code.ensure_loaded?(Igniter)

    @moduledoc false

    alias Igniter.Project.Module, as: ProjectModule
    alias Mix.Brando.Igniter.Site.ErrorPages
    alias Rewrite.Source

    # SHA-256 of the home.html.heex `mix phx.new` writes, phx_new 1.7.0 to
    # 1.8.15, with and without Tailwind. A project created through Elixir's
    # install script gets a variant naming its install paths; that one counts
    # as changed.
    @home_sha256 ~w(
      3dc78e05e4c9182d6c311b9d81f4ab8c1f8525a45b89ebd615933c49efd97582
      faacea1fc6ecb0573c3722e9a0e8f4e8295fb3f006abfe2a34b5341dbef9b8d0
      9e530cda940ed2ec49bf6d1669d3661e1426c90cd0fceb95322b78a239a7d9eb
      bcecb4516a9209dac8b9af803e8da107e941c46d88e9e96c028189e9f6875fcd
      8ea7f63a5071aef298687f616e0246d44c244036ec70c6aba186b4a1a236986d
      98ed26da1335b031907c2b94b2e16e058b588bd22844e6c3ba5b1dd806f301a7
      70808064c87c6c49fac61d8b2380e978332067730d1776c09bbabf243ac3b77b
      b42ca767146054b7893599d3b772bf671d58dc8d0a062480115eb00ae0521384
      472c5fd944122f2834340286feb69d7d656aca50f2e0ae3553ffca4da5f14656
      c1645994b0885b6d97414ae1b6198898a5c7bee915a9e90761820432ae3af90d
      0b71a918a62b68199434c21155677c73c808d04462731d66faf1678e127b3f8f
      70c43c09bad12300ee2a9c848aa180e90339b659898a611ff557dcb3698ab7e2
      8a20904c52725a1ca782897143018834b754b8c253cc7ad0dda29b9f3d6091da
      c570aada5253aa7eaa49f26420ab3b573017169d367ced7516f23af34c758f0f
    )

    @doc """
    Whether the application's `PageController` and its `home.html.heex` are
    still as `mix phx.new` wrote them, so its homepage is phx.new's welcome
    page rather than the application's own.
    """
    def unchanged?(igniter, project) do
      controller = Module.concat(project.web_module, PageController)

      case ProjectModule.find_module(igniter, controller) do
        {:ok, {igniter, source, _zipper}} ->
          template = source |> Source.get(:path) |> Path.dirname() |> Path.join("page_html/home.html.heex")
          content = Source.get(source, :content)

          if Enum.any?(controllers(project), &ErrorPages.same_code?(content, &1)),
            do: home?(igniter, template),
            else: {igniter, false}

        {:error, igniter} ->
          {igniter, false}
      end
    end

    defp home?(igniter, template) do
      if Igniter.exists?(igniter, template) do
        igniter = Igniter.include_existing_file(igniter, template)
        content = igniter.rewrite |> Rewrite.source!(template) |> Source.get(:content)
        {igniter, sha256(content) in @home_sha256}
      else
        {igniter, false}
      end
    end

    # 1.7 renders the homepage without the app layout, 1.8 within it.
    defp controllers(project) do
      web = inspect(project.web_module)

      for render <- ["render(conn, :home)", "render(conn, :home, layout: false)"] do
        """
        defmodule #{web}.PageController do
          use #{web}, :controller

          def home(conn, _params) do
            #{render}
          end
        end
        """
      end
    end

    defp sha256(contents), do: :sha256 |> :crypto.hash(contents) |> Base.encode16(case: :lower)
  end
else
  defmodule Mix.Brando.Igniter.Site.PhoenixHome do
    @moduledoc false
    # Revisit this source when the optional dependency becomes available.
    def __mix_recompile__?, do: Code.ensure_loaded?(Igniter)
  end
end
