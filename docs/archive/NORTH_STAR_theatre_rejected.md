# NORTH STAR — "THE HOUSE" (REJECTED — archived 2026-09-14)

> **REJECTED by the author before approval.** The found-footage / broadcast-
> theatre spine is not this game. Kept only as a worked example of the format
> (fiction paragraph → creature meaning → house rules → beat sheet → round
> plan); the next north star must be built from the author's own corridor,
> modular kit and intent — see the conversation that produced this archive
> entry. Do not revive its fiction; reuse only its structure.

## The fiction, in one paragraph

It is the night before the demolition of the Meridian House, a broadcast
theatre that closed in 1987 after a final performance that — the papers say —
never ended. You are an archive technician sent in with a camcorder to recover
the master tapes of that show. The house is not haunted by a ghost; it is
*occupied by an engagement*. The Performer — the thing in the corridors — is
what remains of a performer denied an ending: it does not hunt you because it
hates you, it hunts you because **it needs an audience**, and you are the only
seat left. Everything the camera does is tape grammar: what you play is the
master tape, deaths are dropouts, respawns are rewinds to the last chapter
marker, and the tape ends when the programme does.

## What the creature means

- It is hospitality, inverted. The kill sequence is not a mauling; it is **the
  closest seat in the house** — which is exactly why the kill cam welds to its
  jaws and breathes on the lens (KILL_SEQUENCE_R30 §4 already built this; the
  fiction now explains why it reads intimate instead of random).
- It never runs while uncertain. Walk speed is *blocking*; the run is
  *performance*, and performance only begins once the scene is confirmed
  (`CreatureAwareness.confirmed()`). An unconfirmed house merely keeps its
  rounds.
- Downed is **intermission**, not defeat (`neutralize_time`): the show pauses,
  the house is briefly yours, and then it gets up angrier because an
  intermission without an audience is an insult.
- Feeding is **the encore** (`_update_feeding`): what it does with the previous
  crew. You watch it once, from the wrong side, and you learn what "caught"
  means here.
- The house applauds only when it finds you. Applause is the failure sting —
  a layer under the kill audio, never heard anywhere else. (New audio, one
  sample, R35.)

## House rules (design laws for all future content)

1. **Sound is currency.** Every verb has a price in the noise meter; the
   cheapest movement is the strongest tool. Content must offer silent
   alternatives before loud conveniences.
2. **The tape is the frame.** Diegesis first: checkpoints are chapter markers
   (heavy doors — they already rebake nav and already gate pursuit), death is
   `SIGNAL LOST — REWIND [R]`, the boot screen is a camcorder/TVE boot, menus
   are OSD. No game-y UI vocabulary enters the fiction.
3. **Every reel costs.** The masters are inventory items with real weight
   (`ItemData.weight` → carry weight → camera mass already exists): carrying
   the programme makes you slower, louder, more present. Greed is a difficulty
   slider the player sets themselves.
4. **Light is a rumour, sound is a fact.** Sight/LOS stays primary; flashlight
   discipline may later multiply detection, but no content may *require*
   darkness before the hall teaches it.
5. **No cheap rooms.** A scare must be payable: the player could have read it
   (noise tier, proximity band, sightline) and chose otherwise. The kill is
   the consequence layer, never the jump layer.

## What the player feels, minute by minute (vertical-slice beat sheet)

Over the geometry that already exists — spawn → door1 → corridor → crawl →
door2 → hall → stage:

| min | beat | teaches / feels |
|---|---|---|
| 0–2 | tape boot, OSD wakes, corridor at walk pace | the tape grammar; noise tiers without words (debris forces crouch) |
| 3–5 | first sight: the Performer mid-blocking; a pipe knocks somewhere (scripted) and it leaves to investigate | it follows sound, not you — hope |
| 6–9 | first confirmed chase; first death = the kill sequence | the thesis: the closest seat. Rewind to chapter 1 marker |
| 10–14 | crawlspace: vertical, intimate, mirrored (it crawls too); first master reel pickup — weight lands in the camera | greed; the programme is on your back |
| 15–19 | hall: intermission window taught honestly (lure or down it; 25 s of house that is yours); second reel | risk/reward with a clock |
| 20–24 | stage: place the reels, house lights up, applause from empty seats, cut to your own camcorder's snow | you were on the tape all along |

Slice scope rule: **no new systems.** Reels are `ItemData`; chapter markers are
respawn-point moves; the knock is a scripted `set_alert`; the finale is light
+ applause + the director's existing fade machinery. Throwables ("noise as an
instrument") are R36+ *if* the slice plays well — they deserve their own round,
not this one.

## Round plan from here

- **R33 — fiction pass (text-only):** this doc approved; UI strings to tape
  grammar (`SIGNAL LOST — REWIND`, chapter markers, boot screen); credits/
  README fiction paragraph. Zero system changes; suites stay green.
- **R34 — the beat sheet lands:** staged investigate knock, first-sight
  pacing, reel items + weight wiring into carry mass, chapter-marker respawn
  points at doors.
- **R35 — the ending:** stage finale, applause sting layer, tape-cut to snow;
  boot/menu shell in OSD grammar.
- **R36 — pacing & audio pass + playtest round** in the house process
  (FIXES_R36_*.md), then itch-page material from headless captures.

## What we will not do

Multiplayer. VR. Open world. Crafting, skill trees, dialogue trees, fetch
quests unconnected to the reels. A second creature before the first has an
arcade of rooms to rule. Anything that makes the house bigger instead of
deeper.

## Alternative spine considered (rejected for now, kept on file)

*The ward:* hospital fiction where the proximity cardiogram is your own
vitals band and the creature tracks the same signal — fear as beacon. Strong
UI fit (medical box props, heartbeat), weaker ending, crowded genre. If the
theatre spine dies in playtest, this is the understudy.
