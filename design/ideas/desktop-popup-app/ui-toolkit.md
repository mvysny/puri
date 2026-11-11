# Which language and toolkit draws the popup

Brainstormed 2026-11-11. Ruby + GTK4 is the plan and the lean; this file records what else was
on the table and why, so the question doesn't reopen from scratch.

## The owner's tiers

1. **Preferred:** Ruby, Kotlin, Java, Dart, Vala.
2. **Acceptable:** Python, JavaScript (GJS), Go.
3. **Only if nothing else works:** C, C++, Rust.

Downloads the owner allows for this: the Kotlin/Native toolchain and whatever else a Gradle build
of the app pulls in, and the Flutter snap. Everything else stays apt-only (`AGENTS.md`).

Also wanted: reasonably fast, not memory-hungry, a fast start if the UI only runs while popped
up. Native look doesn't matter. **Headless development and testing is a big plus**, which favours
GTK4: every GTK4 binding gets the Broadway + Playwright loop of the `gtk4-dev` skill for free.

## Measured: GTK4 + libadwaita through GObject Introspection

A minimal `Adw::Application` with one `Adw::ApplicationWindow` holding a label, on Broadway
(`ADW_DISABLE_PORTAL=1`), timed from process start to the first frame, then quit; three runs
each. Ruby 3.3.8 (no YJIT in the distro build), GTK 4.22.4, libadwaita 1.9.1, Ubuntu 26.04.

| Binding | Startup | Max RSS |
|---|---|---|
| Ruby (`ruby-gtk4` 4.3.4) | ~1.2 s, of it 0.8 s in `require 'gtk4'`, 0.1 s loading Adw | ~116 MB |
| Python (`python3-gi` 3.56) | ~0.2 s | ~71 MB |
| GJS 1.88 | not clean: hit a portal timeout (`org.freedesktop.host.portal.Registry`) in the tty session | ~71 MB |

So GTK4 + libadwaita itself is roughly 60–70 MB; Ruby's binding adds ~45 MB and ~1 s. Broadway
uses no GL, so a native GL/Vulkan renderer adds some memory on top (Mesa); not measured.

What the numbers mean: **1.2 s is too slow to start on the hotkey**, so a Ruby UI stays resident
(`desktop-popup-app.md`, *Hidden, not closed*). The owner accepts ~116 MB for that. And the
daemon is resident anyway, so Ruby + GTK4 *inside the daemon* costs only the GTK half and needs
no D-Bus between UI and agent (`Q_one_process` in `desktop-popup-app.md`).

## Facts that hold for every option

- **Wayland placement is the same for all toolkits.** No client can place its window; only a GNOME
  Shell extension can (`Q_placement`). The toolkit doesn't change that.
- **Resident vs on-demand mostly decides itself.** A Siri feel wants the window in ~150 ms; only
  Vala, Go and maybe Python start that fast. Ruby, the JVM and Flutter stay resident, and then the
  hotkey just activates the running instance (GApplication single-instance, or the equivalent).
- **Markdown parsing is pikuri's and Ruby.** A Ruby UI calls the streaming parser directly. A UI in
  any other language must not reimplement it (two parsers drift): the daemon sends already-parsed
  blocks over D-Bus and the UI only draws them.

## The candidates

### Tier 1

- **Ruby + GTK4 (the plan).** All apt; the headless loop is proven (`gtk4-dev` skill); shares
  pikuri's code and can live in the daemon's process. Costs the measured ~1.2 s and ~116 MB, so
  it is resident.
- **Vala + GTK4.** Reads like C# / Java, compiles to C, reference-counted (no tracing GC; break
  cycles with `weak` / `unowned`). `valac` 0.56 is in apt. GTK4, libadwaita and GDBus are
  first-class: a `[DBus (name = …)]` interface yields a typed proxy. Starts about as fast and as
  small as C, so on-demand launch is realistic. Broadway works (it's GTK). Small ecosystem; some
  errors surface from the generated C. The best non-Ruby pick if the UI ever leaves the daemon.
- **Java / Kotlin on GTK4 via java-gi.** GTK4 through Panama FFM, so JDK 22+ [unverified]; a Maven
  dependency. Broadway and libadwaita for free. JVM on top of GTK: probably 150–200 MB resident,
  a sub-second cold start [estimate, not measured]; resident.
- **Kotlin/Native + gtk-kn.** Small and fast-starting, no JVM. The GTK4 bindings are young and
  the Kotlin/Native compiler is slow [unverified]. Apt's `kotlin` is 1.3.31, useless here; Gradle
  fetches the toolchain (allowed).
- **Dart / Flutter.** The snap is allowed. On Linux Flutter draws into a GTK3 window, ~100–150 MB,
  fast AOT start [estimates]. Strongest at animation (a bar growing into a conversation) and has
  the best headless story of any option: `flutter test` widget and golden tests need no display.
  D-Bus through Canonical's pure-Dart `dbus` package; Canonical ships Ubuntu's own apps in
  Flutter. `flutter_markdown` was discontinued by Google and lives on in community forks
  [unverified]. No Broadway; its own test harness instead.
- **Swing / Compose Desktop: no.** AWT runs through XWayland (blurry under fractional scaling)
  unless on the JetBrains Runtime's Wayland toolkit; testing needs Xvfb, which is parked
  (`gtk4-dev` skill); Compose adds Skia to the JVM's footprint.

### Tier 2

- **Python + PyGObject.** The leanest measured (0.2 s, 71 MB), all apt, Broadway works.
- **GJS.** All apt, ~71 MB, and the language of a Shell extension if `Q_placement` ever needs one.
  TypeScript via ts-for-gir (npm).
- **Go + gotk4.** Fast and small; Go modules, not apt; cgo makes the first build slow; the bindings
  rest mostly on one maintainer [unverified].

### Tier 3

- **Rust + gtk4-rs.** The most mature GTK4 binding after C. Only if everything above fails.

## Ranking

1. **Ruby + GTK4**, resident, likely in the daemon's process.
2. **Vala + GTK4** if the UI must leave Ruby (memory, start time, crash isolation), with parsed
   Markdown over D-Bus. Same widgets, same Broadway loop.
3. **Flutter** if animation polish and its headless tests outweigh the second toolkit.
