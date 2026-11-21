# A form without blocks that has a transformer (TransformerSavesTest), on
# the `synctest_articles` table: its rows are the articles' items.
defmodule Brando.TransformerSaveTest.Album do
  @moduledoc false
  use Brando.Blueprint,
    application: "Brando",
    domain: "TransformerSaveTest",
    schema: "Album",
    singular: "album",
    plural: "albums",
    gettext_module: Brando.Gettext

  table "synctest_articles"
  # The articles' table, not their permissions
  authorization(key: "brando.transformer_save_test.album")

  trait :timestamped

  identifier "{{ entry.title }}"

  attributes do
    attribute :title, :string, required: true
  end

  relations do
    relation :items, :has_many,
      module: Brando.SyncTest.ArticleItem,
      foreign_key: :article_id,
      on_replace: :delete,
      preload_order: [asc: :sequence],
      cast: true,
      sort_param: :sort_items_ids,
      drop_param: :drop_items_ids
  end

  forms do
    form do
      tab "Content" do
        fieldset do
          input :title, :text

          inputs_for :items do
            cardinality :many
            style {:transformer, :cover}
            # A row's fields are drawn only once it is opened
            listing &Brando.SyncTest.ItemSummary.row/1

            input :label, :text
            input :link, :rich_text
          end
        end
      end
    end
  end
end

# A form with blocks and a transformer that creates its entry and stays on
# it (TransformerSavesTest), on the `synctest_articles` table too.
defmodule Brando.TransformerSaveTest.Reel do
  @moduledoc false
  use Brando.Blueprint,
    application: "Brando",
    domain: "TransformerSaveTest",
    schema: "Reel",
    singular: "reel",
    plural: "reels",
    gettext_module: Brando.Gettext

  table "synctest_articles"
  authorization(key: "brando.transformer_save_test.reel")

  trait :timestamped
  trait :blocks

  identifier "{{ entry.title }}"

  attributes do
    attribute :title, :string, required: true
  end

  relations do
    relation :blocks, :has_many, module: :blocks

    relation :items, :has_many,
      module: Brando.SyncTest.ArticleItem,
      foreign_key: :article_id,
      on_replace: :delete,
      preload_order: [asc: :sequence],
      cast: true,
      sort_param: :sort_items_ids,
      drop_param: :drop_items_ids
  end

  forms do
    form do
      tab "Content" do
        fieldset do
          input :title, :text

          inputs_for :items do
            cardinality :many
            style {:transformer, :cover}
            listing &Brando.SyncTest.ItemSummary.row/1

            input :label, :text
            input :link, :rich_text
          end
        end
      end
    end
  end
end

defmodule Brando.TransformerSaveTest do
  @moduledoc false
  use BrandoAdmin, :context
  use Brando.Query

  import Ecto.Query

  alias Brando.TransformerSaveTest.Album
  alias Brando.TransformerSaveTest.Reel

  query :single, Album, do: fn query -> from(q in query) end

  matches Album do
    fn
      {:id, id}, query -> from t in query, where: t.id == ^id
    end
  end

  query :list, Album, do: fn query -> from(q in query) end

  mutation :update, Album

  query :single, Reel, do: fn query -> from(q in query) end

  matches Reel do
    fn
      {:id, id}, query -> from t in query, where: t.id == ^id
    end
  end

  query :list, Reel, do: fn query -> from(q in query) end

  mutation :create, Reel
  mutation :update, Reel
end
