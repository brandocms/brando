defmodule Brando.SSG do
  @doc """
  Static site generation

  - In your `router.ex` add the SSG plug to your `:browser` pipeline:

  ```
      pipeline :browser do
        # ...
        plug Brando.Plug.SSG
      end
  ```

  - Create `lib/my_app_web/ssg.ex`:

  ```
      defmodule MyAppWeb.SSG do
        import Brando.SSG

        urls :pages do
          ["/", "/projects", "/about"]
        end

        urls :projects do
          %{status: :published}
          |> Projects.list_projects!()
          |> Enum.map(Projects.Project.__absolute_url__())
        end
      end
  ```

  Run `mix brando.ssg`

  Then create an rsync script: `code sync.sh`

  ```
  #!/bin/sh
  rsync -arvzi -e 'ssh -p 30000' --progress ssg/ my_user@my_server:/sites/prod/my_app/ --delete
  ```
  """
  defmacro urls(key, do: block) do
    quote do
      def unquote(:"__urls_for_#{key}__")() do
        unquote(block)
      end
    end
  end

  defmacro render_path(path) do
    quote do
      def __render_path__ do
        unquote(path)
      end
    end
  end

  defp has_custom_render_path(module) do
    {:__render_path__, 0} in module.__info__(:functions)
  end

  def get_root_path do
    ssg_module = Brando.web_module(SSG)

    case Code.ensure_compiled(ssg_module) do
      {:module, _} ->
        if has_custom_render_path(ssg_module) do
          ssg_module.__render_path__()
        else
          Path.join([File.cwd!(), "ssg"])
        end

      {:error, _} ->
        raise "Missing SSG module `#{ssg_module}`"
    end
  end

  def get_urls do
    ssg_module = Brando.web_module(SSG)

    case Code.ensure_compiled(ssg_module) do
      {:module, _} ->
        ssg_functions =
          :functions
          |> ssg_module.__info__()
          |> Enum.reject(&(&1 == {:__render_path__, 0}))

        entries = Stream.flat_map(ssg_functions, &apply(ssg_module, elem(&1, 0), []))

        Brando.Repo.transaction(fn -> Enum.to_list(entries) end)

      {:error, _} ->
        raise "Missing SSG module `#{ssg_module}`"
    end
  end
end
