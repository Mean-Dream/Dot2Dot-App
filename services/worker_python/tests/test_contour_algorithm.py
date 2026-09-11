"""
Unit tests for the contour algorithm in processing.py.

Covers the pure geometry functions (_arc_length, _resample_by_arc_length,
_generate_dot_set) using synthetic circle and square contours so tests run
without any image files, Supabase connection, or rembg model.
"""

import math
import os
import sys
from unittest.mock import MagicMock

import numpy as np
import pytest

# ── Stub external I/O before processing.py loads ─────────────────────────────
# processing.py calls create_client() at module level; intercept it.
os.environ.setdefault("SUPABASE_URL", "http://localhost:54321")
os.environ.setdefault("SUPABASE_SERVICE_ROLE_KEY", "test-service-role-key")

sys.modules.setdefault("rembg", MagicMock())
_supabase_mock = MagicMock()
_supabase_mock.create_client.return_value = MagicMock()
sys.modules.setdefault("supabase", _supabase_mock)
sys.modules.setdefault("dotenv", MagicMock())
sys.modules.setdefault("PIL", MagicMock())
sys.modules.setdefault("PIL.Image", MagicMock())

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))
import processing  # noqa: E402  (must come after stubs)


# ── Contour factories ─────────────────────────────────────────────────────────

def circle_contour(cx: float, cy: float, r: float, n: int = 500) -> np.ndarray:
    angles = np.linspace(0, 2 * math.pi, n, endpoint=False)
    return np.column_stack([cx + r * np.cos(angles), cy + r * np.sin(angles)])


def square_contour(x0: float, y0: float, side: float, pts_per_edge: int = 200) -> np.ndarray:
    t = np.linspace(0, 1, pts_per_edge, endpoint=False)
    top    = np.column_stack([x0 + side * t,       np.full(pts_per_edge, y0)])
    right  = np.column_stack([np.full(pts_per_edge, x0 + side), y0 + side * t])
    bottom = np.column_stack([x0 + side * (1 - t), np.full(pts_per_edge, y0 + side)])
    left   = np.column_stack([np.full(pts_per_edge, x0), y0 + side * (1 - t)])
    return np.vstack([top, right, bottom, left])


# ── _arc_length ───────────────────────────────────────────────────────────────

class TestArcLength:
    def test_circle_circumference(self):
        r = 300
        pts = circle_contour(500, 500, r, n=10_000)
        expected = 2 * math.pi * r
        assert abs(processing._arc_length(pts) - expected) / expected < 0.001

    def test_square_perimeter(self):
        side = 400
        pts = square_contour(100, 100, side, pts_per_edge=1000)
        expected = 4 * side
        assert abs(processing._arc_length(pts) - expected) / expected < 0.001


# ── _resample_by_arc_length ───────────────────────────────────────────────────

class TestResampleByArcLength:
    def test_returns_exactly_n_points(self):
        pts = circle_contour(500, 500, 300, 200)
        for n in [10, 30, 100]:
            assert len(processing._resample_by_arc_length(pts, n)) == n

    def test_starts_at_first_input_point(self):
        pts = circle_contour(500, 500, 300, 200)
        result = processing._resample_by_arc_length(pts, 20)
        np.testing.assert_allclose(result[0], pts[0], atol=1e-9)

    def test_even_spacing_on_circle(self):
        # Arc-length resampling on a circle produces near-equal chord lengths.
        pts = circle_contour(500, 500, 300, 2000)
        result = processing._resample_by_arc_length(pts, 36)
        diffs = np.diff(result, axis=0)
        chords = np.hypot(diffs[:, 0], diffs[:, 1])
        cv = np.std(chords) / np.mean(chords)
        assert cv < 0.02, f"chord spacing not uniform (CV={cv:.3f})"


# ── _generate_dot_set ─────────────────────────────────────────────────────────

class TestGenerateDotSetSingleContour:
    """Single-contour tests where the count should equal target_n exactly."""

    def _circle_dots(self, target: int, *, orig: int = 1000, r: float = 400) -> list:
        pts = circle_contour(orig / 2, orig / 2, r, n=500)
        arc = processing._arc_length(pts)
        return processing._generate_dot_set([pts], [arc], target, [], orig, orig)

    def test_circle_count_equals_target(self):
        # Single contour: resampling yields exactly target_n dots.
        for target in [30, 50, 100, 200]:
            result = self._circle_dots(target)
            assert len(result) == target, f"target={target} → got {len(result)}"

    def test_square_count_equals_target(self):
        for target in [20, 40, 80]:
            pts = square_contour(100, 100, 400, pts_per_edge=200)
            arc = processing._arc_length(pts)
            result = processing._generate_dot_set([pts], [arc], target, [], 1000, 1000)
            assert len(result) == target, f"target={target} → got {len(result)}"

    def test_sequence_order_is_consecutive(self):
        result = self._circle_dots(40)
        orders = [d["sequence_order"] for d in result]
        assert orders == list(range(1, len(result) + 1))

    def test_label_matches_sequence_order(self):
        result = self._circle_dots(25)
        for dot in result:
            assert dot["label"] == str(dot["sequence_order"])

    def test_required_fields_present(self):
        result = self._circle_dots(20)
        required = {"x", "y", "sequence_order", "label", "is_new_path"}
        for dot in result:
            assert required.issubset(dot.keys())

    def test_coordinates_within_1024(self):
        result = self._circle_dots(50)
        for dot in result:
            assert 0.0 <= dot["x"] <= 1024.0, f"x out of range: {dot['x']}"
            assert 0.0 <= dot["y"] <= 1024.0, f"y out of range: {dot['y']}"

    def test_is_new_path_false_for_single_contour(self):
        result = self._circle_dots(30)
        assert all(not d["is_new_path"] for d in result)

    def test_min_dots_floor_respected(self):
        # Even target < _MIN_DOTS_PER_CONTOUR should produce at least that many.
        result = self._circle_dots(2)
        assert len(result) >= processing._MIN_DOTS_PER_CONTOUR


class TestGenerateDotSetMultiContour:
    """Two-contour tests: outer circle + small inner circle."""

    def _two_circle_dots(self, target: int):
        outer = circle_contour(512, 512, 400, n=500)
        inner = circle_contour(512, 512,  80, n=200)
        arcs = [processing._arc_length(outer), processing._arc_length(inner)]
        return processing._generate_dot_set([outer, inner], arcs, target, [], 1024, 1024)

    def test_is_new_path_marks_second_contour(self):
        result = self._two_circle_dots(60)
        new_path = [d for d in result if d["is_new_path"]]
        # Exactly one pen-lift: the start of the inner contour.
        assert len(new_path) == 1
        assert new_path[0]["sequence_order"] > 1

    def test_first_dot_never_new_path(self):
        result = self._two_circle_dots(60)
        assert result[0]["is_new_path"] is False

    def test_sequence_order_consecutive_across_contours(self):
        result = self._two_circle_dots(80)
        orders = [d["sequence_order"] for d in result]
        assert orders == list(range(1, len(result) + 1))

    def test_multi_contour_count_in_range(self):
        # Two contours: sum of per-contour counts may exceed target due to
        # the _MIN_DOTS_PER_CONTOUR floor and integer rounding.
        result = self._two_circle_dots(60)
        # outer ≈ 50 dots, inner ≈ 10 dots; minor rounding makes total ±10
        assert abs(len(result) - 60) <= 10


# ── Difficulty targets ────────────────────────────────────────────────────────

class TestDifficultyTargets:
    """Verify the three game difficulty levels land in their expected ranges."""

    def _dots(self, target: int) -> list:
        pts = circle_contour(512, 512, 450, n=1000)
        arc = processing._arc_length(pts)
        return processing._generate_dot_set([pts], [arc], target, [], 1024, 1024)

    def test_easy_30_to_60(self):
        result = self._dots(processing._DIFFICULTY_TARGETS["easy"])
        assert 30 <= len(result) <= 60, f"easy={len(result)}"

    def test_medium_80_to_120(self):
        result = self._dots(processing._DIFFICULTY_TARGETS["medium"])
        assert 80 <= len(result) <= 120, f"medium={len(result)}"

    def test_hard_150_to_250(self):
        result = self._dots(processing._DIFFICULTY_TARGETS["hard"])
        assert 150 <= len(result) <= 250, f"hard={len(result)}"


# ── Eraser mask ───────────────────────────────────────────────────────────────

class TestEraserMask:
    def test_eraser_removes_dots_near_point(self):
        pts = circle_contour(512, 512, 400, n=500)
        arc = processing._arc_length(pts)
        # Generate baseline to find an actual dot position.
        baseline = processing._generate_dot_set([pts], [arc], 100, [], 1024, 1024)
        # Erase at the exact position of the first dot — guaranteed to be on the path.
        erased = [{"x": baseline[0]["x"], "y": baseline[0]["y"]}]
        result = processing._generate_dot_set([pts], [arc], 100, erased, 1024, 1024)
        assert len(result) < len(baseline)

    def test_eraser_away_from_path_removes_nothing(self):
        pts = circle_contour(512, 512, 400, n=500)
        arc = processing._arc_length(pts)
        baseline = processing._generate_dot_set([pts], [arc], 60, [], 1024, 1024)
        # Eraser at the canvas center — far from the circle edge.
        erased = [{"x": 512.0, "y": 512.0}]
        result = processing._generate_dot_set([pts], [arc], 60, erased, 1024, 1024)
        assert len(result) == len(baseline)

    def test_eraser_accepts_list_tuples(self):
        # Erased points may be dicts or [x, y] lists — both are supported.
        pts = circle_contour(512, 512, 400, n=500)
        arc = processing._arc_length(pts)
        baseline = processing._generate_dot_set([pts], [arc], 60, [], 1024, 1024)
        erased_list = [[baseline[0]["x"], baseline[0]["y"]]]
        result = processing._generate_dot_set([pts], [arc], 60, erased_list, 1024, 1024)
        assert len(result) < len(baseline)


# ── Minimum dot spacing ───────────────────────────────────────────────────────

def _check_min_spacing(dots: list) -> None:
    """Assert no two consecutive non-new-path dots violate the minimum spacing."""
    min_px = processing._MIN_DOT_SPACING_PX
    for i in range(1, len(dots)):
        if dots[i]["is_new_path"]:
            continue
        dist = math.hypot(dots[i]["x"] - dots[i - 1]["x"],
                          dots[i]["y"] - dots[i - 1]["y"])
        assert dist >= min_px, (
            f"dots {i-1}→{i} are only {dist:.2f}px apart (min={min_px}px)"
        )


class TestEnforceMinSpacing:
    def test_filter_kicks_in_on_short_dense_line(self):
        # A 100px horizontal line with target=50 → arc-length spacing ≈2px → below MIN.
        # The filter must reduce the count and enforce the minimum distance.
        pts = np.column_stack([np.linspace(100, 200, 500), np.full(500, 500.0)])
        arc = processing._arc_length(pts)
        result = processing._generate_dot_set([pts], [arc], 50, [], 1000, 1000)
        # Spacing in 1024 space: 100*1.024 / 50 ≈ 2px → well below MIN → fewer dots kept.
        assert len(result) < 50
        _check_min_spacing(result)

    def test_invariant_holds_on_well_spaced_circle(self):
        # Standard circle: natural spacing >> MIN → filter is a no-op.
        pts = circle_contour(500, 500, 400, n=500)
        arc = processing._arc_length(pts)
        for target in [45, 100, 200]:
            result = processing._generate_dot_set([pts], [arc], target, [], 1000, 1000)
            _check_min_spacing(result)

    def test_sequence_order_consecutive_after_filtering(self):
        # After the spacing filter removes dots, sequence_order must still be 1..N.
        pts = np.column_stack([np.linspace(100, 200, 500), np.full(500, 500.0)])
        arc = processing._arc_length(pts)
        result = processing._generate_dot_set([pts], [arc], 50, [], 1000, 1000)
        orders = [d["sequence_order"] for d in result]
        assert orders == list(range(1, len(result) + 1))

    def test_new_path_dots_never_removed(self):
        # is_new_path dots must survive even if they're close to the previous dot.
        outer = circle_contour(512, 512, 400, n=500)
        inner = circle_contour(512, 512,  80, n=200)
        arcs = [processing._arc_length(outer), processing._arc_length(inner)]
        result = processing._generate_dot_set([outer, inner], arcs, 60, [], 1024, 1024)
        new_path_dots = [d for d in result if d["is_new_path"]]
        assert len(new_path_dots) == 1

    def test_empty_input_returns_empty(self):
        result = processing._enforce_min_spacing([])
        assert result == []

    def test_single_dot_always_kept(self):
        dot = {"x": 100.0, "y": 200.0, "is_new_path": False}
        result = processing._enforce_min_spacing([dot])
        assert result == [dot]
