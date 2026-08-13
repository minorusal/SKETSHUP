from __future__ import annotations

import math
import base64
import binascii
import uuid
import json
import hashlib
import threading
import shutil
from datetime import datetime, timezone
from pathlib import Path
from typing import Annotated

import cv2
import numpy as np
from fastapi import FastAPI, File, Form, HTTPException, UploadFile
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import FileResponse
from pydantic import BaseModel, Field


app = FastAPI(title="Play Idea Constructor desde Imágenes", version="0.23.0")
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)


@app.get("/health")
def health() -> dict:
    return {"ok": True, "service": "constructor_imagen_playidea", "version": "0.23.0"}


class EncodedImage(BaseModel):
    name: str
    data_url: str


class JsonAnalysisRequest(BaseModel):
    case_id: str = "sin_codigo"
    module_internal_mm: float = 1168.4
    images: list[EncodedImage]
    known_dimensions: dict = Field(default_factory=dict)


class TrainingExampleRequest(BaseModel):
    analysis_id: str
    module_internal_mm: float = 1168.4
    images: list[EncodedImage]
    views: list[dict]
    anchor_views: dict
    correspondences: list[dict]
    known_dimensions: dict = Field(default_factory=dict)


class BatchAnalysisRequest(BaseModel):
    root_path: str
    max_images: int = 10_000


class ReviewDecisionRequest(BaseModel):
    record_name: str
    decision: str
    posts: list[dict] = Field(default_factory=list)


class MaskAnnotationRequest(BaseModel):
    image: EncodedImage
    structure_mask_data_url: str
    ignore_mask_data_url: str
    cleaned_image_data_url: str
    lines: list[dict] = Field(default_factory=list)
    image_width: int
    image_height: int


def training_dataset_dir() -> Path:
    return Path.home() / "Library" / "Application Support" / "PlayIdea" / "constructor_imagen_dataset"


def decode_data_url(data_url: str) -> bytes:
    encoded = data_url.split(",", 1)[1] if "," in data_url else data_url
    return base64.b64decode(encoded, validate=True)


@app.post("/mask-annotation")
def save_mask_annotation(payload: MaskAnnotationRequest) -> dict:
    if not 1 <= payload.image_width <= 12_000 or not 1 <= payload.image_height <= 12_000:
        raise HTTPException(status_code=422, detail="Dimensiones de imagen inválidas.")
    allowed_types = {"z", "x", "y", "diagonal"}
    normalized_lines = []
    for index, line in enumerate(payload.lines):
        try:
            line_type = str(line["type"]).lower()
            x1, y1, x2, y2 = (float(line[key]) for key in ("x1", "y1", "x2", "y2"))
        except (KeyError, TypeError, ValueError):
            raise HTTPException(status_code=422, detail=f"Línea {index + 1} inválida.")
        if line_type not in allowed_types:
            raise HTTPException(status_code=422, detail=f"Tipo de línea {line_type} inválido.")
        if not all((0 <= x1 <= payload.image_width, 0 <= x2 <= payload.image_width, 0 <= y1 <= payload.image_height, 0 <= y2 <= payload.image_height)):
            raise HTTPException(status_code=422, detail=f"Línea {index + 1} fuera de la imagen.")
        if math.hypot(x2 - x1, y2 - y1) < 4:
            continue
        normalized_lines.append({"index": len(normalized_lines), "type": line_type, "x1": x1, "y1": y1, "x2": x2, "y2": y2, "confirmed": True})
    example_id = f"mascara_{uuid.uuid4().hex[:12]}"
    directory = training_dataset_dir() / "mask_annotations" / example_id
    directory.mkdir(parents=True, exist_ok=False)
    try:
        original = decode_data_url(payload.image.data_url)
        structure_mask = decode_data_url(payload.structure_mask_data_url)
        ignore_mask = decode_data_url(payload.ignore_mask_data_url)
        cleaned = decode_data_url(payload.cleaned_image_data_url)
        (directory / "original.png").write_bytes(original)
        (directory / "structure_mask.png").write_bytes(structure_mask)
        (directory / "ignore_mask.png").write_bytes(ignore_mask)
        (directory / "cleaned.png").write_bytes(cleaned)
        annotation = {
            "schema_version": 1, "example_id": example_id,
            "source": "user_mask_ground_truth", "original_name": payload.image.name,
            "image_width": payload.image_width, "image_height": payload.image_height,
            "files": {"original": "original.png", "structure_mask": "structure_mask.png", "ignore_mask": "ignore_mask.png", "cleaned": "cleaned.png"},
            "lines": normalized_lines,
            "line_counts": {line_type: sum(1 for line in normalized_lines if line["type"] == line_type) for line_type in allowed_types},
            "training_policy": "confirmed_masks_and_axes_only",
        }
        (directory / "annotations.json").write_text(json.dumps(annotation, ensure_ascii=False, indent=2), encoding="utf-8")
    except (ValueError, binascii.Error, OSError) as error:
        shutil.rmtree(directory, ignore_errors=True)
        raise HTTPException(status_code=422, detail=f"No se pudo guardar la máscara: {error}")
    return {"ok": True, "example_id": example_id, "path": str(directory), "line_counts": annotation["line_counts"]}


POST_WINDOW = (32, 128)
POST_HOG = cv2.HOGDescriptor(POST_WINDOW, (16, 16), (8, 8), (8, 8), 9)
_post_model_cache: tuple[float, object] | None = None
_offset_model_cache: dict[str, tuple[float, object]] = {}
_training_mode = False
_batch_jobs: dict[str, dict] = {}
_batch_lock = threading.Lock()


def public_batch_job(job: dict) -> dict:
    return {key: value for key, value in job.items() if key != "root_path"}


def batch_import_dir(job_id: str) -> Path:
    return training_dataset_dir() / "batch_imports" / job_id


def save_batch_manifest(job: dict) -> None:
    output_dir = batch_import_dir(job["job_id"])
    output_dir.mkdir(parents=True, exist_ok=True)
    manifest = public_batch_job(job)
    manifest["root_path"] = job["root_path"]
    (output_dir / "manifest.json").write_text(
        json.dumps(manifest, ensure_ascii=False, indent=2), encoding="utf-8"
    )


def discover_images_tm(root: Path) -> list[Path]:
    matches = []
    if root.name.lower() == "images-tm":
        matches.append(root)
    matches.extend(path for path in root.rglob("*") if path.is_dir() and path.name.lower() == "images-tm")
    return sorted(set(matches))


def run_batch_analysis(job_id: str, max_images: int) -> None:
    job = _batch_jobs[job_id]
    extensions = {".jpg", ".jpeg", ".png", ".webp"}
    seen_hashes: set[str] = set()
    try:
        folders = discover_images_tm(Path(job["root_path"]))
        image_paths = []
        for folder in folders:
            image_paths.extend(path for path in folder.rglob("*") if path.is_file() and path.suffix.lower() in extensions)
        image_paths = sorted(image_paths)[:max_images]
        with _batch_lock:
            job.update({"status": "analyzing", "folders_found": len(folders), "images_found": len(image_paths)})
        output_dir = batch_import_dir(job_id)
        output_dir.mkdir(parents=True, exist_ok=True)
        for index, image_path in enumerate(image_paths, start=1):
            try:
                raw = image_path.read_bytes()
                digest = hashlib.sha256(raw).hexdigest()
                if digest in seen_hashes:
                    with _batch_lock:
                        job["duplicates"] += 1
                    continue
                seen_hashes.add(digest)
                view = analyze_image(raw, image_path.name)
                view.pop("overlay_data_url", None)
                structural = [post for post in view["post_candidates"] if post.get("structural_post", post.get("structural_colored", False))]
                mean_confidence = round(sum(post["confidence"] for post in structural) / len(structural), 3) if structural else 0.0
                confidence_class = "high_confidence" if len(structural) >= 4 and mean_confidence >= 0.72 and view["projected_grid_groups"] else "needs_review"
                record = {
                    "source_path": str(image_path), "project": image_path.parent.parent.name,
                    "sha256": digest, "confidence_class": confidence_class,
                    "structural_post_count": len(structural), "mean_post_confidence": mean_confidence,
                    "analysis": view,
                }
                record_name = f"image_{index:06d}_{digest[:10]}.json"
                (output_dir / record_name).write_text(json.dumps(record, ensure_ascii=False, indent=2), encoding="utf-8")
                with _batch_lock:
                    job["analyzed"] += 1
                    job[confidence_class] += 1
            except Exception as error:
                with _batch_lock:
                    job["errors"] += 1
                    if len(job["error_samples"]) < 20:
                        job["error_samples"].append({"path": str(image_path), "message": str(error)})
            finally:
                with _batch_lock:
                    job["processed"] = index
                if index % 10 == 0:
                    save_batch_manifest(job)
        with _batch_lock:
            job["status"] = "completed"
            job["finished_at"] = datetime.now(timezone.utc).isoformat()
        save_batch_manifest(job)
    except Exception as error:
        with _batch_lock:
            job["status"] = "failed"
            job["fatal_error"] = str(error)
            job["finished_at"] = datetime.now(timezone.utc).isoformat()
        save_batch_manifest(job)


@app.post("/batch-analysis")
def start_batch_analysis(payload: BatchAnalysisRequest) -> dict:
    root = Path(payload.root_path).expanduser().resolve()
    if not root.is_dir():
        raise HTTPException(status_code=422, detail="La carpeta raíz no existe o no es accesible.")
    if not 1 <= payload.max_images <= 100_000:
        raise HTTPException(status_code=422, detail="El límite debe estar entre 1 y 100000 imágenes.")
    active = next((job for job in _batch_jobs.values() if job["status"] in {"scanning", "analyzing"}), None)
    if active:
        raise HTTPException(status_code=409, detail=f"Ya está ejecutándose el lote {active['job_id']}.")
    job_id = f"batch_{uuid.uuid4().hex[:12]}"
    job = {
        "job_id": job_id, "root_path": str(root), "status": "scanning",
        "started_at": datetime.now(timezone.utc).isoformat(), "finished_at": None,
        "folders_found": 0, "images_found": 0, "processed": 0, "analyzed": 0,
        "duplicates": 0, "high_confidence": 0, "needs_review": 0, "errors": 0,
        "error_samples": [], "output_path": str(batch_import_dir(job_id)),
        "training_policy": "predictions_are_not_ground_truth",
    }
    with _batch_lock:
        _batch_jobs[job_id] = job
    threading.Thread(target=run_batch_analysis, args=(job_id, payload.max_images), daemon=True).start()
    return public_batch_job(job)


@app.get("/batch-analysis/{job_id}")
def batch_analysis_status(job_id: str) -> dict:
    job = _batch_jobs.get(job_id)
    if not job:
        raise HTTPException(status_code=404, detail="No se encontró ese análisis por lotes.")
    return public_batch_job(job)


def existing_batch_dir(job_id: str) -> Path:
    if not job_id.startswith("batch_") or not job_id.replace("batch_", "", 1).isalnum():
        raise HTTPException(status_code=422, detail="Identificador de lote inválido.")
    directory = training_dataset_dir() / "batch_imports" / job_id
    if not directory.is_dir():
        raise HTTPException(status_code=404, detail="No se encontró el lote guardado.")
    return directory


def existing_batch_record(job_id: str, record_name: str) -> tuple[Path, dict]:
    if not record_name.startswith("image_") or not record_name.endswith(".json") or Path(record_name).name != record_name:
        raise HTTPException(status_code=422, detail="Registro inválido.")
    path = existing_batch_dir(job_id) / record_name
    if not path.is_file():
        raise HTTPException(status_code=404, detail="No se encontró la imagen del lote.")
    return path, json.loads(path.read_text(encoding="utf-8"))


@app.get("/batch-review/{job_id}/items")
def batch_review_items(job_id: str, bucket: str = "high_confidence", limit: int = 50) -> dict:
    if bucket not in {"high_confidence", "needs_review", "all"}:
        raise HTTPException(status_code=422, detail="Categoría de revisión inválida.")
    items = []
    counts = {"pending": 0, "approved": 0, "rejected": 0}
    for path in sorted(existing_batch_dir(job_id).glob("image_*.json")):
        record = json.loads(path.read_text(encoding="utf-8"))
        decision = record.get("review", {}).get("decision", "pending")
        counts[decision] = counts.get(decision, 0) + 1
        if decision != "pending" or (bucket != "all" and record["confidence_class"] != bucket):
            continue
        posts = [post for post in record["analysis"]["post_candidates"] if post.get("structural_post", False)]
        items.append({
            "record_name": path.name, "filename": record["analysis"]["filename"],
            "source_path": record["source_path"], "project": record["project"],
            "confidence_class": record["confidence_class"], "mean_post_confidence": record["mean_post_confidence"],
            "analysis_size": record["analysis"]["analysis_size"], "posts": posts,
            "image_url": f"/batch-review/{job_id}/image/{path.name}",
        })
        if len(items) >= max(1, min(limit, 200)):
            break
    return {"job_id": job_id, "bucket": bucket, "counts": counts, "items": items}


@app.get("/batch-review/{job_id}/image/{record_name}")
def batch_review_image(job_id: str, record_name: str):
    _path, record = existing_batch_record(job_id, record_name)
    source = Path(record["source_path"])
    if not source.is_file():
        raise HTTPException(status_code=404, detail="La imagen original ya no existe.")
    return FileResponse(source)


@app.post("/batch-review/{job_id}/decision")
def batch_review_decision(job_id: str, payload: ReviewDecisionRequest) -> dict:
    if payload.decision not in {"approved", "rejected"}:
        raise HTTPException(status_code=422, detail="La decisión debe ser approved o rejected.")
    record_path, record = existing_batch_record(job_id, payload.record_name)
    if record.get("review", {}).get("decision") == "approved":
        return {"ok": True, "decision": "approved", "already_saved": True}
    example_path = None
    if payload.decision == "approved":
        if not payload.posts:
            raise HTTPException(status_code=422, detail="Dibuja por lo menos un poste antes de aprobar.")
        source = Path(record["source_path"])
        example_id = f"ejemplo_batch_{record['sha256'][:12]}"
        example_dir = training_dataset_dir() / example_id
        example_dir.mkdir(parents=True, exist_ok=True)
        image_name = f"vista_01{source.suffix.lower()}"
        shutil.copy2(source, example_dir / image_name)
        size = record["analysis"]["analysis_size"]
        annotation_posts = []
        for index, post in enumerate(payload.posts):
            try:
                x = float(post["x"]); top_y = float(post["top_y"]); bottom_y = float(post["bottom_y"])
            except (KeyError, TypeError, ValueError):
                raise HTTPException(status_code=422, detail="Una de las líneas dibujadas es inválida.")
            if not 0 <= x <= size["width"] or not 0 <= top_y < bottom_y <= size["height"]:
                raise HTTPException(status_code=422, detail="Una línea quedó fuera de la imagen.")
            annotation_posts.append({"post_index": index, "x": x, "top_y": top_y, "bottom_y": bottom_y, "confirmed": True})
        annotation = {
            "schema_version": 1, "example_id": example_id, "analysis_id": job_id,
            "module_internal_mm": 1168.4,
            "images": [{"index": 1, "original_name": source.name, "file": image_name}],
            "views": [{"view_index": 1, "image_width": size["width"], "image_height": size["height"], "posts": annotation_posts}],
            "anchor_views": {}, "correspondences": [], "training_scope": "post_detection",
            "known_dimensions": {}, "source": "batch_review_user_confirmed",
            "labels": {"post": "poste estructural vertical", "endpoint_order": ["top", "bottom"]},
        }
        (example_dir / "annotations.json").write_text(json.dumps(annotation, ensure_ascii=False, indent=2), encoding="utf-8")
        example_path = str(example_dir)
    record["review"] = {"decision": payload.decision, "reviewed_at": datetime.now(timezone.utc).isoformat(), "source": "user_confirmation", "confirmed_posts": payload.posts if payload.decision == "approved" else []}
    record_path.write_text(json.dumps(record, ensure_ascii=False, indent=2), encoding="utf-8")
    return {"ok": True, "decision": payload.decision, "example_path": example_path}


@app.post("/batch-review/{job_id}/train")
def batch_review_train(job_id: str) -> dict:
    existing_batch_dir(job_id)
    return train_post_detector()


def post_model_path() -> Path:
    return training_dataset_dir() / "models" / "post_detector.xml"


def offset_model_path(axis: str) -> Path:
    return training_dataset_dir() / "models" / f"post_offset_{axis}.xml"


def post_patch(image: np.ndarray, candidate: dict) -> np.ndarray:
    height, width = image.shape[:2]
    half_width = max(10, round(width * 0.018))
    x = round(candidate["x_px"])
    context_y = max(8, round((candidate["bottom_y_px"] - candidate["top_y_px"]) * 0.22))
    y1 = max(0, round(candidate["top_y_px"]) - context_y)
    y2 = min(height, round(candidate["bottom_y_px"]) + context_y)
    x1, x2 = max(0, x - half_width), min(width, x + half_width + 1)
    crop = image[y1:y2, x1:x2]
    if crop.size == 0:
        crop = np.zeros((POST_WINDOW[1], POST_WINDOW[0], 3), dtype=np.uint8)
    return cv2.resize(crop, POST_WINDOW, interpolation=cv2.INTER_AREA)


def post_descriptor(image: np.ndarray, candidate: dict) -> np.ndarray:
    gray = cv2.cvtColor(post_patch(image, candidate), cv2.COLOR_BGR2GRAY)
    return POST_HOG.compute(gray).reshape(-1).astype(np.float32)


def load_post_model():
    global _post_model_cache
    path = post_model_path()
    if not path.exists():
        return None
    modified = path.stat().st_mtime
    if _post_model_cache is None or _post_model_cache[0] != modified:
        _post_model_cache = (modified, cv2.ml.SVM_load(str(path)))
    return _post_model_cache[1]


def load_offset_model(axis: str):
    path = offset_model_path(axis)
    if not path.exists():
        return None
    modified = path.stat().st_mtime
    cached = _offset_model_cache.get(axis)
    if cached is None or cached[0] != modified:
        _offset_model_cache[axis] = (modified, cv2.ml.SVM_load(str(path)))
    return _offset_model_cache[axis][1]


def apply_learned_post_model(image: np.ndarray, candidates: list[dict]) -> None:
    model = load_post_model()
    offset_models = None if _training_mode else {axis: load_offset_model(axis) for axis in ("x", "top", "bottom")}
    height, width = image.shape[:2]
    for candidate in candidates:
        if model is None:
            candidate["structural_post"] = candidate["structural_colored"]
            candidate["detector_source"] = "color_heuristic"
            continue
        descriptor = post_descriptor(image, candidate).reshape(1, -1)
        _unused, prediction = model.predict(descriptor)
        candidate["structural_post"] = bool(prediction[0, 0] > 0)
        candidate["detector_source"] = "learned_hog_svm"
        if candidate["structural_post"] and offset_models and all(offset_models.values()):
            candidate["raw_x_px"] = candidate["x_px"]
            candidate["raw_top_y_px"] = candidate["top_y_px"]
            candidate["raw_bottom_y_px"] = candidate["bottom_y_px"]
            offsets = {}
            for axis, offset_model in offset_models.items():
                _unused, value = offset_model.predict(descriptor)
                offsets[axis] = float(value[0, 0])
            candidate["x_px"] = round(float(np.clip(candidate["x_px"] + offsets["x"] * width, 0, width - 1)), 1)
            candidate["top_y_px"] = int(np.clip(candidate["top_y_px"] + offsets["top"] * height, 0, height - 2))
            candidate["bottom_y_px"] = int(np.clip(candidate["bottom_y_px"] + offsets["bottom"] * height, candidate["top_y_px"] + 1, height - 1))
            candidate["span_px"] = candidate["bottom_y_px"] - candidate["top_y_px"]
            candidate["position_source"] = "learned_endpoint_regression"


def annotation_matches(candidate: dict, post: dict, width: int, height: int) -> bool:
    close_x = abs(candidate["x_px"] - post["x"]) <= max(10.0, width * 0.025)
    overlap = max(0.0, min(candidate["bottom_y_px"], post["bottom_y"]) - max(candidate["top_y_px"], post["top_y"]))
    annotated_span = max(1.0, post["bottom_y"] - post["top_y"])
    return close_x and overlap / annotated_span >= 0.45


def train_post_detector() -> dict:
    global _training_mode
    descriptors, labels = [], []
    positive_descriptors, offset_targets = [], {"x": [], "top": [], "bottom": []}
    example_count = 0
    _training_mode = True
    try:
        for annotation_path in sorted(training_dataset_dir().glob("ejemplo_*/annotations.json")):
            annotation = json.loads(annotation_path.read_text(encoding="utf-8"))
            example_count += 1
            for image_record, view in zip(annotation["images"], annotation["views"]):
                image = cv2.imread(str(annotation_path.parent / image_record["file"]))
                if image is None:
                    continue
                scale = min(1.0, 1600.0 / max(image.shape[:2]))
                if scale < 1.0:
                    image = cv2.resize(image, None, fx=scale, fy=scale, interpolation=cv2.INTER_AREA)
                analysis = analyze_image((annotation_path.parent / image_record["file"]).read_bytes(), image_record["file"])
                posts = view.get("posts", [])
                for candidate in analysis["post_candidates"]:
                    matches = [post for post in posts if annotation_matches(candidate, post, image.shape[1], image.shape[0])]
                    matched = min(matches, key=lambda post: abs(candidate["x_px"] - post["x"]), default=None)
                    label = 1 if matched else -1
                    descriptor = post_descriptor(image, candidate)
                    descriptors.append(descriptor); labels.append(label)
                    descriptors.append(post_descriptor(cv2.convertScaleAbs(image, alpha=0.82, beta=15), candidate)); labels.append(label)
                    if matched:
                        positive_descriptors.append(descriptor)
                        offset_targets["x"].append((matched["x"] - candidate["x_px"]) / image.shape[1])
                        offset_targets["top"].append((matched["top_y"] - candidate["top_y_px"]) / image.shape[0])
                        offset_targets["bottom"].append((matched["bottom_y"] - candidate["bottom_y_px"]) / image.shape[0])
    finally:
        _training_mode = False
    positives, negatives = labels.count(1), labels.count(-1)
    if positives < 6 or negatives < 6:
        raise HTTPException(status_code=422, detail=f"Datos insuficientes: {positives} positivos y {negatives} negativos.")
    samples = np.asarray(descriptors, dtype=np.float32)
    responses = np.asarray(labels, dtype=np.int32)
    svm = cv2.ml.SVM_create()
    svm.setType(cv2.ml.SVM_C_SVC)
    svm.setKernel(cv2.ml.SVM_LINEAR)
    svm.setC(1.5)
    if not svm.train(samples, cv2.ml.ROW_SAMPLE, responses):
        raise HTTPException(status_code=500, detail="OpenCV no pudo entrenar el detector.")
    path = post_model_path()
    path.parent.mkdir(parents=True, exist_ok=True)
    svm.save(str(path))
    regression_samples = np.asarray(positive_descriptors, dtype=np.float32)
    regression_mae = {}
    for axis in ("x", "top", "bottom"):
        target = np.asarray(offset_targets[axis], dtype=np.float32)
        regressor = cv2.ml.SVM_create()
        regressor.setType(cv2.ml.SVM_EPS_SVR); regressor.setKernel(cv2.ml.SVM_RBF)
        regressor.setC(8.0); regressor.setGamma(0.02); regressor.setP(0.004)
        if not regressor.train(regression_samples, cv2.ml.ROW_SAMPLE, target):
            raise HTTPException(status_code=500, detail=f"No se pudo entrenar el ajuste {axis}.")
        regressor.save(str(offset_model_path(axis)))
        _unused, predicted = regressor.predict(regression_samples)
        regression_mae[axis] = round(float(np.mean(np.abs(predicted.reshape(-1) - target))), 5)
    metadata = {"examples": example_count, "positive_samples": positives, "negative_samples": negatives, "position_samples": len(positive_descriptors), "regression_mae_normalized": regression_mae, "descriptor": "HOG", "model": path.name}
    (path.parent / "post_detector.json").write_text(json.dumps(metadata, indent=2), encoding="utf-8")
    global _post_model_cache, _offset_model_cache
    _post_model_cache = None
    _offset_model_cache = {}
    return {"ok": True, **metadata, "path": str(path)}


@app.post("/train-post-detector")
def train_post_detector_endpoint() -> dict:
    return train_post_detector()


@app.post("/training-example")
def save_training_example(payload: TrainingExampleRequest) -> dict:
    if len(payload.images) != len(payload.views):
        raise HTTPException(status_code=422, detail="Cada imagen necesita sus anotaciones de postes.")
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
            "training_scope": "multiview_geometry" if len(payload.correspondences) >= 4 else "post_detection",
            "known_dimensions": payload.known_dimensions,
            "labels": {"post": "poste estructural vertical", "endpoint_order": ["top", "bottom"]},
        }
        (example_dir / "annotations.json").write_text(
            json.dumps(annotation, ensure_ascii=False, indent=2), encoding="utf-8"
        )
    except (ValueError, binascii.Error, OSError) as error:
        raise HTTPException(status_code=422, detail=f"No se pudo guardar el ejemplo: {error}")
    try:
        training = train_post_detector()
    except HTTPException as error:
        training = {"ok": False, "pending": True, "message": str(error.detail)}
    return {"ok": True, "example_id": example_id, "path": str(example_dir), "training": training}


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


def segment_saturation_ratio(hsv: np.ndarray, segment: dict) -> float:
    height, width = hsv.shape[:2]
    samples = max(16, min(64, round(segment["length_px"] / 8)))
    xs = np.linspace(segment["x1"], segment["x2"], samples).round().astype(int)
    ys = np.linspace(segment["y1"], segment["y2"], samples).round().astype(int)
    colored, total = 0, 0
    for x, y in zip(xs, ys):
        patch = hsv[max(0, y - 2):min(height, y + 3), max(0, x - 2):min(width, x + 3)]
        colored += int(np.count_nonzero((patch[:, :, 1] >= 75) & (patch[:, :, 2] >= 45)))
        total += patch.shape[0] * patch.shape[1]
    return round(colored / total, 3) if total else 0.0


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
        # Los postes reales de esta línea de producto vienen en 8 colores del
        # catálogo estándar (ver STANDARD_COLOR_PALETTE en constructor_
        # modulos_playidea), no solo azul. `blue_ratio` -y por lo tanto
        # `confidence`- penalizaba estructuras de otros colores -verde,
        # magenta, naranja, etc.- aunque fueran igual de "postes" que uno
        # azul. `colored_ratio` usa el mismo patrón de agregación pero sobre
        # saturación/valor -cualquier tono vivo cuenta-, no sobre el matiz
        # específico del azul.
        colored_ratio = sum(item["saturation_ratio"] * item["length_px"] for item in cluster) / total_length
        structural_colored = colored_ratio >= 0.12
        confidence = min(0.99, 0.18 + (span / height) * 0.82 + min(len(cluster), 6) * 0.045 + min(colored_ratio, 0.5) * 0.7)
        candidates.append({
            "x_px": round(center_mean, 1),
            "top_y_px": int(top),
            "bottom_y_px": int(bottom),
            "span_px": int(span),
            "segment_count": len(cluster),
            "blue_ratio": round(blue_ratio, 3),
            "structural_blue": structural_blue,
            "colored_ratio": round(colored_ratio, 3),
            "structural_colored": structural_colored,
            "confidence": round(confidence, 2),
        })
    return candidates


def projected_grid_groups(posts: list[dict], module_internal_mm: float, image_height: int) -> list[dict]:
    selected = sorted(
        [post for post in posts if post.get("structural_post", post["structural_colored"]) and post["confidence"] >= 0.45],
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
        # Antes se cortaba el grupo en cuanto UN hueco superaba 2.4x el
        # paso típico, así que un solo poste no detectado -oclusión, mala
        # luz, o simplemente ese color no lo reconoció el clasificador-
        # fragmentaba la fila entera en pedacitos chicos. Validado contra
        # 17 proyectos reales -ver skill/reference-: eso hacía que
        # estructuras de 20-35 módulos de ancho terminaran "detectadas"
        # como de 1-4 módulos. Ahora el corte es mucho más permisivo -solo
        # separa cuando el hueco es TAN grande que es más probable que sea
        # otra ala/estructura separada, no un poste faltante-.
        current = [row[0]]
        for post, gap in zip(row[1:], gaps):
            if typical > 0 and gap > typical * 6.0:
                if len(current) >= 2:
                    groups.append(current)
                current = [post]
            else:
                current.append(post)
        if len(current) >= 2:
            groups.append(current)

    results = []
    for group in groups:
        xs = [post["x_px"] for post in group]
        gaps = np.diff(xs)
        upper = np.percentile(gaps, 75)
        compact = gaps[gaps <= upper]
        typical = float(np.median(compact if len(compact) else gaps))
        span = xs[-1] - xs[0]
        # Bahías estimadas por SPAN/PASO -no por conteo de postes
        # detectados consecutivos-: tolera huecos por detecciones
        # faltantes en medio de la fila, mientras el paso típico y la
        # extensión total sí se hayan medido bien.
        estimated_bay_count = max(1, round(span / typical)) if typical > 0 else max(1, len(group) - 1)
        results.append({
            "post_count": len(group),
            "provisional_bay_count": estimated_bay_count,
            "projected_step_px": round(typical, 1),
            "span_px": round(span, 1),
            "module_internal_mm": module_internal_mm,
            "confidence": 0.45,
        })
    return results


def assign_provisional_post_heights(candidates: list[dict], grid_groups: list[dict], segments: list[dict], width: int, height: int, module_internal_mm: float) -> None:
    steps = [group["projected_step_px"] for group in grid_groups if group["projected_step_px"] > 0]
    projected_module_px = float(np.median(steps)) if steps else None
    for candidate in candidates:
        crossing_y = []
        for segment in segments:
            if segment["kind"] != "horizontal" or segment.get("saturation_ratio", 0) < 0.16 or segment["length_px"] < width * 0.075:
                continue
            x_min, x_max = sorted((segment["x1"], segment["x2"]))
            y = (segment["y1"] + segment["y2"]) / 2.0
            if x_min - width * 0.015 <= candidate["x_px"] <= x_max + width * 0.015 and candidate["top_y_px"] <= y <= candidate["bottom_y_px"]:
                crossing_y.append(y)
        clusters = []
        for y in sorted(crossing_y):
            if not clusters or y - float(np.mean(clusters[-1])) > height * 0.035:
                clusters.append([y])
            else:
                clusters[-1].append(y)
        rail_levels = len(clusters) - 1
        if 1 <= rail_levels <= 6:
            levels, source = rail_levels, "colored_horizontal_levels"
        elif projected_module_px:
            levels, source = max(1, min(4, round(candidate["span_px"] / projected_module_px))), "projected_module_ratio"
        else:
            levels, source = 1, "unscaled_default"
        candidate["provisional_levels"] = levels
        candidate["provisional_height_mm"] = round(levels * module_internal_mm, 1)
        candidate["height_source"] = source


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
            segment["saturation_ratio"] = segment_saturation_ratio(hsv, segment)
            raw_segments.append(segment)

    raw_segments.sort(key=lambda item: item["length_px"], reverse=True)
    segments = [segment for segment in raw_segments if not is_presentation_border(segment, width, height)]
    counts = {kind: sum(1 for segment in segments if segment["kind"] == kind) for kind in ("horizontal", "vertical", "diagonal")}
    post_candidates = build_post_candidates(segments, width, height)
    apply_learned_post_model(image, post_candidates)
    grid_groups = projected_grid_groups(post_candidates, 1168.4, height)
    assign_provisional_post_heights(post_candidates, grid_groups, segments, width, height, 1168.4)
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
    # Antes priorizaba `post_count` -cuántos postes se lograron
    # emparejar sin huecos-, así que un grupito denso y angosto le
    # ganaba a una fila ancha pero con detecciones dispersas. Para
    # estimar el ANCHO real de la estructura, lo que importa es
    # `span_px` -qué tanto abarca en la imagen-, no cuántos postes
    # individuales se alcanzaron a emparejar.
    return max(groups, key=lambda group: (group["span_px"], group["post_count"]), default=None)


def inferred_levels(view: dict, grid: dict | None) -> int:
    if not grid or grid["projected_step_px"] <= 0:
        return 1
    structural = [post for post in view["post_candidates"] if post.get("structural_post", post["structural_colored"])]
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


def analysis_response(views: list[dict], case_id: str, module_internal_mm: float, multiview: dict, known_dimensions: dict | None = None) -> dict:
    totals = {key: sum(view["line_counts"][key] for view in views) for key in ("horizontal", "vertical", "diagonal")}
    metric_plan = build_metric_plan(module_internal_mm, views, multiview)
    known_dimensions = known_dimensions or {}
    spacing_x = known_dimensions.get("spacing_x_mm") or []
    spacing_y = known_dimensions.get("spacing_y_mm") or []
    if spacing_x and spacing_y:
        height_mm = float(known_dimensions.get("height_mm") or module_internal_mm)
        levels = max(1, min(20, round(height_mm / module_internal_mm)))
        metric_plan = {
            "status": "confirmed_dimensions",
            "module_internal_mm": module_internal_mm,
            "grid_width_modules": len(spacing_x), "grid_depth_modules": len(spacing_y),
            "spacing_x_mm": spacing_x, "spacing_y_mm": spacing_y, "height_mm": height_mm,
            "zones": [{"id": "estructura_confirmada", "label": "Estructura confirmada", "kind": "modular", "x": 0, "y": 0, "width": len(spacing_x), "depth": len(spacing_y), "levels": levels, "confidence": 1.0, "source": "user_ground_truth"}],
            "message": "Cuadrícula fijada con medidas conocidas proporcionadas por el usuario.",
        }
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
        "known_dimensions": known_dimensions,
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
    return analysis_response(views, payload.case_id, payload.module_internal_mm, multiview, payload.known_dimensions)


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
