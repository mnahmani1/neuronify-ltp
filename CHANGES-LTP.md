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

## New feature: quantification — axis control, CSV export, metadata

**Scalable axes with gradations.** A voltmeter's Properties panel now has an *Axis scaling*
section: time span, voltage/time division counts, and a gridline toggle. Every control accepts a
typed exact value as well as a drag, so figures are reproducible. The plot draws labelled
gradation lines at each division. Settings are saved with the simulation.

**Per-voltmeter CSV export.** A *Data recording* section (Record / Stop / Clear / Export CSV)
exports `time_ms` plus a voltage and a **spike** column per neuron. The spike column matters:
in an integrate-and-fire model the potential resets at threshold, so the voltage column alone
never shows a spike.

**Session recording — every meter and synapse into one file.** With nothing selected, press
Properties to reach the *Simulation* page, then *Record all*. This captures every voltmeter and
every synapse weight on a single shared 1 ms timebase:

```
time_ms, V1_<neuron>_mV, V1_<neuron>_spike, ..., S1_<from>_to_<to>_weight, ...
```

The weight columns make the **LTP learning curve** recordable for the first time.

**Metadata sidecar.** Each export also writes `<name>.metadata.json` with the conditions the data
was produced under — version, timestamps, sampling interval, every neuron's threshold / resting
potential / resistance / capacitance / refractory period, every synapse's current / delay / time
constant / full LTP settings, and each synapse's weight at the start and end of the run.

## Important: scope of the neuron model

Neuronify uses a **leaky integrate-and-fire** neuron: `Cm dV/dt = I_leak + I_syn + I_inj` with
`I_leak = -(V - Em)/R`, plus a threshold-and-reset rule. There are **no voltage-gated Na+/K+
conductances, no ion reversal potentials, and no action-potential waveform**.

Consequently **spike amplitude, width and shape are not modelled** — the spikes drawn in the
voltmeter are markers at a fixed +40 mV so the trace is readable. (They were previously drawn at
+1000 mV, which overshot every possible y-axis and made amplitude look unbounded; that is fixed.)

What *is* quantitative: spike times, firing rate, ISI and CV; EPSP/IPSP amplitude; temporal and
spatial summation; the membrane time constant `tau = R × Cm` (100 MΩ × 0.2 nF = 20 ms); and
synaptic weight over time. **Below threshold is modelled physics; at and above threshold is a
marker.**

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
- Spike Window default corrected to 1.0 s (was 100 s — outside the 0.1–5.0 s slider
  range, which made the window effectively unbounded).
- Spikes are drawn at +40 mV instead of +1000 mV, so amplitude no longer appears
  unbounded (see the scope note above).
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

## Running the pre-built apps (recipients — no building required)

Pre-built, self-contained downloads are on the [Releases page](https://github.com/mnahmani1/neuronify-ltp/releases).

**Windows (10/11, 64-bit):** download `Neuronify-LTP-Windows-x64.zip`, unzip anywhere, run
**Neuronify.exe**. If a blue "Windows protected your PC" box appears, click **More info →
Run anyway** (one-time; the app is unsigned, not malicious). No Qt or installer needed.

**macOS (Apple Silicon, macOS 11+):** download the `.dmg` (signed ad-hoc, not with a paid
Apple Developer ID), drag **Neuronify.app** to **Applications**, then **right-click →
Open → Open** the first time. Only needed once.

The Windows build is produced automatically by GitHub Actions
(`.github/workflows/build-windows.yml`) — every push to `main` rebuilds it and refreshes
the release asset; it can also be run manually from the repo's **Actions** tab.

---

## License

GPLv3, inherited from upstream Neuronify. The corresponding modified source is this
repository; anyone you give the binary to is entitled to it under the GPL.
