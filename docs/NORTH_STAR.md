# NORTH STAR v2 — "THE LINE" (working title; draft, pending approval)

> **DRAFT built from the author's interview (docs/DESIGN-INTERVIEW.md lives in
> the workspace; batches 1–3, 2026-09-14).** Supersedes the rejected theatre
> spine (docs/archive/NORTH_STAR_theatre_rejected.md). Nothing here is canon
> until the author approves; the open questions at the bottom are part of the
> draft.

## The fiction, in one paragraph

Under the demolished-east-wing paperwork of a decommissioned research institute
there is an annex that was never on the public plans: poured-concrete levels of
glazed-brick corridors, troffer lights that still hum, a painted wayfinding
line running at chest height through all of it. You are a site assessor sent
down for the pre-demolition survey — clipboard job, one day, in and out. The
annex has other paperwork. You worked here: junior researcher, ambitious,
afraid, complicit in the mind experiments until you were filed as a subject
yourself and forgot all of it on the way out. The isolation is pulling the
repression apart seam by seam; something walks the corridors that behaves like
a creature and remembers like a guilt; and the deeper the line leads, the less
of what you perceive was ever down here — until the final file, which says the
experiment succeeded, the subject walked out, and the subject is standing where
you are standing, reading this. **You are the source of the horror.** The
corridor leads to you.

## What the creature means

- Two layers, one body. PHYSICAL: a real, hideable-from presence with the
  existing awareness/navigator AI. PERCEPTION: a mind-state director that
  modulates what is shown, heard and instrumented. Some encounters are both
  layers; some are only one. The player can never fully subtract them.
- It is repressed guilt with a gait. It does not need to catch you; it needs
  you to keep running from what it remembers. Defeat condition is
  psychological: stop repressing, accept complicity.
- **The cry-wolf gauge (author's loop, canon):** the first hallucination is a
  FALSE POSITIVE on the proximity cardiogram — spike, panic, hide, nothing.
  The instrument's unreliability is taught in one beat. Later the real creature
  arrives exactly when the player has learned to distrust the spike. Doubt is
  the ambush vector; the game manufactures the doubt, then arms it.
- **The gun is a trap (author's rule, canon):** the shotgun works only on the
  physical layer; a "kill" respawns the creature angrier or faster; firing
  plummets the mind-state because violence triggers the guilt. The player must
  learn to put it down. Lights, noisemakers, hiding spots are the real tools.
  You cannot shoot guilt.

## House rules (design laws for all future content)

1. **Two layers, one truth budget.** Every hallucination has a rule and a
   learnable signature. The game never lies without a tell; a lie the player
   could not have read is a bug, not a scare.
2. **Instruments can lie; bodies don't.** Breath, heartbeat, tremor, cold,
   light-behaviour are always honest. When the cardiogram and the body
   disagree, the body is true. The player always has a floor to stand on.
3. **Violence feeds it.** See the gun rule. Any future weapon inherits it.
4. **The line is a promise.** The painted wayfinding stripe is level-design
   grammar: it leads somewhere real; every place the level deviates from it
   (a repainted segment, a branch that isn't signed, a stretch scrubbed out)
   is authored meaning, never decoration.
5. **Maintained, not decayed.** The annex is clean, lit, humming. Someone
   changes the fluorescents. Dread comes from care, not rot. Retro look stays
   as a period grade with light grain — crisp geometry, no tape fiction, no
   VHS overlays (found-footage devices are dead per the rejection).
6. **No sanity bars.** The mind-state is a director, not a resource the player
   watches drain. Its only faces are the quiet gauge, the body, and the world.

## The quiet gauge — CANON: wrist vitals band

Author delegated the call (batch 4); agent chose the **wrist vitals band**
from their subject days — they cannot remember why they own it. Easiest to
model (strap + small face), easiest to implement (glance-down overlay, no
hold-animation, no hand-slot conflict with flashlight or shotgun), and the
masterpiece payload: its serial number is a subject ID, and the registry at
the bottom of the line matches it to their file. The cardiogram stays
creature-only and *mostly* honest; the band carries the mind-state; when the
two disagree, rule 2 decides which to believe. (Handheld survey device
considered and retired.)

## Vertical slice — "one wing, one reveal, one door" (20–30 min)

Beat sheet, which doubles as the **module shopping list** for the author's
kit (rooms/corridors below are what the greybox and then the real modules must
provide):

| min | beat | space needed from the kit |
|---|---|---|
| 0–3 | descent: stair/elevator to annex door; hum, lights, the line begins; job-paperwork framing | entry stair or lift lobby, blast door |
| 3–7 | orientation: first long corridor, turns, signage; walking-pace noise tiers teach themselves | straight corridor module ×long, one T-junction |
| 7–10 | **the lie:** cardiogram false positive; panic; nothing; the instrument is guilty now | corridor with hiding alcove (first hide spot) |
| 10–15 | first REAL presence: sighting, patrol, hide-or-be-chased; hiding verb proven | junction + one room shell (machine room: drone audio source) |
| 15–20 | **the teeth:** a true spike the player may now dismiss; gun offered, gun punishes if taken | second room shell (office: shotgun + shells on a desk) |
| 20–26 | confession gate tease: an intercom/record room where their own pre-experiment voice speaks; the door it holds opens only if you listen | small room + intercom prop + gate door |
| 26–30 | the reveal, mid-truth, on a door: the patient registry; their file open, photo current, date today. Cut to black with the hum | registry office + sealed door = slice end |

Slice scope rule: **no acceptance system yet** (one gate as a promise), **no
second creature**, **no endings** — the slice ends mid-truth by contract.

## Round plan

- **R33 — canon pass (text + paper):** this doc approved; slice level paper
  map (room graph over kit pieces); gauge design note; UI strings de-taped
  (no rewind/chapter language — that died with the theatre); drone-bed spec.
- **R34 — the lie, playable:** greybox slice level at the author's module
  dimensions; hiding verb + hide spots; cardiogram false-positive event;
  mind-state director v0 (hidden, tells only). Suites extended.
- **R35 — kit swap pass 1 + the teeth:** author's modules replace greybox as
  they land (LFS/uploads pipeline); true-spike trap; gun-trap wiring; drone
  bed in.
- **R36 — the reveal:** registry office, confession gate, slice ending beat;
  playtest round (FIXES_R36_*.md); itch page material from captures.
- Then reassess toward the 60–90 min short: acceptance system (confession
  gates vs single final choice) designed at the slice playtest, not before.

## Production contract (anti-waste clauses)

- **Ownership:** author owns the place (kit, textures, rooms, set pieces,
  audio direction). Agent owns play (systems, AI, wiring, tests, exports,
  docs). Every round: author places or decides; agent makes it move and
  proves it green.
- **Pipeline:** author holds GitHub; agent sends patches. Protocol (batch 4):
  `scripts/make-patches.sh` emits a `git format-patch` series from trunk
  tip..HEAD; author applies with `git am` and pushes; author's asset commits
  land on trunk and the agent fetches+merges trunk before each round. The
  R32+design divergence is resolved by the FIRST patch bundle (delivered
  2026-09-14), after which trunk and workbench share history again.
- **Cadence (batch 4):** author bandwidth 10 h/week. Agent front-loads systems
  on greybox so kit never blocks a round; author delivers ~1 kit piece or 1
  decision batch per week; slice playtest (R36) projected ~5-6 weeks out.
- **Kill criterion:** if the hiding loop is not fun at the R35 playtest, the
  slice pivots (perception-first, creature reduced) BEFORE more content is
  built. Killing early is the system working.
- **Definition of done (slice):** the seven beats above playable end-to-end
  with author's modules in the primary spaces, suites green, one external
  playtest round documented.

## What we will not do

Found-footage devices. Sanity bars. Jumpscare-only scares. Combat as a
solution. Open world. Second creature before acceptance proves. Multiplayer,
VR, crafting, dialogue trees. Anything that makes the annex bigger instead of
truer.

## Kit standard & request list (batch 4: 2 m × 2 m wall, floor, ceiling exist)

Canon dimension: **2 m wide × 2 m high** wall segment; floor and ceiling tiles
to match. 2 m ceiling is oppressive in the right way — keep it. Consequence:
the chained troffer fixture hangs into headroom; either ship a flush/recessed
troffer variant for corridors (recommended) or let the chained hang live only
in rooms and crouch-moments (also fine, author's call, both play).

Requested, in slice order (one piece per author-week at 10 h/wk):

1. **Wall segment with door opening** + **industrial door leaf & frame** —
   doors are gates, hide-beats and chapter beats; nothing else matters first.
2. **Stair flight down** (one storey) or lift cab + shaft door — the descent
   beat; stair preferred (simpler, and stairs are horror).
3. **Hide alcove**: 1 m recessed nook piece (cheaper than a room shell per
   hiding spot; reads as service recess in the brick).
4. **Flush troffer variant** (see above).
5. R35+: junction signage plate, pipe/duct run props, desk + filing cabinet
   (office), intercom box (confession gate), registry shelving (reveal room).

Corner pieces NOT requested: butted walls read fine at period grade.
T-junctions compose from straights. Room shells compose from walls+floor+
ceiling. The kit is already sufficient for everything except openings.

## Title candidates (author: "something cool, reference real games, not AI-smelling")

1. **HUM** — one-word modern register (Signalis, Routine, Scorn). Names the
   real-world phenomenon: a low sound with no findable source — unreliable
   perception as a title. The drone bed IS the hum; the audio direction and
   the title become the same object. Store-page strong.
2. **THE ASSESSMENT** — paperwork horror (Severance's corporate dread, Papers
   Please mundanity). The surface story as title; at the reveal it inverts:
   the player understands who was really being assessed, and since when.
3. **B2** — signage title, liminal lineage (backrooms, Kane Pixels): an
   elevator button as a name. Cryptic, human, un-marketable-safe, very cool
   in the right typography.

Agent's pick: **HUM** (shortest distance between the audio design and the
theme; impossible to mistake for generated filler). Retired: "THE LINE"
(working title, served its purpose).

## Answered / remaining

Answered in batch 4: grid 2×2 m · gauge = wrist band · 10 h/wk · patches
protocol · (title = pick above). Remaining: title pick; author's veto window
on any of the above; first kit piece (door opening + leaf).
