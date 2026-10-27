- A link var's **Default tab** (Link settings in the var editor) sets whether its link dialog opens on URL or on Content while the var has no link; editors can still switch.
  `brando_224` adds `content_vars.link_default_type` in every environment; run `mix brando.gen.migrations` and `mix brando.migrate`.
  A module or table template var that opened on Content through an empty link of that type gets Content as its default.
  A module's blocks take the setting when the module is saved, and their empty link vars then open on it; links already set keep theirs.
  In a module definition, set it with `settings link_default_type: :identifier`.
