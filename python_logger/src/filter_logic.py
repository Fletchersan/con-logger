from typing import Optional, Literal
from dataclasses import dataclass
import re

@dataclass
class FilterInfo:
    pattern: Optional[str] = None
    invert_pattern: bool = False
    output_format: Literal["count", "print"] = "print"
    _rx: Optional[re.Pattern[str]] = None

    def compile(self) -> None:
        self._rx = re.compile(self.pattern) if self.pattern else None

def should_keep(line: str, info: FilterInfo) -> bool:
    if info._rx is None:
        return True
    matched = info._rx.search(line) is not None
    return (not matched) if info.invert_pattern else matched