# Settings of a configuration and its schedule in cron format, used by bashclub-zsync-timer, bashclub-zsync-setup
# and the systemd generator bashclub-zsync-generator (sourced, no output of its own)

# value of a setting without running the configuration: last line key=..., quotes removed
conf_value() {
    local file=$1 key=$2 line value
    line=$(grep -E "^[[:space:]]*$key=" "$file" 2> /dev/null | tail -1)
    [[ -n $line ]] || return 0
    value=${line#*=}
    if [[ $value == \"* ]]; then value=${value#\"}; value=${value%%\"*}
    elif [[ $value == \'* ]]; then value=${value#\'}; value=${value%%\'*}
    else value=${value%%[[:space:]]*}; fi
    printf '%s\n' "$value"
}

# write a setting: replaced where it is, appended otherwise; the configuration is run by bash, so a value with other
# characters than letters, digits and _ . : / @ , + = - is written in single quotes (nothing is expanded there),
# a value with ' \ or a line break is refused
set_conf_value() {
    local file=$1 key=$2 value=$3 line
    if ! [[ $key =~ ^[a-z_]+$ ]] || [[ $value == *[\'\\]* ]] || [[ $value == *$'\n'* ]]; then
        echo "invalid value for $key: $value" >&2
        return 1
    fi
    if [[ $value =~ ^[A-Za-z0-9_.:/@,+=-]*$ ]]; then line="$key=$value"; else line="$key='$value'"; fi
    if grep -qE "^[[:space:]]*$key=" "$file"; then
        # the line from the environment: awk -v would interpret backslashes
        line=$line awk -v k="$key" '$0 ~ "^[[:space:]]*" k "=" { print ENVIRON["line"]; next } { print }' "$file" > "$file.tmp" \
            && cat "$file.tmp" > "$file" && rm -f "$file.tmp"
    else
        printf '%s\n' "$line" >> "$file"
    fi
}

#### checks of values from options, questions and cron jobs
# dataset or pool: components of letters, digits and _ . : - separated by /
valid_dataset() { [[ $1 =~ ^[A-Za-z0-9][A-Za-z0-9_.:-]*(/[A-Za-z0-9_.:-]+)*$ ]]; }
# host name, IPv4 or IPv6 address
valid_host() { [[ $1 =~ ^[A-Za-z0-9]([A-Za-z0-9.-]*[A-Za-z0-9])?$ ]] || [[ $1 =~ ^[0-9A-Fa-f:]+$ ]]; }
valid_port() { [[ $1 =~ ^[0-9]{1,5}$ ]] && [ "$1" -ge 1 ] && [ "$1" -le 65535 ]; }
# user property, e.g. bashclub:zsync
valid_tag() { [[ $1 =~ ^[a-z0-9_.-]+:[a-z0-9_.:-]+$ ]]; }
# snapshot label (part of snapshot names)
valid_label() { [[ $1 =~ ^[A-Za-z0-9][A-Za-z0-9_.:-]*$ ]]; }
valid_user() { [[ $1 =~ ^[a-z_][a-z0-9_-]{0,31}$ ]]; }
# absolute path without spaces, quotes, % (systemd specifiers) and ..
valid_path() { [[ $1 =~ ^/[A-Za-z0-9_./-]+$ ]] && [[ $1 != *..* ]]; }

# trigger of a configuration: systemd, autorun or cron (also without the setting: legacy)
conf_trigger() {
    local trigger
    trigger=$(conf_value "$1" trigger)
    case $trigger in
        systemd|autorun) echo "$trigger" ;;
        *) echo cron ;;
    esac
}

#### cron schedule (5 fields or @keyword) -> OnCalendar, fails if it cannot be converted exactly
# fields: minute hour day-of-month month day-of-week; a-b -> a..b, */n -> start/n, lists stay lists
cron_field() {
    local value=$1 start=$2 part out=() parts
    [[ $value == "*" ]] && { echo "*"; return 0; }
    IFS=',' read -ra parts <<< "$value"
    for part in "${parts[@]}"; do
        if [[ $part =~ ^\*/([0-9]+)$ ]]; then out+=("$start/${BASH_REMATCH[1]}")
        elif [[ $part =~ ^([0-9]+)/([0-9]+)$ ]]; then out+=("${BASH_REMATCH[1]}/${BASH_REMATCH[2]}")
        elif [[ $part =~ ^([0-9]+)-([0-9]+)$ ]]; then out+=("${BASH_REMATCH[1]}..${BASH_REMATCH[2]}")
        elif [[ $part =~ ^[0-9]+$ ]]; then out+=("$part")
        else return 1
        fi
    done
    (IFS=','; echo "${out[*]}")
}
cron_dow() {
    local value=${1,,} part out=() parts names=(sun mon tue wed thu fri sat sun) a b n
    [[ $value == "*" ]] && return 0
    IFS=',' read -ra parts <<< "$value"
    for part in "${parts[@]}"; do
        for n in 0 1 2 3 4 5 6 7; do part=${part//${names[$n]}/$n}; done
        if [[ $part =~ ^([0-7])-([0-7])$ ]]; then
            a=${names[${BASH_REMATCH[1]}]^}; b=${names[${BASH_REMATCH[2]}]^}; out+=("$a..$b")
        elif [[ $part =~ ^[0-7]$ ]]; then out+=("${names[$part]^}")
        else return 1
        fi
    done
    (IFS=','; echo "${out[*]}")
}
cron_to_calendar() {
    case $1 in
        @hourly) echo hourly; return ;; @daily|@midnight) echo daily; return ;; @weekly) echo weekly; return ;;
        @monthly) echo monthly; return ;; @yearly|@annually) echo yearly; return ;; @*) return 1 ;;
    esac
    local min hour dom mon dow d m h mi rest
    read -r min hour dom mon dow rest <<< "$1"
    [[ -n $dow && -z $rest ]] || return 1
    mi=$(cron_field "$min" 0) && h=$(cron_field "$hour" 0) && d=$(cron_field "$dom" 1) && m=$(cron_field "$mon" 1) \
        && dow=$(cron_dow "$dow") || return 1
    # minutes with two digits for single values (systemd accepts both, the output is easier to read)
    [[ $mi =~ ^[0-9]$ ]] && mi=0$mi
    echo "${dow:+$dow }*-$m-$d $h:$mi:00"
}

# schedule setting: one or more cron schedules separated by ";" -> one OnCalendar per line
schedule_calendars() {
    local entries entry calendar out=()
    IFS=';' read -ra entries <<< "$1"
    for entry in "${entries[@]}"; do
        # trim spaces (no echo: * would be expanded)
        entry=${entry#"${entry%%[![:space:]]*}"}
        entry=${entry%"${entry##*[![:space:]]}"}
        [[ -n $entry ]] || continue
        calendar=$(cron_to_calendar "$entry") || return 1
        out+=("$calendar")
    done
    [ ${#out[@]} -gt 0 ] || return 1
    printf '%s\n' "${out[@]}"
}

# configuration name usable as unit instance (bashclub-zsync@<name>.timer)
valid_name() {
    [[ $1 =~ ^[A-Za-z0-9_.-]+$ ]]
}
