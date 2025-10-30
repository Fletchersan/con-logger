from optparse import Option
import threading
from queue import Queue
from typing import Optional, Tuple

from filter_logic import FilterInfo, should_keep

LineItem = Tuple[int, str]
LineQueue = Queue[Option[LineItem]]

def reader(path: str, in_q: LineQueue, n: int) -> None:
    with open(path, 'r') as f:
        for seq, line in enumerate(f):
            in_q.put(seq , line.strip())
    for _ in range(n):
        in_q.put(None)

def worker(
    in_q: LineQueue,
    out_q: LineQueue,
    info: FilterInfo
) -> None:
    while True:
        item = in_q.get()
        if item is None:
            out_q.put(None)
            break
        seq, line = item
        if should_keep(line, info):
            out_q.put((seq, line))

def sink(
    out_q: Queue[Optional[LineItem]], n: int, info: FilterInfo
) -> None:
    if getattr(info, "output_format", "print") == "count":
        # Count-only mode: no ordering or buffering needed
        done = 0
        total = 0
        while True:
            item = out_q.get()
            if item is None:
                done += 1
                if done == n:
                    print(total)
                    break
                continue
            # Every emitted item is a kept line
            total += 1
        return

    # Print mode with ordered output by sequence id
    next_seq = 0
    buf = {}
    done = 0
    while True:
        item = out_q.get()
        if item is None:
            done += 1
            if done == n:
                while next_seq in buf:
                    print(buf.pop(next_seq))
                    next_seq += 1
                break
            continue
        seq, line = item
        if seq == next_seq:
            print(line)
            next_seq += 1
            while next_seq in buf:
                print(buf.pop(next_seq))
                next_seq += 1
        else:
            buf[seq] = line

def run(path: str, info, n_workers: int = 4) -> None:
    in_q: Queue[Optional[LineItem]] = Queue(maxsize=10000)
    out_q: Queue[Optional[LineItem]] = Queue(maxsize=10000)
    info.compile()

    t_r = threading.Thread(target=reader, args=(path, in_q, n_workers))
    ws = [threading.Thread(target=worker, args=(in_q, out_q, info))
          for _ in range(n_workers)]
    t_s = threading.Thread(target=sink, args=(out_q, n_workers, info))

    t_r.start(); [w.start() for w in ws]; t_s.start()
    t_r.join(); [w.join() for w in ws]; t_s.join()