#!/usr/bin/env python3
"""
app_health_checker.py
─────────────────────
Checks the uptime / health of one or more HTTP(S) applications by inspecting
their HTTP status codes and optional response content.

Usage:
    python3 app_health_checker.py [OPTIONS] URL [URL ...]

Examples:
    # Check a single endpoint
    python3 app_health_checker.py https://example.com

    # Check multiple endpoints with a custom timeout
    python3 app_health_checker.py --timeout 5 https://app1.example.com https://app2.example.com

    # Load URLs from a file, write report to JSON
    python3 app_health_checker.py --file urls.txt --output report.json

    # Continuous monitoring every 30 seconds
    python3 app_health_checker.py --interval 30 https://example.com
"""

import argparse
import json
import logging
import sys
import time
from dataclasses import dataclass, field, asdict
from datetime import datetime, timezone
from typing import List, Optional

import urllib.request
import urllib.error

# ── Logging setup ──────────────────────────────────────────────────────────────
logging.basicConfig(
    format="%(asctime)s  %(levelname)-8s  %(message)s",
    datefmt="%Y-%m-%d %H:%M:%S",
    level=logging.INFO,
)
log = logging.getLogger(__name__)

# ── ANSI colours ───────────────────────────────────────────────────────────────
GREEN  = "\033[92m"
RED    = "\033[91m"
YELLOW = "\033[93m"
CYAN   = "\033[96m"
RESET  = "\033[0m"


# ── Data model ─────────────────────────────────────────────────────────────────
@dataclass
class HealthResult:
    url: str
    status: str               # "UP" | "DOWN" | "DEGRADED"
    http_code: Optional[int]
    response_time_ms: float
    timestamp: str
    error: Optional[str] = None
    notes: List[str] = field(default_factory=list)


# ── Core check logic ───────────────────────────────────────────────────────────
def check_endpoint(url: str, timeout: int = 10, keyword: Optional[str] = None) -> HealthResult:
    """
    Perform an HTTP GET request and evaluate the application health.

    Parameters
    ----------
    url     : The endpoint URL to check.
    timeout : Request timeout in seconds.
    keyword : Optional string that must appear in the response body for UP status.

    Returns
    -------
    HealthResult with status UP / DOWN / DEGRADED.
    """
    ts = datetime.now(timezone.utc).isoformat()
    start = time.monotonic()

    try:
        req = urllib.request.Request(url, headers={"User-Agent": "AppHealthChecker/1.0"})
        with urllib.request.urlopen(req, timeout=timeout) as response:
            elapsed_ms = (time.monotonic() - start) * 1000
            code: int = response.status
            body: str = response.read(4096).decode("utf-8", errors="replace")

    except urllib.error.HTTPError as exc:
        elapsed_ms = (time.monotonic() - start) * 1000
        code = exc.code
        body = ""
        # 4xx/5xx → DOWN
        return HealthResult(
            url=url, status="DOWN", http_code=code,
            response_time_ms=round(elapsed_ms, 2), timestamp=ts,
            error=f"HTTP {code}: {exc.reason}",
        )

    except urllib.error.URLError as exc:
        elapsed_ms = (time.monotonic() - start) * 1000
        return HealthResult(
            url=url, status="DOWN", http_code=None,
            response_time_ms=round(elapsed_ms, 2), timestamp=ts,
            error=str(exc.reason),
        )

    except Exception as exc:  # noqa: BLE001
        elapsed_ms = (time.monotonic() - start) * 1000
        return HealthResult(
            url=url, status="DOWN", http_code=None,
            response_time_ms=round(elapsed_ms, 2), timestamp=ts,
            error=str(exc),
        )

    # ── Evaluate status ────────────────────────────────────────────────────────
    notes: List[str] = []
    status = "UP"

    # 2xx → healthy base
    if 200 <= code < 300:
        status = "UP"
    elif 300 <= code < 400:
        status = "DEGRADED"
        notes.append(f"Redirect: {code}")
    else:
        status = "DOWN"

    # Optional keyword check
    if keyword and status == "UP":
        if keyword not in body:
            status = "DEGRADED"
            notes.append(f"Keyword '{keyword}' not found in response body")

    # Warn on slow responses (> 3 s)
    if elapsed_ms > 3000:
        notes.append(f"Slow response: {elapsed_ms:.0f}ms")
        if status == "UP":
            status = "DEGRADED"

    return HealthResult(
        url=url, status=status, http_code=code,
        response_time_ms=round(elapsed_ms, 2), timestamp=ts,
        notes=notes,
    )


# ── Formatting ─────────────────────────────────────────────────────────────────
STATUS_COLOUR = {"UP": GREEN, "DOWN": RED, "DEGRADED": YELLOW}

def _colour(status: str) -> str:
    return f"{STATUS_COLOUR.get(status, RESET)}[{status}]{RESET}"


def print_result(r: HealthResult) -> None:
    http = f"HTTP {r.http_code}" if r.http_code else "No response"
    extra = f"  ({'; '.join(r.notes)})" if r.notes else ""
    err   = f"  ⚠  {r.error}" if r.error else ""
    print(
        f"  {_colour(r.status):30s}  {r.url}\n"
        f"           ↳ {http}  •  {r.response_time_ms:.0f}ms{extra}{err}"
    )


def print_summary(results: List[HealthResult]) -> None:
    total = len(results)
    up    = sum(1 for r in results if r.status == "UP")
    down  = sum(1 for r in results if r.status == "DOWN")
    deg   = sum(1 for r in results if r.status == "DEGRADED")
    print(
        f"\n{CYAN}────────── Summary ──────────{RESET}\n"
        f"  Total   : {total}\n"
        f"  {GREEN}UP      : {up}{RESET}\n"
        f"  {YELLOW}DEGRADED: {deg}{RESET}\n"
        f"  {RED}DOWN    : {down}{RESET}\n"
    )


# ── Main ───────────────────────────────────────────────────────────────────────
def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Check the health / uptime of HTTP(S) applications.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    parser.add_argument("urls", nargs="*", help="One or more URLs to check.")
    parser.add_argument("--file",     help="File with one URL per line.")
    parser.add_argument("--timeout",  type=int, default=10, help="Request timeout (seconds). Default: 10")
    parser.add_argument("--interval", type=int, default=0,  help="Poll interval (seconds). 0 = run once.")
    parser.add_argument("--keyword",  help="String that must appear in response body.")
    parser.add_argument("--output",   help="Write JSON report to this file.")
    parser.add_argument("--fail-fast", action="store_true",
                        help="Exit with code 1 if any endpoint is DOWN.")
    return parser.parse_args()


def collect_urls(args: argparse.Namespace) -> List[str]:
    urls = list(args.urls)
    if args.file:
        try:
            with open(args.file) as fh:
                urls.extend(line.strip() for line in fh if line.strip() and not line.startswith("#"))
        except FileNotFoundError:
            log.error("URL file not found: %s", args.file)
            sys.exit(1)
    if not urls:
        log.error("No URLs provided. Use positional args or --file.")
        sys.exit(1)
    return urls


def run_once(urls: List[str], args: argparse.Namespace) -> List[HealthResult]:
    print(f"\n{CYAN}Health Check @ {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}{RESET}")
    print("─" * 60)
    results: List[HealthResult] = []
    for url in urls:
        result = check_endpoint(url, timeout=args.timeout, keyword=args.keyword)
        print_result(result)
        results.append(result)
    print_summary(results)

    if args.output:
        with open(args.output, "w") as fh:
            json.dump([asdict(r) for r in results], fh, indent=2)
        print(f"Report written to: {args.output}")

    return results


def main() -> None:
    args = parse_args()
    urls = collect_urls(args)

    if args.interval > 0:
        while True:
            results = run_once(urls, args)
            if args.fail_fast and any(r.status == "DOWN" for r in results):
                sys.exit(1)
            print(f"\nNext check in {args.interval}s …  (Ctrl-C to stop)")
            time.sleep(args.interval)
    else:
        results = run_once(urls, args)
        if args.fail_fast and any(r.status == "DOWN" for r in results):
            sys.exit(1)


if __name__ == "__main__":
    main()
