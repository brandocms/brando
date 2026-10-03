defmodule Brando.Forms do
  @moduledoc """
  Forms visitors fill in on the site. See `Brando.Forms.Form`.
  """
  use Brando.Query

  import Ecto.Query

  alias Brando.Forms.Form

  query :list, Form, do: fn query -> from(q in query) end

  filters Form do
    fn
      {:title, title}, query ->
        from q in query, where: ilike(q.title, ^"%#{title}%")

      {:language, language}, query ->
        from q in query, where: q.language == ^language
    end
  end

  query :single, Form, do: fn query -> from(q in query) end

  matches Form do
    fn
      {:id, id}, query ->
        from q in query, where: q.id == ^id

      {:key, key}, query ->
        from q in query, where: q.key == ^key

      {:language, language}, query ->
        from q in query, where: q.language == ^language
    end
  end

  mutation :create, Form
  mutation :update, {Form, preload: [:fields]}
  mutation :delete, Form

  # A copy in the same language needs its own key; fields keep theirs.
  mutation :duplicate,
           {Form,
            preload: [:fields],
            change_fields: [
              :title,
              {:key, &__MODULE__.duplicate_key/2},
              alternates: [],
              alternate_entries: []
            ]}

  @doc false
  def duplicate_key(_entry, key), do: "#{key}_copy"
end
