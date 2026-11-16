# Shared app config

OS-independent application config that is **imported through an app's own UI**,
rather than installed to a path by `install-windows.ps1` / `install-wsl2.sh`.

That distinction is why these do not live under `windows/` or `wsl2/`: the same
file is used from every environment, including ones this repo does not manage
(an iPhone PWA, for instance). Nothing here is copied anywhere by a script.

## Contents

| File | App | How to apply |
|---|---|---|
| `t3code-theme-dimidium.json` | T3 Code (`deanjstone/t3code`) | Settings → Appearance → Import. Accepts the file or pasted JSON. |

## `t3code-theme-dimidium.json`

The Dimidium palette as a T3 Code theme file — the same palette as this repo's
`windows/zed-theme-dimidium*.json` and `windows/wt-scheme-dimidium*.json`, in a
different app's format. One file covers both appearances (`colors` is light,
`variants.dark` is dark), unlike the Zed ports which are split.

Generated with T3 Code's own `serializeThemeFile()`, so it round-trips through
that app's importer — verified by parsing it back with `parseThemeFile`.

**Import once per client.** It persists in that client's `localStorage`, but a
browser profile, a PWA install and the desktop app are each separate clients.
On iOS, paste the JSON rather than picking a file.

**It cannot be used in the T3 Code mobile (React Native) app.** That app
enumerates built-in themes only and has no custom-theme support. The iPhone PWA
is unaffected — it runs the web bundle.

**Nothing validates this file's contrast.** Every theme guard in the T3 Code
repo iterates its built-in theme list, so an imported theme is checked by none
of them — including the WCAG AA test. Hand-editing a colour here will not be
caught by anything.

Every text pair in this file was audited by hand and clears WCAG AA; the muted
and secondary text family clears **AAA (7.0:1)**. That matters because the app's
Appearance → Contrast slider exists to compensate for dim palettes: an earlier
version of this file sat at 4.58–4.70 across all secondary text — legal, but
only just — and needed the slider at 150% to read comfortably. Contrast was
raised at the palette level instead, so the slider can stay at 100%.

If you edit a colour, re-audit rather than trusting the eye: pair every
`*Foreground`/`*Muted`/`placeholder` role against each surface it can sit on
(canvas, surface, surfaceOverlay, sidebar, input) and keep text at 4.5:1
minimum, 7.0:1 for the muted family.
