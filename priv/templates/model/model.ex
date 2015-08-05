defmodule <%= module %> do
  use <%= base %>.Web, :model
<%= if villain_fields != [] do %>  use Brando.Villain.Model<% end %>
<%= if img_fields != [] do %>  use Brando.Field.ImageField
<% end %>
  schema <%= inspect plural %> do
<%= for model_field <- model_fields do %>    <%= model_field %>
<% end %><%= for {k, _, m} <- assocs do %>    belongs_to <%= inspect k %>, <%= m %>
<% end %>
    timestamps
  end
<%= for {v, k} <- img_fields do %>
  has_image_field <%= inspect k %>,
    %{allowed_mimetypes: ["image/jpeg", "image/png"],
      default_size: :medium,
      upload_path: Path.join("images", "<%= k %>"),
      random_filename: true,
      size_limit: 10240000,
      sizes: %{
        "micro"  => %{"size" => "25x25>", "quality" => 100, "crop" => true},
        "thumb"  => %{"size" => "150x150>", "quality" => 100, "crop" => true},
        "small"  => %{"size" => "300", "quality" => 100},
        "medium" => %{"size" => "500", "quality" => 100},
        "large"  => %{"size" => "700", "quality" => 100},
        "xlarge" => %{"size" => "900", "quality" => 100}
      }
    }
<% end %>
  @required_fields ~w(<%= Enum.map_join(Keyword.drop(attrs, Keyword.values(img_fields)), " ", &elem(&1, 0)) %>)
  @optional_fields ~w(<%= Enum.map_join(img_fields, " ", &elem(&1, 1)) %>)

  @doc """
  Creates a changeset based on the `model` and `params`.

  If no params are provided, an invalid changeset is returned
  with no validation performed.
  """
  def changeset(model, params \\ :empty) do
    model
    |> cast(params, @required_fields, @optional_fields)
  end

  def delete(record) do
<%= for {v, k} <- img_fields do %>    record.<%= k %> |> delete_original_and_sized_images
<% end %>    Brando.repo.delete!(record)
  end

  #
  # Meta

  use Brando.Meta,
    [en:
      [singular: "<%= singular %>",
       plural: "<%= plural %>",
       repr: &("#{&1.<%= Dict.keys(attrs) |> List.first %>}"),
       fields: [
         id: "Id",
<%= for {k, _} <- attrs do %>         <%= k %>: "<%= String.capitalize(Atom.to_string(k)) %>",
<% end %><%= if villain_fields != [] do %>         html: "HTML",<% end %>
         inserted_at: "Inserted at",
         updated_at: "Updated at"],
       hidden_fields: []],
     no:
      [singular: "<%= no_singular %>",
       plural: "<%= no_plural %>",
       repr: &("#{&1.<%= Dict.keys(attrs) |> List.first %>}"),
       fields: [
         id: "Id",
<%= for {k, _} <- attrs do %>         <%= k %>: "<%= String.capitalize(Atom.to_string(k)) %>",
<% end %><%= if villain_fields != [] do %>         html: "HTML",<% end %>
         inserted_at: "Opprettet",
         updated_at: "Oppdatert"],
       hidden_fields: []],
    ]
end
