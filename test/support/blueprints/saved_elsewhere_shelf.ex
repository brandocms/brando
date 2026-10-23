# Another tab's save reaching an open form (EntrySavedElsewhereTest), on the
# `synctest_articles` table: a has_many with Ecto's default `on_replace`
# (`:raise`), and a form whose query leaves it unloaded.
defmodule Brando.SavedElsewhereTest.Shelf do
  @moduledoc false
  use Brando.Blueprint,
    application: "Brando",
    domain: "SavedElsewhereTest",
    schema: "Shelf",
    singular: "shelf",
    plural: "shelves",
    gettext_module: Brando.Gettext

  table "synctest_articles"

  trait :timestamped

  identifier "{{ entry.title }}"

  attributes do
    attribute :title, :string, required: true
  end

  relations do
    relation :items, :has_many,
      module: Brando.SyncTest.ArticleItem,
      foreign_key: :article_id,
      preload_order: [asc: :sequence],
      cast: true
  end

  forms do
    form do
      tab "Content" do
        fieldset do
          input :title, :text
        end

        fieldset do
          inputs_for :items do
            cardinality :many
            style :inline
            default %{}

            input :label, :text
          end
        end
      end
    end

    # Reads the entry without its rows
    form :title_only do
      query %{}

      tab "Content" do
        fieldset do
          input :title, :text
        end
      end
    end
  end
end

defmodule Brando.SavedElsewhereTest do
  @moduledoc false
  use BrandoAdmin, :context
  use Brando.Query

  import Ecto.Query

  alias Brando.SavedElsewhereTest.Shelf

  query :single, Shelf, do: fn query -> from(q in query) end

  matches Shelf do
    fn
      {:id, id}, query -> from t in query, where: t.id == ^id
    end
  end

  query :list, Shelf, do: fn query -> from(q in query) end

  mutation :update, Shelf
end
