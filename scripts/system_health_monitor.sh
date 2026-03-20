#!/usr/bin/env bash
# system_health_monitor.sh - Monitors CPU, memory, disk, processes
set -euo pipefail

LOG_FILE="/tmp/system_health.log"
INTERVAL=60
CPU_THRESHOLD=80
MEM_THRESHOLD=80
DISK_THRESHOLD=80
PROC_THRESHOLD=300

log() {
    local level="$1"; shift
    local msg="$*"
    local ts
    ts=$(date '+%Y-%m-%d %H:%M:%S')
    echo "${ts} [${level}] ${msg}" | tee -a "$LOG_FILE"
}

check_cpu() {
    local idle usage
    idle=$(top -bn1 | grep -E "%Cpu|Cpu" | head -1 | awk '{print $8}' | tr -d '%,')
    idle="${idle:-0}"
    usage=$(awk "BEGIN{printf \"%.0f\", 100 - ${idle}}")
    if (( usage >= CPU_THRESHOLD )); then
        log ALERT "CPU usage is ${usage}% (threshold: ${CPU_THRESHOLD}%)"
    else
        log OK "CPU usage is ${usage}%"
    fi
}

check_memory() {
    local total used usage
    total=$(free -m | awk '/^Mem:/{print $2}')
    used=$(free -m | awk '/^Mem:/{print $3}')
    usage=$(awk "BEGIN{printf \"%.0f\", (${used}/${total})*100}")
    if (( usage >= MEM_THRESHOLD )); then
        log ALERT "Memory usage is ${usage}% (${used}MB/${total}MB)"
    else
        log OK "Memory usage is ${usage}% (${used}MB/${total}MB)"
    fi
}

check_disk() {
    while IFS= read -r line; do
        local usage mount
        usage=$(echo "$line" | awk '{print $5}' | tr -d '%')
        mount=$(echo "$line" | awk '{print $6}')
        if (( usage >= DISK_THRESHOLD )); then
            log ALERT "Disk ${mount} is ${usage}% full"
        else
            log OK "Disk ${mount} is ${usage}% full"
        fi
    done < <(df -h | tail -n +2 | grep -v tmpfs)
}

check_processes() {
    local count
    count=$(ps aux --no-header | wc -l)
    if (( count >= PROC_THRESHOLD )); then
        log WARN "Process count is ${count} (threshold: ${PROC_THRESHOLD})"
    else
        log OK "Process count is ${count}"
    fi
}

run_checks() {
    log INFO "── Health Check @ $(date '+%Y-%m-%d %H:%M:%S') ──"
    check_cpu
    check_memory
    check_disk
    check_processes
}

mkdir -p "$(dirname "$LOG_FILE")"

if (( INTERVAL == 0 )); then
    run_checks
else
    while true; do
        run_checks
        sleep "$INTERVAL"
    done
fi
