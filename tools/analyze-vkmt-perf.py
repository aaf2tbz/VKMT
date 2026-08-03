#!/usr/bin/env python3
"""Validate P0 correlation coverage and report per-run phase durations."""
from __future__ import annotations

import csv
import glob
import os
import sys
from collections import defaultdict


def main() -> int:
    if len(sys.argv) != 3:
        print(f"usage: {sys.argv[0]} TRACE_DIR OUTPUT_TSV", file=sys.stderr)
        return 2
    trace_dir, output = sys.argv[1:]
    allow_provider_gap = os.environ.get("VKMT_PERF_ALLOW_PROVIDER_TELEMETRY_GAP") == "1"
    events: dict[str, list[dict[str, str]]] = defaultdict(list)
    for path in glob.glob(os.path.join(trace_dir, "*.tsv")):
        with open(path, newline="", encoding="utf-8") as stream:
            for record in csv.DictReader(stream, delimiter="\t"):
                if record.get("schema") != "VKMT_PERF_V1":
                    continue
                record["monotonic_ns"] = int(record["monotonic_ns"])  # type: ignore[assignment]
                events[record["run_id"]].append(record)

    host_required = {
        "launch_request", "wine_spawn", "runtime_ready", "wineserver_connect_enter",
        "wineserver_connect_complete", "ntdll_process_init_enter",
        "ntdll_process_init_complete", "process_exit",
    }
    provider_required = {
        "process_init_enter", "context_init_enter", "context_init_complete",
        "process_init_complete", "thread_init_enter", "thread_init_complete",
        "process_term_before",
    }
    header = [
        "run_id", "coverage", "total_ms", "loader_ms", "server_connect_ms",
        "ntdll_init_ms", "fex_context_ms", "fex_process_init_ms", "guest_lifetime_ms",
    ]
    failures = []
    with open(output, "w", newline="", encoding="utf-8") as stream:
        writer = csv.writer(stream, delimiter="\t")
        writer.writerow(header)
        for run_id in sorted(events):
            records = events[run_id]
            is_primer = "_primer-" in run_id
            if is_primer:
                # The persistent-session primer intentionally launches Wine's
                # service closure rather than the measured guest. It is
                # useful for warming the session, but is not a guest phase
                # correlation and must not poison the measured rows.
                records = [record for record in records if record["component"] == "vkmt-launcher"]
                by_name: dict[str, list[int]] = defaultdict(list)
                for record in records:
                    by_name[record["event"]].append(record["monotonic_ns"])
                writer.writerow([run_id, "PRIMER", "", "", "", "", "", "", ""])
                continue
            guest_names = {
                record["executable"].replace("\\", "/").rsplit("/", 1)[-1].lower()
                for record in records if record["component"].startswith("fex-")
            }
            if len(guest_names) == 1:
                guest_name = next(iter(guest_names))
            elif allow_provider_gap:
                # P8 providers may intentionally omit FEX lifecycle TSV rows.
                # Recover the guest image from the non-launcher host records,
                # but retain the telemetry gap in the coverage column.
                host_names = {
                    record["executable"].replace("\\", "/").rsplit("/", 1)[-1].lower()
                    for record in records if record["component"] != "vkmt-launcher"
                }
                if len(host_names) == 1:
                    guest_name = next(iter(host_names))
                else:
                    failures.append((run_id, ["unambiguous_guest_executable"]))
                    guest_name = ""
            else:
                failures.append((run_id, ["unambiguous_guest_executable"]))
                guest_name = ""
            records = [
                record for record in records
                if record["component"] == "vkmt-launcher"
                or record["executable"].replace("\\", "/").rsplit("/", 1)[-1].lower() == guest_name
            ]
            by_name: dict[str, list[int]] = defaultdict(list)
            for record in records:
                by_name[record["event"]].append(record["monotonic_ns"])  # type: ignore[arg-type]
            missing_host = sorted(host_required - set(by_name))
            missing_provider = sorted(provider_required - set(by_name))
            missing = missing_host + ([] if allow_provider_gap else missing_provider)
            coverage = "PASS"
            if missing_host or (missing_provider and not allow_provider_gap):
                failures.append((run_id, missing))
            elif missing_provider or not guest_names:
                if allow_provider_gap:
                    details = []
                    if not guest_names:
                        details.append("provider_telemetry_unavailable")
                    if missing_provider:
                        details.append("missing_provider:" + ",".join(missing_provider))
                    coverage = "OBSERVE:" + ";".join(details)
                else:
                    coverage = "MISSING:" + ",".join(missing_provider)
            elif missing:
                coverage = "MISSING:" + ",".join(missing)

            def first(name: str) -> int:
                return min(by_name[name]) if by_name[name] else 0

            def last(name: str) -> int:
                return max(by_name[name]) if by_name[name] else 0

            def duration(start: str, end: str) -> str:
                a, b = first(start), last(end)
                return f"{(b - a) / 1_000_000:.3f}" if a and b and b >= a else ""

            writer.writerow([
                run_id, coverage,
                duration("launch_request", "process_exit"),
                duration("launch_request", "runtime_ready"),
                duration("wineserver_connect_enter", "wineserver_connect_complete"),
                duration("ntdll_process_init_enter", "ntdll_process_init_complete"),
                duration("context_init_enter", "context_init_complete"),
                duration("process_init_enter", "process_init_complete"),
                duration("thread_init_complete", "process_term_before"),
            ])

    if failures:
        for run_id, missing in failures:
            print(f"{run_id}: missing correlated events: {','.join(missing)}", file=sys.stderr)
        return 1
    print(f"VKMT_PERF_P0_CORRELATION_OK runs={len(events)} output={output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
