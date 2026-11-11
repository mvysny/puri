# Splitting Core and Desktop into two processes over D-Bus

Not planned; optional, not a milestone (`D_one_process`). It happens when the costs of one
process bite, when a second client becomes real (`Q_tui_client`), or when Desktop leaves Ruby for
Vala (`D_ruby_gtk4`). Protocol is already D-Bus-shaped and round-trips JSON, so the split swaps
`BackendClient`'s in-process call for a D-Bus proxy and nothing else. The facts for that day:

- **A local socket, never a TCP port.** *Local first* means no network listener, not even on
  loopback. So the D-Bus session bus, GNOME's native IPC; a `.service` file could start Core on
  the first call. A Unix socket in `$XDG_RUNTIME_DIR`, `0700`, is the fallback.
- **Ruby D-Bus without a new dependency:** `ruby-gio2` (already pulled in by `ruby-gtk4`) wraps
  GDBus on the GLib main loop; `ruby-dbus` (apt) is the pure-Ruby alternative, for a Core that
  shouldn't load GLib.

## Open questions

- `Q_dbus_binding`: GDBus via `ruby-gio2`, or `ruby-dbus`? Does Core want GLib at all?
- `Q_tui_client`: is a TUI just another client of Protocol (pikuri-tui talking D-Bus)? Not
  planned; noted because Protocol makes it cheap, and it would be a reason to split.
