# Low-Memory Global JVM Configuration

`configure-low-memory-jvm.sh` installs a **global** (non-project-local) low-memory
JVM configuration for an 8 GB RAM Linux dev machine running Java, Scala, sbt, ZIO,
Metals, Neovim, and jdtls. It manages a single sourced config file plus one
marker-guarded block in `~/.bashrc`, and it is idempotent: re-running it is a no-op.

## Install

```sh
./configure-low-memory-jvm.sh          # install (requires java on PATH)
./configure-low-memory-jvm.sh --dry-run
./configure-low-memory-jvm.sh --verify
./configure-low-memory-jvm.sh --uninstall
```

- Managed config: `~/.config/jvm-memory/jvm-memory.sh` (whole file is regenerated,
  guarded by `# >>> low-memory-jvm-config >>>` markers).
- `~/.bashrc` gets one source line inside the same markers.
- Any existing file that is **not** marked is preserved and reported — the script
  never overwrites it.
- Timestamped `.bak.<ts>` backups are created only when a file actually changes.

Restart your shell (or `source ~/.config/jvm-memory/jvm-memory.sh`) after installing.

## How it works

The config is layered so that tools that know their own memory settings win, while
everything else is bounded by a global default cap.

| Tool | Mechanism | Effective setting |
|------|-----------|-------------------|
| Any JVM (Java, ZIO apps, scala-cli bloop worker, ...) | `JDK_JAVA_OPTIONS` is prepended by every JDK launcher; an explicit `-Xmx` on the command line overrides it | `-XX:MaxRAM=4g -XX:MaxRAMPercentage=25` → default max heap ~1G (2G would be the default on 8 GB) |
| sbt | `SBT_OPTS` → passed as JVM args by the sdkman runner; beats `JAVA_OPTS`, `JAVA_TOOL_OPTIONS`, and the default `-mem 1024m` | `-Xms256m -Xmx1280m -Xss1m -XX:MaxMetaspaceSize=256m -XX:ReservedCodeCacheSize=128m` |
| Scala CLI | No env var set — it warns and ignores heap flags in `JAVA_OPTS`/`JDK_JAVA_OPTIONS` (VirtusLab/scala-cli#2841) | Use `scala-cli --java-opt -Xmx...` or `scala-cli config java.properties` |
| Metals | `JAVA_OPTS` is expanded by the coursier launcher; nvim-metals filters `-Xms*`/`-Xmx*`/`-Xss*` from its `-J` flags but the server still sees them via the launcher | Unset by default (server bounded to ~1G by the cap); uncomment the pinned line in the config for `-Xms256m -Xmx768m -Xss4m -XX:MaxMetaspaceSize=256m`, or use nvim-metals `serverProperties` |
| Bloop | `BLOOP_JAVA_OPTS` read by `bloop start`; default `-XX:+UseZGC` (uncommits unused heap) is kept | `-Xmx1g` |
| jdtls | No env var; Arch launcher hardcodes `-Xms1G`, no `-Xmx` (2G default max) | Bounded to ~1G by the cap; use nvim-jdtls `-vmargs` or vscode `java.jdt.ls.vmargs` for a smaller server |
| Scala (REPL/compiler) | Inherits `JDK_JAVA_OPTIONS` | ~1G default cap |
| Coursier | Launchers embed `--java-opt` and expand `$JAVA_OPTS` | Inherits the ~1G cap; pass `--java-opt` per invocation to override |
| ZIO applications | Just a JVM launch | ~1G default cap; set `-Xmx` explicitly in the app's launcher to override |

### Why these choices

- **No global `-Xmx`.** A global `-Xmx` would also cap apps you *want* to give more
  memory to. `JDK_JAVA_OPTIONS` with `-XX:MaxRAM=4g -XX:MaxRAMPercentage=25` bounds
  the *default* while letting explicit `-Xmx` win.
- **sbt gets the headroom** (1280m) because it is the interactive driver; editor +
  server stay within the ~1G cap.
- **G1 is kept** (Java 26 default). No `SerialGC` forcing — modern G1 is fine for
  an 8 GB machine and parallel-friendly.
- **Bloop keeps ZGC**, which uncommits unused heap back to the OS — the right fit
  for a low-RAM box.
- **`JAVA_OPTS` is unset by default** because scala-cli emits a warning on every
  invocation when heap flags are present, and because most tools are already bounded
  by the JDK cap.

## Verification

`--verify` reports the effective values and checks the runtime default max heap via
`java -XshowSettings:vm`; exit code is `3` when problems are found, `0` otherwise.
sbt's own heap is confirmed manually:

```sh
sbt -v          # then, in another shell:
jps -lv         # find the sbt launcher pid; its -Xmx1280m should be visible
```

## Uninstall

`--uninstall` removes the `~/.bashrc` source block and the managed config file
(backing both up). A pre-existing, unmarked file is left untouched.

## Notes / caveats

- `~/.bashrc` is only sourced by **interactive** bash shells. Non-interactive shells
  that need these settings should source the managed file via `BASH_ENV`.
- This is Arch-focused and pairs with the repo's `setup.sh`/`scripts/` layout, but the
  script itself is portable to any Linux with `java` on PATH.
- The config is safe to re-run; conflicts with existing config files are detected and
  reported, never silently overwritten.