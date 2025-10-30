# read file line by line
# filter each line
# process line -> print or count
# move to next line

import argparse
import dotenv
import os
from typing import Iterator, Optional
from dataclasses import dataclass
import re

@dataclass
class FilterInfo:
    pattern: Optional[str] = None
    invert_pattern: bool = False
    _rx: Optional[re.Pattern[str]] = None

    def compile(self) -> None:
        self._rx = re.compile(self.pattern) if self.pattern else None

def load_env(path: str = ".env") -> None:
    if dotenv is not None and os.path.exists(path):
        dotenv.load_dotenv(path)

def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Ingest and process log file"
    )
    parser.add_argument(
        "--input"
    )
    parser.add_argument(
        "--filter-pattern", default=None
    )
    parser.add_argument(
        "--invert", action="store_true"
    )
    parser.add_argument(
        "--output-format",
        choices=("print", "count"),
        default="print",
        type=str.lower,
        help="Output format."
    )
    return parser.parse_args()

def should_keep(line: str, info: FilterInfo) -> bool:
    if info._rx is None:
        return True
    matched = info._rx.search(line) is not None
    return (not matched) if info.invert_pattern else matched

def filtered_line_reader(file_path: str) -> Iterator[str]:
    with open(file_path, 'r') as f:
        for line in f:
                yield line.strip()


def main():
    load_env()
    args = parse_args()

    file_path: str = args.input
    filter_info = FilterInfo(
        pattern = args.filter_pattern,
        invert_pattern= args.invert
    )
    filter_info.compile()
    reader = filtered_line_reader(file_path=file_path)
    ctr = 0
    while True:
        try:
            log_line =next(reader)
            if should_keep(log_line, filter_info):
                if args.output_format == "print":
                    print(log_line)
                ctr += 1
        except StopIteration:
            break
    if args.output_format == "count":
        print(ctr)

if __name__ == '__main__':
    main()