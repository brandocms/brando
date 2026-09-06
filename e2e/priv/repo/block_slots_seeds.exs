# A deliberately small note palette: ordinary modules, including the existing
# asset pickers. Kept separate so the same fixture can be used for UX review.
alias Brando.Content
alias Brando.Villain.Blocks

user = E2eProject.Repo.get_by!(Brando.Users.User, email: "admin@brandocms.com")

ref = fn name, data ->
  %Content.Ref{name: name, uid: Brando.Utils.generate_uid(), data: data}
end

insert_module = fn name, code, refs, vars, sequence ->
  E2eProject.Repo.insert!(%Content.Module{
    name: %{"en" => name, "no" => name},
    namespace: %{"en" => "09 NOTES & REGIONS", "no" => "09 NOTES & REGIONS"},
    type: :liquid,
    class: "note-content",
    code: code,
    sequence: sequence,
    multi: false,
    datasource: false,
    refs: refs,
    vars: vars
  })
end

note_text =
  insert_module.(
    "Note text",
    "{% ref refs.text %}",
    [
      ref.("text", %Blocks.TextBlock{
        data: %Blocks.TextBlock.Data{text: "<p></p>", extensions: ["p", "bold", "italic", "link", "list"]}
      })
    ],
    [],
    50
  )

note_image =
  insert_module.(
    "Note image",
    "{% ref refs.image %}",
    [
      ref.("image", %Blocks.PictureBlock{data: %Blocks.PictureBlock.Data{}})
    ],
    [],
    51
  )

note_video =
  insert_module.(
    "Note video",
    "{% ref refs.video %}",
    [
      ref.("video", %Blocks.VideoBlock{data: %Blocks.VideoBlock.Data{}})
    ],
    [],
    52
  )

note_file =
  insert_module.(
    "Note download",
    """
    <p class="note-download">{% if attachment %}<a href="{{ attachment | media_url }}">{{ label }}</a>{% endif %}</p>
    """,
    [],
    [
      %Content.Var{
        type: :string,
        key: "label",
        label: "Link text",
        value: "Download supporting material",
        width: :full,
        placement: :content,
        creator_id: user.id
      },
      %Content.Var{type: :file, key: "attachment", label: "File", width: :full, placement: :content, creator_id: user.id}
    ],
    53
  )

E2eProject.Repo.insert!(%Content.ModuleSet{
  title: "Footnotes",
  creator_id: user.id,
  module_set_modules:
    Enum.with_index([note_text, note_image, note_video, note_file], fn module, index ->
      %Content.ModuleSetModule{module_id: module.id, sequence: index}
    end)
})

insert_module.(
  "Article with notes",
  """
  <article class="article-with-notes">
    <div class="article-copy">{% ref refs.text %}</div>
    <aside class="article-sidebar">{% ref refs.sidebar %}</aside>
  </article>
  """,
  [
    ref.("text", %Blocks.TextBlock{
      data: %Blocks.TextBlock.Data{
        text:
          "<p>Small details can tell a larger story. Add a note to share the source, a photograph or a supporting film.</p>",
        footnotes: true,
        footnote_module_set: "Footnotes"
      }
    }),
    %{
      ref.("sidebar", %Blocks.BlocksBlock{data: %Blocks.BlocksBlock.Data{module_set: "Footnotes"}})
      | description: "Further reading"
    }
  ],
  [],
  54
)

insert_module.(
  "Text without notes",
  "{% ref refs.text %}",
  [
    ref.("text", %Blocks.TextBlock{data: %Blocks.TextBlock.Data{text: "<p>This text has no footnotes enabled.</p>"}})
  ],
  [],
  55
)
