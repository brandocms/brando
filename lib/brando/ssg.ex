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

  def get_urls do
    ssg_module = Brando.web_module(SSG)

    case Code.ensure_compiled(ssg_module) do
      {:module, _} ->
        ssg_functions = ssg_module.__info__(:functions)
        entries = Stream.flat_map(ssg_functions, &apply(ssg_module, elem(&1, 0), []))

        Brando.repo().transaction(fn ->
          entries
          |> Enum.to_list()
        end)
      {:error, _} ->
        raise "Missing SSG module `#{ssg_module}`"
    end


  end
end
