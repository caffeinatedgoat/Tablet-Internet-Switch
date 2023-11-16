#!/bin/bash

GATEWAY=
TARGET_IP=
TARGET_HOST=tablet_hostname___or_use_ip_above_which_overrides_this
INTERFACE=

LOG_FILE="/var/log/switch_listener.log"
PROGRAM_LOG_FILE="/var/log/disable-tablet.log"
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


get_switch_cmd() {
                                             # interface  target  gateway
    local switch_cmd_template="/usr/sbin/arpspoof -i %s -t %s -r %s"
    local switch_cmd=
    local iface="$INTERFACE"
    local gw="$GATEWAY"
    local targ_ip="$TARGET_IP"

    if [[ -z "$iface" ]]; then
        log_action "Looking up interface"
        iface=$(get_default_interface)
        log_action "Using interfae '$iface'"
    fi

    if [[ -z "$gw" ]]; then
        log_action "Looking up gateway"
        gw=$(get_network_gateway)
        log_action "Using gateway '$gw'"
    fi
        
    if [[ -z "$targ_ip" ]]; then
        if [[ -z "$TARGET_HOST" ]]; then
            log_action "Error: target not specifed."
            return 1;
        else
            log_action "Looking up IP for $TARGET_HOST"
            targ_ip=$(get_ip_by_hostname "$TARGET_HOST")
            if [[ -z "$targ_ip" ]]; then
                log_action "Failed to lookup IP for $TARGET_HOST"
                return 2
            else
                log_action "IP for target ($TARGET_HOST) is $targ_ip"
            fi
        fi
    fi
    
    
    switch_cmd=$(printf "$switch_cmd_template" "$iface" "$targ_ip" "$gw")
    
    log_action "Using switch cmd: '$switch_cmd'"
    echo -n "$switch_cmd"
}



get_ip_by_hostname() {
  [[ -z "$1" ]] && return 1
  host "$1" |cut -d' ' -f4
}


get_default_interface() {
    read -r j j gw j dev j ip j < <(ip route list |grep "^default via ")
    echo "$dev"
}

get_network_gateway() {
    read -r j j gw j dev j ip j < <(ip route list |grep "^default via ")
    echo "$gw"
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
    $(get_switch_cmd) >> "$PROGRAM_LOG_FILE" 2>&1 &
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

