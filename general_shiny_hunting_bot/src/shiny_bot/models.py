from dataclasses import dataclass, field
from PIL import Image
from typing import Any

@dataclass(frozen=True)
class Rect:
    x: int
    y: int
    width: int
    height: int

    def __post_init__(self):
        if self.width <= 0 or self.height <= 0:
            raise ValueError("Rectangle width and height must be positive")

    def translate(self, parent: "Rect"):
        return Rect(
            x=parent.x + self.x,
            y=parent.y + self.y,
            width=self.width,
            height=self.height,
        )

@dataclass(frozen=True)
class CaptureResult:
    status: str
    image: Image.Image | None = None
    viewport: Rect | None = None
    reason: str | None = None

    def __post_init__(self):
        if self.status == "ok":
            if self.image is None or self.viewport is None:
                raise ValueError("Successful captures requires an image and a viewport.")
            if self.reason:
                raise ValueError("Successful captures can not have a reason.")
        elif self.status == "error":
            if self.reason is None:
                raise ValueError("An error needs a reason.")
            if self.image or self.viewport:
                raise ValueError("An error cannot have an image or viewport.")

    @classmethod
    def ok(cls, image: Image.Image, viewport: Image.Image):
        return cls(status="ok", image=image, viewport=viewport)

    @classmethod
    def error(cls, reason: str):
        return cls(status="error", reason=reason)
    
@dataclass(frozen=True) 
class VisionResult:
    status: str
    confidence: float 
    species_form: str | None = None
    reason: str | None = None

    def __post_init__(self):
        if self.confidence < 0.0 or self.confidence > 1.0:
            raise ValueError("Confidence is not in range.")

        if self.status == "match":
            if self.reason:
                raise ValueError("A match can not have a reason.")
        elif self.status == "unknown" or self.status == "error":
            if self.reason is None:
                raise ValueError("An error status needs a reason.")
            if self.species_form:
                raise ValueError("An error status can not have a species.")

    @classmethod
    def match(cls, species_form: str, confidence: float):
        return cls(status="match", species_form=species_form, confidence=confidence)

    @classmethod
    def unknown(cls, reason: str):
        return cls(status="unknown", confidence=0.0, reason=reason)

    @classmethod
    def error(cls, reason: str):
        return cls(status="error", confidence=0.0, reason=reason)

class StartupError(RuntimeError):
    """Could not start."""

@dataclass(frozen=True)
class Profile:
    version: int
    keys: dict[str, str] = field(default_factory=dict)
    timings: dict[str, float] = field(default_factory=dict)
    thresholds: dict[str, float] = field(default_factory=dict)

@dataclass(frozen=True)
class UserConfig:
    profile_version: int
    viewport: Rect | None = None
    keys: dict[str, str] = field(default_factory=dict)