defmodule <%= module %> do
  use <%= base %>Web, :schema
<%= if villain_fields != [] do %>  use Brando.Villain.Schema<% end %>
<%= if sequenced do %>  use Brando.Sequence, :schema<% end %>
<%= if file_fields != [] do %>  use Brando.Field.FileField<% end %>
<%= if img_fields != [] do %>  use Brando.Field.ImageField
  import Brando.Images.Optimize, only: [optimize: 2]<% end %>

  @type t :: %__MODULE__{}

  schema <%= inspect "#{snake_domain}_#{plural}" %> do
<%= for schema_field <- schema_fields do %>    <%= schema_field %>
<% end %><%= for {k, _, m} <- schema_assocs do %>    belongs_to <%= inspect k %>, <%= m %>
<% end %>
<%= if sequenced do %>    sequenced()<% end %>
    timestamps()
  end
<%= for {_v, k} <- img_fields do %>
  has_image_field <%= inspect k %>,
    %{allowed_mimetypes: ["image/jpeg", "image/png", "image/gif"],
      default_size: :medium,
      upload_path: Path.join("images", "<%= k %>"),
      random_filename: true,
      size_limit: 10_240_000,
      sizes: %{
        "micro"  => %{"size" => "25", "quality" => 20, "crop" => false},
        "thumb"  => %{"size" => "150x150>", "quality" => 90, "crop" => true},
        "small"  => %{"size" => "700", "quality" => 90},
        "medium" => %{"size" => "1100", "quality" => 90},
        "large"  => %{"size" => "1700", "quality" => 90},
        "xlarge" => %{"size" => "2100", "quality" => 90}
      }
    }
<% end %>
<%= for {_v, k} <- file_fields do %>
  has_file_field <%= inspect k %>,
    %{allowed_mimetypes: ["application/pdf"],
      random_filename: true,
      upload_path: Path.join("files", "<%= k %>"),
      size_limit: 10_240_000,
    }
<% end %>
  @required_fields ~w(<%= Enum.map_join(Keyword.drop(attrs, Keyword.values(img_fields ++ file_fields)) |> Keyword.drop(Keyword.values(villain_fields)), " ", &elem(&1, 0)) %><%= if villain_fields != [] do %> <% end %><%= Enum.map_join(villain_fields, " ", fn({_k, v}) -> if v == :data, do: "#{v}", else: "#{v}_data" end) %><%= if schema_assocs do %> <% end %><%= Enum.map_join(schema_assocs, " ", fn {_, y, _} -> if to_string(y) not in Keyword.values(gallery_fields), do: y, else: nil end) %>)a
  @optional_fields ~w(<%= Enum.map_join(img_fields ++ file_fields ++ gallery_fields, " ", &elem(&1, 1)) %>)a

  @doc """
  Creates a changeset based on the `schema` and `params`.

  If no params are provided, an invalid changeset is returned
  with no validation performed.
  """
  def changeset(schema, params \\ %{}, user) do
    schema
    |> cast(params, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)<%= if villain_fields != [] do %><%= for {_k, v} <- villain_fields do %><%= if v == :data do %>
    |> generate_html()<% else %>
    |> generate_html(<%= inspect v %>)<% end %><% end %><% end %><%= if img_fields != [] do %><%= for {_v, k} <- img_fields do %>
    |> validate_upload({:image, <%= inspect k %>}, user)
    |> optimize(<%= inspect k %>)<% end %><% end %>
  end
end
