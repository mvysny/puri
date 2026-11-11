# The popup on Mutter: placement, resizing, a second hotkey

The popup was built and screenshotted on Broadway; the installer and the shortcut are verified
natively (`R_gnome_activation`). What Broadway can't show is still open, all [unverified]:

- **A Wayland client can't place its window.** xdg-shell has no absolute positioning; Mutter
  decides. `org.gnome.mutter center-new-windows` centers new windows, but the user may have it
  off, and "a third of the way down the screen" is not on offer. gtk4-layer-shell would do it, but
  Mutter doesn't implement layer-shell.
- **A self-resized window keeps its top-left corner** on Mutter, so it grows down and right. The
  pill is already 33 % wide, so the jump to full size only grows it downward; the history sidebar
  widens it to the right.
- **Focus-out** reaches the app as `is-active` changes; the pill has no dialog or file chooser
  that could take focus away.

## Open questions

- `Q_placement`: is Mutter's centering good enough? Does Mutter keep a 70 %-tall window on
  screen when the pill sat at mid-height? Or does the popup need the GNOME Shell extension route,
  which can place windows but is JavaScript and per-GNOME-version?
- `Q_user_resize`: does the next popup remember a size the user dragged, or always open at
  33 % × 70 %? Can an undecorated GTK4 window be resized from its edges on Mutter, or does it need
  GTK's own CSD resize borders?
- `Q_copilot_key`: besides Super+Space, also bind the Copilot key (Shift+Super+F23) where a
  keyboard has one, the one key that already means "assistant"?
- The XDG `GlobalShortcuts` portal instead of a custom keybinding: which GNOME version
  implements it, and is it worth it now that the keybinding works?
