defmodule Brando.GraphQL.Resolver do
  defmacro __using__(opts) do
    schema =
      opts
      |> Keyword.fetch!(:schema)
      |> Macro.expand(__CALLER__)

    singular =
      schema
      |> Module.split()
      |> List.last()
      |> Inflex.underscore()

    plural = Inflex.pluralize(singular)

    context =
      opts
      |> Keyword.fetch!(:context)
      |> Macro.expand(__CALLER__)

    quote generated: true do
      @doc false
      def all(args, %{context: %{current_user: _}}) do
        unquote(context).unquote(:"list_#{plural}")(Map.put(args, :paginated, true))
      end

      @doc false
      def get(args, _) do
        unquote(context).unquote(:"get_#{singular}")(args)
      end

      @doc false
      def create(%{unquote(:"#{singular}_params") => params}, %{
            context: %{current_user: user}
          }) do
        unquote(context).unquote(:"create_#{singular}")(params, user)
      end

      if unquote(schema).__revisioned__ do
        def update(
              %{
                unquote(:"#{singular}_id") => id,
                unquote(:"#{singular}_params") => params,
                revision: revision
              },
              %{
                context: %{current_user: user}
              }
            ) do
          if revision == "0" do
            unquote(context).unquote(:"update_#{singular}")(
              id,
              params,
              user
            )
          else
            Brando.Revisions.create_from_base_revision(
              unquote(schema),
              revision,
              id,
              params,
              user
            )
          end
        end
      else
        def update(
              %{
                unquote(:"#{singular}_id") => id,
                unquote(:"#{singular}_params") => params
              },
              %{
                context: %{current_user: user}
              }
            ) do
          unquote(context).unquote(:"update_#{singular}")(
            id,
            params,
            user
          )
        end
      end

      @doc false
      def delete(%{unquote(:"#{singular}_id") => id}, %{
            context: %{current_user: user}
          }) do
        unquote(context).unquote(:"delete_#{singular}")(id, user)
      end
    end
  end
end
