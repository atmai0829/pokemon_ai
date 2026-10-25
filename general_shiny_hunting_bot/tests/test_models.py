import pytest
from shiny_bot.models import CaptureResult, Profile, Rect, StartupError, UserConfig, VisionResult


def test_rect_converts_relative_coordinates_to_screen_coordinates():
    assert Rect(10, 20, 30, 40).translate(Rect(100, 200, 640, 480)) == Rect(110, 220, 30, 40)


def test_capture_and_vision_results_require_explicit_statuses():
    assert CaptureResult.error("capture failed").status == "error"
    assert VisionResult.unknown("unreadable name").confidence == 0.0


def test_models_reject_invalid_invariants():
    with pytest.raises(ValueError):
        Rect(0, 0, 0, 1)
    with pytest.raises(ValueError):
        VisionResult(status="match", confidence=1.1)
    with pytest.raises(ValueError):
        CaptureResult(status="ok", image=None, viewport=None, reason=None)


def test_profile_config_and_startup_error_are_typed():
    assert Profile.__dataclass_fields__
    assert UserConfig.__dataclass_fields__
    assert issubclass(StartupError, RuntimeError)