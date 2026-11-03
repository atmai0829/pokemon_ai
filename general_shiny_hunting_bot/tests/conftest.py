import json
import shutil
from pathlib import Path

import pytest

@pytest.fixture
def profile_copy(profile_dir: Path, tmp_path: Path):
    destination = tmp_path / profile_dir.name
    shutil.copytree(profile_dir, destination)
    return destination

@pytest.fixture
def mutate_profile(profile_copy: Path, mutation: str) -> None:
    profile_path = profile_copy / "profile.json"
    profile = json.loads(profile_path.read_text(encoding="utf-8"))

    if mutation == "zero-width-region":
        profile["regions"]["battle"]["width"] = 0
    elif mutation == "bad-threshold":
        profile["thresholds"]["ui_match_threshold"] = 1.5
    elif mutation == "unsupported-key":
        profile["keys"]["a"] = "definitely-not-a-key"
    elif mutation == "missing-asset":
        profile["assets"].append(
            {
                "filename": "does-not-exist.png",
                "kind": "normal_sprite",
                "species_form": "zubat",
                "enabled": True,
            }
        )
    else:
        raise ValueError(f"Unknown profile mutation: {mutation}")

    profile_path.write_text(
        json.dumps(profile, indent=2),
        encoding="utf-8",
    )
