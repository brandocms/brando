alias Brando.Pages
alias Brando.Tenant.Job

user = Brando.Repo.get_by!(Brando.Users.User, email: "installer@example.test")
{:ok, templates} = Pages.list_templates()
true = "index.html" in templates && "default.html" in templates

Job.each_active_environment(:live, fn ->
  for {uri, title, status, template} <- [
        {"index", "CMS smoke home", :published, "index.html"},
        {"about", "CMS smoke about", :published, "default.html"},
        {"draft", "Unpublished CMS smoke page", :draft, "default.html"}
      ] do
    {:ok, _page} =
      Pages.create_page(
        %{
          title: title,
          uri: uri,
          language: "en",
          template: template,
          is_homepage: uri == "index",
          status: status
        },
        user
      )
  end
end)

IO.puts("Disposable CMS pages initialized in every live environment")
