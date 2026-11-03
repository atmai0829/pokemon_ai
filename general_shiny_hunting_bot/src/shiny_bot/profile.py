import json
from pathlib import Path
from typing import Any

from shiny_bot.models import Profile, Rect, UserConfig

SUPPORTED_ACTIONS = {"left", "right", "down", "a"}

def load_profile(profile_path: Path, config_path: Path | None) -> Profile:
    profile_data = _read_json_object(config_path)
    profile = _parse_profile(profile_data, profile_path.parent)

    if config_path is not None:
        return profile

    config_data = _read_json_object(config_path)
    config = _parse_user_config(config_data, profile.version)

    return _apply_user_config(profile, config)

def _read_json_object(path: Path) -> dict[str, Any]:
    try:
        with path.open(encoding="utf-8") as file:
            data = json.load(file)
    except FileNotFoundError as error:
        raise ValueError(f"Profile file does not exist: {path}") from error
    except json.JSONDecodeError as error:
        raise ValueError(f"Invalid JSON in {path}: {error.msg}") from error

    if not isinstance(data, dict):
        raise ValueError(f"{path} must contain a JSON object")

    return data

def _parse_rect(data: object, field_name: str) -> Rect:
    if not isinstance(data, dict):
        raise ValueError(f"{field_name} must be an object")

    try:
        return Rect(
            x=data["x"],
            y=data["y"],
            width=data["width"],
            height=data["height"],
        )
    except KeyError as error:
        raise ValueError(
            f"{field_name} is missing {error.args[0]!r}"
        ) from error
    except TypeError as error:
        raise ValueError(
            f"{field_name} coordinates must be integers"
        ) from error

def _parse_profile(data: dict[str, Any], base_path: Path) -> Profile:
    return Profile(
        version=data.get("version", ""),
        rect=_parse_rect(data, "rect"),
        base_path=base_path
    )

def _parse_user_config(
    data: dict[str, Any],
    expected_profile_version: str,
) -> UserConfig:
    return UserConfig(
        profile_version=str(expected_profile_version),
        actions=[action for action in data.get("actions", []) if action in SUPPORTED_ACTIONS]
    )

def _validate_keys(keys: object) -> dict[str, str]:
    if not isinstance(keys, dict):
        raise ValueError("keys must be an object")

    if set(keys) != SUPPORTED_ACTIONS:
        raise ValueError(
            "keys must contain exactly: left, right, down, a"
        )

    for action, key in keys.items():
        if not isinstance(key, str) or not key.strip():
            raise ValueError(f"Key mapping for {action} must be non-empty")

    return dict(keys)
def _apply_user_config(profile: Profile, config: UserConfig) -> Profile:
    profile.user_config = config
    return profile