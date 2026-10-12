- **`mix brando.images.adopt --verbose` says what differs.** Instead of "its
  sizes differ" or "its formats differ", each line names the difference:
  `sizes: missing ["xlarge"], extra ["thumb"]`,
  `formats: has [:jpg], config [:jpg, :avif]`, or
  `large: 1200×800 vs config 1400×933`. The run ends with a count per config
  target and reason, so you can judge whether recreating the images that
  differ is needed before you start.
