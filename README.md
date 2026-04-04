# audioctrl

A command-line tool for reading and writing CoreAudio device properties on macOS.

```
$ audioctrl list
    ID  Name                               Rate     In  Out  Transport
----------------------------------------------------------------------
    71  Built-in Microphone               48000      2    0  Built-in
    72  Built-in Speakers                 48000      0    2  Built-in
   136  AirPods Pro                       24000      1    0  Bluetooth
   130  AirPods Pro                       48000      0    2  Bluetooth
    89  BlackHole 2ch                     44100      2    2  Virtual
    91  Studio Display                    48000      0    2  USB
    55  Sample Aggregate Device           48000      2    0  Aggregate
```

## Requirements

- macOS 13 or later
- Swift 5.9+

## Installation

```sh
git clone https://github.com/your-username/audioctrl.git
cd audioctrl
swift build -c release
cp .build/release/audioctrl /usr/local/bin/
```

## Commands

### `list` — List all audio devices

```
audioctrl list [--verbose] [--sort <key>]
```

Prints a table of all CoreAudio devices with their object ID, name, sample rate, input/output channel counts, and transport type.

| Flag | Description |
|------|-------------|
| `-v`, `--verbose` | Also print each device's UID |
| `-s`, `--sort` | Sort by `transport` (default), `id`, `name`, or `rate` |

The default transport sort groups devices so physical outputs appear first: **Built-in** → **Bluetooth** → **USB** → **HDMI/DisplayPort/Thunderbolt** → **Virtual** → **Aggregate**.

```sh
audioctrl list
audioctrl list --sort name
audioctrl list --verbose
```

---

### `get` — Read a property

```
audioctrl get <device> <property>
audioctrl get <device>
```

Prints the current value of a property on the specified device. Omit `<property>` to dump all readable properties for that device.

**Device selection** — three equivalent options:

| Form | Behavior |
|------|----------|
| Positional `<device>` | Matches by name substring, exact UID, or numeric object ID |
| `--id <n>` / `-i <n>` | Exact numeric object ID lookup |
| `--name <pattern>` / `-n <pattern>` | Case-insensitive name substring or exact UID |

```sh
audioctrl get Speakers volume
audioctrl get --id 72 sample-rate
audioctrl get Speakers                  # dump all properties
```

Example dump output:

```
  name           BlackHole 2ch
  uid            BlackHole2ch_UID
  sample-rate    96000
  buffer-size    512
  transport      Virtual
  is-running     0
  is-hidden      0
  volume         1    [output]
  volume-db      0    [output]
  volume-input   1    [input]
  mute           0    [output]
  mute-input     0    [input]
  clock-source   0    [global]
  'evis'         —    [output]
```

Control-backed properties (volume, mute, etc.) show their scope in brackets — `[input]` or `[output]` — indicating which direction of the device they apply to. Device-level properties (name, sample-rate…) have no scope annotation. Unrecognised device-specific controls appear at the bottom with `—` as their value.

---

### `set` — Write a property

```
audioctrl set <device> <property> <value>
```

Sets a writable property on the specified device. Device selection works the same as `get`.

```sh
audioctrl set Speakers volume 0.8
audioctrl set --id 72 sample-rate 48000
audioctrl set Speakers mute 1
```

---

### `props` — List known properties

```
audioctrl props
```

Prints all built-in property names with their types and read/write status.

```
  Name           Type     R/W  Description
  ---------------------------------------------------------------
  name           string   r    Device name
  uid            string   r    Unique identifier (UID)
  model-uid      string   r    Model UID
  sample-rate    float64  r/w  Sample rate (Hz)
  buffer-size    uint32   r/w  I/O buffer size (frames)
  latency        uint32   r    Device latency (frames)
  safety-offset  uint32   r    Safety offset (frames)
  transport      uint32   r    Transport type
  is-running     uint32   r    I/O is active (0/1)
  is-hidden      uint32   r    Hidden device flag (0/1)
  volume         float32  r/w  Output volume scalar (0–1)
  volume-db      float32  r/w  Output volume (dB)
  volume-input   float32  r/w  Input volume scalar (0–1)
  mute           uint32   r/w  Output mute (0/1)
  mute-input     uint32   r/w  Input mute (0/1)
  clock-source   uint32   r/w  Clock source (0=fixed, 1=adjustable) [BlackHole]
  pitch          float32  r/w  Playback speed (0.5=normal) [BlackHole, requires clock-source=1]
```

---

## Raw selectors

Any `get` or `set` command accepts a raw CoreAudio property selector when the property is not in the built-in list. Pass `--type` to specify the value type.

```sh
# Read kAudioDevicePropertyNominalSampleRate by 4-char code
audioctrl get --id 72 nsrt --type float64

# Same property by hex selector
audioctrl get --id 72 0x6E737274 --type float64

# Override the property scope
audioctrl get --id 72 nsrt --type float64 --scope output
```

| Option | Description |
|--------|-------------|
| `-t`, `--type` | `float32`, `float64`, `uint32`, or `string` |
| `-s`, `--scope` | `global` (default), `input`, or `output` |
| `-e`, `--element` | Property element (default: `0`) |

## License

MIT
