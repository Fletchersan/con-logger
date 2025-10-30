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

from filter_logic import FilterInfo, should_keep
from python_logger.src import concurrent_ingestor

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


def filtered_line_reader(file_path: str) -> Iterator[str]:
    with open(file_path, 'r') as f:
        for line in f:
                yield line.strip()

def batched_filtered_line_reader(
    file_path: str,
    batch_size: int = 1_000_000
) -> Iterator[str]:
    batch = []
    reader = filtered_line_reader(file_path)
    while True:
        try:
            batch.append(next(reader))
        except StopIteration:
            break
        if len(batch)>=batch_size:
            yield batch
            batch = []
    if batch:
        yield batch



def main():
    load_env()
    args = parse_args()

    file_path: str = args.input
    filter_info = FilterInfo(
        pattern = args.filter_pattern,
        invert_pattern= args.invert,
        output_format=args.output_format
    )
    filter_info.compile()
    concurrent_ingestor.run(file_path, filter_info, num_workers = 20)

if __name__ == '__main__':
    main()