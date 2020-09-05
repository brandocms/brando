defmodule <%= schema_module %> do
  use <%= web_module %>, :schema<%= if villain_fields != [] do %>
  use Brando.Villain.Schema<% end %><%= if gallery do %>
  use Brando.Gallery.Schema<% end %><%= if soft_delete do %>
  use Brando.SoftDelete.Schema<% end %><%= if sequenced do %>
  use Brando.Sequence.Schema<% end %><%= if file_fields != [] do %>
  use Brando.Field.File.Schema<% end %><%= if img_fields != [] do %>
  use Brando.Field.Image.Schema<% end %>

  @type t :: %__MODULE__{}

  schema <%= inspect "#{snake_domain}_#{plural}" %> do
<%= for schema_field <- schema_fields do %>    <%= schema_field %>
<% end %><%= for {k, _, m} <- schema_assocs do %>    belongs_to <%= inspect k %>, <%= m %>
<% end %><%= if creator do %>    belongs_to :creator, Brando.Users.User
<% end %><%= if sequenced do %>    sequenced()
<% end %><%= if soft_delete do %>    soft_delete()
<% end %>    timestamps()
  end
<%= for {_v, k} <- img_fields do %>
  has_image_field <%= inspect k %>,
    %{allowed_mimetypes: ["image/jpeg", "image/png", "image/gif"],
      default_size: "medium",
      upload_path: Path.join(["images", "<%= plural %>", "<%= k %>"]),
      random_filename: true,
      size_limit: 10_240_000,
      sizes: %{
        "micro"  => %{"size" => "25", "quality" => 20, "crop" => false},
        "thumb"  => %{"size" => "300x300>", "quality" => 70, "crop" => true},
        "small"  => %{"size" => "700", "quality" => 70},
        "medium" => %{"size" => "1100", "quality" => 70},
        "large"  => %{"size" => "1700", "quality" => 70},
        "xlarge" => %{"size" => "2100", "quality" => 70}
      }
    }
<% end %><%= for {_v, k} <- file_fields do %>
  has_file_field <%= inspect k %>,
    %{allowed_mimetypes: ["application/pdf"],
      random_filename: true,
      upload_path: Path.join("files", "<%= k %>"),
      size_limit: 10_240_000,
    }
<% end %>
  @required_fields <%= required_fields %>
  @optional_fields <%= optional_fields %>

  @doc """
  Creates a changeset based on the `schema` and `params`.

  If no params are provided, an invalid changeset is returned
  with no validation performed.
  """
  def changeset(schema, params \\ %{}, user \\ :system) do
    schema<%= if creator do %>
    |> cast(params, @required_fields ++ @optional_fields)<%= if gallery do %><%= for {_k, v} <- gallery_fields do %>
    |> cast_assoc(:<%= v %>, with: {Brando.ImageSeries, :changeset, [user]})<% end %><% end %>
    |> put_creator(user)<% end %>
    |> validate_required(@required_fields)<%= if villain_fields != [] do %><%= for {_k, v} <- villain_fields do %><%= if v == :data do %>
    |> generate_html()<% else %>
    |> generate_html(<%= inspect v %>)<% end %><% end %><% end %><%= if img_fields != [] do %><%= for {_v, k} <- img_fields do %>
    |> validate_upload({:image, <%= inspect k %>}, user)<% end %><% end %><%= if slug do %>
    |> avoid_slug_collision()<% end %>
  end
end
