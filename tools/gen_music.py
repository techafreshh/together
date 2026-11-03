#!/usr/bin/env python3
"""Synthesize the single CC0 looping music track for `assets/music/loop.ogg`.

Stdlib only (`wave`, `struct`, `math`, `random`, `subprocess` for the
`ffmpeg` encode step): no downloads, no network, so CI stays offline. The
track is a cheerful 120 BPM chiptune loop, 40 s (20 two-second bars, margin
over the 30 s floor): I-V-vi-IV pad in C plus a root bass, a pentatonic
arp, a kick on every beat and a noise tick on every offbeat.

Every note carries a short raised-cosine attack/release envelope that starts
and ends at silence, so bar boundaries and the loop seam are click-free by
construction (the final bar ends exactly at the 40 s mark and the first
note attacks from zero). The output is CC0 by construction (pure synthesis,
no sampled sources), the same argument `tools/gen_sfx.py` already uses:
released into the public domain; no attribution required.

Usage: python3 tools/gen_music.py  (writes assets/music/loop.ogg via a wav
intermediate; needs `ffmpeg` on PATH for the Ogg encode only)
"""

import math
import os
import random
import struct
import subprocess
import wave

SAMPLE_RATE = 22050
BPM = 120.0
BEAT = 60.0 / BPM  # 0.5 s
BAR = 4 * BEAT  # 2.0 s
BARS = 20
DURATION = BARS * BAR  # 40.0 s

# I-V-vi-IV in C, one chord per bar: (bass root, pad triad).
PROGRESSION = [
    (65.41, (130.81, 164.81, 196.00)),  # C2 + C3 E3 G3
    (98.00, (146.83, 196.00, 246.94)),  # G2 + D3 G3 B3
    (110.00, (130.81, 164.81, 220.00)),  # A2 + C3 E3 A3
    (87.31, (146.83, 174.61, 220.00)),  # F2 + D3 F3 A3
]

# C-major pentatonic ladder for the 8th-note arp (two octaves).
ARP_NOTES = (261.63, 293.66, 329.63, 392.00, 440.00, 523.25, 587.33, 659.25)

HAT_INTERVAL = BEAT / 2.0  # 8th-note offbeat ticks


def _adsr_edge(n: int, total: int, edge: int) -> float:
    """Raised-cosine attack/release over `edge` samples; 1.0 in between."""
    if total <= 1:
        return 1.0
    edge = max(1, min(edge, total // 2))
    if n < edge:
        return 0.5 - 0.5 * math.cos(math.pi * n / edge)
    if n >= total - edge:
        return 0.5 - 0.5 * math.cos(math.pi * (total - 1 - n) / edge)
    return 1.0


def _add_tone(mix: list, start: float, dur: float, freq: float, amp: float,
              edge_ms: float = 5.0, harmonic: float = 0.0) -> None:
    """Add a sine note (plus optional 2nd harmonic) with click-free edges."""
    total = int(dur * SAMPLE_RATE)
    edge = int(SAMPLE_RATE * edge_ms / 1000.0)
    base = int(start * SAMPLE_RATE)
    for n in range(total):
        idx = base + n
        if 0 <= idx < len(mix):
            phase = 2.0 * math.pi * freq * n / SAMPLE_RATE
            env = _adsr_edge(n, total, edge)
            sample = amp * math.sin(phase)
            if harmonic > 0.0:
                sample += harmonic * amp * math.sin(2.0 * phase)
            mix[idx] += sample * env


def _add_kick(mix: list, start: float, amp: float = 0.35) -> None:
    """Pitched-down sine thump (120 -> 50 Hz) on the beat."""
    dur = 0.18
    total = int(dur * SAMPLE_RATE)
    base = int(start * SAMPLE_RATE)
    phase = 0.0
    for n in range(total):
        idx = base + n
        if 0 <= idx < len(mix):
            frac = n / max(1, total - 1)
            freq = 120.0 + (50.0 - 120.0) * frac
            phase += 2.0 * math.pi * freq / SAMPLE_RATE
            env = math.exp(-n / (SAMPLE_RATE * 0.05))
            mix[idx] += amp * math.sin(phase) * env


def _add_hat(mix: list, start: float, rng: random.Random, amp: float = 0.06) -> None:
    """Short seeded noise tick on the offbeat."""
    dur = 0.03
    total = int(dur * SAMPLE_RATE)
    edge = max(1, int(SAMPLE_RATE * 0.002))
    base = int(start * SAMPLE_RATE)
    for n in range(total):
        idx = base + n
        if 0 <= idx < len(mix):
            mix[idx] += amp * rng.uniform(-1.0, 1.0) * _adsr_edge(n, total, edge)


def make_music() -> list:
    """Return float samples in [-1, 1] for the full 40 s loop."""
    total = int(DURATION * SAMPLE_RATE)
    mix = [0.0] * total
    rng = random.Random(20261103)
    for bar in range(BARS):
        t0 = bar * BAR
        bass_root, triad = PROGRESSION[bar % len(PROGRESSION)]
        # Pad: whole-bar triad swell (slow 100 ms edges).
        for freq in triad:
            _add_tone(mix, t0, BAR, freq, 0.11, edge_ms=100.0)
        # Bass: root on every quarter-note beat.
        for beat in range(4):
            _add_tone(mix, t0 + beat * BEAT, BEAT * 0.95, bass_root, 0.26,
                       harmonic=0.25)
        # Arp: pentatonic 8ths climbing one rung per bar rotation.
        step = bar % len(ARP_NOTES)
        for eighth in range(8):
            note = ARP_NOTES[(step + eighth) % len(ARP_NOTES)]
            _add_tone(mix, t0 + eighth * HAT_INTERVAL, HAT_INTERVAL * 0.9,
                       note, 0.15)
        # Kick on beats, ticks on offbeats.
        for beat in range(4):
            _add_kick(mix, t0 + beat * BEAT)
        for eighth in range(8):
            _add_hat(mix, t0 + (eighth + 0.5) * HAT_INTERVAL, rng)
    peak = max(1e-6, max(abs(s) for s in mix))
    gain = 0.89 / peak
    out = [max(-1.0, min(1.0, s * gain)) for s in mix]
    # Global 8 ms edge fade pins the loop seam exactly to silence so the
    # Ogg encoder sees no step between the last and first sample.
    edge = max(1, int(SAMPLE_RATE * 0.008))
    for n in range(len(out)):
        out[n] *= _adsr_edge(n, len(out), edge)
    return out


def write_wav(path: str, samples: list) -> None:
    """Write mono 16-bit PCM samples to path."""
    frames = b"".join(
        struct.pack("<h", max(-32768, min(32767, int(s * 32767)))) for s in samples
    )
    with wave.open(path, "wb") as wav:
        wav.setnchannels(1)
        wav.setsampwidth(2)
        wav.setframerate(SAMPLE_RATE)
        wav.writeframes(frames)


def main() -> None:
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    out_dir = os.path.join(root, "assets", "music")
    os.makedirs(out_dir, exist_ok=True)
    wav_path = os.path.join(out_dir, "loop.wav")
    ogg_path = os.path.join(out_dir, "loop.ogg")
    samples = make_music()
    print("music: %.1f s @ %d Hz (%d samples)" % (DURATION, SAMPLE_RATE, len(samples)))
    seam = abs(samples[-1] - samples[0])
    print("music: loop-seam discontinuity %.6f (envelope-pinned to ~0)" % seam)
    write_wav(wav_path, samples)
    subprocess.run(
        ["ffmpeg", "-y", "-v", "error", "-i", wav_path,
         "-ac", "1", "-ar", "22050", "-b:a", "48k", ogg_path],
        check=True,
    )
    os.remove(wav_path)
    size = os.path.getsize(ogg_path)
    print("wrote %s (%d bytes, %.1f s)" % (ogg_path, size, DURATION))


if __name__ == "__main__":
    main()
