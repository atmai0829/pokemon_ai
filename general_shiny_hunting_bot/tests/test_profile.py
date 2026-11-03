import pytest
from pathlib import Path
from shiny_bot.profile import load_profile

PROFILE_PATH = Path(__file__).parents[1] / "profiles" / "soulsilver_desmume" / "profile.json"


def test_local_keyboard_override_wins_over_profile_default(tmp_path):
    config = tmp_path / "user-config.json"
    config.write_text('{"profile_version": 1, "keys": {"a": "z"}}')
    profile = load_profile(PROFILE_PATH, config)
    assert profile.keys["a"] == "z"


def test_mismatched_config_profile_version_is_rejected(tmp_path):
    config = tmp_path / "user-config.json"
    config.write_text('{"profile_version": 999, "keys": {}}')
    with pytest.raises(ValueError, match="profile version"):
        load_profile(PROFILE_PATH, config)


@pytest.mark.parametrize("mutation", ["zero-width-region", "bad-threshold", "unsupported-key", "missing-asset"])
def test_invalid_profile_is_rejected(profile_copy, mutation):
    mutate_profile(profile_copy, mutation)
    with pytest.raises(ValueError):
        load_profile(profile_copy / "profile.json", None)


@pytest.mark.parametrize("config", [
    '{"profile_version": 1, "keys": {"invalid": "z"}}',
    '{"profile_version": 1, "viewport": {"width": 0}}',
    '{"profile_version": 1, "ui_match_threshold": 0.1}',
])
def test_config_rejects_invalid_or_forbidden_overrides(tmp_path, config):
    path = tmp_path / "user-config.json"
    path.write_text(config)
    with pytest.raises(ValueError):
        load_profile(PROFILE_PATH, path)