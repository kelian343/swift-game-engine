# FitMotion

Offline tool to fit ASCII FBX animation curves into Fourier series coefficients.

## Usage

```sh
python3 /Users/karpellus/Desktop/Game/Tools/FitMotion/fit_motion.py \
  --fbx /Users/karpellus/Desktop/Game/Game/Walking.fbx \
  --out /Users/karpellus/Desktop/Game/Game/Walking.motionProfile.json \
  --name Walking \
  --fps 60 \
  --order 4 \
  --skeleton-swift /Users/karpellus/Desktop/Game/Game/Skeleton.swift
```

## Output format

The JSON file contains per-bone Fourier coefficients for translation and rotation channels.
Coefficients are stored as:

- `[a0, a1, b1, a2, b2, ... aN, bN]`
- `a0` is the constant term.
- `aK` corresponds to `cos(2πKφ)` and `bK` to `sin(2πKφ)`.

All rotation values are in degrees, matching the FBX `Lcl Rotation` channel.
`phase.mode` is `normalized_time` (φ = t / duration) for now.
If `--skeleton-swift` is provided and foot contacts are detected, the tool
switches to `phase.mode = left_foot_contact` and emits `phase.cycle_duration`
along with `contacts.left/right` curves.
