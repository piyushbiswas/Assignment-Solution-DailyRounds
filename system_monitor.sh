#!/bin/bash

# Function to collect system information
get_system_info() {
    echo "System Performance Report"
    echo "----------------------------"
    echo "CPU Usage: $(top -bn1 | grep 'Cpu(s)' | awk '{print $2 + $4}')%"
    echo "Memory Usage:"
    free -h | awk '/Mem:/ {print "  Total: "$2" Used: "$3" Free: "$4}'
    echo "Disk Usage:"
    df -h | awk 'NR==1 || $NF ~ /^\// {print "  "$NF": Total: "$2" Used: "$3" Available: "$4}'
    echo "Top 5 CPU-Consuming Processes:"
    ps -eo pid,comm,%cpu --sort=-%cpu | head -n 6
}

# Function to trigger alerts
trigger_alerts() {
    cpu_usage=$(top -bn1 | grep 'Cpu(s)' | awk '{print $2 + $4}')
    memory_used=$(free | awk '/Mem:/ {print $3}')
    memory_total=$(free | awk '/Mem:/ {print $2}')
    memory_percent=$((memory_used * 100 / memory_total))

    if (( $(echo "$cpu_usage > 80" | bc -l) )); then
        echo "Warning: CPU usage exceeded 80%"
    fi

    if (( memory_percent > 75 )); then
        echo "Warning: Memory usage exceeded 75%"
    fi

    df -h | awk '$6 ~ /^\// && $5+0 > 90 {print "Warning: Disk usage on "$6" exceeded 90%"}'
}

# Function to write report to a file
write_report() {
    local format=$1
    local filename=$2

    if [[ $format == "text" ]]; then
        get_system_info > "$filename"
    elif [[ $format == "json" ]]; then
        {
            echo "{"
            echo "  \"cpu_usage\": $(top -bn1 | grep 'Cpu(s)' | awk '{print $2 + $4}'),"
            echo "  \"memory\": {"
            free -b | awk '/Mem:/ {printf "    \"total\": %d, \"used\": %d, \"free\": %d\n", $2, $3, $4}'
            echo "  },"
            echo "  \"disk_usage\": ["
            df -B1 | awk '$6 ~ /^\// {printf "    {\"mount\": \"%s\", \"total\": %d, \"used\": %d, \"free\": %d},\n", $6, $2, $3, $4}'
            echo "  ],"
            echo "  \"top_processes\": ["
            ps -eo pid,comm,%cpu --sort=-%cpu | head -n 6 | tail -n 5 | awk '{printf "    {\"pid\": %d, \"name\": \"%s\", \"cpu_percent\": %.2f},\n", $1, $2, $3}'
            echo "  ]"
            echo "}"
        } > "$filename"
    elif [[ $format == "csv" ]]; then
        {
            echo "Metric,Value"
            echo "CPU Usage,$(top -bn1 | grep 'Cpu(s)' | awk '{print $2 + $4}')"
            echo "Memory Total,$(free -b | awk '/Mem:/ {print $2}')"
            echo "Memory Used,$(free -b | awk '/Mem:/ {print $3}')"
            echo "Memory Free,$(free -b | awk '/Mem:/ {print $4}')"
            df -h | awk '$6 ~ /^\// {printf "Disk %s,%s,%s,%s\n", $6, $2, $3, $4}'
            ps -eo pid,comm,%cpu --sort=-%cpu | head -n 6 | tail -n 5 | awk '{printf "Process,%d,%s,%.2f\n", $1, $2, $3}'
        } > "$filename"
    else
        echo "Unsupported format: $format" >&2
        exit 1
    fi
}

# Main script
interval=5
format="text"
output="system_report"

while [[ $# -gt 0 ]]; do
    case $1 in
        --interval)
            interval=$2
            shift 2
            ;;
        --format)
            format=$2
            shift 2
            ;;
        --output)
            output=$2
            shift 2
            ;;
        *)
            echo "Unknown option: $1" >&2
            exit 1
            ;;
    esac
done

trap "echo 'Monitoring stopped.'; exit" INT

while true; do
    system_info=$(get_system_info)
    echo "$system_info"

    alerts=$(trigger_alerts)
    if [[ -n $alerts ]]; then
        echo "$alerts"
    fi

    write_report "$format" "$output.$format"
    echo "Report saved to $output.$format"

    sleep "$interval"
done

