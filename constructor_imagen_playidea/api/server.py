from __future__ import annotations

import math
import uuid
from typing import Annotated

import cv2
import numpy as np
from fastapi import FastAPI, File, Form, HTTPException, UploadFile
from fastapi.middleware.cors import CORSMiddleware


app = FastAPI(title="Play Idea Constructor desde Imágenes", version="0.2.1")
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)


@app.get("/health")
def health() -> dict:
    return {"ok": True, "service": "constructor_imagen_playidea", "version": "0.2.1"}


def classify_angle(angle_deg: float) -> str:
    absolute = abs(angle_deg)
    if absolute <= 12 or absolute >= 168:
        return "horizontal"
    if 78 <= absolute <= 102:
        return "vertical"
    return "diagonal"


def cluster_positions(values: list[float], tolerance_px: float) -> list[float]:
    if not values:
        return []
    clusters: list[list[float]] = []
    for value in sorted(values):
        if not clusters or value - np.mean(clusters[-1]) > tolerance_px:
            clusters.append([value])
        else:
            clusters[-1].append(value)
    return [round(float(np.mean(cluster)), 1) for cluster in clusters]


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

    segments = []
    counts = {"horizontal": 0, "vertical": 0, "diagonal": 0}
    vertical_centers = []
    if lines is not None:
        for packed in lines[:, 0]:
            x1, y1, x2, y2 = [int(value) for value in packed]
            dx, dy = x2 - x1, y2 - y1
            length = math.hypot(dx, dy)
            angle = math.degrees(math.atan2(dy, dx))
            kind = classify_angle(angle)
            counts[kind] += 1
            if kind == "vertical":
                vertical_centers.append((x1 + x2) / 2.0)
            segments.append(
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

    segments.sort(key=lambda item: item["length_px"], reverse=True)
    post_candidates = cluster_positions(vertical_centers, max(8.0, width * 0.012))
    return {
        "filename": filename,
        "original_size": {"width": original_width, "height": original_height},
        "analysis_size": {"width": width, "height": height},
        "edge_pixels": int(np.count_nonzero(edges)),
        "line_counts": counts,
        "post_candidate_x_px": post_candidates,
        "strongest_segments": segments[:120],
    }


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
