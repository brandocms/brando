- **`mix brando.entries.resave` and `mix brando.identifiers.sync` print no
  colour codes into a file.** Their progress lines wrote ANSI escapes whether
  or not stdout was a terminal, so a log of a piped run was full of `^[[34m`.
  They now colour only on a terminal, as Mix's own output does.
