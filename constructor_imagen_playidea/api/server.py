from __future__ import annotations

import math
import base64
import binascii
import uuid
from typing import Annotated

import cv2
import numpy as np
from fastapi import FastAPI, File, Form, HTTPException, UploadFile
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel


app = FastAPI(title="Play Idea Constructor desde Imágenes", version="0.3.0")
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)


@app.get("/health")
def health() -> dict:
    return {"ok": True, "service": "constructor_imagen_playidea", "version": "0.3.0"}


class EncodedImage(BaseModel):
    name: str
    data_url: str


class JsonAnalysisRequest(BaseModel):
    case_id: str = "sin_codigo"
    module_internal_mm: float = 1168.4
    images: list[EncodedImage]


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
        confidence = min(0.99, 0.22 + (span / height) * 0.95 + min(len(cluster), 6) * 0.055)
        candidates.append({
            "x_px": round(center_mean, 1),
            "top_y_px": int(top),
            "bottom_y_px": int(bottom),
            "span_px": int(span),
            "segment_count": len(cluster),
            "confidence": round(confidence, 2),
        })
    return candidates


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
            raw_segments.append(
                {
                    "x1": x1,
                    "y1": y1,
                    "x2": x2,
                    "y2": y2,
                    "length_px": round(length, 1),
                    "angle_deg": round(angle, 1),
                    "kind": kind,
                }
            )

    raw_segments.sort(key=lambda item: item["length_px"], reverse=True)
    segments = [segment for segment in raw_segments if not is_presentation_border(segment, width, height)]
    counts = {kind: sum(1 for segment in segments if segment["kind"] == kind) for kind in ("horizontal", "vertical", "diagonal")}
    post_candidates = build_post_candidates(segments, width, height)
    return {
        "filename": filename,
        "original_size": {"width": original_width, "height": original_height},
        "analysis_size": {"width": width, "height": height},
        "edge_pixels": int(np.count_nonzero(edges)),
        "raw_line_counts": raw_counts,
        "line_counts": counts,
        "discarded_border_segments": len(raw_segments) - len(segments),
        "post_candidates": post_candidates,
        "strongest_segments": segments[:120],
        "overlay_data_url": annotated_preview(image, segments, post_candidates),
    }


def analysis_response(views: list[dict], case_id: str, module_internal_mm: float) -> dict:
    totals = {key: sum(view["line_counts"][key] for view in views) for key in ("horizontal", "vertical", "diagonal")}
    return {
        "analysis_id": str(uuid.uuid4()),
        "case_id": case_id,
        "module_internal_mm": module_internal_mm,
        "image_count": len(views),
        "stage": "geometric_features",
        "totals": totals,
        "views": views,
        "next_stage": "calibrate_multiview_grid",
    }


@app.post("/analyze-json")
def analyze_json(payload: JsonAnalysisRequest) -> dict:
    if not 1 <= len(payload.images) <= 8:
        raise HTTPException(status_code=422, detail="Se requieren entre 1 y 8 imágenes.")
    if payload.module_internal_mm <= 0:
        raise HTTPException(status_code=422, detail="El módulo interior debe ser mayor que cero.")

    views = []
    for image in payload.images:
        try:
            encoded = image.data_url.split(",", 1)[1] if "," in image.data_url else image.data_url
            raw = base64.b64decode(encoded, validate=True)
        except (ValueError, binascii.Error):
            raise HTTPException(status_code=422, detail=f"Los datos de {image.name} no son Base64 válido.")
        if len(raw) > 25 * 1024 * 1024:
            raise HTTPException(status_code=413, detail=f"{image.name} supera 25 MB.")
        views.append(analyze_image(raw, image.name or "imagen"))
    return analysis_response(views, payload.case_id, payload.module_internal_mm)


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
    for image in images:
        raw = await image.read()
        if len(raw) > 25 * 1024 * 1024:
            raise HTTPException(status_code=413, detail=f"{image.filename} supera 25 MB.")
        views.append(analyze_image(raw, image.filename or "imagen"))

    return analysis_response(views, case_id, module_internal_mm)
