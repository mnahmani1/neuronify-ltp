# Neuronify — LTP Edition (fork changelog)

This is a modified build of the open-source **Neuronify** educational neural-network
app (CINPLA / ovilab, GPLv3). It adds synaptic plasticity (Long-Term Potentiation)
and fixes save/reload so that circuits keep their configuration.

Base: Neuronify 1.3.9. Platform verified: macOS (Apple Silicon, macOS 11+), Qt 5.15.

---

## New feature: Long-Term Potentiation (LTP)

Any synaptic connection can now learn. Enable **LTP** in a synapse's Properties
panel and the connection strengthens with repeated pre-synaptic activity — the line
grows thicker and darker as its weight climbs. Five per-synapse controls:

| Control | Default | Range | What it does |
|---|---|---|---|
| **Max Weight** | 3.0 | 1.1 – 10.0 | Ceiling on synaptic strength. |
| **Learning Rate** | 0.10 | 0.01 – 0.50 | Size of each potentiation step (proportional to the gap to the ceiling). |
| **Spike Window** | 1.0 s | 0.1 – 5.0 s | Rolling window over which pre-synaptic spikes are counted. |
| **Spike Threshold** | 3 | 1 – 20 | Spikes needed within the window to trigger one LTP event. |
| **Forgetting Rate** | 0.20 /s | 0.00 – 1.00 /s | How fast the weight relaxes back to baseline when unused (0 = never forgets). |

- **Strengthening** (per LTP event): `w += learning_rate * (max_weight - w)`.
- **Forgetting** (per step, exponential relaxation): `w = baseline + (w - baseline) * e^(-forgetting_rate * dt)`.
- Works for both `CurrentSynapse` (neuron→neuron) and `ImmediateFireSynapse`
  (e.g. TouchSensor-driven) edges. Implemented in C++ (`EdgeBase`/`EdgeEngine`).

A companion plain-language guide for entry-level neuroscientists,
**`Neuronify_LTP_Reference.docx`**, explains each parameter and the math.

## New feature: full configuration persistence on save / reload

Saving a `.neuronify` file and reopening it now restores the complete configuration:

- **Synapse settings** — LTP parameters (all five above) plus current, delay, and time constant.
- **Neuron / generator / sensor settings** — threshold, resistance, capacitance, resting
  potential, refractory period, etc. (previously these silently reset to defaults on load).

## Bug fixes included in this build

- Connection lines are drawn again (were invisible; only the diamond connector showed).
- Synapse modulation controls (current / delay / time constant) restored to the panel.
- Reciprocal connections (A→B **and** B→A) can coexist.
- Existing `.neuronify` example files (SQLite format) open correctly.
- Saving writes the correct SQLite format, so files reopen faithfully.
- Passive weight decay is observable (was ~1000× too slow to see).
- Simulation stepping / pan-zoom / drag-to-connect / add-node crashes fixed.

---

## Build from source (any platform)

Requires **Qt 5.15** (Qt 6 not supported) and a C++14 compiler.

```bash
qmake neuronify.pro          # generates the Makefile
make -j4                     # builds Neuronify.app (macOS) / Neuronify (Linux/Win)
```

### macOS: make a distributable, self-contained app

The freshly built `.app` links against your local Qt and will not run on another
Mac until Qt is bundled into it and it is (re-)signed:

```bash
# 1. Bundle Qt frameworks + QML plugins into the app
macdeployqt Neuronify.app -qmldir=qml

# 2. Ad-hoc code-sign (REQUIRED on Apple Silicon, or the app is killed on launch)
codesign --force --deep --sign - Neuronify.app

# 3. (optional) package as a .dmg
hdiutil create -volname "Neuronify LTP" -srcfolder Neuronify.app \
  -ov -format UDZO Neuronify-LTP.dmg
```

## Opening the pre-built macOS app (recipients)

The `.dmg` is signed *ad-hoc*, not with a paid Apple Developer ID, so on first
launch macOS shows an "unverified developer" warning. To open it:

1. Drag **Neuronify.app** to **Applications**.
2. **Right-click** (Control-click) Neuronify → **Open** → **Open** in the dialog.

Only needed once. Requires an Apple Silicon Mac, macOS 11+.

---

## License

GPLv3, inherited from upstream Neuronify. The corresponding modified source is this
repository; anyone you give the binary to is entitled to it under the GPL.
