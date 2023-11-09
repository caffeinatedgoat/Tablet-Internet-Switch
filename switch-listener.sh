#!/bin/bash

LOG_FILE="/var/log/switch_listener.log"
PROGRAM_LOG_FILE="/var/log/disable-tablet.log"
PROGRAM="/usr/sbin/arpspoof -i eth0 -t 192.168.1.223 -r 192.168.1.204"
GPIO_PIN=2
PID_FILE="/var/run/disable-tablet.pid"
SLEEP_INTERVAL=1
KILL_WAIT_TIME=60
ALREADY_RUNNING_LOGGED=false
NO_PID_FILE_LOGGED=false

# Function to log messages
log_action() {
    echo "$(date +"%Y-%m-%d %H:%M:%S") - $1" >> "$LOG_FILE"
}

# Function to start the external program
start_program() {
    if [ -f "$PID_FILE" ]; then
        PID=$(cat "$PID_FILE")
        if kill -0 "$PID" 2> /dev/null; then
            if [ "$ALREADY_RUNNING_LOGGED" = false ]; then
                log_action "The program is already running with PID $PID."
                ALREADY_RUNNING_LOGGED=true
            fi
            return
        else
            log_action "PID file exists but the program does not seem to be running. Cleaning up."
            rm -f "$PID_FILE"
            ALREADY_RUNNING_LOGGED=false
        fi
    fi

    log_action "Starting the program."
    $PROGRAM >> "$PROGRAM_LOG_FILE" 2>&1 &
    PID=$!
    echo $PID > "$PID_FILE"
    NO_PID_FILE_LOGGED=false
    log_action "Program started with PID $PID."
    ALREADY_RUNNING_LOGGED=false
}

# Function to stop the external program
stop_program() {
    if [ -f "$PID_FILE" ]; then
        PID=$(cat "$PID_FILE")
        if kill -0 "$PID" 2> /dev/null; then
            log_action "Stopping the program with PID $PID."
            kill -TERM "$PID"
            local count=0
            while kill -0 "$PID" 2> /dev/null; do
                if [ $count -ge $KILL_WAIT_TIME ]; then
                    log_action "Program did not terminate after $KILL_WAIT_TIME seconds, sending KILL signal."
                    kill -KILL "$PID"
                    break
                fi
                if [ "$CLEAN_UP" = true ]; then
                    log_action "Cleanup called; sending KILL signal."
                    kill -KILL "$PID"
                    break
                fi
                sleep $SLEEP_INTERVAL
                let count+=SLEEP_INTERVAL
            done
            rm -f "$PID_FILE"
            log_action "Program stopped."
        else
            log_action "Program is not running."
        fi
    else
	if [[ "$NO_PID_FILE_LOGGED" == false ]]; then
            log_action "No PID file found."
            NO_PID_FILE_LOGGED=true
	fi
    fi
}

# Function to initialize GPIO pin
init_gpio() {
    echo "$GPIO_PIN" > /sys/class/gpio/export
    echo "in" > "/sys/class/gpio/gpio$GPIO_PIN/direction"
}

# Function to read GPIO pin state
read_gpio() {
    cat "/sys/class/gpio/gpio$GPIO_PIN/value"
}

# Function to clean up GPIO before exit
cleanup_gpio() {
    echo "$GPIO_PIN" > /sys/class/gpio/unexport
}

# Trap for clean exit
trap 'CLEAN_UP=true; stop_program; cleanup_gpio; log_action "Exiting."; exit 0' SIGTERM SIGINT

# Initialize GPIO pin
init_gpio

# Main daemon loop
log_action "Entering main daemon loop."
while true; do
    GPIO_STATE=$(read_gpio)
    if [ "$GPIO_STATE" -eq 1 ]; then
        start_program
    elif [ "$GPIO_STATE" -eq 0 ]; then
        stop_program
    fi

    # Sleep for a while before checking again
    sleep $SLEEP_INTERVAL
done

