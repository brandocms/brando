defmodule <%= app_module %>.Repo.Migrations.Create<%= scoped %> do
  use Ecto.Migration<%= if sequenced do %>
  use Brando.Sequence.Migration<% end %><%= if soft_delete do %>
  use Brando.SoftDelete.Migration<% end %><%= if gallery do %>
  use Brando.Gallery.Migration<% end %><%= if villain_fields != [] do %>
  use Brando.Villain.Migration<% end %>

  def change do
    create table(:<%= snake_domain %>_<%= plural %>) do
<%= for migration <- migration_fields do %>      <%= migration %>
<% end %><%= for {_, i, s, on_delete} <- migration_assocs do %>      add <%= inspect i %>, references(<%= inspect s %>, on_delete: <%= inspect on_delete %>)
<% end %>
<%= if creator do %>      add :creator_id, references(:users_users, on_delete: :nothing)<% end %>
<%= if sequenced do %>      sequenced()<% end %>
<%= if soft_delete do %>      soft_delete()<% end %>
      timestamps()
    end
  <%= for index <- indexes do %>
    <%= index %><% end %><%= if creator do %>
    create index(:<%= snake_domain %>_<%= plural %>, [:creator_id])<% end %><%= if status do %>
    create index(:<%= snake_domain %>_<%= plural %>, [:status])<% end %><%= if slug do %>
    create index(:<%= snake_domain %>_<%= plural %>, [:slug])<% end %>
  end
end
