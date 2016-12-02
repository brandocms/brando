defmodule <%= module %> do
  use <%= base %>.Web, :model
<%= if villain_fields != [] do %>  use Brando.Villain, :model<% end %>
<%= if sequenced do %>  use Brando.Sequence, :model<% end %>
<%= if img_fields != [] do %>  use Brando.Field.ImageField
<% end %>
  import <%= base %>.Backend.Gettext
  schema <%= inspect plural %> do
<%= for model_field <- model_fields do %>    <%= model_field %>
<% end %><%= for {k, _, m} <- assocs do %>    belongs_to <%= inspect k %>, <%= m %>
<% end %>
<%= if sequenced do %>    sequenced<% end %>
    timestamps
  end
<%= for {v, k} <- img_fields do %>
  has_image_field <%= inspect k %>,
    %{allowed_mimetypes: ["image/jpeg", "image/png", "image/gif"],
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
  @required_fields ~w(<%= Enum.map_join(Keyword.drop(attrs, Keyword.values(img_fields)) |> Keyword.drop(Keyword.values(villain_fields)), " ", &elem(&1, 0)) %><%= if villain_fields != [] do %> <% end %><%= Enum.map_join(villain_fields, " ", fn({k, v}) -> if v == :data, do: "#{v}", else: "#{v}_data" end) %><%= if assocs do %> <% end %><%= Enum.map_join(assocs, " ", &elem(&1, 1)) %>)a
  @optional_fields ~w(<%= Enum.map_join(img_fields, " ", &elem(&1, 1)) %>)a

  @doc """
  Creates a changeset based on the `model` and `params`.

  If no params are provided, an invalid changeset is returned
  with no validation performed.
  """
  def changeset(model, params \\ %{}) do
    model
    |> cast(params, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)<%= if villain_fields != [] do %><%= for {k, v} <- villain_fields do %><%= if v == :data do %>
    |> generate_html()<% else %>
    |> generate_html(<%= inspect v %>)<% end %><% end %><% end %><%= if img_fields != [] do %>
    |> cleanup_old_images()<% end %>
  end

  def delete(record) do
<%= for {v, k} <- img_fields do %>    record |> delete_original_and_sized_images(<%= inspect k %>)
<% end %>    Brando.repo.delete!(record)
  end

  #
  # Meta

  use Brando.Meta.Model, [
    singular: "<%= Phoenix.Naming.humanize(singular) |> String.downcase %>",
    plural: "<%= Phoenix.Naming.humanize(plural) |> String.downcase %>",
    repr: &("#{&1.<%= Dict.keys(attrs) |> List.first %>}"),
    fields: [
      id: gettext("Id"),
<%= for {k, _} <- attrs do %>      <%= k %>: gettext("<%= Phoenix.Naming.humanize(k) %>"),
<% end %><%= if villain_fields != [] do %>      html: gettext("HTML"),<% end %>
      inserted_at: gettext("Inserted at"),
      updated_at: gettext("Updated at")],
    hidden_fields: []
  ]
end
