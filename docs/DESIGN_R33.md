# R33 — Canon pass: title, voice, slice map, gauge v0, drone bed

Round 33 is text-and-paper only, per the north star. No system behaviour
changed except two death-overlay strings. Suites stay green by construction
(re-verified at round close).

## 1. Title and voice canon

- **Title: THE ASSESSMENT.** Chosen by the author from the R32 candidate list
  (HUM / THE ASSESSMENT / B2). `project.godot` config/name updated.
- **Death-screen voice rule (new canon):** the overlay speaks in the surface
  story's job-paperwork register, because the surface story IS an assessment:
  `ASSESSMENT INTERRUPTED` / `[R] resume the survey`. Pre-reveal this reads as
  employer bureaucracy; post-reveal it recontextualises without changing a
  letter (they were the assessment). No tape grammar, no fantasy register
  ("rise again" retired), no clinical research vocabulary before act two —
  except as deliberate, rule-1-compliant leaks.
- **String audit result:** the codebase carried zero tape-language strings
  (the rejected theatre spine died before implementation). Inventory, toast,
  settings and debug strings are register-neutral and stay.

## 2. Slice paper map — "one wing, one reveal, one door"

2 m module = M. Doors D*, alcoves A*. Beats reference the north-star sheet.

```
 [STAIR ↓1 storey]                       kit: stair flight
        │ D1 (chapter gate, locks behind)  kit: door opening + leaf
 [INTAKE CORRIDOR]  8M straight, flush troffers, stripe begins
        │   A1 @ M5 (hide alcove)          <- THE LIE beat: cardiogram
        │                                   false positive here, nothing comes
 [T-JUNCTION]
        ├── [MACHINE ROOM] 3×3M            kit: room shell + vent prop
        │      drone source #1; sightline break; first hiding lesson room
        │
        └── [DOGLEG CORRIDOR] 10M + 4M offset
               A2 @ dogleg apex            <- first REAL sighting at the
        │                                   10M vanishing point; hide-or-chase
        │ D2
 [OFFICE] 2×3M                            kit: room shell + desk/filing props
        shotgun + 2 shells on the desk    <- gun-trap placement; notes prop
        │ D3                                (surface paperwork, buried leaks)
 [HALL] 6M wide                           <- TRUE-SPIKE beat: cardiogram and
        │                                   band agree here; dismissing both
        ├── [INTERCOM ROOM] 1×2M            is what kills
        │      confession gate: your own pre-experiment voice;
        │      listening opens D4          kit: intercom prop
        │ D4
 [REGISTRY] 2×2M                          kit: room shell + shelving prop
        your file open, photo current, date today
        │ D5 SEALED — cut to black with the hum   <- slice end, mid-truth
```

Kit tally confirmed against the request list: doors ×5 (+frames), stair ×1,
alcoves ×2, room shells ×4 (machine, office, intercom, registry), flush
troffer, props at R35+. Nothing outside the list. Nothing on the list unused.

## 3. Gauge design note v0 — the wrist band and the FAIR lie

- Mind-state: one hidden float, `arousal` 0..1. Drivers: unlit time, true
  proximity, gunfire (large spike), hallucination events, exertion in the
  dark. Decay: lit rest, seated/still, post-confession.
- The band's faces (all diegetic, no UI bars): glance-down overlay trace +
  BPM numeral; breath audio layer; hand tremor = camera noise amplitude;
  at high arousal, the band's own hum sits slightly under the room tone.
- **The fair-lie protocol (canon, implements house rules 1+2):** during a
  FALSE cardiogram spike the band reads CALM. Instruments may lie; bodies
  don't — and the band is the body. Therefore a attentive player can always
  discriminate lie from truth by cross-reading scope vs band; doubt is a
  skill, never a coin flip. TRUE spikes: scope and band agree. The author's
  trap ("they ignore the gauge because they think it's lying") now kills
  only players who dismissed BOTH channels — earned, per rule 5 of R32.
- Lie budget: scripted lies only in authored zones (A1 first), plus at most
  one unscripted lie per ~8 min of play, never twice in the same room,
  never during a chase. Every lie logs to the creature-log drain for
  playtest analysis.

## 4. Drone bed spec — the facility as instrument

1. **Room tone:** fluorescent ballast hum (100 Hz component) + concrete air
   movement. Present everywhere lit; absent in dead rooms (absence = tell).
2. **Machine drones:** positional loops per room (vent, pumps, lift relay).
   The machine room's vent is the slice's first instrument.
3. **Sub bed:** sine sub-bass tied to `arousal`, inaudible at 0, felt at 0.6,
   audible at 0.85. The mind-state's only always-on voice — and it is the
   title: the HUM.
4. **Percussion:** chase only. Metal-on-metal hits, no kit, no cymbals.
5. **Melody:** none before the confession gate. After it, one detuned piano
   motif (the memory motif), reused exactly once: the registry reveal.
6. **Mix rule:** glancing at the band ducks layers 1-2 by 3 dB — listening to
   yourself costs you the room. (Teaches the glance as a decision.)

## 5. Round close

- Changed: `project.godot` (title), `scenes/ui/death_overlay.tscn` (two
  strings), this doc, NORTH_STAR title canon.
- Suites: green (jumpscare 43/43, noise 47/47, proximity 23/23, ai 0, fly 5/5).
- Next: **R34** — greybox the slice map at 2 m modules, hiding verb + hide
  spots, cardiogram false-positive event + band v0 (fair-lie protocol),
  mind-state director v0. Author's week: kit piece #1 (door opening + leaf).
