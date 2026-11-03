#!/usr/bin/env python3
"""Synthesize the 8 CC0 placeholder SFX for `assets/sfx/`.

Stdlib only (`wave`, `struct`, `math`, `random`): no downloads, no network,
so CI stays offline. Every effect is a short 44.1 kHz 16-bit mono sine/noise
blip (0.15-0.40 s) with a 5 ms fade-in and an exponential decay envelope so
loops never click.

The output is CC0 by construction (pure synthesis, no sampled sources):
released into the public domain; no attribution required.

Usage: python3 tools/gen_sfx.py  (writes assets/sfx/<name>.wav in repo root)
"""

import math
import os
import random
import struct
import wave

SAMPLE_RATE = 44100

# Effect names in the order the Sfx bus documents them.
EFFECTS = ("jump", "flop", "grab", "throw", "button", "checkpoint", "goal", "coin")


def _envelope(n: int, total: int, decay: float) -> float:
    """5 ms fade-in times an exponential decay; ends near silence."""
    fade_len = max(1, int(SAMPLE_RATE * 0.005))
    fade = min(1.0, n / fade_len)
    t = n / SAMPLE_RATE
    return fade * math.exp(-t * decay)


def _sweep(f0: float, f1: float, dur: float, decay: float, amp: float) -> list:
    """Sine gliding linearly from f0 to f1 Hz."""
    total = int(SAMPLE_RATE * dur)
    out = []
    phase = 0.0
    for n in range(total):
        frac = n / max(1, total - 1)
        freq = f0 + (f1 - f0) * frac
        phase += 2.0 * math.pi * freq / SAMPLE_RATE
        out.append(amp * math.sin(phase) * _envelope(n, total, decay))
    return out


def _tone_seq(notes: list, decay: float, amp: float) -> list:
    """Concatenated fixed-pitch sine notes; each entry is (freq, dur)."""
    out = []
    for freq, dur in notes:
        total = int(SAMPLE_RATE * dur)
        for n in range(total):
            phase = 2.0 * math.pi * freq * n / SAMPLE_RATE
            out.append(amp * math.sin(phase) * _envelope(n, total, decay))
    return out


def _flop() -> list:
    """Comedy splat: seeded noise burst over a low sine thump."""
    rng = random.Random(1234)
    dur = 0.40
    total = int(SAMPLE_RATE * dur)
    out = []
    phase = 0.0
    for n in range(total):
        phase += 2.0 * math.pi * 90.0 / SAMPLE_RATE
        noise = rng.uniform(-1.0, 1.0)
        splat = 0.35 * noise * _envelope(n, total, 9.0)
        thump = 0.30 * math.sin(phase) * _envelope(n, total, 11.0)
        out.append(splat + thump)
    return out


def make_effect(name: str) -> list:
    """Return float samples in [-1, 1] for the named effect."""
    if name == "jump":
        return _sweep(300.0, 750.0, 0.25, 6.0, 0.5)
    if name == "flop":
        return _flop()
    if name == "grab":
        return _sweep(1200.0, 1100.0, 0.15, 20.0, 0.4)
    if name == "throw":
        return _sweep(900.0, 300.0, 0.20, 8.0, 0.5)
    if name == "button":
        return _tone_seq([(600.0, 0.10), (900.0, 0.10)], 8.0, 0.5)
    if name == "checkpoint":
        return _tone_seq([(520.0, 0.15), (780.0, 0.15)], 6.0, 0.5)
    if name == "goal":
        return _tone_seq([(523.25, 0.13), (659.25, 0.13), (783.99, 0.14)], 4.0, 0.5)
    if name == "coin":
        return _tone_seq([(987.77, 0.10), (1318.5, 0.20)], 6.0, 0.4)
    raise KeyError("unknown effect: %s" % name)


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
    out_dir = os.path.join(root, "assets", "sfx")
    os.makedirs(out_dir, exist_ok=True)
    for name in EFFECTS:
        path = os.path.join(out_dir, name + ".wav")
        write_wav(path, make_effect(name))
        print("wrote %s" % path)


if __name__ == "__main__":
    main()
