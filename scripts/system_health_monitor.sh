
#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# system_health_monitor.sh
# Monitors CPU, memory, disk space and process count.
# Sends alerts to console and appends to a log file when thresholds are crossed.
#
# Usage:  ./system_health_monitor.sh [--log /path/to/log] [--interval 60]
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

# ── Defaults ──────────────────────────────────────────────────────────────────
LOG_FILE="/var/log/system_health.log"
INTERVAL=60          # seconds between checks (0 = run once)

# ── Alert thresholds (%) ──────────────────────────────────────────────────────
CPU_THRESHOLD=80
MEM_THRESHOLD=80
DISK_THRESHOLD=80
PROC_THRESHOLD=300   # number of running processes

# ── Colors ────────────────────────────────────────────────────────────────────
RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
NC='\033[0m'   # no color

# ── Parse CLI arguments ────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
    case "$1" in
        --log)      LOG_FILE="$2"; shift 2 ;;
        --interval) INTERVAL="$2"; shift 2 ;;
        --cpu)      CPU_THRESHOLD="$2"; shift 2 ;;
        --mem)      MEM_THRESHOLD="$2"; shift 2 ;;
        --disk)     DISK_THRESHOLD="$2"; shift 2 ;;
        --procs)    PROC_THRESHOLD="$2"; shift 2 ;;
        -h|--help)
            echo "Usage: $0 [--log FILE] [--interval SEC] [--cpu N] [--mem N] [--disk N] [--procs N]"
            exit 0 ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
done

# ── Helper: log + print ────────────────────────────────────────────────────────
log() {
    local level="$1"; shift
    local msg="$*"
    local ts; ts=$(date '+%Y-%m-%d %H:%M:%S')
    echo "${ts} [${level}] ${msg}" >> "$LOG_FILE"

    case "$level" in
        ALERT)   echo -e "${RED}[ALERT]${NC}  ${msg}" ;;
        WARN)    echo -e "${YELLOW}[WARN]${NC}   ${msg}" ;;
        OK)      echo -e "${GREEN}[OK]${NC}     ${msg}" ;;
        INFO)    echo -e "${CYAN}[INFO]${NC}   ${msg}" ;;
    esac
}

# ── Ensure log directory exists ────────────────────────────────────────────────
mkdir -p "$(dirname "$LOG_FILE")"

# ── Check CPU usage ────────────────────────────────────────────────────────────
check_cpu() {
    # Average idle % over 1 second, then compute usage
    local idle; idle=$(top -bn1 | grep "Cpu(s)" | awk '{print $8}' | tr -d '%,')
    # fallback for different top output formats
    if [[ -z "$idle" ]]; then
        idle=$(top -bn1 | grep "%Cpu" | awk '{print $8}')
    fi
    local usage; usage=$(awk "BEGIN{printf \"%.0f\", 100 - ${idle//,/}}")

    if (( usage >= CPU_THRESHOLD )); then
        log ALERT "CPU usage is ${usage}% (threshold: ${CPU_THRESHOLD}%)"
    else
        log OK    "CPU usage is ${usage}%"
    fi
}

# ── Check memory usage ─────────────────────────────────────────────────────────
check_memory() {
    local total used usage
    read -r total used _ < <(free -m | awk '/^Mem:/{print $2, $3, $4}')
    usage=$(awk "BEGIN{printf \"%.0f\", ($used/$total)*100}")

    if (( usage >= MEM_THRESHOLD )); then
        log ALERT "Memory usage is ${usage}% (${used}MB / ${total}MB) [threshold: ${MEM_THRESHOLD}%]"
    else
        log OK    "Memory usage is ${usage}% (${used}MB / ${total}MB)"
    fi
}

# ── Check disk space ───────────────────────────────────────────────────────────
check_disk() {
    local alerted=0
    while IFS= read -r line; do
        local usage mount
        usage=$(echo "$line" | awk '{print $5}' | tr -d '%')
        mount=$(echo "$line" | awk '{print $6}')

        if (( usage >= DISK_THRESHOLD )); then
            log ALERT "Disk ${mount} is ${usage}% full (threshold: ${DISK_THRESHOLD}%)"
            alerted=1
        else
            log OK    "Disk ${mount} is ${usage}% full"
        fi
    done < <(df -h --output=source,size,used,avail,pcent,target | tail -n +2 | grep -v tmpfs)

    [[ $alerted -eq 0 ]] || return 0
}

# ── Check running processes ────────────────────────────────────────────────────
check_processes() {
    local count; count=$(ps aux --no-header | wc -l)

    if (( count >= PROC_THRESHOLD )); then
        log WARN "Running process count is ${count} (threshold: ${PROC_THRESHOLD})"
        log INFO "Top 5 CPU-consuming processes:"
        ps aux --sort=-%cpu --no-header | head -5 | \
            awk '{printf "  %-10s %-6s %s%%  %s\n", $1, $2, $3, $11}' | \
            tee -a "$LOG_FILE"
    else
        log OK   "Running process count is ${count}"
    fi
}

# ── Main loop ──────────────────────────────────────────────────────────────────
run_checks() {
    log INFO "──────────── Health Check @ $(date '+%Y-%m-%d %H:%M:%S') ────────────"
    check_cpu
    check_memory
    check_disk
    check_processes
    log INFO "──────────────────────────────────────────────────────────────────"
}

echo -e "${CYAN}System Health Monitor started. Thresholds → CPU:${CPU_THRESHOLD}% MEM:${MEM_THRESHOLD}% DISK:${DISK_THRESHOLD}% PROCS:${PROC_THRESHOLD}${NC}"
echo "Logging to: $LOG_FILE"

if (( INTERVAL == 0 )); then
    run_checks
else
    while true; do
        run_checks
        sleep "$INTERVAL"
    done
fi
