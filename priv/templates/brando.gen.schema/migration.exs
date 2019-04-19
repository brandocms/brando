defmodule <%= base %>.Repo.Migrations.Create<%= scoped %> do
  use Ecto.Migration
<%= if sequenced do %>  use Brando.Sequence, :migration<% end %>
<%= if villain_fields != [] do %>  use Brando.Villain, :migration<% end %>

  def change do
    create table(:<%= snake_domain %>_<%= plural %>) do
<%= for migration <- migrations do %>      <%= migration %>
<% end %><%= for {_, i, s, on_delete} <- migration_assocs do %>      add <%= inspect i %>, references(<%= inspect s %>, on_delete: <%= inspect on_delete %>)
<% end %>
<%= if sequenced do %>      sequenced()<% end %>
      timestamps()
    end
  <%= for index <- indexes do %>
    <%= index %>
  <% end %>
  end
end
