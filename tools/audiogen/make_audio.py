"""Synthesise every Hollowmoth sound from scratch (no samples, no licences).

    python make_audio.py <out folder>      -> <out>/sfx/*.wav, <out>/music/*.ogg, <out>/amb/*.ogg

Everything is built from sines, noise, plucked strings and filters, then
placed in a convolution "room" so it sits in the same dark space.
"""
import os, sys, subprocess
import numpy as np
from scipy import signal
from scipy.io import wavfile

SR = 44100
OUT = sys.argv[1] if len(sys.argv) > 1 else "out"
rng = np.random.default_rng(1337)
for d in ("sfx", "music", "amb"):
    os.makedirs(os.path.join(OUT, d), exist_ok=True)


# ----------------------------------------------------------------- building blocks
def t_(dur):
    return np.arange(int(dur * SR)) / SR


def noise(dur):
    return rng.standard_normal(int(dur * SR))


def filt(x, kind, f, order=2):
    if kind == "bp":
        b, a = signal.butter(order, [max(20, f[0]) / (SR / 2), min(f[1], SR / 2 - 100) / (SR / 2)], "band")
    else:
        b, a = signal.butter(order, min(f, SR / 2 - 100) / (SR / 2), kind)
    return signal.lfilter(b, a, x)


def env_exp(dur, decay, attack=0.002):
    t = t_(dur)
    e = np.exp(-t / decay)
    a = np.clip(t / max(attack, 1e-4), 0, 1)
    return e * a


def env_adsr(dur, a, d, s, r):
    t = t_(dur)
    e = np.interp(t, [0, a, a + d, max(a + d, dur - r), dur], [0, 1, s, s, 0])
    return e


def sine(freq, dur, phase=0.0):
    t = t_(dur)
    if callable(freq):
        f = freq(t)
        return np.sin(2 * np.pi * np.cumsum(f) / SR + phase)
    return np.sin(2 * np.pi * freq * t + phase)


def saw(freq, dur):
    t = t_(dur)
    f = freq(t) if callable(freq) else np.full_like(t, freq)
    ph = np.cumsum(f) / SR
    return 2 * (ph - np.floor(ph + 0.5))


def pluck(freq, dur, damp=0.996):
    """Karplus-Strong string."""
    n = int(dur * SR)
    p = int(SR / freq)
    buf = rng.uniform(-1, 1, p)
    out = np.zeros(n)
    for i in range(n):
        out[i] = buf[i % p]
        buf[i % p] = damp * 0.5 * (buf[i % p] + buf[(i + 1) % p])
    return out


def bell(freq, dur, decay=1.2, bright=1.0):
    parts = [(1.0, 1.0), (2.0, 0.6), (2.76, 0.45 * bright), (5.4, 0.25 * bright), (8.93, 0.12 * bright)]
    x = np.zeros(int(dur * SR))
    for mult, amp in parts:
        x += amp * sine(freq * mult, dur) * env_exp(dur, decay / (mult ** 0.5), 0.001)
    return x


def formant(x, vowel="a"):
    F = {"a": (800, 1150, 2900), "o": (450, 800, 2830), "u": (325, 700, 2530), "e": (400, 1700, 2600)}[vowel]
    y = np.zeros_like(x)
    for i, f in enumerate(F):
        y += filt(x, "bp", (f * 0.85, f * 1.15)) * (1.0, 0.5, 0.25)[i]
    return y


def ir(length, decay, bright=4000, seed=0):
    r = np.random.default_rng(seed)
    n = int(length * SR)
    x = r.standard_normal(n) * np.exp(-np.arange(n) / SR / decay)
    x = filt(x, "low", bright)
    x[0] = 1.0
    return x / np.abs(x).sum() * 6.0


ROOM = ir(0.6, 0.12, 5000, 1)
HALL_L, HALL_R = ir(3.5, 0.9, 3500, 2), ir(3.5, 0.9, 3500, 3)


def verb(x, wet=0.25, room=None):
    room = ROOM if room is None else room
    y = signal.fftconvolve(x, room)[: len(x) + len(room) // 2]
    out = np.zeros(len(y))
    out[: len(x)] += x * (1 - wet)
    out += y * wet
    return out


def mix(*parts):
    n = max(len(p) for p in parts)
    out = np.zeros(n)
    for p in parts:
        out[: len(p)] += p
    return out


def at(x, delay):
    return np.concatenate([np.zeros(int(delay * SR)), x])


def norm(x, peak=0.85):
    m = np.abs(x).max()
    return x / m * peak if m > 0 else x


def fade(x, fin=0.003, fout=0.02):
    n_in, n_out = int(fin * SR), int(fout * SR)
    x = x.copy()
    if n_in:
        x[:n_in] *= np.linspace(0, 1, n_in)
    if n_out:
        x[-n_out:] *= np.linspace(1, 0, n_out)
    return x


def save_wav(name, x, peak=0.85):
    x = fade(norm(x, peak))
    wavfile.write(os.path.join(OUT, "sfx", name + ".wav"), SR, (x * 32767).astype(np.int16))


def save_ogg(folder, name, x, stereo=False, q=5):
    path_wav = os.path.join(OUT, folder, name + ".tmp.wav")
    data = x if stereo else x
    data = np.clip(data, -1, 1)
    wavfile.write(path_wav, SR, (data * 32767).astype(np.int16))
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", path_wav, "-c:a", "libvorbis", "-q:a", str(q),
                    os.path.join(OUT, folder, name + ".ogg")], check=True)
    os.remove(path_wav)


def loopable(x, tail):
    """Wrap the reverb tail of a rendered loop back onto its start, so it loops seamlessly."""
    n = len(x) - tail
    y = x[:n].copy()
    y[:tail] += x[n:]
    return y


# ----------------------------------------------------------------- combat
for i in range(3):
    d = 0.2 + 0.03 * i
    sweep = lambda t, d=d, i=i: 500 + 2600 * (t / d) ** 1.4 * (1 - 0.15 * i)
    n = noise(d)
    x = np.zeros_like(n)
    seg = 64
    cs = sweep(t_(d))
    for k in range(0, len(n), seg):     # moving band-pass: the "whoosh"
        c = cs[k]
        x[k:k + seg] = filt(n[max(0, k - 512):k + seg], "bp", (c * 0.6, c * 1.4))[-len(n[k:k + seg]):]
    x *= np.sin(np.pi * np.clip(t_(d) / d, 0, 1)) ** 1.5
    save_wav(f"swing_{i}", verb(x, 0.15), 0.55)
heavy = noise(0.38)
heavy = filt(heavy, "bp", (180, 1400)) * np.sin(np.pi * t_(0.38) / 0.38) ** 2
save_wav("swing_heavy", verb(heavy, 0.2), 0.7)

for i in range(3):
    d = 0.35
    f0 = 85 + 12 * i
    thud = sine(lambda t, f0=f0: f0 * (1 + 1.5 * np.exp(-t / 0.02)), d) * env_exp(d, 0.08)
    crack = filt(noise(d), "low", 1800) * env_exp(d, 0.025)
    crunch = filt(noise(d), "bp", (2000, 4500)) * env_exp(d, 0.012) * 0.6
    wet = filt(noise(d), "bp", (300, 900)) * env_exp(d, 0.05) * 0.5
    save_wav(f"hit_{i}", verb(mix(thud, crack * 0.7, crunch, wet), 0.2))
d = 0.9
crit = mix(
    sine(lambda t: 55 * (1 + 2 * np.exp(-t / 0.03)), d) * env_exp(d, 0.25) * 1.2,
    filt(noise(d), "low", 2200) * env_exp(d, 0.05),
    filt(noise(d), "bp", (2500, 6000)) * env_exp(d, 0.02) * 0.7,
    bell(720, d, 0.35, 0.6) * 0.18,
)
save_wav("hit_crit", verb(crit, 0.3), 0.95)

d = 1.4
parry = mix(bell(520, d, 0.45, 1.4), filt(noise(d), "high", 3000) * env_exp(d, 0.01) * 1.5, bell(1310, d, 0.25) * 0.3)
save_wav("parry", verb(parry, 0.35), 0.8)
d = 0.4
block = mix(sine(lambda t: 160 * (1 + 0.4 * np.exp(-t / 0.01)), d) * env_exp(d, 0.06), bell(380, d, 0.08, 0.5) * 0.5,
            filt(noise(d), "low", 1500) * env_exp(d, 0.02))
save_wav("block", verb(block, 0.2), 0.7)

d = 0.32
dash = filt(noise(d), "bp", (250, 2200)) * np.sin(np.pi * t_(d) / d) ** 2 * (0.7 + 0.3 * np.sin(2 * np.pi * 32 * t_(d)))
save_wav("dash", verb(dash, 0.15), 0.5)

for i in range(4):
    d = 0.14
    squelch = filt(noise(d), "low", 380 + 90 * i) * env_exp(d, 0.03 + 0.008 * i)
    tap = sine(60 + 10 * i, d) * env_exp(d, 0.025) * 0.6
    drip = filt(noise(d), "bp", (900, 1800)) * env_exp(d, 0.012) * 0.25
    save_wav(f"step_{i}", mix(squelch, tap, at(drip, 0.02)), 0.35)

d = 0.6
bow = mix(pluck(98, d, 0.993) * env_exp(d, 0.18) * 0.8, filt(noise(d), "bp", (800, 3000)) * env_exp(d, 0.06) * 0.35)
save_wav("bow", verb(bow, 0.15), 0.7)
d = 0.3
arrow_hit = mix(sine(lambda t: 210 * (1 + 0.6 * np.exp(-t / 0.01)), d) * env_exp(d, 0.05), filt(noise(d), "high", 2500) * env_exp(d, 0.008))
save_wav("arrow_hit", verb(arrow_hit, 0.15), 0.6)

d = 1.1
slam = mix(
    sine(lambda t: 42 * (1 + 2.5 * np.exp(-t / 0.05)), d) * env_exp(d, 0.4) * 1.3,
    filt(noise(d), "low", 260) * env_exp(d, 0.35),
    filt(noise(d), "bp", (1200, 4000)) * env_exp(d, 0.15) * (rng.random(int(d * SR)) > 0.985) * 3,
)
save_wav("slam", verb(slam, 0.35), 0.98)

d = 0.9
death = mix(
    sine(lambda t: 70 * (1 + np.exp(-t / 0.02)), 0.4) * env_exp(0.4, 0.09),
    at(sine(lambda t: 60 * (1 + np.exp(-t / 0.02)), 0.4) * env_exp(0.4, 0.07) * 0.7, 0.22),
    at(formant(saw(lambda t: 95 - 30 * t, 0.55), "o") * env_adsr(0.55, 0.05, 0.1, 0.6, 0.3) * 0.5, 0.02),
)
save_wav("death", verb(death, 0.25), 0.7)
d = 0.28
hurt = mix(sine(lambda t: 120 * (1 + np.exp(-t / 0.015)), d) * env_exp(d, 0.05),
           formant(saw(lambda t: 150 - 60 * t, d), "u") * env_adsr(d, 0.01, 0.05, 0.5, 0.15) * 0.6)
save_wav("hurt", verb(hurt, 0.15), 0.6)

# ----------------------------------------------------------------- magic & items
d = 1.4
cast = np.zeros(int(d * SR))
for k, f0 in enumerate([392, 466, 587, 698]):
    cast += sine(lambda t, f0=f0: f0 * (1 + 0.25 * t) * (1 + 0.006 * np.sin(2 * np.pi * 6 * t)), d) * env_adsr(d, 0.15 + 0.05 * k, 0.3, 0.5, 0.7) * 0.3
cast += filt(noise(d), "high", 5000) * env_adsr(d, 0.3, 0.3, 0.3, 0.6) * 0.15
save_wav("cast", verb(cast, 0.5, ir(1.6, 0.4, 6000, 4)), 0.6)

d = 2.2
heal = mix(*[at(bell(f, d - k * 0.12, 0.9), k * 0.12) * 0.5 for k, f in enumerate([587, 698, 880, 1175])])
save_wav("heal", verb(heal, 0.45, ir(2.0, 0.6, 5000, 5)), 0.6)

d = 1.2
smoke = filt(noise(d), "low", 700) * env_adsr(d, 0.08, 0.2, 0.4, 0.8)
save_wav("smoke", verb(smoke, 0.3), 0.55)

d = 0.7
bolt = sine(lambda t: 900 * np.exp(-t * 3) + 120 + 200 * np.sin(2 * np.pi * 37 * t), d) * env_exp(d, 0.25) * 0.8
bolt += filt(noise(d), "bp", (1500, 5000)) * env_exp(d, 0.15) * 0.3
save_wav("bolt", verb(bolt, 0.3), 0.55)
d = 0.5
shock = filt(noise(d), "high", 2500) * (rng.random(int(d * SR)) > 0.7) * env_exp(d, 0.18)
shock += saw(lambda t: 60 + 40 * np.sin(2 * np.pi * 9 * t), d) * env_exp(d, 0.15) * 0.3
save_wav("shock", verb(shock, 0.2), 0.6)

d = 0.6
drink = np.zeros(int(d * SR))
for k in range(3):
    g = sine(lambda t: 210 - 80 * t / 0.08, 0.09) * env_adsr(0.09, 0.01, 0.03, 0.5, 0.04)
    seg = formant(g * 0.5 + saw(160, 0.09) * 0.2 * env_exp(0.09, 0.03), "o") + g
    st = int(k * 0.16 * SR)
    drink[st:st + len(seg)] += seg[: len(drink) - st]
save_wav("drink", verb(drink, 0.15), 0.6)

d = 0.8
loot = mix(*[at(bell(rng.uniform(2200, 3600), 0.5, 0.12, 1.5) * 0.4, k * rng.uniform(0.05, 0.09) + k * 0.04) for k in range(4)])
save_wav("loot", verb(loot, 0.3), 0.55)

d = 0.9
spark = mix(*[at(sine(rng.uniform(3000, 6500), 0.15) * env_exp(0.15, 0.03) * 0.3, rng.uniform(0, 0.5)) for _ in range(14)])
save_wav("starlight", verb(spark, 0.5, ir(1.2, 0.35, 8000, 6)), 0.5)

# ----------------------------------------------------------------- big moments
def choir(freqs, dur, vowel="a", attack=0.6, release=1.0, vib=5.0):
    x = np.zeros(int(dur * SR))
    for f in freqs:
        for det in (-0.004, 0.0, 0.005):
            v = saw(lambda t, f=f, det=det: f * (1 + det) * (1 + 0.004 * np.sin(2 * np.pi * vib * t + f)), dur)
            x += v
    x = formant(x, vowel) * env_adsr(dur, attack, 0.3, 0.8, release)
    return x / len(freqs)


d = 3.2
levelup = mix(choir([146.8, 220, 293.7, 349.2, 440], d, "a", 0.4, 1.4) * 0.7, at(bell(1175, 2.6, 1.1) * 0.25, 0.25), at(bell(1760, 2.4, 0.9) * 0.15, 0.45))
save_wav("levelup", verb(levelup, 0.45, HALL_L), 0.7)

d = 4.0
shrine = mix(bell(146.8, d, 2.2, 0.7), choir([73.4, 110, 146.8, 174.6], d, "o", 1.2, 1.8) * 0.4)
save_wav("shrine", verb(shrine, 0.5, HALL_L), 0.75)

d = 1.8
creak = np.zeros(int(d * SR))
src = filt(noise(d), "bp", (100, 900))
for k in range(1, 5):
    delay = int(SR / (90 * k + 40 * np.sin(k)))
    creak[delay:] += src[:-delay] * 0.5 / k
creak *= env_adsr(d, 0.2, 0.2, 0.7, 0.4) * (0.6 + 0.4 * np.sin(2 * np.pi * 7 * t_(d)))
gate = mix(creak, at(sine(lambda t: 55 * (1 + np.exp(-t / 0.04)), 0.6) * env_exp(0.6, 0.2), 1.5))
save_wav("gate", verb(gate, 0.35), 0.8)

d = 2.2
roar_src = saw(lambda t: 58 + 20 * np.exp(-t * 2) + 6 * np.sin(2 * np.pi * 18 * t), d) + filt(noise(d), "low", 900) * 0.6
roar = formant(roar_src, "a") * env_adsr(d, 0.15, 0.3, 0.75, 0.9) * (0.75 + 0.25 * np.sin(2 * np.pi * 18 * t_(d)))
roar = mix(roar, sine(lambda t: 38 + 10 * np.exp(-t), d) * env_adsr(d, 0.1, 0.3, 0.6, 1.0) * 0.6)
save_wav("roar", verb(roar, 0.45, HALL_L), 0.95)

# --- Act II: glass, wings, dragon fire
d = 0.9
shards = mix(*[at(bell(f, 0.6, 0.12, 2.5) * 0.4, k * 0.035) for k, f in enumerate([2630, 3170, 2210, 3810, 2950, 4400])])
crash = filt(noise(d), "high", 2500) * env_exp(d, 0.09)
save_wav("shatter", verb(mix(shards, crash * 0.8), 0.3), 0.7)

d = 0.8
flap = filt(noise(d), "low", 700) * (0.5 + 0.5 * np.sin(2 * np.pi * 9 * t_(d))) ** 3 * env_adsr(d, 0.05, 0.2, 0.6, 0.3)
save_wav("wings", verb(flap, 0.25), 0.8)

d = 2.0
fire = filt(noise(d), "bp", (300, 2600)) * env_adsr(d, 0.06, 0.25, 0.8, 0.9)
crackle = filt(noise(d), "high", 3000) * (rng.random(int(d * SR)) > 0.997) * 6.0 * env_adsr(d, 0.1, 0.2, 0.7, 0.8)
rumble = filt(noise(d), "low", 140) * env_adsr(d, 0.05, 0.3, 0.8, 0.9) * 1.5
save_wav("breath", verb(mix(fire, crackle, rumble), 0.35), 0.95)

d = 4.5
died = mix(sine(lambda t: 36 * (1 + np.exp(-t / 0.1)), d) * env_exp(d, 1.2), choir([73.4, 87.3, 110, 138.6], d, "u", 0.8, 2.0) * 0.55)
save_wav("you_died", verb(died, 0.5, HALL_L), 0.9)

save_wav("ui_move", sine(1250, 0.05) * env_exp(0.05, 0.012), 0.25)
save_wav("ui_confirm", mix(sine(660, 0.12) * env_exp(0.12, 0.04), at(sine(990, 0.14) * env_exp(0.14, 0.05), 0.06)), 0.35)
save_wav("ui_back", mix(sine(660, 0.12) * env_exp(0.12, 0.04), at(sine(440, 0.14) * env_exp(0.14, 0.05), 0.06)), 0.35)
save_wav("talk_blip", sine(520, 0.03) * env_exp(0.03, 0.008), 0.12)


# ----------------------------------------------------------------- ambience (seamless loops)
def amb_rain(dur=24.0):
    """Soft rain on leaves: dark, low-passed wash with slow swells and gentle taps (no hiss)."""
    n = int(dur * SR)
    t = t_(dur)
    wash = filt(filt(noise(dur + 2), "bp", (180, 1900))[:n], "low", 1600) * 0.22
    swell = 0.75 + 0.25 * np.sin(2 * np.pi * 0.06 * t) * np.sin(2 * np.pi * 0.023 * t + 1.0)
    rumble = filt(noise(dur + 2), "low", 260)[:n] * 0.18
    taps = np.zeros(n)
    for _ in range(int(dur * 40)):
        p = rng.integers(0, n - 4000)
        f = rng.uniform(700, 1900)
        taps[p:p + 1764] += sine(f, 0.04) * env_exp(0.04, 0.004) * rng.uniform(0.02, 0.07)
    taps = filt(taps, "low", 2400)
    return wash * swell + rumble + taps


def amb_wind(dur=30.0):
    n = int(dur * SR)
    t = t_(dur)
    x = np.zeros(n)
    src = noise(dur)
    for lo, hi, rate, ph in [(120, 500, 0.07, 0), (300, 900, 0.11, 2), (700, 1600, 0.05, 4)]:
        band = filt(src, "bp", (lo, hi))
        x += band * (0.5 + 0.5 * np.sin(2 * np.pi * rate * t + ph)) ** 2
    return x


def fire_loop(dur=8.0):
    n = int(dur * SR)
    rumble = filt(noise(dur), "low", 300) * 0.5 * (0.8 + 0.2 * np.sin(2 * np.pi * 0.7 * t_(dur)))
    hiss = filt(noise(dur), "bp", (1200, 3200)) * 0.03
    pops = np.zeros(n)
    for _ in range(int(dur * 9)):
        p = rng.integers(0, n - 2000)
        pops[p:p + 1323] += filt(noise(0.03), "high", 1500) * env_exp(0.03, 0.004) * rng.uniform(0.2, 0.9)
    return rumble + hiss + filt(pops, "low", 3800) * 0.7


def make_loop(fn, name, xfade=1.0):
    x = fn()
    k = int(xfade * SR)
    head, body = x[:k], x[k:]
    body[-k:] = body[-k:] * np.linspace(1, 0, k) + head * np.linspace(0, 1, k)
    save_ogg("amb", name, norm(body, 0.7))


make_loop(amb_rain, "rain")
make_loop(amb_wind, "wind")
make_loop(fire_loop, "fire", 0.4)


# ----------------------------------------------------------------- music (D minor, three layers, seamless)
def pad_chord(freqs, dur, vowel="o"):
    return choir(freqs, dur, vowel, attack=dur * 0.35, release=dur * 0.45, vib=4.0)


def drum(dur=0.9, f0=55, amp=1.0):
    return (sine(lambda t: f0 * (1 + 1.8 * np.exp(-t / 0.03)), dur) * env_exp(dur, 0.22) + filt(noise(dur), "low", 900) * env_exp(dur, 0.03) * 0.5) * amp


def render_stereo(left, right, tail):
    L = signal.fftconvolve(left, HALL_L)[: len(left)] * 0.5 + left * 0.7
    R = signal.fftconvolve(right, HALL_R)[: len(right)] * 0.5 + right * 0.7
    L, R = loopable(L, tail), loopable(R, tail)
    m = max(np.abs(L).max(), np.abs(R).max())
    return np.stack([L, R], 1) / m * 0.8


def music_explore():
    bar = 4.0
    prog = [[73.4, 110, 146.8, 174.6], [58.3, 116.5, 146.8, 174.6], [49.0, 98, 146.8, 196], [55.0, 110, 138.6, 164.8]]
    bars = 16
    total = bars * bar
    tail = int(4 * SR)
    n = int(total * SR) + tail
    L, R = np.zeros(n), np.zeros(n)
    for b in range(bars):
        ch = prog[b % 4]
        p = pad_chord(ch, bar * 1.6) * 0.55
        s = int(b * bar * SR)
        L[s:s + len(p)] += p[: n - s]
        R[s:s + len(p)] += np.roll(p, 300)[: n - s]
        dr = (saw(ch[0] / 2, bar) * 0.25)
        dr = filt(dr, "low", 180) * env_adsr(bar, 0.5, 0.5, 0.8, 0.6)
        L[s:s + len(dr)] += dr
        R[s:s + len(dr)] += dr
    melody = [587, 698, 659, 587, 523, 440, 466, 440]
    for k in range(10):
        f = melody[rng.integers(0, len(melody))]
        s = int(rng.uniform(2, total - 3) * SR)
        bl = bell(f, 3.0, 1.0) * 0.18
        pan = rng.uniform(0.2, 0.8)
        L[s:s + len(bl)] += bl[: n - s] * (1 - pan)
        R[s:s + len(bl)] += bl[: n - s] * pan
    return render_stereo(L, R, tail)


def music_combat(bpm=92, bars=8, boss=False):
    beat = 60.0 / bpm
    bar = beat * 4
    total = bars * bar
    tail = int(3 * SR)
    n = int(total * SR) + tail
    L, R = np.zeros(n), np.zeros(n)
    roots = [73.4, 73.4, 58.3, 55.0] if not boss else [73.4, 77.8, 73.4, 69.3]
    pattern = [1, 0, 0, 1, 0, 0, 1, 0, 1, 0, 0, 1, 0, 1, 1, 0] if not boss else [1, 0, 1, 0, 1, 0, 1, 1, 1, 0, 1, 0, 1, 1, 1, 1]
    for b in range(bars):
        root = roots[b % 4]
        s = int(b * bar * SR)
        for k, hit in enumerate(pattern):
            if hit:
                p = int(s + k * beat / 4 * SR)
                dm = drum(0.8, 48 if k % 4 == 0 else 62, 1.0 if k % 4 == 0 else 0.6)
                L[p:p + len(dm)] += dm[: n - p] * 0.9
                R[p:p + len(dm)] += dm[: n - p] * 0.9
        # low string ostinato
        for k in range(8):
            f = root * (2 if k % 4 != 3 else 2.378)
            nt = filt(saw(f, beat / 2 * 0.9), "low", 900) * env_adsr(beat / 2 * 0.9, 0.01, 0.08, 0.6, 0.05) * 0.28
            p = int(s + k * beat / 2 * SR)
            L[p:p + len(nt)] += nt[: n - p]
            R[p:p + len(nt)] += nt[: n - p] * 0.8
        pad = pad_chord([root, root * 1.5, root * 2, root * 2.378], bar * 1.3, "a") * (0.3 if not boss else 0.45)
        L[s:s + len(pad)] += pad[: n - s]
        R[s:s + len(pad)] += np.roll(pad, 250)[: n - s]
        if boss and b % 2 == 1:
            stab = filt(saw(root * 4, beat), "low", 1400) * env_exp(beat, 0.25) * 0.35
            for off in (0, beat * 1.5):
                p = int(s + (2 * beat + off) * SR)
                L[p:p + len(stab)] += stab[: n - p]
                R[p:p + len(stab)] += stab[: n - p]
    return render_stereo(L, R, tail)


save_ogg("music", "explore", music_explore(), stereo=True)
save_ogg("music", "combat", music_combat(92, 16), stereo=True)
save_ogg("music", "boss", music_combat(112, 16, True), stereo=True)
print("audio done")
