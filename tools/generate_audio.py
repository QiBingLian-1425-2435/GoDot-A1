"""Original deterministic procedural audio; no samples or third-party source audio."""
from pathlib import Path
import json
import wave
import numpy as np

RATE = 22050
OUT = Path(__file__).resolve().parents[1] / "assets" / "audio"
RNG = np.random.default_rng(17102026)


def write(name, samples):
    samples = np.asarray(samples, dtype=np.float64)
    samples -= samples.mean(axis=0)
    samples = np.clip(samples, -0.95, 0.95)
    pcm = np.rint(samples * 32767).astype("<i2")
    channels = 1 if pcm.ndim == 1 else pcm.shape[1]
    with wave.open(str(OUT / (name + ".wav")), "wb") as wav:
        wav.setnchannels(channels)
        wav.setsampwidth(2)
        wav.setframerate(RATE)
        wav.writeframes(pcm.tobytes())
    return {"name": name, "seconds": len(pcm) / RATE, "channels": channels,
            "peak": round(float(np.max(np.abs(samples))), 4),
            "rms": round(float(np.sqrt(np.mean(samples ** 2))), 4)}


def wind(length, cutoff, seed):
    # FFT filtering creates a periodic smooth texture, including the loop seam.
    rng = np.random.default_rng(seed)
    spectrum = np.fft.rfft(rng.normal(size=length))
    frequencies = np.fft.rfftfreq(length, 1 / RATE)
    spectrum *= (1 - np.exp(-(frequencies / 28) ** 2)) * np.exp(-(frequencies / cutoff) ** 2)
    spectrum[0] = 0
    out = np.fft.irfft(spectrum, n=length)
    return out / max(1, np.max(np.abs(out)))


def bell(t, frequency, decay=3.0):
    # Soft, slightly inharmonic struck glass with a rounded attack.
    envelope = (1 - np.exp(-t * 110)) * np.exp(-t * decay)
    return envelope * (np.sin(2 * np.pi * frequency * t)
                       + 0.22 * np.sin(2 * np.pi * frequency * 2.005 * t) * np.exp(-t * 2)
                       + 0.07 * np.sin(2 * np.pi * frequency * 3.012 * t) * np.exp(-t * 5))


def chime(duration, notes):
    t = np.arange(round(duration * RATE)) / RATE
    output = np.zeros_like(t)
    for onset, frequency, amplitude in notes:
        local = np.maximum(0, t - onset)
        output += amplitude * bell(local, frequency, 4.0) * (t >= onset)
    output *= np.minimum(1, (duration - t) / 0.08)
    return output


OUT.mkdir(parents=True, exist_ok=True)
report = []
duration = 12.0
t = np.arange(round(RATE * duration)) / RATE
ambient = np.zeros((len(t), 2))
for channel in range(2):
    phase = channel * 0.65
    airflow = wind(len(t), 520, 117 + channel) * (0.15 + 0.035 * np.sin(2 * np.pi * t / duration + phase))
    drone = np.zeros_like(t)
    # Every frequency and modulation completes an integer number of loop cycles.
    for frequency, amplitude in [(110, 0.035), (165, 0.018), (220, 0.011), (330, 0.006)]:
        drone += amplitude * np.sin(2 * np.pi * frequency * t + phase) * (0.8 + 0.2 * np.cos(2 * np.pi * t / duration))
    ambient[:, channel] = airflow + drone
report.append(write("ambient", ambient))
report.append(write("pickup", chime(0.65, [(0, 659.255, 0.29), (0.11, 987.767, 0.20)])))
report.append(write("rescue", chime(1.15, [(0, 329.628, 0.23), (0.14, 440, 0.22), (0.29, 659.255, 0.20)])))
report.append(write("extract", chime(1.65, [(0, 261.626, 0.23), (0.15, 329.628, 0.21), (0.3, 391.995, 0.20), (0.48, 523.251, 0.18)])))

t = np.arange(round(RATE * 0.95)) / RATE
envelope = (1 - np.exp(-t * 55)) * np.exp(-t * 4) * np.minimum(1, (0.95 - t) / 0.1)
phase = 2 * np.pi * (185 * t - 42 * t * t)
down = envelope * (0.3 * np.sin(phase) + 0.12 * np.sin(phase * 1.5) + 0.09 * wind(len(t), 650, 222))
report.append(write("down", down))

t = np.arange(round(RATE * 0.16)) / RATE
envelope = (1 - np.exp(-t * 400)) * np.exp(-t * 36) * np.minimum(1, (0.16 - t) / 0.02)
step = envelope * (0.30 * wind(len(t), 2200, 333) + 0.16 * np.sin(2 * np.pi * 96 * t))
report.append(write("step", step))

t = np.arange(round(RATE * 1.1)) / RATE
danger = np.zeros_like(t)
for onset in (0, 0.38):
    local = np.maximum(0, t - onset)
    envelope = (1 - np.exp(-local * 75)) * np.exp(-local * 7) * (t >= onset)
    danger += envelope * (0.22 * np.sin(2 * np.pi * 103.826 * local) + 0.12 * np.sin(2 * np.pi * 155.563 * local))
danger += 0.07 * wind(len(t), 450, 444) * np.sin(np.pi * t / 1.1) ** 2
danger *= np.minimum(1, (1.1 - t) / 0.08)
report.append(write("danger", danger))

for path in OUT.glob("*.wav"):
    with wave.open(str(path), "rb") as wav:
        assert wav.getcomptype() == "NONE"
        assert wav.getsampwidth() == 2 and wav.getframerate() == RATE
        assert len(wav.readframes(wav.getnframes())) == wav.getnframes() * wav.getnchannels() * 2
assert sum(p.stat().st_size for p in OUT.glob("*.wav")) < 2_000_000
print(json.dumps(report, indent=2))
print("Total WAV bytes:", sum(p.stat().st_size for p in OUT.glob("*.wav")))
