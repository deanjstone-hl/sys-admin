# Diagrams

How sys-admin works: the declared dev stack and sysadmin skills, how an installer run changes the laptop, and the check, promote and install path.

Self-contained HTML/SVG diagrams drawn with the [diagram-design](https://github.com/cathrynlavery/diagram-design) Claude Code plugin in the house style of [argus-config `docs/diagrams/`](https://github.com/deanjstone/argus-config/tree/main/docs/diagrams) (sys-admin#195, map argus-config#1433). Open a `.html` file in a browser. Each is theme-aware and fits a phone width.

| Diagram | Type | Flow | Step ids | Sources |
|---|---|---|---|---|
| [`architecture.html`](architecture.html) | Architecture | `arch` | `stack` `skills` `install` `link` `live` `drift` | `README.md`, `stack/docs/SCOPE.md`, `stack/install-wsl2.sh`, `stack/check-drift.sh` |
| [`installer-run.html`](installer-run.html) | Process | `apply` | `dry` `guard` `link` `node` `units` `tools` `drift` | `stack/install-wsl2.sh`, `scripts/require-deploy-checkout.sh`, `README.md` |
| [`build-deploy.html`](build-deploy.html) | Pipeline | `deploy` | `edit` `push` `ci` `approve` `release` `owner` | `README.md`, `.github/workflows/`, `scripts/check.sh` |

Each step node is a `<g id="step-<flow>-<step>">`, the deep-link contract of [ops-hub#13](https://github.com/deanjstone/ops-hub/issues/13): the hub links `#/diagrams/<repo>/<path>#<step-id>`, and the page highlights the targeted step (`:target`). Anything inferred is marked `[speculation]` in the diagram or its source line.

## Not drawn

Not drawn: the Syncthing scripts, the one-time T3 boot cutover, the Windows installers and the skills' own steps.

## Network

The diagrams use the system font stack and make no network request.

## Redrawing

The diagrams are hand-checked against their sources, not generated from them. After the sources change, redraw with the plugin and rerun its checks: `self_check.py` in the skill directory and `verify-geometry.py` in the plugin's `scripts/`.
