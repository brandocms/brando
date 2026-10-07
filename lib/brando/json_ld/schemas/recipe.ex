defmodule Brando.JSONLD.Schema.Recipe do
  @moduledoc """
  A recipe, for Google's recipe results.

  Google requires `name` and `image`. It recommends `author`,
  `datePublished`, `description`, `recipeIngredient`, `recipeInstructions`
  (as `HowToStep`s), `recipeYield`, `totalTime`, `prepTime` and `cookTime`
  (ISO 8601 durations), `recipeCategory`, `recipeCuisine`, `keywords`,
  `nutrition.calories`, `aggregateRating` and `video`.

      json_ld_schema JSONLD.Schema.Recipe do
        field :name, :string, & &1.title
        field :description, :string, & &1.meta_description
        field :image, :image, & &1.cover
        field :author, :person, & &1.creator
        field :datePublished, :datetime, & &1.publish_at
        field :prepTime, :duration, & &1.prep_minutes
        field :cookTime, :duration, & &1.cook_minutes
        field :totalTime, :duration, &(&1.prep_minutes + &1.cook_minutes)
        field :recipeYield, :string, &"\#{&1.servings} servings"
        field :recipeIngredient, :string, & &1.ingredients
        field :recipeInstructions, {:list, JSONLD.Schema.HowToStep}, & &1.steps
        field :nutrition, JSONLD.Schema.NutritionInformation, &%{calories: &1.calories}
      end

  The `:duration` field type turns whole minutes, a `Duration` or `"HH:MM:SS"`
  into ISO 8601 (`90` is `"PT1H30M"`). The recipe's videos are described
  automatically, as for articles.

  https://developers.google.com/search/docs/appearance/structured-data/recipe
  """

  @derive Jason.Encoder
  defstruct "@context": "https://schema.org",
            "@type": "Recipe",
            "@id": nil,
            name: nil,
            description: nil,
            image: nil,
            author: nil,
            datePublished: nil,
            prepTime: nil,
            cookTime: nil,
            totalTime: nil,
            recipeYield: nil,
            recipeCategory: nil,
            recipeCuisine: nil,
            keywords: nil,
            recipeIngredient: nil,
            recipeInstructions: nil,
            nutrition: nil,
            aggregateRating: nil,
            video: nil,
            url: nil
end
