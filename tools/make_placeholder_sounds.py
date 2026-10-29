"""Synthesizes placeholder sound effects, ambience and music, so the game
has something to play before real recordings exist. Writes 16-bit mono WAVs
into audio/, named the way Sound (scripts/sound.gd) asks for them.

Run from the project root: python3 tools/make_placeholder_sounds.py

Loops (name ends in _loop) are cross-faded at the seam so they repeat cleanly.
Impacts come in a few variations each (name_1.wav, name_2.wav, ...), which
Sound picks between at random so repeated hits don't sound canned.
"""
import wave
from pathlib import Path

import numpy as np

RATE = 22050
rng = np.random.default_rng(1985)


def seconds(n):
    return int(n * RATE)


def t_axis(duration):
    return np.arange(seconds(duration)) / RATE


def noise(duration):
    return rng.uniform(-1.0, 1.0, seconds(duration))


def tone(freq, duration, shape="sine"):
    """`freq` is a number or an array of per-sample frequencies (for sweeps)."""
    n = seconds(duration)
    freq = np.broadcast_to(np.asarray(freq, dtype=float), (n,))
    phase = np.cumsum(2.0 * np.pi * freq / RATE)
    if shape == "sine":
        return np.sin(phase)
    if shape == "square":
        return np.sign(np.sin(phase))
    if shape == "saw":
        return 2.0 * ((phase / (2.0 * np.pi)) % 1.0) - 1.0
    if shape == "triangle":
        return 2.0 * np.abs(2.0 * ((phase / (2.0 * np.pi)) % 1.0) - 1.0) - 1.0
    raise ValueError(shape)


def sweep(start, end, duration):
    return np.geomspace(start, end, seconds(duration))


def decay(duration, rate):
    """Exponential fade out: `rate` is how many times it falls by e."""
    return np.exp(-rate * t_axis(duration) / duration)


def attack_decay(duration, attack, rate):
    t = t_axis(duration)
    env = np.minimum(t / max(attack, 1e-4), 1.0)
    return env * np.exp(-rate * np.maximum(t - attack, 0.0) / duration)


def lowpass(x, cutoff):
    """One-pole low-pass filter."""
    a = np.exp(-2.0 * np.pi * cutoff / RATE)
    out = np.empty_like(x)
    y = 0.0
    for i, v in enumerate(x):
        y = (1.0 - a) * v + a * y
        out[i] = y
    return out


def highpass(x, cutoff):
    return x - lowpass(x, cutoff)


def bandpass(x, low, high):
    return lowpass(highpass(x, low), high)


def pad(x, duration):
    out = np.zeros(seconds(duration))
    out[: min(len(x), len(out))] = x[: len(out)]
    return out


def mix(*parts):
    n = max(len(p) for p in parts)
    return sum(pad(p, n / RATE) for p in parts)


def at(x, start, total):
    """`x` placed `start` seconds into a silence `total` seconds long."""
    out = np.zeros(seconds(total))
    i = seconds(start)
    end = min(i + len(x), len(out))
    out[i:end] += x[: end - i]
    return out


def loop_seam(x, fade=0.25):
    """Cross-fades the end into the start so the sound loops without a click."""
    n = seconds(fade)
    head, body, tail = x[:n], x[n:-n], x[-n:]
    ramp = np.linspace(0.0, 1.0, n)
    return np.concatenate([tail * (1.0 - ramp) + head * ramp, body])


def drive(x, amount):
    """Soft-clips for weight and punch."""
    return np.tanh(x * amount) / np.tanh(amount)


def normalize(x, peak=0.85):
    top = np.max(np.abs(x))
    return x * (peak / top) if top > 0 else x


def write(path, x):
    data = (np.clip(normalize(x), -1.0, 1.0) * 32767).astype("<i2")
    with wave.open(str(path), "wb") as f:
        f.setnchannels(1)
        f.setsampwidth(2)
        f.setframerate(RATE)
        f.writeframes(data.tobytes())


# --- Combat -------------------------------------------------------------

def _thump(low, high, duration, rate=7.0):
    return tone(sweep(high, low, duration), duration) * decay(duration, rate)


def _smack(duration=0.035, low=900, high=5500):
    return bandpass(noise(duration), low, high) * decay(duration, 6)


def _crunch(duration=0.09, cutoff=2500):
    return lowpass(noise(duration), cutoff) * attack_decay(duration, 0.004, 8)


def punch(v=1.0):
    """Fists and brass knuckles on a body: deep thump, sharp smack, a bit of crunch."""
    return drive(mix(_thump(50 * v, 150 * v, 0.2), _smack() * 1.3, _crunch(0.07, 1800 * v) * 0.6), 2.5)


def bat_hit(v=1.0):
    """Wood on a body: a heavier thump and a hollow knock."""
    knock = sum(tone(f * v, 0.14) * decay(0.14, r) * a for f, r, a in [(430, 11, 1.0), (690, 14, 0.5), (1020, 18, 0.25)])
    crack = highpass(noise(0.02), 3000) * decay(0.02, 5)
    return drive(mix(_thump(42 * v, 125 * v, 0.24, 6), knock * 0.8, _smack(0.03) * 1.1, crack * 0.7, _crunch(0.1) * 0.5), 2.2)


def knife_hit(v=1.0):
    """A slash: a quick swish, and a wet squelch with a small thump under it."""
    swish = highpass(noise(0.11), 2200 * v) * attack_decay(0.11, 0.01, 6)
    squelch = bandpass(noise(0.12), 250, 1400) * attack_decay(0.12, 0.02, 5)
    return drive(mix(swish, at(squelch * 0.9, 0.02, 0.15), _thump(60 * v, 140 * v, 0.12) * 0.6), 1.8)


def bullet_hit(v=1.0):
    """A bullet striking a body: a hard thwack."""
    snap = highpass(noise(0.015), 2500) * decay(0.015, 4)
    return drive(mix(snap * 1.2, _smack(0.05, 600, 4500) * 1.4, _thump(48 * v, 170 * v, 0.22, 6) * 1.3, _crunch(0.09) * 0.7), 3.5)


def car_thump(v=1.0):
    """Someone hit by a car: a heavy body slam with a metal clunk."""
    clunk = sum(tone(f * v, 0.3) * decay(0.3, r) * a for f, r, a in [(160, 6, 1.0), (255, 8, 0.6), (410, 10, 0.4)])
    return drive(mix(_thump(35 * v, 110 * v, 0.35, 5) * 1.3, _smack(0.05, 500, 4000) * 1.2, clunk * 0.6, _crunch(0.15, 1500) * 0.8), 2.5)


def body_fall(v=1.0):
    """Someone hitting the ground."""
    cloth = lowpass(noise(0.18), 900) * attack_decay(0.18, 0.01, 6)
    return drive(mix(_thump(38 * v, 85 * v, 0.28, 6) * 1.2, cloth * 0.7), 2.0)


def car_hit(v=1.0):
    """A weapon on a car: a thud, the panel ringing, and a rattle."""
    t = 0.6
    ring = sum(tone(f * v, t) * decay(t, r) * a for f, r, a in [(185, 6, 1.0), (297, 7, 0.8), (466, 9, 0.6), (748, 11, 0.4), (1210, 14, 0.25)])
    rattle = bandpass(noise(0.12), 1800, 6000) * decay(0.12, 6)
    return drive(mix(_thump(45 * v, 120 * v, 0.2), ring * 0.7, rattle * 0.5, _smack(0.03) * 0.8), 2.2)


def bullet_car(v=1.0):
    """A bullet punching into a car: a sharp metal tink."""
    t = 0.3
    tink = sum(tone(f * v, t) * decay(t, r) * a for f, r, a in [(2350, 10, 1.0), (3720, 13, 0.6), (5100, 16, 0.3)])
    return mix(tink * 0.8, highpass(noise(0.012), 3000) * decay(0.012, 4), _thump(80 * v, 200 * v, 0.06, 8) * 0.5)


def swing():
    whoosh = bandpass(noise(0.2), 400, 1600)
    return whoosh * np.sin(np.linspace(0.0, np.pi, len(whoosh))) ** 2


def block():
    ring = sum(tone(f, 0.2) * decay(0.2, r) for f, r in [(820, 9), (1290, 11), (1930, 14)])
    return mix(ring, punch() * 0.4)


def gunshot():
    crack = lowpass(noise(0.3), 5000) * decay(0.3, 9)
    boom = tone(sweep(90, 40, 0.3), 0.3) * decay(0.3, 6)
    return mix(crack, boom * 0.9)


def tec9_shot():
    crack = lowpass(noise(0.12), 6500) * decay(0.12, 8)
    thump = tone(sweep(140, 70, 0.12), 0.12) * decay(0.12, 6)
    return mix(crack, thump * 0.5)


def ricochet():
    zing = tone(sweep(3200, 1100, 0.22), 0.22) * decay(0.22, 4)
    return mix(zing * 0.7, highpass(noise(0.02), 3000) * 0.5)


def throw():
    return swing() * 0.8


def glass():
    t = 0.6
    shards = np.zeros(seconds(t))
    for _ in range(14):
        ping = tone(rng.uniform(2200, 6500), 0.25) * decay(0.25, rng.uniform(8, 16))
        shards += at(ping, rng.uniform(0.0, 0.18), t) * rng.uniform(0.3, 0.8)
    crash = highpass(noise(t), 1500) * decay(t, 10)
    return mix(shards, crash * 0.8)


def explosion():
    t = 1.8
    rumble = lowpass(noise(t), 400) * attack_decay(t, 0.01, 4)
    crack = lowpass(noise(0.25), 3000) * decay(0.25, 6)
    sub = tone(sweep(60, 28, t), t) * decay(t, 3)
    return mix(rumble * 1.4, crack * 0.6, sub * 0.9)


def fire_loop():
    t = 3.0
    roar = lowpass(noise(t), 300) * 0.5
    crackle = np.zeros(seconds(t))
    for _ in range(60):
        pop = highpass(noise(0.015), 1200) * decay(0.015, 5)
        crackle += at(pop, rng.uniform(0.0, t - 0.02), t) * rng.uniform(0.3, 1.0)
    return loop_seam(mix(roar, crackle))


# --- Cars ---------------------------------------------------------------

def engine_loop():
    t = 1.0
    wobble = 1.0 + 0.03 * np.sin(2 * np.pi * 7 * t_axis(t))
    hum = tone(55 * wobble, t, "saw") + 0.5 * tone(110 * wobble, t, "saw")
    return lowpass(hum, 600) + lowpass(noise(t), 200) * 0.3


def crash():
    t = 0.7
    bang = lowpass(noise(t), 2500) * decay(t, 8)
    metal = sum(tone(f, t) * decay(t, r) for f, r in [(420, 6), (690, 8), (1150, 10)])
    return mix(bang, metal * 0.4, punch() * 0.8)


def clang():
    t = 1.2
    return sum(tone(f, t) * decay(t, r) * a for f, r, a in [(310, 4, 1.0), (472, 5, 0.7), (815, 7, 0.5), (1340, 9, 0.3)])


def horn():
    t = 0.45
    blare = tone(410, t, "square") + tone(515, t, "square")
    return lowpass(blare, 2200) * attack_decay(t, 0.02, 1.5)


def siren_loop():
    t = 2.0
    # The wail: up and back down, smoothly.
    rise = 650 + 600 * np.sin(np.linspace(0.0, np.pi, seconds(t))) ** 2
    return lowpass(tone(rise, t, "triangle"), 3000)


def rollup():
    t = 0.7
    rattle = bandpass(noise(t), 300, 2500) * (0.6 + 0.4 * np.sign(np.sin(2 * np.pi * 22 * t_axis(t))))
    return rattle * attack_decay(t, 0.05, 2)


# --- The world ----------------------------------------------------------

def rain_loop():
    t = 4.0
    hiss = bandpass(noise(t), 800, 6000) * 0.6
    patter = np.zeros(seconds(t))
    for _ in range(300):
        drop = highpass(noise(0.01), 2000) * decay(0.01, 5)
        patter += at(drop, rng.uniform(0.0, t - 0.02), t) * rng.uniform(0.1, 0.6)
    return loop_seam(mix(hiss, patter), 0.5)


def city_loop():
    t = 8.0
    rumble = lowpass(noise(t), 120)
    # Distant traffic swelling now and then.
    swell = 0.6 + 0.4 * np.sin(2 * np.pi * t_axis(t) / t * 3) ** 2
    hum = lowpass(noise(t), 500) * 0.3 * swell
    return loop_seam(mix(rumble, hum), 1.0)


def door():
    t = 0.5
    creak = tone(180 + 60 * np.sin(2 * np.pi * 9 * t_axis(t)), t, "saw")
    creak = bandpass(creak, 200, 1500) * attack_decay(t, 0.05, 3) * 0.6
    return mix(creak, at(punch() * 0.7, 0.35, t))


def cash():
    t = 0.6
    ching = sum(at(tone(f, 0.4) * decay(0.4, 6), s, t) for f, s in [(1975, 0.0), (2637, 0.09)])
    rattle = highpass(noise(0.12), 3000) * decay(0.12, 4) * 0.4
    return mix(ching, rattle)


def pickup():
    return tone(sweep(600, 1300, 0.12), 0.12, "square") * attack_decay(0.12, 0.005, 3) * 0.5


def click():
    return highpass(noise(0.025), 2000) * decay(0.025, 6) * 0.6


def eat():
    t = 0.6
    out = np.zeros(seconds(t))
    for s in (0.0, 0.2, 0.4):
        out += at(bandpass(noise(0.09), 500, 3500) * decay(0.09, 5), s, t)
    return out


def sniff():
    t = 0.45
    air = bandpass(noise(t), 1500, 6000)
    return air * np.linspace(0.2, 1.0, len(air)) * attack_decay(t, 0.3, 2)


def war_start():
    t = 0.9
    notes = [(220, 0.0), (277, 0.22), (330, 0.44)]
    return sum(at(lowpass(tone(f, 0.4, "saw"), 2500) * decay(0.4, 3), s, t) for f, s in notes)


def victory():
    t = 1.3
    notes = [(523, 0.0), (659, 0.13), (784, 0.26), (1047, 0.42)]
    out = sum(at(lowpass(tone(f, 0.8, "square"), 3000) * decay(0.8, 3), s, t) for f, s in notes)
    return out


# --- Music --------------------------------------------------------------

def radio_loop():
    """Four bars of an 80s drum machine with a bassline, at 92 BPM."""
    beat = 60.0 / 92.0
    bars = 4
    t = beat * 4 * bars
    out = np.zeros(seconds(t))

    def kick():
        return tone(sweep(120, 40, 0.25), 0.25) * decay(0.25, 7)

    def snare():
        return mix(bandpass(noise(0.2), 900, 6000) * decay(0.2, 8), tone(190, 0.1) * decay(0.1, 8) * 0.5)

    def hat():
        return highpass(noise(0.05), 6000) * decay(0.05, 9) * 0.35

    bass_notes = [41.2, 41.2, 49.0, 55.0]  # E1, E1, G1, A1, one per bar
    for bar in range(bars):
        start = bar * 4 * beat
        for step in range(8):
            out += at(hat(), start + step * beat / 2, t)
        for k in (0.0, 1.5, 2.0):
            out += at(kick(), start + k * beat, t)
        for s in (1.0, 3.0):
            out += at(snare(), start + s * beat, t)
        note = bass_notes[bar]
        for b in (0.0, 0.75, 1.5, 2.5, 3.0):
            pluck = lowpass(tone(note * 2, beat * 0.45, "saw"), 700) * decay(beat * 0.45, 4)
            out += at(pluck * 0.9, start + b * beat, t)
        # A synth stab on the offbeat.
        stab = sum(tone(note * m, beat * 0.3, "square") for m in (8, 10, 12))
        out += at(lowpass(stab, 2500) * decay(beat * 0.3, 6) * 0.12, start + 2.5 * beat, t)
    return out


# Impacts, made in a few variations each, a little higher or lower.
VARIED = {
    "punch": punch, "bat_hit": bat_hit, "knife_hit": knife_hit, "bullet_hit": bullet_hit,
    "car_thump": car_thump, "body_fall": body_fall, "car_hit": car_hit, "bullet_car": bullet_car,
}
VARIATIONS = (0.9, 1.0, 1.12)

SOUNDS = {
    "swing": swing,
    "block": block, "gunshot": gunshot, "tec9_shot": tec9_shot, "ricochet": ricochet,
    "throw": throw, "glass": glass, "explosion": explosion, "fire_loop": fire_loop,
    "engine_loop": engine_loop, "crash": crash, "clang": clang, "horn": horn,
    "siren_loop": siren_loop, "rollup": rollup, "rain_loop": rain_loop, "city_loop": city_loop,
    "door": door, "cash": cash, "pickup": pickup, "click": click, "eat": eat,
    "sniff": sniff, "war_start": war_start, "victory": victory, "radio_loop": radio_loop,
}


def main():
    out = Path(__file__).resolve().parent.parent / "audio"
    out.mkdir(exist_ok=True)
    for name, make in SOUNDS.items():
        write(out / f"{name}.wav", make())
    for name, make in VARIED.items():
        # No single-file version left behind to shadow the variations.
        (out / f"{name}.wav").unlink(missing_ok=True)
        (out / f"{name}.wav.import").unlink(missing_ok=True)
        for i, v in enumerate(VARIATIONS, 1):
            write(out / f"{name}_{i}.wav", make(v))
    print(f"Wrote {len(SOUNDS)} sounds and {len(VARIED)} impacts x {len(VARIATIONS)} to {out}")


if __name__ == "__main__":
    main()
