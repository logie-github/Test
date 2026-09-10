#!/usr/bin/env python3
"""Convert pret/poketcg Duel Theme 1 score to Gen1Recomp ChipAsm.

The TCG engine's `speed N` is a frame multiplier: every note/rest lasts
N * encoded_length VBlanks. Gen1Recomp's ChipSynth uses tempo=0x100 (256)
for exactly one 60 Hz frame per speed unit, so this translation preserves the
original timing without guessing a BPM.

Finite loops and music_call subroutines are expanded at build time. MainLoop
remains an infinite ChipAsm loop. Commands not affecting pitch/timing (cutoff,
echo and the TCG-specific tie retrigger suppression) are intentionally omitted;
the score timing, notes, octaves, duty changes, envelopes, wave instrument and
noise rhythm are preserved.
"""
from pathlib import Path
import re

HERE = Path(__file__).resolve().parent
SRC = HERE / "dueltheme1.asm"
OUT = HERE.parent / "dueltheme1.lua"

lines = [line.strip() for line in SRC.read_text(encoding="utf-8").splitlines()]
labels = {}
current = None
for line in lines:
    if not line or line.startswith(";"):
        continue
    if line.endswith(":"):
        current = line[:-1]
        labels[current] = []
    elif current:
        labels[current].append(line)


def expand(seq, stack=()):
    out = []
    i = 0
    while i < len(seq):
        line = seq[i]
        if line.startswith("Loop "):
            count = int(line.split()[1])
            depth = 1
            j = i + 1
            while j < len(seq):
                if seq[j].startswith("Loop "):
                    depth += 1
                elif seq[j] == "EndLoop":
                    depth -= 1
                    if depth == 0:
                        break
                j += 1
            if depth:
                raise RuntimeError("unclosed Loop")
            inner = expand(seq[i + 1:j], stack)
            out.extend(inner * count)
            i = j + 1
            continue
        if line == "EndLoop":
            raise RuntimeError("unexpected EndLoop")
        if line.startswith("music_call "):
            label = line.split(None, 1)[1]
            if label in stack:
                raise RuntimeError(f"recursive music_call: {label}")
            out.extend(expand(labels[label], stack + (label,)))
            i += 1
            continue
        if line == "music_ret":
            i += 1
            continue
        out.append(line)
        i += 1
    return out


def channel_parts(number):
    raw = labels[f"Music_DuelTheme1_Ch{number}"]
    start = raw.index("MainLoop")
    end = raw.index("EndMainLoop")
    return expand(raw[:start]), expand(raw[start + 1:end])


def q(s):
    return '"' + s.replace('\\', '\\\\').replace('"', '\\"') + '"'


NOTE = {"C_":"C", "C#":"C#", "D_":"D", "D#":"D#", "E_":"E",
        "F_":"F", "F#":"F#", "G_":"G", "G#":"G#", "A_":"A",
        "A#":"A#", "B_":"B"}
DRUM = {"bass":1, "snare1":2, "snare2":3, "snare3":4, "snare4":5, "snare5":6}


def duration_frames(seq, initial_speed=7):
    speed = initial_speed
    total = 0
    for line in seq:
        if line.startswith("speed "):
            speed = int(line.split()[1])
            continue
        op = line.split()[0]
        if op == "note":
            length = int(line.rsplit(",", 1)[1].strip())
            total += speed * length
        elif op == "rest" or op in DRUM:
            length = int(line.split()[-1])
            total += speed * length
    return total


def convert(number, seq, state=None):
    # PRELUDE and MainLoop are one continuous hardware channel.  Carry the
    # complete sound state across that boundary: resetting speed to ChipAsm's
    # default 12 at MainLoop was the v1.0.339 timing bug.  The TCG score starts
    # each channel with `speed 7`, and every branch/finite loop below is already
    # expanded inline, so a shared state makes later envelope commands preserve
    # the source speed instead of silently changing the rhythm.
    if state is None:
        state = {
            "speed": 12,
            "volume": 12,
            "fade": 0,
            "wave_level": 2,
            "wave_instrument": 0,
            "octave": 4,
            "vibrato_type": 0,
            "vibrato_delay": 0,
        }
    speed = state["speed"]
    volume = state["volume"]
    fade = state["fade"]
    wave_level = state["wave_level"]
    wave_instrument = state["wave_instrument"]
    octave = state["octave"]
    vibrato_type = state["vibrato_type"]
    vibrato_delay = state["vibrato_delay"]
    events = []

    def notetype():
        if number in (1, 2):
            events.append(f"{{notetype={{speed={speed},volume={volume},fade={fade}}}}}")
        elif number == 3:
            events.append(f"{{notetype={{speed={speed},waveLevel={wave_level},waveInstrument={wave_instrument}}}}}")
        else:
            events.append("{notetype={speed=%d}}" % speed)

    for line in seq:
        if line.startswith("speed "):
            speed = int(line.split()[1])
            notetype()
        elif line.startswith("octave "):
            source_oct = int(line.split()[1])
            octave = source_oct + 1  # TCG octave numbering is one below ChipSynth's.
            if number != 4:
                events.append(f"{{octave={octave}}}")
        elif line == "inc_octave":
            octave += 1
            if number != 4:
                events.append(f"{{octave={octave}}}")
        elif line == "dec_octave":
            octave -= 1
            if number != 4:
                events.append(f"{{octave={octave}}}")
        elif line.startswith("duty "):
            if number in (1, 2):
                events.append(f"{{duty={int(line.split()[1])}}}")
        elif line.startswith("volume_envelope "):
            a, b = [int(x.strip()) for x in line.split(None, 1)[1].split(",")]
            if number in (1, 2):
                volume, fade = a, b
                notetype()
            elif number == 3:
                wave_level = max(0, min(3, a))
                notetype()
        elif line.startswith("wave "):
            if number == 3:
                wave_instrument = int(line.split()[1])
                notetype()
        elif line.startswith("vibrato_type "):
            vibrato_type = int(line.split()[1])
        elif line.startswith("vibrato_delay "):
            vibrato_delay = int(line.split()[1])
            if number in (1, 2) and vibrato_type:
                # TCG vibrato type 8 is a compact +/-4 pitch wobble. ChipSynth's
                # sinusoidal model is not byte-identical, but this keeps the
                # intended delayed modulation without changing event timing.
                depth, rate = (4, 4) if vibrato_type == 8 else (2, 4)
                events.append(f"{{vibrato={{delay={vibrato_delay},depth={depth},rate={rate}}}}}")
        elif line.startswith("note "):
            match = re.fullmatch(r"note\s+([^,]+),\s*(\d+)", line)
            if not match:
                raise RuntimeError(f"bad note: {line}")
            events.append(f"{{note={q(NOTE[match.group(1)])},len={int(match.group(2))}}}")
        elif line.startswith("rest "):
            events.append(f"{{rest={int(line.split()[1])}}}")
        elif line.split()[0] in DRUM:
            op, length = line.split()
            events.append(f"{{drum={DRUM[op]},len={int(length)}}}")
        elif line.startswith(("stereo_panning ", "cutoff ", "echo ", "frequency_offset ")):
            # Rendering/timbre controls with no timing effect. Stereo is already
            # both channels in this score; the others have no exact ChipAsm
            # analogue in the Gen1 command set.
            pass
        elif line == "tie":
            # TCG tie suppresses retrigger only; the following note still owns
            # its full duration, so omission preserves rhythm and pitch timing.
            pass
        else:
            raise RuntimeError(f"unhandled source command in Ch{number}: {line}")
    state.update({
        "speed": speed,
        "volume": volume,
        "fade": fade,
        "wave_level": wave_level,
        "wave_instrument": wave_instrument,
        "octave": octave,
        "vibrato_type": vibrato_type,
        "vibrato_delay": vibrato_delay,
    })
    return events, state


parts = {}
loop_frames = []
for number in range(1, 5):
    pre, body = channel_parts(number)
    # Establish source speed from prelude for the independent duration audit.
    initial_speed = 7
    for line in pre:
        if line.startswith("speed "):
            initial_speed = int(line.split()[1])
    frames = duration_frames(body, initial_speed)
    loop_frames.append(frames)
    pre_events, channel_state = convert(number, pre)
    body_events, channel_state = convert(number, body, channel_state)
    parts[number] = (pre_events, body_events)

if len(set(loop_frames)) != 1:
    raise RuntimeError(f"channel loop lengths diverge: {loop_frames}")
if loop_frames[0] != 7840:
    raise RuntimeError(f"unexpected source loop length: {loop_frames[0]} frames")

waves = [
    [0x7,0x9,0xb,0xd,0xf,0xf,0xf,0xf,0xf,0xf,0xf,0xf,0xf,0xd,0xb,0x9,0x7,0x5,0x3,0x1,0,0,0,0,0,0,0,0,0,0x1,0x3,0x5],
    [0,1,1,2,2,3,3,4,4,5,5,6,6,7,7,7,8,8,9,9,0xa,0xa,0xb,0xb,0xc,0xc,0xd,0xd,0xe,0xe,0xf,0xf],
    [4,6,8,0xa,0xc,0xc,0xc,0xc,0xc,0xc,0xc,0xc,0xc,0xa,8,6,4,2,1,1,0,0,0,0,0,0,0,0,0,1,1,2],
    [7,0xa,0xd,0xf,0xf,0xf,0xd,0xa,7,4,1,0,0,0,1,4,7,0xa,0xd,0xf,0xf,0xf,0xd,0xa,7,4,1,0,0,0,1,4],
    [0xe]*16 + [0]*16,
]

out = []
out.append("-- Pokemon Trading Card Game (GBC) - Duel Theme 1")
out.append("-- Exact score/rhythm conversion from pret/poketcg dueltheme1.asm.")
out.append("-- Source commit: 7a75fe810e91dda43538b249c70ee5da14e38686")
out.append("-- The source engine times every event as speed * length VBlanks; tempo=256")
out.append("-- maps that exactly to Gen1Recomp ChipSynth's 60 Hz frame clock.")
out.append('local ChipAsm=require("src.audio.ChipAsm")')
out.append("return ChipAsm.song({")
out.append("  tempo=256,")
out.append("  waves={")
for wave in waves:
    out.append("    {" + ",".join(str(x) for x in wave) + "},")
out.append("  },")
out.append("  drums={")
out.append("    [1]={{len=2,volume=13,fade=-2,parameter=0x61}}, -- bass")
out.append("    [2]={{len=2,volume=10,fade=-2,parameter=0x16}}, -- snare1")
out.append("    [3]={{len=2,volume=9, fade=-2,parameter=0x05}}, -- snare2")
out.append("    [4]={{len=2,volume=11,fade=-2,parameter=0x02}}, -- snare3")
out.append("    [5]={{len=3,volume=8, fade=-1,parameter=0x04}}, -- snare4")
out.append("    [6]={{len=3,volume=12,fade=-1,parameter=0x05}}, -- snare5")
out.append("  },")
out.append("  channels={")
for number in range(1,5):
    pre, body = parts[number]
    out.append(f"    {{hw={number},program={{")
    for event in pre:
        out.append("      " + event + ",")
    out.append(f'      {{label="main_{number}"}},')
    for event in body:
        out.append("      " + event + ",")
    out.append(f'      {{loop={{count=0,to="main_{number}"}}}},')
    out.append("    }},")
out.append("  },")
out.append("})")
OUT.write_text("\n".join(out) + "\n", encoding="utf-8")
print(f"wrote {OUT}")
print(f"source loop: {loop_frames[0]} frames = {loop_frames[0]/60:.6f}s on every channel")
print("events:", {n: len(parts[n][0]) + len(parts[n][1]) for n in parts})
