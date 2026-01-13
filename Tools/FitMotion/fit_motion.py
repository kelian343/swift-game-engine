#!/usr/bin/env python3
import argparse
import json
import math
import re
from dataclasses import dataclass
from pathlib import Path
from typing import Dict, List, Optional, Tuple

TIME_SCALE = 46186158000.0


@dataclass
class AnimationCurve:
    times: List[float]
    values: List[float]
    default_value: float = 0.0

    def sample(self, t: float) -> float:
        if not self.times or len(self.times) != len(self.values):
            return self.default_value
        if t <= self.times[0]:
            return self.values[0]
        if t >= self.times[-1]:
            return self.values[-1]
        lo = 0
        hi = len(self.times) - 1
        while hi - lo > 1:
            mid = (lo + hi) // 2
            if self.times[mid] <= t:
                lo = mid
            else:
                hi = mid
        t0 = self.times[lo]
        t1 = self.times[hi]
        v0 = self.values[lo]
        v1 = self.values[hi]
        span = max(t1 - t0, 1e-6)
        a = (t - t0) / span
        return v0 + (v1 - v0) * a


def parse_model_names(text: str) -> Dict[int, str]:
    pattern = r'Model:\s+(\d+),\s+"Model::([^"]+)",\s+"LimbNode"'
    out: Dict[int, str] = {}
    for match in re.finditer(pattern, text):
        out[int(match.group(1))] = match.group(2)
    return out


def parse_curve_node_bindings(text: str, model_id_to_name: Dict[int, str]) -> Dict[int, Tuple[str, str]]:
    pattern = r'C:\s+"OP",(\d+),(\d+),\s+"Lcl (Translation|Rotation)"'
    out: Dict[int, Tuple[str, str]] = {}
    for match in re.finditer(pattern, text):
        node_id = int(match.group(1))
        model_id = int(match.group(2))
        bone_name = model_id_to_name.get(model_id)
        if bone_name is None:
            continue
        channel = match.group(3).lower()
        out[node_id] = (bone_name, channel)
    return out


def parse_curve_bindings(text: str) -> Dict[int, Tuple[int, str]]:
    pattern = r'C:\s+"OP",(\d+),(\d+),\s+"d\|([XYZ])"'
    out: Dict[int, Tuple[int, str]] = {}
    for match in re.finditer(pattern, text):
        curve_id = int(match.group(1))
        node_id = int(match.group(2))
        axis = match.group(3).lower()
        out[curve_id] = (node_id, axis)
    return out


def _parse_float_list(raw: str) -> List[float]:
    cleaned = raw.replace("\n", "")
    items = []
    for part in cleaned.split(","):
        part = part.strip()
        if not part:
            continue
        items.append(float(part))
    return items


def _parse_int_list(raw: str) -> List[int]:
    cleaned = raw.replace("\n", "")
    items = []
    for part in cleaned.split(","):
        part = part.strip()
        if not part:
            continue
        items.append(int(part))
    return items


def parse_curves(text: str) -> Dict[int, AnimationCurve]:
    pattern = re.compile(
        r'AnimationCurve:\s+(\d+),.*?KeyTime:\s*\*\d+\s*\{\s*a:\s*([^\}]*)\}\s*'
        r'KeyValueFloat:\s*\*\d+\s*\{\s*a:\s*([^\}]*)\}',
        re.S,
    )
    curves: Dict[int, AnimationCurve] = {}
    for match in pattern.finditer(text):
        curve_id = int(match.group(1))
        times = [t / TIME_SCALE for t in _parse_int_list(match.group(2))]
        values = _parse_float_list(match.group(3))
        curves[curve_id] = AnimationCurve(times=times, values=values)
    return curves


def build_bone_curves(text: str) -> Tuple[Dict[str, dict], float]:
    model_id_to_name = parse_model_names(text)
    curve_node_bindings = parse_curve_node_bindings(text, model_id_to_name)
    curve_bindings = parse_curve_bindings(text)
    curves = parse_curves(text)

    bone_anims: Dict[str, dict] = {}
    max_time = 0.0

    for curve_id, (node_id, axis) in curve_bindings.items():
        curve = curves.get(curve_id)
        if curve is None:
            continue
        node = curve_node_bindings.get(node_id)
        if node is None:
            continue
        bone_name, channel = node
        max_time = max(max_time, curve.times[-1] if curve.times else 0.0)
        anim = bone_anims.setdefault(bone_name, {"translation": {}, "rotation": {}})
        anim[channel][axis] = curve

    return bone_anims, max(max_time, 0.001)


def parse_skeleton_humanoid8(swift_path: Path) -> dict:
    text = swift_path.read_text(encoding="utf-8")
    start = text.find("public static func humanoid8()")
    if start < 0:
        raise ValueError(f"Failed to find humanoid8() in {swift_path}")
    end = text.find("public static func rotationXYZDegrees", start)
    if end < 0:
        end = text.find("public static func translation", start)
    if end < 0:
        raise ValueError(f"Failed to find humanoid8() end in {swift_path}")
    text = text[start:end]

    def extract_block(label: str) -> str:
        pattern = rf"{label}\s*=\s*\[(.*?)\]"
        match = re.search(pattern, text, flags=re.S)
        if not match:
            raise ValueError(f"Failed to find {label} block in {swift_path}")
        return match.group(1)

    names_block = extract_block("let names")
    names = re.findall(r"\"([^\"]+)\"", names_block)

    parent_block = extract_block("let parent: \\[Int\\]")
    parent = [int(x.strip()) for x in parent_block.replace("\\n", "").split(",") if x.strip()]

    translations_block = extract_block("let translations: \\[SIMD3<Float>\\]")
    translations = []
    for match in re.finditer(r"SIMD3<Float>\(([^)]+)\)", translations_block):
        parts = [float(x.strip()) for x in match.group(1).split(",")]
        translations.append(parts)

    pre_rot_block = extract_block("let preRotations: \\[SIMD3<Float>\\]")
    pre_rotations = []
    for match in re.finditer(r"SIMD3<Float>\(([^)]+)\)", pre_rot_block):
        parts = [float(x.strip()) for x in match.group(1).split(",")]
        pre_rotations.append(parts)

    scale_match = re.search(r"let scale: Float = ([0-9.\\-eE]+)", text)
    if not scale_match:
        raise ValueError(f"Failed to find scale in {swift_path}")
    scale = float(scale_match.group(1))

    if len(names) != len(parent) or len(names) != len(translations) or len(names) != len(pre_rotations):
        raise ValueError(
            f"Skeleton arrays mismatch: names={len(names)} parent={len(parent)} "
            f"translations={len(translations)} pre_rotations={len(pre_rotations)}"
        )

    return {
        "names": names,
        "parent": parent,
        "translations": translations,
        "pre_rotations": pre_rotations,
        "scale": scale,
    }


def rotation_xyz_degrees(rx: float, ry: float, rz: float) -> List[List[float]]:
    rx = math.radians(rx)
    ry = math.radians(ry)
    rz = math.radians(rz)
    cx, sx = math.cos(rx), math.sin(rx)
    cy, sy = math.cos(ry), math.sin(ry)
    cz, sz = math.cos(rz), math.sin(rz)

    rot_x = [
        [1, 0, 0, 0],
        [0, cx, -sx, 0],
        [0, sx, cx, 0],
        [0, 0, 0, 1],
    ]
    rot_y = [
        [cy, 0, sy, 0],
        [0, 1, 0, 0],
        [-sy, 0, cy, 0],
        [0, 0, 0, 1],
    ]
    rot_z = [
        [cz, -sz, 0, 0],
        [sz, cz, 0, 0],
        [0, 0, 1, 0],
        [0, 0, 0, 1],
    ]

    return mat_mul(rot_z, mat_mul(rot_y, rot_x))


def translation_matrix(tx: float, ty: float, tz: float) -> List[List[float]]:
    return [
        [1, 0, 0, 0],
        [0, 1, 0, 0],
        [0, 0, 1, 0],
        [tx, ty, tz, 1],
    ]


def mat_mul(a: List[List[float]], b: List[List[float]]) -> List[List[float]]:
    out = [[0.0] * 4 for _ in range(4)]
    for i in range(4):
        for j in range(4):
            out[i][j] = a[i][0] * b[0][j] + a[i][1] * b[1][j] + a[i][2] * b[2][j] + a[i][3] * b[3][j]
    return out


def transform_point(mat: List[List[float]], point: List[float]) -> List[float]:
    x, y, z = point
    return [
        x * mat[0][0] + y * mat[1][0] + z * mat[2][0] + mat[3][0],
        x * mat[0][1] + y * mat[1][1] + z * mat[2][1] + mat[3][1],
        x * mat[0][2] + y * mat[1][2] + z * mat[2][2] + mat[3][2],
    ]


def build_model_transforms(parent: List[int], local: List[List[List[float]]]) -> List[List[List[float]]]:
    model = [[[0.0] * 4 for _ in range(4)] for _ in range(len(local))]
    for i in range(len(local)):
        p = parent[i]
        if p < 0:
            model[i] = local[i]
        else:
            model[i] = mat_mul(model[p], local[i])
    return model


def compute_foot_contacts(bone_anims: Dict[str, dict],
                          skeleton: dict,
                          t_samples: List[float],
                          in_place: bool = True) -> Tuple[List[float], List[float], List[float], List[float]]:
    names = skeleton["names"]
    parent = skeleton["parent"]
    translations = skeleton["translations"]
    pre_rotations = skeleton["pre_rotations"]
    scale = skeleton["scale"]
    name_to_index = {n: i for i, n in enumerate(names)}

    left_name = "mixamorig:LeftFoot"
    right_name = "mixamorig:RightFoot"
    if left_name not in name_to_index or right_name not in name_to_index:
        return [], []
    left_index = name_to_index[left_name]
    right_index = name_to_index[right_name]

    root_fix = rotation_xyz_degrees(0.0, 180.0, 0.0)

    left_positions: List[List[float]] = []
    right_positions: List[List[float]] = []

    for t in t_samples:
        local = []
        for i, name in enumerate(names):
            anim = bone_anims.get(name, {})
            trans_curves = anim.get("translation", {})
            rot_curves = anim.get("rotation", {})

            rest_raw = translations[i]
            rest_scaled = [0.0, 0.0, 0.0] if i == 0 else [v * scale for v in rest_raw]

            anim_raw = [
                (trans_curves.get("x") or AnimationCurve([], [], rest_raw[0])).sample(t),
                (trans_curves.get("y") or AnimationCurve([], [], rest_raw[1])).sample(t),
                (trans_curves.get("z") or AnimationCurve([], [], rest_raw[2])).sample(t),
            ]

            delta = [anim_raw[0] - rest_raw[0], anim_raw[1] - rest_raw[1], anim_raw[2] - rest_raw[2]]
            trans = [
                rest_scaled[0] + delta[0] * scale,
                rest_scaled[1] + delta[1] * scale,
                rest_scaled[2] + delta[2] * scale,
            ]
            if i == 0 and in_place:
                trans[0] = rest_scaled[0]
                trans[2] = rest_scaled[2]

            anim_rot = [
                (rot_curves.get("x") or AnimationCurve([], [], 0.0)).sample(t),
                (rot_curves.get("y") or AnimationCurve([], [], 0.0)).sample(t),
                (rot_curves.get("z") or AnimationCurve([], [], 0.0)).sample(t),
            ]
            pre_rot = pre_rotations[i]
            rot = rotation_xyz_degrees(pre_rot[0], pre_rot[1], pre_rot[2])
            rot = mat_mul(rot, rotation_xyz_degrees(anim_rot[0], anim_rot[1], anim_rot[2]))
            if i == 0:
                rot = mat_mul(root_fix, rot)

            local_mat = mat_mul(translation_matrix(trans[0], trans[1], trans[2]), rot)
            local.append(local_mat)

        model = build_model_transforms(parent, local)
        left_positions.append(transform_point(model[left_index], [0.0, 0.0, 0.0]))
        right_positions.append(transform_point(model[right_index], [0.0, 0.0, 0.0]))

    def compute_weights(positions: List[List[float]]) -> List[float]:
        ys = [p[1] for p in positions]
        if not ys:
            return []
        sorted_y = sorted(ys)
        y_min = sorted_y[max(0, int(len(sorted_y) * 0.05) - 1)]
        y_max = sorted_y[min(len(sorted_y) - 1, int(len(sorted_y) * 0.95))]
        height_range = max(y_max - y_min, 1e-4)
        height_thresh = max(height_range * 0.15, 0.01)

        velocities = [0.0]
        for i in range(1, len(ys)):
            velocities.append((ys[i] - ys[i - 1]) * len(ys))
        vel_abs = [abs(v) for v in velocities]
        vel_max = max(vel_abs) if vel_abs else 1e-4
        vel_thresh = max(vel_max * 0.25, 0.05)

        weights = []
        for y, vy in zip(ys, velocities):
            h = max(0.0, min(1.0, 1.0 - (y - y_min) / height_thresh))
            v = max(0.0, min(1.0, 1.0 - abs(vy) / vel_thresh))
            weights.append(h * v)

        smoothed = []
        win = 5
        for i in range(len(weights)):
            start = max(0, i - win)
            end = min(len(weights), i + win + 1)
            smoothed.append(sum(weights[start:end]) / (end - start))
        return smoothed

    left_weights = compute_weights(left_positions)
    right_weights = compute_weights(right_positions)
    left_y = [p[1] for p in left_positions]
    right_y = [p[1] for p in right_positions]
    return left_weights, right_weights, left_y, right_y


def compute_phase_from_contacts(times: List[float], weights: List[float], threshold: float = 0.5) -> Tuple[List[float], float]:
    if not times or not weights:
        return [], 0.0
    max_w = max(weights)
    if max_w <= 0.0:
        return [], 0.0
    if max_w < threshold:
        threshold = max_w * 0.6
    events = []
    prev = weights[0]
    for i in range(1, len(weights)):
        cur = weights[i]
        if prev < threshold and cur >= threshold:
            events.append(times[i])
        prev = cur

    if len(events) < 2:
        return [], 0.0

    durations = [events[i + 1] - events[i] for i in range(len(events) - 1)]
    avg_adj = sum(durations) / len(durations)
    avg_period = avg_adj
    if len(events) >= 3:
        skip = [events[i + 2] - events[i] for i in range(len(events) - 2)]
        avg_skip = sum(skip) / len(skip)
        if avg_skip > avg_adj * 1.5:
            avg_period = avg_skip
    if avg_period <= 0:
        return [], 0.0

    phase = []
    event_index = 0
    for t in times:
        while event_index + 1 < len(events) and t >= events[event_index + 1]:
            event_index += 1
        phi = (t - events[event_index]) / avg_period
        phi = phi - math.floor(phi)
        phase.append(phi)
    return phase, avg_period


def detect_minima_events(times: List[float], values: List[float]) -> List[float]:
    if len(values) < 3:
        return []
    v_min = min(values)
    v_max = max(values)
    if v_max - v_min <= 1e-4:
        return []
    threshold = v_min + (v_max - v_min) * 0.25
    events: List[float] = []
    last_t = -1e9
    min_spacing = (times[-1] - times[0]) / max(len(times), 1) * 10.0
    for i in range(1, len(values) - 1):
        if values[i] <= values[i - 1] and values[i] <= values[i + 1] and values[i] <= threshold:
            t = times[i]
            if t - last_t >= min_spacing:
                events.append(t)
                last_t = t
    return events


def compute_phase_from_events(times: List[float], events: List[float]) -> Tuple[List[float], float]:
    if len(events) < 2:
        return [], 0.0
    durations = [events[i + 1] - events[i] for i in range(len(events) - 1)]
    avg_adj = sum(durations) / len(durations)
    avg_period = avg_adj
    if len(events) >= 3:
        skip = [events[i + 2] - events[i] for i in range(len(events) - 2)]
        avg_skip = sum(skip) / len(skip)
        if avg_skip > avg_adj * 1.5:
            avg_period = avg_skip
    if avg_period <= 0:
        return [], 0.0
    phase = []
    event_index = 0
    for t in times:
        while event_index + 1 < len(events) and t >= events[event_index + 1]:
            event_index += 1
        phi = (t - events[event_index]) / avg_period
        phi = phi - math.floor(phi)
        phase.append(phi)
    return phase, avg_period


def compute_phase_from_autocorr(times: List[float], values: List[float]) -> Tuple[List[float], float]:
    if len(times) < 4 or len(values) != len(times):
        return [], 0.0
    duration = times[-1] - times[0]
    if duration <= 0:
        return [], 0.0
    n = len(values)
    mean = sum(values) / n
    centered = [v - mean for v in values]
    var = sum(v * v for v in centered)
    if var <= 1e-6:
        return [], 0.0

    dt = duration / n
    min_lag = max(2, int(0.2 / max(dt, 1e-6)))
    max_lag = min(n - 2, int(0.9 * n))
    best_lag = 0
    best_corr = -1e9
    corr_table: List[Tuple[int, float]] = []
    for lag in range(min_lag, max_lag + 1):
        corr = 0.0
        count = n - lag
        for i in range(count):
            corr += centered[i] * centered[i + lag]
        corr_table.append((lag, corr))
        if corr > best_corr:
            best_corr = corr
            best_lag = lag
    if corr_table:
        threshold = best_corr * 0.9
        preferred = [lag for lag, corr in corr_table if corr >= threshold]
        if preferred:
            best_lag = max(preferred)
    if best_lag <= 0:
        return [], 0.0

    period = best_lag * dt
    if period <= 0:
        return [], 0.0
    phase = []
    start = times[0]
    for t in times:
        phi = ((t - start) % period) / period
        phase.append(phi)
    return phase, period

def fit_fourier(phi: List[float], values: List[float], order: int) -> List[float]:
    count = len(phi)
    if count == 0:
        return [0.0] * (1 + order * 2)
    inv_count = 1.0 / count
    two_over_count = 2.0 * inv_count
    a0 = sum(values) * inv_count
    out = [a0]
    for k in range(1, order + 1):
        cos_sum = 0.0
        sin_sum = 0.0
        freq = 2.0 * math.pi * k
        for p, v in zip(phi, values):
            angle = freq * p
            cos_sum += v * math.cos(angle)
            sin_sum += v * math.sin(angle)
        out.append(cos_sum * two_over_count)
        out.append(sin_sum * two_over_count)
    return out


def sample_curve(curve: Optional[AnimationCurve], t_samples: List[float], default_value: float) -> List[float]:
    if curve is None:
        return [default_value for _ in t_samples]
    return [curve.sample(float(t)) for t in t_samples]


def fit_fbx_to_fourier(fbx_path: Path,
                       output_path: Path,
                       clip_name: str,
                       fps: int,
                       order: int,
                       skeleton_swift: Optional[Path]) -> None:
    text = fbx_path.read_text(encoding="utf-8")
    bone_anims, duration = build_bone_curves(text)

    sample_count = max(2, int(duration * fps))
    t_samples = [(i / sample_count) * duration for i in range(sample_count)]
    phi = [i / sample_count for i in range(sample_count)]
    phase_mode = "normalized_time"
    cycle_duration = duration
    contacts_left: List[float] = []
    contacts_right: List[float] = []
    left_y: List[float] = []
    right_y: List[float] = []
    if skeleton_swift is not None and skeleton_swift.exists():
        skeleton = parse_skeleton_humanoid8(skeleton_swift)
        contacts_left, contacts_right, left_y, right_y = compute_foot_contacts(
            bone_anims,
            skeleton,
            t_samples,
            in_place=True
        )
        contact_phase, period = compute_phase_from_contacts(t_samples, contacts_left)
        if contact_phase:
            phi = contact_phase
            phase_mode = "left_foot_contact"
            cycle_duration = period
        else:
            contact_phase, period = compute_phase_from_contacts(t_samples, contacts_right)
            if contact_phase:
                phi = contact_phase
                phase_mode = "right_foot_contact"
                cycle_duration = period
            else:
                events = detect_minima_events(t_samples, left_y)
                contact_phase, period = compute_phase_from_events(t_samples, events)
                if contact_phase:
                    phi = contact_phase
                    phase_mode = "left_foot_min"
                    cycle_duration = period
                    if cycle_duration < duration * 0.75:
                        contact_phase, period = compute_phase_from_autocorr(t_samples, left_y)
                        if contact_phase:
                            phi = contact_phase
                            phase_mode = "left_foot_auto"
                            cycle_duration = period
                else:
                    events = detect_minima_events(t_samples, right_y)
                    contact_phase, period = compute_phase_from_events(t_samples, events)
                    if contact_phase:
                        phi = contact_phase
                        phase_mode = "right_foot_min"
                        cycle_duration = period
                        if cycle_duration < duration * 0.75:
                            contact_phase, period = compute_phase_from_autocorr(t_samples, right_y)
                            if contact_phase:
                                phi = contact_phase
                                phase_mode = "right_foot_auto"
                                cycle_duration = period
                    else:
                        contact_phase, period = compute_phase_from_autocorr(t_samples, left_y)
                        if contact_phase:
                            phi = contact_phase
                            phase_mode = "left_foot_auto"
                            cycle_duration = period

        if cycle_duration > 0:
            ratio = duration / cycle_duration
            if 1.8 <= ratio <= 2.2:
                cycle_duration = duration
                phase_mode = f"{phase_mode}_stride"
                phi = [(t % cycle_duration) / cycle_duration for t in t_samples]

    bones_out = {}
    for bone_name in sorted(bone_anims.keys()):
        anim = bone_anims[bone_name]
        entry = {}
        for channel in ("translation", "rotation"):
            axis_curves = anim.get(channel, {})
            channel_out = {}
            for axis in ("x", "y", "z"):
                curve = axis_curves.get(axis)
                if curve is None:
                    channel_out[axis] = None
                    continue
                values = sample_curve(curve, t_samples, default_value=0.0)
                coeffs = fit_fourier(phi, values, order)
                channel_out[axis] = coeffs
            entry[channel] = channel_out
        bones_out[bone_name] = entry

    contacts_out = None
    if contacts_left and contacts_right:
        contacts_out = {
            "left": fit_fourier(phi, contacts_left, order),
            "right": fit_fourier(phi, contacts_right, order),
            "threshold": 0.5,
        }

    payload = {
        "version": 1,
        "name": clip_name,
        "duration": float(duration),
        "order": order,
        "sample_fps": fps,
        "phase": {"mode": phase_mode, "cycle_duration": float(cycle_duration)},
        "units": {"rotation": "degrees", "translation": "fbx_local"},
        "bones": bones_out,
    }
    if contacts_out is not None:
        payload["contacts"] = contacts_out

    output_path.write_text(json.dumps(payload, indent=2, sort_keys=True), encoding="utf-8")


def main() -> None:
    parser = argparse.ArgumentParser(description="Fit FBX animation curves to Fourier coefficients.")
    parser.add_argument("--fbx", required=True, help="Path to ASCII FBX file")
    parser.add_argument("--out", required=True, help="Output JSON path")
    parser.add_argument("--name", default="Walking", help="Clip name")
    parser.add_argument("--fps", type=int, default=60, help="Sampling FPS")
    parser.add_argument("--order", type=int, default=4, help="Fourier order")
    parser.add_argument("--skeleton-swift", default=None, help="Path to Skeleton.swift for phase/contact extraction")
    args = parser.parse_args()

    swift_path = Path(args.skeleton_swift) if args.skeleton_swift else None
    fit_fbx_to_fourier(Path(args.fbx), Path(args.out), args.name, args.fps, args.order, swift_path)


if __name__ == "__main__":
    main()
