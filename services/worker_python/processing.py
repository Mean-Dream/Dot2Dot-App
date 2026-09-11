import os
import io
import traceback
import numpy as np
import cv2
from PIL import Image
from rembg import remove
from supabase import create_client, Client
from dotenv import load_dotenv

load_dotenv()

supabase: Client = create_client(
    os.environ["SUPABASE_URL"],
    os.environ["SUPABASE_SERVICE_ROLE_KEY"],
)

_MIN_AREA_FRACTION = 0.0003
_MIN_DOTS_PER_CONTOUR = 6
_MAX_CONTOURS = 20
_MIN_DOT_SPACING_PX = 8.0  # minimum Euclidean distance between dots in 1024 space

# Target dot counts for each game difficulty level.
_DIFFICULTY_TARGETS = {
    "easy": 45,    # Range 30-60
    "medium": 100, # Range 80-120
    "hard": 200,   # Range 150-250
}


def _cumulative_arc(pts: np.ndarray) -> np.ndarray:
    diffs = np.diff(pts, axis=0)
    seg = np.hypot(diffs[:, 0], diffs[:, 1])
    return np.concatenate([[0.0], np.cumsum(seg)])


def _resample_by_arc_length(pts: np.ndarray, n: int) -> np.ndarray:
    if len(pts) < 2 or n < 2:
        return pts
    cumlen = _cumulative_arc(pts)
    total = cumlen[-1]
    if total == 0.0:
        return pts[:n] if len(pts) >= n else pts
    targets = np.linspace(0.0, total, n, endpoint=False)
    xs = np.interp(targets, cumlen, pts[:, 0])
    ys = np.interp(targets, cumlen, pts[:, 1])
    return np.column_stack([xs, ys])


def _arc_length(pts: np.ndarray) -> float:
    return float(_cumulative_arc(pts)[-1])


def _enforce_min_spacing(dots: list[dict], min_dist: float = _MIN_DOT_SPACING_PX) -> list[dict]:
    """Remove dots closer than min_dist px (in 1024 space) to the previous kept dot.

    is_new_path dots (pen-lift markers) always reset the reference point and
    are never removed — skipping them would orphan a contour segment.
    """
    if not dots:
        return dots
    min_dist_sq = min_dist * min_dist
    kept = [dots[0]]
    last_x, last_y = dots[0]["x"], dots[0]["y"]
    for dot in dots[1:]:
        if dot["is_new_path"]:
            kept.append(dot)
            last_x, last_y = dot["x"], dot["y"]
        else:
            dx = dot["x"] - last_x
            dy = dot["y"] - last_y
            if dx * dx + dy * dy >= min_dist_sq:
                kept.append(dot)
                last_x, last_y = dot["x"], dot["y"]
    return kept


def _generate_dot_set(
    contour_pts: list,
    arc_lengths: list,
    target_n: int,
    erased_points: list,
    orig_w: int,
    orig_h: int,
) -> list[dict]:
    """Generate a scaled dot set targeting target_n dots total across all contours."""
    total_arc = sum(arc_lengths)
    # Mirror the original formula: rdp_epsilon scales with sparsity = 2000/target_n
    rdp_epsilon = max(1.5, (2000.0 / target_n) * 0.25)
    raw_output: list[dict] = []

    for i, (pts, arc_len) in enumerate(zip(contour_pts, arc_lengths)):
        if arc_len == 0 or total_arc == 0:
            continue

        n_dots = max(
            _MIN_DOTS_PER_CONTOUR,
            int(round((arc_len / total_arc) * target_n)),
        )

        approx = cv2.approxPolyDP(
            pts.astype(np.int32).reshape(-1, 1, 2),
            epsilon=rdp_epsilon,
            closed=True,
        )
        simplified = approx.squeeze(axis=1).astype(float)
        if len(simplified) < 3:
            simplified = pts

        resampled = _resample_by_arc_length(simplified, n_dots)

        for j, (x, y) in enumerate(resampled):
            raw_output.append({
                "x_raw": x,
                "y_raw": y,
                "is_new_path": (j == 0 and i > 0),
            })

    # Apply eraser mask
    if erased_points:
        mask_radius_sq = 25 ** 2
        kept = []
        for d in raw_output:
            x_1024 = (d["x_raw"] / orig_w) * 1024.0
            y_1024 = (d["y_raw"] / orig_h) * 1024.0
            masked = any(
                (x_1024 - (ep["x"] if isinstance(ep, dict) else ep[0])) ** 2 +
                (y_1024 - (ep["y"] if isinstance(ep, dict) else ep[1])) ** 2 < mask_radius_sq
                for ep in erased_points
            )
            if not masked:
                kept.append(d)
        raw_output = kept

    scaled = [
        {
            "x": round((d["x_raw"] / orig_w) * 1024.0, 2),
            "y": round((d["y_raw"] / orig_h) * 1024.0, 2),
            "is_new_path": d["is_new_path"],
        }
        for d in raw_output
    ]
    spaced = _enforce_min_spacing(scaled)
    return [
        {**d, "sequence_order": seq, "label": str(seq)}
        for seq, d in enumerate(spaced, start=1)
    ]


def _fail(project_id: str, reason: str):
    print(f"[FAIL] {project_id}: {reason}")
    supabase.table("projects").update({"status": "error"}).eq("id", project_id).execute()


def process_dots(
    project_id: str,
    sparsity: int,
    remove_bg: bool,
    erased_points: list = [],
):
    local_path = f"temp/{project_id}_input.jpg"
    try:
        print(f"--- Processing: {project_id}  sparsity={sparsity}  remove_bg={remove_bg} ---")

        if not os.path.exists("temp"):
            os.makedirs("temp")

        # 1. Image acquisition
        if os.path.exists(local_path):
            with open(local_path, "rb") as fh:
                raw_bytes = fh.read()
        else:
            row = (
                supabase.table("projects")
                .select("image_path")
                .eq("id", project_id)
                .single()
                .execute()
            )
            if not row.data:
                _fail(project_id, "project not found in database")
                return
            image_path = row.data["image_path"]
            # image_path may be a full public URL; extract the in-bucket path.
            _marker = "/object/public/images/"
            if image_path and _marker in image_path:
                image_path = image_path[image_path.index(_marker) + len(_marker):]
            print(f"Downloading image: {image_path}")
            raw_bytes = supabase.storage.from_("images").download(image_path)
            print(f"Downloaded {len(raw_bytes)} bytes")
            with open(local_path, "wb") as fh:
                fh.write(raw_bytes)

        # 2. Pre-processing
        alpha_mask = None
        nparr = np.frombuffer(raw_bytes, np.uint8)

        if remove_bg:
            pil_input = Image.open(io.BytesIO(raw_bytes)).convert("RGBA")
            pil_rgba = remove(pil_input)
            alpha_mask = np.array(pil_rgba)[:, :, 3]
            white_bg = Image.new("RGBA", pil_rgba.size, (255, 255, 255, 255))
            img_bgr = cv2.cvtColor(
                np.array(Image.alpha_composite(white_bg, pil_rgba).convert("RGB")),
                cv2.COLOR_RGB2BGR,
            )
        else:
            img_raw = cv2.imdecode(nparr, cv2.IMREAD_UNCHANGED)
            if img_raw is None:
                _fail(project_id, f"cv2 could not decode image ({len(raw_bytes)} bytes)")
                return
            # Transparent PNG: use alpha channel as the silhouette mask
            if len(img_raw.shape) == 3 and img_raw.shape[2] == 4:
                print("Detected transparent PNG — using alpha channel as mask")
                alpha_mask = img_raw[:, :, 3]
                # Composite onto white for img_bgr (used for shape dimensions)
                bgra = img_raw.astype(float)
                alpha_f = bgra[:, :, 3:4] / 255.0
                white = np.full_like(bgra[:, :, :3], 255.0)
                composited = (bgra[:, :, :3] * alpha_f + white * (1 - alpha_f)).astype(np.uint8)
                img_bgr = cv2.cvtColor(composited, cv2.COLOR_RGB2BGR)
            else:
                img_bgr = cv2.imdecode(nparr, cv2.IMREAD_COLOR)

        orig_h, orig_w = img_bgr.shape[:2]
        print(f"Image decoded: {orig_w}x{orig_h}  has_alpha_mask={alpha_mask is not None}")
        min_area = orig_w * orig_h * _MIN_AREA_FRACTION

        # 3. Contour extraction
        if alpha_mask is not None:
            _, binary = cv2.threshold(alpha_mask, 10, 255, cv2.THRESH_BINARY)
            kernel = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (5, 5))
            binary = cv2.morphologyEx(binary, cv2.MORPH_CLOSE, kernel)

            # Outer silhouette boundary (and any interior holes like donuts)
            outer, _ = cv2.findContours(binary, cv2.RETR_LIST, cv2.CHAIN_APPROX_NONE)

            # Interior detail: run Canny only inside the silhouette.
            # Erode the mask by ~15 px so the outer boundary edge itself isn't
            # re-detected and double-counted alongside the alpha contour.
            inner_mask = cv2.erode(binary, kernel, iterations=3)
            gray_inner = cv2.cvtColor(img_bgr, cv2.COLOR_BGR2GRAY)
            blurred_inner = cv2.GaussianBlur(gray_inner, (5, 5), 0)
            edges_inner = cv2.Canny(blurred_inner, 50, 150)
            edges_inner = cv2.bitwise_and(edges_inner, edges_inner, mask=inner_mask)
            inner, _ = cv2.findContours(edges_inner, cv2.RETR_LIST, cv2.CHAIN_APPROX_NONE)

            raw_contours = list(outer) + list(inner)
            print(f"Alpha path — outer: {len(outer)}  interior Canny: {len(inner)}")
        else:
            gray = cv2.cvtColor(img_bgr, cv2.COLOR_BGR2GRAY)
            blurred = cv2.GaussianBlur(gray, (5, 5), 0)
            edges = cv2.Canny(blurred, 50, 150)
            raw_contours, _ = cv2.findContours(
                edges, cv2.RETR_LIST, cv2.CHAIN_APPROX_NONE
            )

        print(f"Raw contours found: {len(raw_contours)}")
        if not raw_contours:
            _fail(project_id, "no contours found in image")
            return

        # 4. Filter and rank contours
        # Interior Canny edge lines are open curves with area≈0 but meaningful
        # arc length, so accept a contour if EITHER criterion is met.
        min_arc = (orig_w + orig_h) * 0.02  # ~40 px on a 1024-px image
        significant = [
            c for c in raw_contours
            if cv2.contourArea(c) >= min_area or
               cv2.arcLength(c, closed=False) >= min_arc
        ]
        if not significant:
            significant = [max(raw_contours, key=lambda c: cv2.arcLength(c, closed=False))]

        # Sort by arc length so the longest (most meaningful) curves rank first.
        significant.sort(key=lambda c: cv2.arcLength(c, closed=False), reverse=True)
        significant = significant[:_MAX_CONTOURS]
        print(f"Significant contours after filter: {len(significant)}")

        contour_pts = [
            c.squeeze(axis=1).astype(float)
            for c in significant
            if c.shape[0] >= 3
        ]
        if not contour_pts:
            _fail(project_id, "no valid contour points after filtering")
            return

        arc_lengths = [_arc_length(pts) for pts in contour_pts]

        # 5. Editor dot set — uses the user's chosen sparsity value
        editor_target = max(15, int(2000 / sparsity))
        editor_dots = _generate_dot_set(
            contour_pts, arc_lengths, editor_target, erased_points, orig_w, orig_h
        )

        # 6. Difficulty-calibrated dot sets
        diff_dots = {
            name: _generate_dot_set(
                contour_pts, arc_lengths, target, erased_points, orig_w, orig_h
            )
            for name, target in _DIFFICULTY_TARGETS.items()
        }

        # 7. Persist
        supabase.table("projects").update(
            {
                "dots": editor_dots,
                "dots_easy": diff_dots["easy"],
                "dots_medium": diff_dots["medium"],
                "dots_hard": diff_dots["hard"],
                "status": "completed",
                "sparsity": sparsity,
                "dot_count": len(editor_dots),
            }
        ).eq("id", project_id).execute()

        print(
            f"Done — editor:{len(editor_dots)}  "
            f"easy:{len(diff_dots['easy'])}  "
            f"medium:{len(diff_dots['medium'])}  "
            f"hard:{len(diff_dots['hard'])} dots"
        )

    except Exception as e:
        print(f"Error: {e}\n{traceback.format_exc()}")
        supabase.table("projects").update({"status": "error"}).eq("id", project_id).execute()
    finally:
        if os.path.exists(local_path):
            os.remove(local_path)
