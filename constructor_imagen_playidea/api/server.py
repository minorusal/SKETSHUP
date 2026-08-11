from __future__ import annotations

import math
import base64
import binascii
import uuid
import json
from pathlib import Path
from typing import Annotated

import cv2
import numpy as np
from fastapi import FastAPI, File, Form, HTTPException, UploadFile
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel


app = FastAPI(title="Play Idea Constructor desde Imágenes", version="0.9.0")
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)


@app.get("/health")
def health() -> dict:
    return {"ok": True, "service": "constructor_imagen_playidea", "version": "0.9.0"}


class EncodedImage(BaseModel):
    name: str
    data_url: str


class JsonAnalysisRequest(BaseModel):
    case_id: str = "sin_codigo"
    module_internal_mm: float = 1168.4
    images: list[EncodedImage]


class TrainingExampleRequest(BaseModel):
    analysis_id: str
    module_internal_mm: float = 1168.4
    images: list[EncodedImage]
    views: list[dict]
    anchor_views: dict
    correspondences: list[dict]


def training_dataset_dir() -> Path:
    return Path.home() / "Library" / "Application Support" / "PlayIdea" / "constructor_imagen_dataset"


@app.post("/training-example")
def save_training_example(payload: TrainingExampleRequest) -> dict:
    if len(payload.images) != len(payload.views):
        raise HTTPException(status_code=422, detail="Cada imagen necesita sus anotaciones de postes.")
    if len(payload.correspondences) < 4:
        raise HTTPException(status_code=422, detail="Se requieren al menos cuatro correspondencias confirmadas.")

    example_id = f"ejemplo_{uuid.uuid4().hex[:12]}"
    example_dir = training_dataset_dir() / example_id
    example_dir.mkdir(parents=True, exist_ok=False)
    image_records = []
    try:
        for index, image in enumerate(payload.images, start=1):
            encoded = image.data_url.split(",", 1)[1] if "," in image.data_url else image.data_url
            raw = base64.b64decode(encoded, validate=True)
            suffix = Path(image.name).suffix.lower()
            suffix = suffix if suffix in {".jpg", ".jpeg", ".png", ".webp"} else ".png"
            filename = f"vista_{index:02d}{suffix}"
            (example_dir / filename).write_bytes(raw)
            image_records.append({"index": index, "original_name": image.name, "file": filename})

        annotation = {
            "schema_version": 1,
            "example_id": example_id,
            "analysis_id": payload.analysis_id,
            "module_internal_mm": payload.module_internal_mm,
            "images": image_records,
            "views": payload.views,
            "anchor_views": payload.anchor_views,
            "correspondences": payload.correspondences,
            "labels": {"post": "poste estructural vertical", "endpoint_order": ["top", "bottom"]},
        }
        (example_dir / "annotations.json").write_text(
            json.dumps(annotation, ensure_ascii=False, indent=2), encoding="utf-8"
        )
    except (ValueError, binascii.Error, OSError) as error:
        raise HTTPException(status_code=422, detail=f"No se pudo guardar el ejemplo: {error}")
    return {"ok": True, "example_id": example_id, "path": str(example_dir)}


def classify_angle(angle_deg: float) -> str:
    absolute = abs(angle_deg)
    if absolute <= 12 or absolute >= 168:
        return "horizontal"
    if 78 <= absolute <= 102:
        return "vertical"
    return "diagonal"


def is_presentation_border(segment: dict, width: int, height: int) -> bool:
    margin_x = width * 0.04
    margin_y = height * 0.04
    long_horizontal = segment["length_px"] >= width * 0.18
    long_vertical = segment["length_px"] >= height * 0.18
    on_top_or_bottom = (
        max(segment["y1"], segment["y2"]) <= margin_y
        or min(segment["y1"], segment["y2"]) >= height - margin_y
    )
    on_left_or_right = (
        max(segment["x1"], segment["x2"]) <= margin_x
        or min(segment["x1"], segment["x2"]) >= width - margin_x
    )
    return (long_horizontal and on_top_or_bottom) or (long_vertical and on_left_or_right)


def segment_blue_ratio(hsv: np.ndarray, segment: dict) -> float:
    height, width = hsv.shape[:2]
    samples = max(16, min(64, round(segment["length_px"] / 8)))
    xs = np.linspace(segment["x1"], segment["x2"], samples).round().astype(int)
    ys = np.linspace(segment["y1"], segment["y2"], samples).round().astype(int)
    blue, total = 0, 0
    for x, y in zip(xs, ys):
        x0, x1 = max(0, x - 2), min(width, x + 3)
        y0, y1 = max(0, y - 2), min(height, y + 3)
        patch = hsv[y0:y1, x0:x1]
        hue, saturation, value = patch[:, :, 0], patch[:, :, 1], patch[:, :, 2]
        blue += int(np.count_nonzero((hue >= 85) & (hue <= 135) & (saturation >= 70) & (value >= 35)))
        total += patch.shape[0] * patch.shape[1]
    return round(blue / total, 3) if total else 0.0


def build_post_candidates(segments: list[dict], width: int, height: int) -> list[dict]:
    verticals = [
        segment for segment in segments
        if segment["kind"] == "vertical" and segment["length_px"] >= height * 0.045
    ]
    tolerance = max(8.0, width * 0.012)
    clusters: list[list[dict]] = []
    for segment in sorted(verticals, key=lambda item: (item["x1"] + item["x2"]) / 2.0):
        center = (segment["x1"] + segment["x2"]) / 2.0
        previous_center = np.mean([
            (item["x1"] + item["x2"]) / 2.0 for item in clusters[-1]
        ]) if clusters else None
        if previous_center is None or center - previous_center > tolerance:
            clusters.append([segment])
        else:
            clusters[-1].append(segment)

    candidates = []
    for cluster in clusters:
        centers = [(item["x1"] + item["x2"]) / 2.0 for item in cluster]
        center_mean = float(np.mean(centers))
        if center_mean <= width * 0.04 or center_mean >= width * 0.96:
            continue
        ys = [coordinate for item in cluster for coordinate in (item["y1"], item["y2"])]
        top, bottom = min(ys), max(ys)
        span = bottom - top
        longest = max(item["length_px"] for item in cluster)
        if span < height * 0.10 and longest < height * 0.08:
            continue
        total_length = sum(item["length_px"] for item in cluster)
        blue_ratio = sum(item["blue_ratio"] * item["length_px"] for item in cluster) / total_length
        structural_blue = blue_ratio >= 0.12
        confidence = min(0.99, 0.18 + (span / height) * 0.82 + min(len(cluster), 6) * 0.045 + min(blue_ratio, 0.5) * 0.7)
        candidates.append({
            "x_px": round(center_mean, 1),
            "top_y_px": int(top),
            "bottom_y_px": int(bottom),
            "span_px": int(span),
            "segment_count": len(cluster),
            "blue_ratio": round(blue_ratio, 3),
            "structural_blue": structural_blue,
            "confidence": round(confidence, 2),
        })
    return candidates


def projected_grid_groups(posts: list[dict], module_internal_mm: float, image_height: int) -> list[dict]:
    selected = sorted(
        [post for post in posts if post["structural_blue"] and post["confidence"] >= 0.45],
        key=lambda post: (post["bottom_y_px"], post["top_y_px"]),
    )
    if len(selected) < 2:
        return []
    rows: list[list[dict]] = []
    for post in selected:
        matching = None
        for row in rows:
            mean_bottom = np.mean([item["bottom_y_px"] for item in row])
            mean_top = np.mean([item["top_y_px"] for item in row])
            if abs(post["bottom_y_px"] - mean_bottom) <= image_height * 0.09 and abs(post["top_y_px"] - mean_top) <= image_height * 0.15:
                matching = row
                break
        if matching is None:
            rows.append([post])
        else:
            matching.append(post)

    groups = []
    for row in rows:
        row.sort(key=lambda post: post["x_px"])
        if len(row) < 2:
            continue
        gaps = np.diff([post["x_px"] for post in row])
        upper = np.percentile(gaps, 75)
        compact = gaps[gaps <= upper]
        typical = float(np.median(compact if len(compact) else gaps))
        current = [row[0]]
        for post, gap in zip(row[1:], gaps):
            if gap > typical * 2.4:
                if len(current) >= 2:
                    groups.append(current)
                current = [post]
            else:
                current.append(post)
        if len(current) >= 2:
            groups.append(current)
    return [{
        "post_count": len(group),
        "provisional_bay_count": len(group) - 1,
        "projected_step_px": round(float(np.median(np.diff([post["x_px"] for post in group]))), 1),
        "span_px": round(group[-1]["x_px"] - group[0]["x_px"], 1),
        "module_internal_mm": module_internal_mm,
        "confidence": 0.45,
    } for group in groups]


def annotated_preview(image: np.ndarray, segments: list[dict], posts: list[dict]) -> str:
    overlay = image.copy()
    height, width = overlay.shape[:2]
    margin_x, margin_y = round(width * 0.04), round(height * 0.04)
    cv2.rectangle(overlay, (margin_x, margin_y), (width - margin_x, height - margin_y), (255, 180, 0), 2)
    colors = {"horizontal": (50, 210, 50), "vertical": (40, 40, 240), "diagonal": (0, 210, 255)}
    for segment in segments[:100]:
        cv2.line(
            overlay,
            (segment["x1"], segment["y1"]),
            (segment["x2"], segment["y2"]),
            colors[segment["kind"]],
            2,
            cv2.LINE_AA,
        )
    for index, post in enumerate(posts, start=1):
        x = round(post["x_px"])
        cv2.line(overlay, (x, post["top_y_px"]), (x, post["bottom_y_px"]), (255, 0, 220), 3)
        cv2.circle(overlay, (x, post["bottom_y_px"]), 6, (255, 0, 220), -1)
        cv2.putText(overlay, str(index), (x + 5, post["top_y_px"] + 13), cv2.FONT_HERSHEY_SIMPLEX, 0.42, (90, 0, 80), 1, cv2.LINE_AA)
    preview_scale = min(1.0, 1000.0 / max(width, height))
    if preview_scale < 1.0:
        overlay = cv2.resize(overlay, None, fx=preview_scale, fy=preview_scale, interpolation=cv2.INTER_AREA)
    ok, encoded = cv2.imencode(".jpg", overlay, [cv2.IMWRITE_JPEG_QUALITY, 82])
    if not ok:
        return ""
    return "data:image/jpeg;base64," + base64.b64encode(encoded.tobytes()).decode("ascii")


def analyze_image(raw: bytes, filename: str) -> dict:
    encoded = np.frombuffer(raw, dtype=np.uint8)
    image = cv2.imdecode(encoded, cv2.IMREAD_COLOR)
    if image is None:
        raise HTTPException(status_code=422, detail=f"No se pudo leer {filename} como imagen.")

    original_height, original_width = image.shape[:2]
    scale = min(1.0, 1600.0 / max(original_width, original_height))
    if scale < 1.0:
        image = cv2.resize(image, None, fx=scale, fy=scale, interpolation=cv2.INTER_AREA)
    height, width = image.shape[:2]

    gray = cv2.cvtColor(image, cv2.COLOR_BGR2GRAY)
    hsv = cv2.cvtColor(image, cv2.COLOR_BGR2HSV)
    gray = cv2.GaussianBlur(gray, (5, 5), 0)
    edges = cv2.Canny(gray, 55, 165)
    minimum = max(30, round(min(width, height) * 0.035))
    lines = cv2.HoughLinesP(
        edges,
        1,
        np.pi / 180,
        threshold=45,
        minLineLength=minimum,
        maxLineGap=max(8, round(minimum * 0.35)),
    )

    raw_segments = []
    raw_counts = {"horizontal": 0, "vertical": 0, "diagonal": 0}
    if lines is not None:
        for packed in lines[:, 0]:
            x1, y1, x2, y2 = [int(value) for value in packed]
            dx, dy = x2 - x1, y2 - y1
            length = math.hypot(dx, dy)
            angle = math.degrees(math.atan2(dy, dx))
            kind = classify_angle(angle)
            raw_counts[kind] += 1
            segment = {
                    "x1": x1,
                    "y1": y1,
                    "x2": x2,
                    "y2": y2,
                    "length_px": round(length, 1),
                    "angle_deg": round(angle, 1),
                    "kind": kind,
                }
            segment["blue_ratio"] = segment_blue_ratio(hsv, segment)
            raw_segments.append(segment)

    raw_segments.sort(key=lambda item: item["length_px"], reverse=True)
    segments = [segment for segment in raw_segments if not is_presentation_border(segment, width, height)]
    counts = {kind: sum(1 for segment in segments if segment["kind"] == kind) for kind in ("horizontal", "vertical", "diagonal")}
    post_candidates = build_post_candidates(segments, width, height)
    grid_groups = projected_grid_groups(post_candidates, 1168.4, height)
    return {
        "filename": filename,
        "original_size": {"width": original_width, "height": original_height},
        "analysis_size": {"width": width, "height": height},
        "edge_pixels": int(np.count_nonzero(edges)),
        "raw_line_counts": raw_counts,
        "line_counts": counts,
        "discarded_border_segments": len(raw_segments) - len(segments),
        "post_candidates": post_candidates,
        "projected_grid_groups": grid_groups,
        "strongest_segments": segments[:120],
        "overlay_data_url": annotated_preview(image, segments, post_candidates),
    }


def multiview_correspondence(raw_images: list[tuple[bytes, str]], views: list[dict]) -> dict:
    orb = cv2.ORB_create(nfeatures=2200, scaleFactor=1.2, nlevels=8)
    features = []
    for raw, _name in raw_images:
        image = cv2.imdecode(np.frombuffer(raw, dtype=np.uint8), cv2.IMREAD_GRAYSCALE)
        height, width = image.shape[:2]
        image = image[round(height * 0.06):round(height * 0.90), round(width * 0.06):round(width * 0.94)]
        scale = min(1.0, 1100.0 / max(image.shape[:2]))
        if scale < 1.0:
            image = cv2.resize(image, None, fx=scale, fy=scale, interpolation=cv2.INTER_AREA)
        keypoints, descriptors = orb.detectAndCompute(image, None)
        features.append((keypoints, descriptors))

    matcher = cv2.BFMatcher(cv2.NORM_HAMMING)
    pairs = []
    for left in range(len(features)):
        for right in range(left + 1, len(features)):
            left_points, left_desc = features[left]
            right_points, right_desc = features[right]
            good, inliers = [], 0
            if left_desc is not None and right_desc is not None:
                for match_pair in matcher.knnMatch(left_desc, right_desc, k=2):
                    if len(match_pair) == 2 and match_pair[0].distance < 0.74 * match_pair[1].distance:
                        good.append(match_pair[0])
            if len(good) >= 8:
                points_left = np.float32([left_points[match.queryIdx].pt for match in good])
                points_right = np.float32([right_points[match.trainIdx].pt for match in good])
                _fundamental, mask = cv2.findFundamentalMat(points_left, points_right, cv2.FM_RANSAC, 1.8, 0.995)
                inliers = int(mask.sum()) if mask is not None else 0
            pairs.append({
                "view_a": left + 1,
                "view_b": right + 1,
                "good_matches": len(good),
                "geometric_inliers": inliers,
                "confidence": round(min(0.98, inliers / 40.0), 2),
            })
    front_index = max(range(len(views)), key=lambda index: views[index]["line_counts"]["vertical"])
    depth_index = max(range(len(views)), key=lambda index: views[index]["line_counts"]["diagonal"])
    strong_pairs = [pair for pair in pairs if pair["geometric_inliers"] >= 12]
    return {
        "front_anchor_view": front_index + 1,
        "depth_anchor_view": depth_index + 1,
        "pair_count": len(pairs),
        "strong_pair_count": len(strong_pairs),
        "pairs": pairs,
        "status": "ready_for_topology" if len(strong_pairs) >= 2 else "needs_manual_correspondence",
    }


def strongest_grid(view: dict) -> dict | None:
    groups = view.get("projected_grid_groups", [])
    return max(groups, key=lambda group: (group["post_count"], group["span_px"]), default=None)


def inferred_levels(view: dict, grid: dict | None) -> int:
    if not grid or grid["projected_step_px"] <= 0:
        return 1
    structural = [post for post in view["post_candidates"] if post["structural_blue"]]
    if not structural:
        return 1
    median_height = float(np.median([post["span_px"] for post in structural]))
    # En una proyección, la separación horizontal es la única escala local
    # disponible. El resultado es provisional y queda editable en la UI.
    return max(1, min(6, round(median_height / grid["projected_step_px"])))


def build_metric_plan(module_internal_mm: float, views: list[dict], multiview: dict) -> dict:
    front = views[multiview["front_anchor_view"] - 1]
    depth = views[multiview["depth_anchor_view"] - 1]
    front_grid = strongest_grid(front)
    depth_grid = strongest_grid(depth)
    if front_grid is None and depth_grid is None:
        return {
            "status": "insufficient_structural_signal",
            "module_internal_mm": module_internal_mm,
            "grid_width_modules": 0,
            "grid_depth_modules": 0,
            "zones": [],
            "message": "No se detectó una cuadrícula estructural confiable; no se generó una plantilla de otro juego.",
        }

    primary = front_grid or depth_grid
    width = max(1, int(primary["provisional_bay_count"]))
    depth_count = int(depth_grid["provisional_bay_count"]) if depth_grid else 1
    depth_count = max(1, depth_count)
    levels = inferred_levels(front, front_grid)
    confidence = round(min(primary["confidence"], 0.65), 2)
    zone = {
        "id": "estructura_detectada_1",
        "label": "Estructura detectada 1",
        "kind": "modular",
        "x": 0,
        "y": 0,
        "width": width,
        "depth": depth_count,
        "levels": levels,
        "confidence": confidence,
        "source": "opencv_post_grid",
    }
    return {
        "status": "editable_detected",
        "module_internal_mm": module_internal_mm,
        "grid_width_modules": width,
        "grid_depth_modules": depth_count,
        "zones": [zone],
        "message": "Dimensiones estimadas desde postes y crujías; confirma la cuadrícula antes de construir.",
    }


def build_topological_plan(module_internal_mm: float, metric_plan: dict, multiview: dict) -> dict:
    zones = metric_plan["zones"]
    if not zones:
        return {"status": metric_plan["status"], "source": "opencv", "module_internal_mm": module_internal_mm, "nodes": [], "edges": []}
    nodes = []
    for index, zone in enumerate(zones):
        nodes.append({
            "id": zone["id"],
            "label": zone["label"],
            "kind": zone["kind"],
            "x": 50 if len(zones) == 1 else 15 + index * 70 / max(1, len(zones) - 1),
            "y": 50,
            "levels": zone["levels"],
            "confidence": zone.get("confidence", 0.45),
        })
    return {
        "status": "topology_detected" if multiview["status"] == "ready_for_topology" else "provisional",
        "source": "opencv_post_grid",
        "module_internal_mm": module_internal_mm,
        "nodes": nodes,
        "edges": [],
    }


def analysis_response(views: list[dict], case_id: str, module_internal_mm: float, multiview: dict) -> dict:
    totals = {key: sum(view["line_counts"][key] for view in views) for key in ("horizontal", "vertical", "diagonal")}
    metric_plan = build_metric_plan(module_internal_mm, views, multiview)
    return {
        "analysis_id": str(uuid.uuid4()),
        "case_id": case_id,
        "module_internal_mm": module_internal_mm,
        "image_count": len(views),
        "stage": "geometric_features",
        "totals": totals,
        "views": views,
        "multiview": multiview,
        "topology": build_topological_plan(module_internal_mm, metric_plan, multiview),
        "metric_plan": metric_plan,
        "next_stage": "confirm_metric_grid" if metric_plan["zones"] else "request_clearer_views",
    }


@app.post("/analyze-json")
def analyze_json(payload: JsonAnalysisRequest) -> dict:
    if not 1 <= len(payload.images) <= 8:
        raise HTTPException(status_code=422, detail="Se requieren entre 1 y 8 imágenes.")
    if payload.module_internal_mm <= 0:
        raise HTTPException(status_code=422, detail="El módulo interior debe ser mayor que cero.")

    views = []
    raw_images = []
    for image in payload.images:
        try:
            encoded = image.data_url.split(",", 1)[1] if "," in image.data_url else image.data_url
            raw = base64.b64decode(encoded, validate=True)
        except (ValueError, binascii.Error):
            raise HTTPException(status_code=422, detail=f"Los datos de {image.name} no son Base64 válido.")
        if len(raw) > 25 * 1024 * 1024:
            raise HTTPException(status_code=413, detail=f"{image.name} supera 25 MB.")
        views.append(analyze_image(raw, image.name or "imagen"))
        raw_images.append((raw, image.name or "imagen"))
    multiview = multiview_correspondence(raw_images, views)
    return analysis_response(views, payload.case_id, payload.module_internal_mm, multiview)


@app.post("/analyze")
async def analyze(
    images: Annotated[list[UploadFile], File(...)],
    case_id: Annotated[str, Form()] = "sin_codigo",
    module_internal_mm: Annotated[float, Form()] = 1168.4,
) -> dict:
    if not 1 <= len(images) <= 8:
        raise HTTPException(status_code=422, detail="Se requieren entre 1 y 8 imágenes.")
    if module_internal_mm <= 0:
        raise HTTPException(status_code=422, detail="El módulo interior debe ser mayor que cero.")

    views = []
    raw_images = []
    for image in images:
        raw = await image.read()
        if len(raw) > 25 * 1024 * 1024:
            raise HTTPException(status_code=413, detail=f"{image.filename} supera 25 MB.")
        views.append(analyze_image(raw, image.filename or "imagen"))
        raw_images.append((raw, image.filename or "imagen"))

    multiview = multiview_correspondence(raw_images, views)
    return analysis_response(views, case_id, module_internal_mm, multiview)
