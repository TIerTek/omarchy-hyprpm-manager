# How detection works

## Two sources of truth

hyprpm records what *should* be loaded. The compositor knows what *is* loaded.
Everything this plugin reports comes from the disagreement between them.

| Question | Source |
|---|---|
| Which plugins exist, and are they enabled? | `$STATE_DIR/<repo>/state.toml` |
| Which ABI were they built against? | `$STATE_DIR/state.toml`, key `hash` |
| Which plugins are loaded right now? | `hyprctl plugin list` |
| Which Hyprland is running? | `hyprctl -j version` |

`$STATE_DIR` defaults to `/var/cache/hyprpm/$USER`.

`hyprpm list` is deliberately **not** used. Its output is human-formatted and
carries ANSI colour escapes inside the values, so `enabled: true` does not
compare equal to the string `true`. The TOML files it writes are stable and
machine-readable; the printed form is not.

## The headers hash

The global `state.toml` records the ABI hyprpm built against, not a bare commit:

```toml
[state]
hash = 'efb50993...d9f_aq_0.14_hu_0.14_hg_0.5_hc_0.1_hlg_0.6'
```

The prefix before the first `_` is the Hyprland commit; the suffixes pin
aquamarine, hyprutils, hyprgraphics and friends. This is the string hyprpm
itself compares, so it is preferred over the installed `version.h`, which is
kept only as a fallback for state stores written by older hyprpm versions.

**Presence is judged from `version.h`, never from the recorded hash.** A
`state.toml` can name a hash for headers that are no longer on disk.

## Precedence

Report the cause, not its symptoms. A user with stale headers and four plugins
that failed to load has *one* problem, not five.

```
no state store, or no repositories        -> unavailable   (widget hides)
build tools missing                       -> broken        deps_missing
headers absent                            -> broken        headers_missing
headers hash != running commit
    and some enabled plugin not loaded    -> broken        abi_mismatch
    and every enabled plugin loaded       -> degraded      rebuild_pending
headers current
    plugin recorded as failed             -> broken        build_failed
    plugin enabled but not loaded         -> broken        not_loaded
otherwise                                 -> ok
```

`rebuild_pending` is the case worth having the plugin for: everything works
right now, and will keep working until the session restarts. Nothing else on
the system warns about it.

Disabled plugins are skipped entirely — not being loaded is what disabled
means.

## Failure behaviour

The collector always prints valid JSON and always exits 0. Any path it cannot
make sense of degrades to `unavailable`, which hides the widget. A status
widget that renders a half-parsed state is worse than one that renders nothing.
