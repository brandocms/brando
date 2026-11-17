- The upgrade from 0.51 keeps free-standing `html`, `svg` and `map` blocks as HTML, SVG and map refs, where `brando_108` made text refs of them: HTML blocks render their markup and Liquid again, and SVG and map blocks keep their content.
  Sites that ran the chain on a 0.55 pre-release: replay it from the 0.51 dump with the fixed templates (`mix brando.migrations.check --update`), or rewrite the text refs as the workaround in [#3498](https://github.com/brandocms/brando/issues/3498) does.

- The upgrade from 0.51 no longer stops at `brando_92` or `brando_95` on a file or video field stored as `jsonb`.
  Sites that ran the chain on a 0.55 pre-release got past it with the workaround in [#3499](https://github.com/brandocms/brando/issues/3499) and need nothing more.

- The upgrade from 0.51 gives the videos of video fields their type (Vimeo, YouTube or an external file) and source URL, where `brando_131` left them empty and the players rendered nothing. Video blocks that play the same file keep a video of their own, with their own playback settings, in the upgrade and in `mix brando.repair.legacy_media`.
  Sites that ran the chain on a 0.55 pre-release: replay it from the 0.51 dump with the fixed templates (`mix brando.migrations.check --update`), or set `videos.type` and `source_url` as the workaround in [#3500](https://github.com/brandocms/brando/issues/3500) does.

- The upgrade from 0.51 no longer stops at `brando_107` or `brando_108` on a datasource whose limit was a number.
  A site stopped there: `mix brando.migrations.check --update` replaces the copies of `brando_107` and `brando_108`, then `mix brando.migrate` goes on. A site that rewrote its limits with the workaround in [#3501](https://github.com/brandocms/brando/issues/3501) needs nothing more.

- The upgrade from 0.51 converts free-standing comment blocks into comment refs, which render nothing, where `brando_108` stopped with "unknown block".
  Sites that ran the chain on a 0.55 pre-release removed theirs with the workaround in [#3502](https://github.com/brandocms/brando/issues/3502) and need nothing more.

- The upgrade from 0.51 keeps refs that an editor deleted on 0.51 inactive, and keeps no rows of a deleted list or table, where `brando_108` made them active again and they showed on the page.
  Sites that ran the chain on a 0.55 pre-release: replay it from the 0.51 dump with the fixed templates (`mix brando.migrations.check --update`), or set those refs inactive as the workaround in [#3503](https://github.com/brandocms/brando/issues/3503) does.
