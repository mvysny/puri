# GTK4 dev environment, headless: Ruby + libadwaita + Broadway + Playwright

Goal: build and test a Ruby GTK4 / libadwaita app (this project's popup, see `popup-ui.md`) on
this machine, which has no display (`XDG_SESSION_TYPE=tty`). An agent must be able to launch the
app, click and type into it, and look at it. Evaluated 2026-11-10 with a throwaway chat-shaped
window: a header bar, a `boxed-list` transcript of `Adw::ActionRow`s, an entry and a Send button.

## Verdict: it works, with Broadway

- **Stack, all from apt:** `ruby-gtk4` 4.3.4 (pulls in `ruby-gobject-introspection`, `ruby-gio2`
  and the rest), GTK 4.22.4, `gir1.2-adw-1` 1.9.1, and `gtk4-broadwayd` from `libgtk-4-bin`.
  Nothing downloaded.
- **libadwaita without a `ruby-adwaita` package:** load it through GObject Introspection, and it
  renders with the real Adwaita look (header bar, rounded window, accent button):

  ```ruby
  require 'gtk4'
  GObjectIntrospection::Repository.default.require('Adw', '1')
  module Adw; end
  GObjectIntrospection::Loader.load('Adw', Adw)
  ```

- **The loop:**

  ```sh
  gtk4-broadwayd --address 127.0.0.1 :5        # HTTP on 127.0.0.1:8085 (8080 + display)
  GDK_BACKEND=broadway BROADWAY_DISPLAY=:5 ruby app.rb
  ```

  Then the Playwright MCP opens `http://127.0.0.1:8085/` and reloads it once the app is up.
  `page.mouse.click(x, y)` and `page.keyboard.type/press` reach GTK, Enter included.
  `page.screenshot` gives the view as the user would see it.
- **In-process PNG, the test-friendly capture:** pixel-exact, just the window, no shadow. It needs
  a painted frame, and Broadway paints only while a browser has the page open. Without one, the
  window reports itself mapped at full size, yet `snap.to_node` is `nil` and `render_texture`
  raises:

  ```ruby
  paintable = Gtk::WidgetPaintable.new(win)
  snap = Gtk::Snapshot.new
  paintable.snapshot(snap, win.width, win.height)
  win.native.renderer.render_texture(snap.to_node, nil).save_to_png(path)
  ```

  Call it from a `GLib::Timeout` after `present` (the boot frame) or after an action. Ruby-GNOME
  has no `GLib::SOURCE_REMOVE` / `SOURCE_CONTINUE`: the block returns `false` to stop, `true` to
  repeat. Retry until `to_node` stops being `nil` rather than trusting a fixed delay.

## Gotchas hit (each cost a blank screen)

- **`require 'gtk4'` runs `gtk_init`.** Without `GDK_BACKEND` / `BROADWAY_DISPLAY` in the env *at
  require time*, it raises `Gtk::InitError`. So `spec_helper` has to set them before requiring.
- **`app.run` hands `ARGV` to GApplication.** A leftover argument is taken as a file to open,
  `activate` never fires, and nothing complains. Use `app.run([])`, and parse your own args first.
- **GApplication is single-instance on the session bus.** A second launch with the same id just
  activates the running one and exits. Create test and dev runs with the `:non_unique` flag.
- **The Broadway page needs a reload** once the app has connected; one opened earlier stays blank.
- **stdout is block-buffered** when it isn't a tty, so log lines show up late or not at all. Set
  `$stdout.sync = true` in dev.
- **Broadway listens on TCP** (127.0.0.1 only with `--address`). That's dev-only, and never the
  shipped app's IPC (see `popup-ui.md`).
- **Playwright MCP writes only under the project** (`.playwright-mcp/`). Screenshots can't go to
  the scratchpad.
- **A Ruby subclass of a GTK widget calls `super` with positional arguments**:
  `super(app)` in an `Adw::ApplicationWindow` subclass; `super(application: app)` raises.

## Broadway vs native

Re-checked 2026-11-10 with a second throwaway app: a rich-text editor (`TextView`, bold and italic
`TextTag`s, `ToggleButton`s, `win.*` actions with Ctrl+B / Ctrl+I accelerators). Typing, the
Shift / Ctrl / Home / End selection keys, the accelerators and the button state all behaved the
same as when it was launched natively.

Broadway replaces only the GDK backend, the layer that talks to the display. The widget tree,
signals, layout, `TextBuffer`, actions, CSS and libadwaita's widgets run the same code on both. So
Broadway is good enough for building and testing app logic and layout. What differs is where the
app meets the desktop, ranked by how much it could bite:

1. **Desktop settings don't reach the app.** Seen: the icon theme. Natively the
   `format-text-bold-symbolic` icon is Yaru's "B" (`gsettings … icon-theme` = `Yaru`); on
   Broadway it is GTK's default, Adwaita, whose icon is a bold lowercase "a". Not checked, but
   probably the same for fonts (name, size, scaling), dark mode and the accent colour. Fonts
   matter most: a different size changes text widths, so wrapping, truncation and minimum window
   sizes can differ. Dark mode can be forced through `Adw::StyleManager`.
2. **Desktop integration** is missing or only roughly imitated: window management, popover and
   dialog placement, focus between windows, the clipboard shared with other apps, drag and drop,
   IME and dead keys, `GlobalShortcuts`, portals such as the file chooser. See `Q_wayland_fidelity`.
3. **The keyboard goes through the browser** and Broadway's keymap translation. Plain keys,
   modifiers and Enter work; the browser may intercept some combinations.
4. **Pixels differ:** Broadway's own renderer versus GL or Vulkan, HiDPI scale, font hinting.
   Screenshots answer "does it look right", not "does it match a native golden".

So a native launch now and then stays part of the workflow, at least before trusting anything in
point 2.

## Xvfb: tried, parked

`xvfb-run` with `GDK_BACKEND=x11` drew no frame within 8 s, even with `GSK_RENDERER=cairo` and
`:non_unique` (the GL path also warns about missing DRI3). It wasn't chased further: Broadway
covers both the look and the input, and Xvfb would also need `xdotool` plus `xwd` or ImageMagick.
Revisit only if CI wants an X server rather than a broadwayd.

## Open questions

- `Q_test_harness`: rspec plus in-process PNGs plus synthetic input. Can a spec drive the widget
  tree directly (`button.clicked`, `entry.text =`, then a `GLib::MainContext` iteration) instead of
  going through the browser, keeping Playwright for exploratory looks? That's the GTK twin of
  `Tuile::Testing`. The in-process PNG needs a browser attached to Broadway, so the specs that
  take PNGs can't run without one. Does something other than a browser make Broadway paint?
- `Q_golden_images`: compare PNGs against checked-in goldens? Fonts and the GTK version drift, so
  a tolerance or a perceptual diff would be needed. Goldens would also have to come from Broadway,
  since its theme and fonts differ from the desktop's (*Broadway vs native*).
- `Q_wayland_fidelity`: the popup, focus and `GlobalShortcuts` need a real compositor.
  `mutter --headless --virtual-monitor` isn't installed. When does the project need it?
- `Q_ci`: does Woodpecker's image get `gtk4-broadwayd` + `ruby-gtk4` from apt the same way?
