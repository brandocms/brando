defmodule Forge do
  use Blacksmith

  @save_one_function &Blacksmith.Config.save/2
  @save_all_function &Blacksmith.Config.save_all/2

  register :user,
    __struct__: Brando.User,
    full_name: "James Williamson",
    email: "james@thestooges.com",
    password: "hunter2hunter2",
    username: "jamesw",
    avatar: nil,
    role: [:admin, :superuser],
    language: "en"

  register :user_w_hashed_pass,
    __struct__: Brando.User,
    full_name: "James Williamson",
    email: "james@thestooges.com",
    password: "$2b$12$VD9opg289oNQAHii8VVpoOIOe.y4kx7.lGb9SYRwscByP.tRtJTsa",
    username: "jamesw",
    avatar: nil,
    role: [:admin, :superuser],
    language: "en"

end

defmodule Blacksmith.Config do
  def save(repo, map) do
    repo.insert!(map)
  end

  def save_all(repo, list) do
    Enum.map(list, &repo.insert!/1)
  end
end