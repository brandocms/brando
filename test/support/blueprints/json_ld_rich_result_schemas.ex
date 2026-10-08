defmodule Brando.JSONLDTest do
  @moduledoc false
  # Stands in for the test blueprints' context: lists the products a test
  # puts in the app env (`put_test_env(Brando.JSONLDTest, products: [...])`),
  # for the site-wide structured data check, which may run in a task.
  def list_products(_args), do: {:ok, Keyword.get(Application.get_env(:brando, __MODULE__, []), :products, [])}

  # Shelves are listed without their relations, as a context's list function
  # returns them; their `vars` are loaded by whoever reads them.
  def list_shelves(_args), do: {:ok, shelves()}

  def get_shelf(%{matches: %{id: id}}) do
    case Enum.find(shelves(), &(&1.id == id)) do
      nil -> {:error, {:shelf, :not_found}}
      shelf -> {:ok, shelf}
    end
  end

  defp shelves, do: Keyword.get(Application.get_env(:brando, __MODULE__, []), :shelves, [])
end

defmodule Brando.JSONLDTest.Product do
  @moduledoc false
  # A shop product with an offer and an aggregate rating.
  use Brando.Blueprint,
    application: "Brando",
    domain: "JSONLDTest",
    schema: "Product",
    singular: "product",
    plural: "products",
    gettext_module: Brando.Gettext

  alias Brando.JSONLD

  identifier ~H"{@entry.title}"
  absolute_url ~H"/shop/{@entry.slug}"

  trait Brando.Trait.Timestamped

  attributes do
    attribute :title, :string, required: true
    attribute :slug, :slug, required: true
    attribute :summary, :text
    attribute :sku, :string
    attribute :price, :decimal
    attribute :in_stock, :boolean
    attribute :rating, :float
    attribute :review_count, :integer
  end

  assets do
    asset :cover, :image, cfg: [upload_path: "images/products"]
  end

  json_ld_schema JSONLD.Schema.Product do
    field :name, :string, & &1.title
    field :description, :string, & &1.summary
    field :image, :image, & &1.cover
    field :sku, :string, & &1.sku

    field :offers, JSONLD.Schema.Offer, fn product ->
      %{
        price: product.price,
        price_currency: "NOK",
        availability: if(product.in_stock, do: :in_stock, else: :out_of_stock)
      }
    end

    field :aggregateRating, JSONLD.Schema.AggregateRating, &%{rating_value: &1.rating, review_count: &1.review_count}
    field :url, :current_url
  end
end

defmodule Brando.JSONLDTest.Job do
  @moduledoc false
  # A remote job opening.
  use Brando.Blueprint,
    application: "Brando",
    domain: "JSONLDTest",
    schema: "Job",
    singular: "job",
    plural: "jobs",
    gettext_module: Brando.Gettext

  alias Brando.JSONLD

  identifier ~H"{@entry.title}"
  absolute_url ~H"/jobs/{@entry.slug}"

  attributes do
    attribute :title, :string, required: true
    attribute :slug, :slug, required: true
    attribute :description, :text
    attribute :posted_on, :date
    attribute :deadline, :datetime
    attribute :salary_from, :integer
    attribute :salary_to, :integer
  end

  json_ld_schema JSONLD.Schema.JobPosting do
    field :title, :string, & &1.title
    field :description, :string, & &1.description
    field :datePosted, :date, & &1.posted_on
    field :validThrough, :datetime, & &1.deadline
    field :employmentType, :string, fn _ -> "FULL_TIME" end
    field :hiringOrganization, :identity
    field :jobLocationType, :string, fn _ -> "TELECOMMUTE" end
    field :applicantLocationRequirements, JSONLD.Schema.Thing, fn _ -> %{type: "Country", name: "NO"} end

    field :baseSalary, JSONLD.Schema.MonetaryAmount, fn job ->
      %{currency: "NOK", min: job.salary_from, max: job.salary_to, unit: "year"}
    end

    field :url, :current_url
  end
end

defmodule Brando.JSONLDTest.Recipe do
  @moduledoc false
  # A recipe with its steps, times and nutrition.
  use Brando.Blueprint,
    application: "Brando",
    domain: "JSONLDTest",
    schema: "Recipe",
    singular: "recipe",
    plural: "recipes",
    gettext_module: Brando.Gettext

  alias Brando.JSONLD

  identifier ~H"{@entry.title}"
  absolute_url ~H"/recipes/{@entry.slug}"

  trait Brando.Trait.Creator
  trait Brando.Trait.Timestamped

  attributes do
    attribute :title, :string, required: true
    attribute :slug, :slug, required: true
    attribute :summary, :text
    attribute :prep_minutes, :integer
    attribute :cook_minutes, :integer
    attribute :servings, :integer
    attribute :ingredients, Brando.Type.StringList, default: []
    attribute :steps, Brando.Type.StringList, default: []
    attribute :calories, :integer
  end

  assets do
    asset :cover, :image, cfg: [upload_path: "images/recipes"]
  end

  json_ld_schema JSONLD.Schema.Recipe do
    field :name, :string, & &1.title
    field :description, :string, & &1.summary
    field :image, :image, & &1.cover
    field :author, :person, & &1.creator
    field :datePublished, :datetime, & &1.inserted_at
    field :prepTime, :duration, & &1.prep_minutes
    field :cookTime, :duration, & &1.cook_minutes
    field :totalTime, :duration, &(&1.prep_minutes + &1.cook_minutes)
    field :recipeYield, :string, &"#{&1.servings} servings"
    field :recipeIngredient, :string, & &1.ingredients
    field :recipeInstructions, {:list, JSONLD.Schema.HowToStep}, & &1.steps
    field :nutrition, JSONLD.Schema.NutritionInformation, &%{calories: "#{&1.calories} calories"}
    field :url, :current_url
  end
end

defmodule Brando.JSONLDTest.BookReview do
  @moduledoc false
  # A critic's review of a book.
  use Brando.Blueprint,
    application: "Brando",
    domain: "JSONLDTest",
    schema: "BookReview",
    singular: "book_review",
    plural: "book_reviews",
    gettext_module: Brando.Gettext

  alias Brando.JSONLD

  identifier ~H"{@entry.title}"
  absolute_url ~H"/reviews/{@entry.slug}"

  trait Brando.Trait.Creator
  trait Brando.Trait.Timestamped

  attributes do
    attribute :title, :string, required: true
    attribute :slug, :slug, required: true
    attribute :book_title, :string
    attribute :verdict, :text
    attribute :rating, :integer
  end

  json_ld_schema JSONLD.Schema.Review do
    field :name, :string, & &1.title
    field :author, :person, & &1.creator
    field :datePublished, :datetime, & &1.inserted_at
    field :reviewBody, :string, & &1.verdict
    field :reviewRating, JSONLD.Schema.Rating, &%{rating_value: &1.rating, best_rating: 6, worst_rating: 1}
    field :itemReviewed, JSONLD.Schema.Thing, &%{type: "Book", name: &1.book_title}
    field :publisher, :identity
    field :url, :current_url
  end
end

defmodule Brando.JSONLDTest.Shelf do
  @moduledoc false
  # A mapping whose field function enumerates a relation, as a site's
  # `keywords/1` lists an entry's categories. The relation borrows the pages'
  # variables (`page_id`), so a shelf with a page's id has that page's rows.
  use Brando.Blueprint,
    application: "Brando",
    domain: "JSONLDTest",
    schema: "Shelf",
    singular: "shelf",
    plural: "shelves",
    gettext_module: Brando.Gettext

  alias Brando.JSONLD

  identifier ~H"{@entry.title}"
  absolute_url ~H"/shelves/{@entry.slug}"

  trait Brando.Trait.Timestamped

  attributes do
    attribute :title, :string, required: true
    attribute :slug, :slug, required: true
  end

  relations do
    relation :vars, :has_many, module: Brando.Content.Var, foreign_key: :page_id
  end

  json_ld_schema JSONLD.Schema.Article do
    field :headline, :string, & &1.title
    field :description, :string, &__MODULE__.describe/1
    field :url, :current_url
  end

  # A shelf named "broken" stands for an entry the site's mapping can't
  # describe: its field function raises.
  def describe(%{slug: "broken"}), do: raise(ArgumentError, "the shelf has no description")
  def describe(shelf), do: Enum.map_join(shelf.vars, ", ", & &1.key)
end
