##########################################################################
#
# MakeStaticSite --- a shell script to create and deploy static websites 
# Copyright 2022-2024 Paul Trafford <pt@ptworld.net>
#
# validate.sh - validation functions for MakeStaticSite
# This file is part of MakeStaticSite.
#
# MakeStaticSite is free software: you can redistribute it and/or modify 
# it under the terms of the GNU Affero General Public License as published 
# by the Free Software Foundation, either version 3 of the License, or 
# (at your option) any later version. MakeStaticSite is distributed in the 
# hope that it will be useful, but WITHOUT ANY WARRANTY; without even the
# implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. 
# See the GNU Affero General Public License for more details.
# You should have received a copy of the GNU General Public License along 
# with MakeStaticSite. If not, see <https://www.gnu.org/licenses/>.
#
##########################################################################


bash_check() {
  BASH_VERSION=${BASH_VERSINFO[0]}
  read -r SH <setup.sh
  shell_path="${SH:2}"
  if [ "$BASH_VERSION" -lt "4" ]; then
    echolog "Just checking your system ..."
    echolog -n "Attention! This script is written in Bash and you are currently using $shell_path, at version $BASH_VERSION. "
    if [ "$BASH_VERSION" = "3" ]; then
      echolog "This is sufficient, but entering setup options will take more effort. "
    else
      echolog " Sorry, this version is not supported, at least 3 is required. "
    fi
    echolog "Looking for other Bash versions in /etc/shells ... "
    alt_bash=$(grep bash /etc/shells | grep -vw "$shell_path")
    if [ "$alt_bash" != "" ]; then
      echolog "You could try updating the default version or else replace the path in the first line of this script (setup.sh) with one of the following alternatives:"
      echolog "$alt_bash"
    else
      echolog -n "Unable to find alternative versions. So, "
      if [ "$BASH_VERSION" -lt "3" ]; then
        echolog -n "in order to proceed please use/install"
      else
        echolog -n "we recommend using/installing"
      fi
      echolog " another version of Bash and add it to /etc/shells"
    fi
    echolog "Please press any key to continue ... "
    read -r -s -n 1
  fi
}

cmd_check() {
  [ -z ${1+x} ] && echolog "Checking command: $1" "$2"
  if ! command -v "$1" 1> /dev/null; then
    [ -z ${1+x} ] && echolog "There doesn't appear to be a valid command at $1"
    return 1
  fi
}

version() {
  printf "%s" "$@" | awk -F. '{ printf("%d%03d%03d%03d\n", $1,$2,$3,$4); }';
}

version_check() {
  if [ "$(version "$2")" -gt "$(version "$1")" ]; then
    [ -z ${2+x} ] && echolog "The version $1 is older than the recommended version $2"
    return 1
  fi
}

# Expects 1 parameter + 2 optional
# - directory path
# - (optional) prefix, such as remote ssh
validate_dir() {
  echo "$1"
  local err_msg="There doesn't appear to be a valid directory at $1"
  if [ -n "${2+x}" ]; then
    "$2" [ -d "$1" ] || { echolog "$err_msg"; return 1; }
  else
    [ -d "$1" ] || { echolog "$err_msg"; return 1; }
  fi
}

# Timestamp validation (up to year 2999)
# Expected format: YYYYMMDDhhmmss
# Allows substring matches (YYYY, YYYYMM, and so on)
validate_timestamp() {
  # First, test special cases: YYYY, YYYYMM
  local y="^[0-2][0-9]{3}"
  local t_m1="${1:4:1}"; local t_m2="${1:5:1}"

  case ${#1} in
    "4")
      if [[ $1 =~ ^$y ]]; then
        return 0
      else
        return 1
      fi
      exit
      ;;
    "6")
      if [[ $1 =~ ^$y ]] && { (( t_m1 == 0 )) || { (( t_m1 == 1 )) && (( t_m2 <= 2 )); }; }; then
        return 0
      else
        return 1
      fi
      exit
      ;;
     *)
      echo 
      ;; 
  esac

  # convert fully numeric timestamp to one acceptable to date command
  local t="${1:0:4}-${1:4:2}-${1:6:2} ${1:8:2}:${1:10:2}:${1:12:2}"

  local date_options=()
  if [ "$ostype" = "BSD" ]; then
    date_options+=(-j)
    date_options+=(-f "%Y-%m-%d %H:%M:%S")
  else
    date_options+=(-d)
  fi
  date_options+=("$t")
  if [[ $1 =~ ^[0-2][0-9]{3}[0-1][0-9][0-3][0-9][0-2][0-9][0-5][0-9][0-5][0-9]$ ]] && date "${date_options[@]}" >/dev/null 2>&1; then
    return 0
  else
    return 1  
  fi
}

validate_domain() {
  if [[ ! $1 =~ $domain_re ]]; then
    return 1
  fi
}

validate_url() {
  if [[ ! $1 =~ $url_re ]]; then
    return 1
  fi
}

# Test internet connection:
# ping default gateway with aid of ip command or, if not available, use netcat
validate_internet() {
  if command -v "ip" 1> /dev/null; then
    ping -q -w 1 -c 1 "$(ip r | grep default | cut -d ' ' -f 3)" > /dev/null 2>&1 && return 0 || return 1
  else
    printf "GET http://google.com HTTP/1.0\n\n" | nc google.com 80 > /dev/null 2>&1 && return 0 || return 1
  fi  
}


# Receives one required parameter (URL)
# and two optional parameters:
# - variable name for dynamically updating URLs following redirection
# - mode ('quiet' to suppress output to terminal)
# Uses cURL with following options:
#  -A (--user-agent): specify user agent
#  -s (--silent): no download progress bar
#  -k (--insecure): don't verify security of connection
#  -w (--write-out): on completion, display HTTP code (variable) on stdout
#  -o: send output to null device
validate_http() {
  local e msg_status="Checking connection to $1 ..."
  if [ "$3" = "quiet" ]; then
    e="1"
  else
    echolog "$msg_status"
  fi
  curl_options=(-s -k)
  if [ "$wget_user_agent" != "" ] && [ "$wget_user_agent" != "default" ];then
    curl_options+=(-A "$wget_user_agent") # note that we don't need to insert extra quotes
  fi
  curl_options+=(--head -w "%{http_code}" "$1" -o /dev/null)
  status="$(curl "${curl_options[@]}")"
  if [ "$status" = "200" ]; then
    echolog "Connection established OK."
    return
  elif [ "$status" = "301" ] || [ "$status" = "302" ] || [ "$status" = "307" ] || [ "$status" = "308" ]; then
    url_effective=$(curl -s -k -L --max-redirs "$max_redirects" -o /dev/null -w "%{url_effective}" "$1") || { echolog "$msg_error: Unable to follow the redirection"; return 1; } # -L: follow redirects up to the value of max_redirects
    msg_redirect="Redirect detected (HTTP code $status) from $1 to $url_effective. "
    # If url simply adds a trailing slash to url_effective, then don't change it
    # because we need to respect Wget --no-parent option
    if [ "$1" = "$url_effective/" ]; then
      msg_redirect="$msg_info: $msg_redirect Retaining the URL as the server will just remove the trailing slash, whilst we need to the slash for Wget --no-parent option ... "
      echolog -n "$msg_redirect"
    else
      echolog "$msg_warning: $msg_redirect"
      # Require the user to confirm (y/n):
      if [ "$run_unattended" != "yes" ]; then
        read -r -e -p "Do you wish to proceed with the redirection? [Y/n] " confirm < /dev/tty
        confirm=${confirm:0:1}
      else
        confirm=Y
      fi
      if [ "$confirm" != "Y" ] && [ "$confirm" != "y" ] && [ "$confirm" != "" ]; then
        printf "%s\n" "OK. Will not redirect."
      else
        echolog "OK.  URL effectively redirected from $1 to $url_effective."
        # Having specified the effective URL, checks its status
        status_redirect="$(curl -s -k  --max-redirs "$max_redirects" --head -w "%{http_code}" "$url_effective" -o /dev/null)"
        if [ -n "${2+x}" ]; then
          printf -v "$2" '%s' "$url_effective"
          msg_redirect="Following redirection, value of variable $2 changed to $url_effective."
          [ "${BASH_SOURCE[1]}" = './makestaticsite.sh' ] && msg_redirect+=" Please ensure that this value is stored in the configuration file to avoid potential issues in generating the mirror."
          echolog "$msg_redirect"; return
        fi
        if [ "$status_redirect" = "200" ]; then
          echolog "Connection established OK."
          return
        elif [ "$status_redirect" = "401" ]; then
          echolog "$msg_warning: unauthorised (HTTP code $status). This means that you will need to enter a username and password as wget parameters for wget_extra_options (which you can set a bit later)."
        else
          echolog "$msg_error: failed to connect; the response code was $status (exit code: $?). Please try again."
          return 1
        fi
      fi
    fi
  elif [ "$status" = "401" ]; then
    echolog "$msg_warning: unauthorised (HTTP response code $status).  This means that you will need to enter a username and password as wget parameters for wget_extra_options (which you can set a bit later)."
  elif [ "$status" = "404" ]; then
    echolog "$msg_error: File not found (HTTP response code $status). The server was unable to find any resource at this URL."
    return 1
  elif [ "$run_unattended" = "yes" ]; then
    echolog "$msg_error: failed to connect; the HTTP response code was $status (exit code: $?). Aborting.  Please check the URL and your network connectivity."; exit
  else
    echolog -n "$msg_error: Unable to connect to $1. The response code was $status (exit code: $?). "
    ! validate_internet && echolog -n "There doesn't appear to be any Internet connectivity. Is the server up and running? Perhaps you are offline? "
    return 1
  fi
}

# Validate a URL with a range
# Expects two parameters: 
#  - URL 
#  - variable name to store URL
validate_url_range() {
  [ -z ${1+x} ] && { invalid_http_reason="System error: unable to test connectivity as no URL supplied."; return 1; }
  [ -z ${2+x} ] && { invalid_http_reason="System error: unable to test connectivity as no URL variable name supplied."; return 1; }
  url_var="$1"
  # For Wayback URLs with ranges, use (and update) the 'from' date
  datetime_range_check=$(echo "$url_var" | grep "/$datetime_regex-")
  if [ "$datetime_range_check" != "" ]; then
    echolog "Date range detected in URL."
# shellcheck disable=SC2001
    url_from=$(echo "$url_var" | sed 's~\('/"$datetime_regex"'\)-'"$datetime_regex"/'~\1/~')
    wayback_date_from=$(echo "$url_var" | grep -o "/${datetime_regex}-${datetime_regex}/" | grep -o "$datetime_regex\-" | grep -o "$datetime_regex")
    wayback_date_to=$(echo "$url_var" | grep -o "/${datetime_regex}-${datetime_regex}/" | grep -o "\-$datetime_regex" | grep -o "$datetime_regex")
    if (( phase < 4 )) && ! validate_http "$url_from" "url_from" "quiet"; then
      invalid_http_reason="The URL (assumed as Wayback) is invalid."
    else
      url_var=$(echo "$url_from" | sed 's~\('/"$datetime_regex"'\)/~\1'"-$wayback_date_to"'/~')
    fi
# shellcheck disable=SC2001
    url_var=$(echo "$url_from" | sed 's~\('/"$datetime_regex"'\)/~\1'"-$wayback_date_to"'/~')
  elif (( phase < 4 )) && ! validate_http "$url_var" "url_var"; then
    invalid_http_reason="Unable to connect to URL."
  fi
  printf -v "$2" '%s' "$url_var" 
}

validate_yesno() {
  # Assume that any option that starts with 'n' or 'N' is a 'no', similarly for 'yes'
  if [ "${1:0:1}" != "n" ] && [ "${1:0:1}" != "N" ] && [ "${1:0:1}" != "y" ] && [ "${1:0:1}" != "Y" ]; then
    echolog "Error: please enter 'y' for yes or 'n' for no."
    return 1
  fi
}

# Expects three parameters:
# - prompt text
# - description
# - option variable name
validate_input() {
  while true; do
    if [ "$1" != "" ]; then
      IFS= read -r -e "$1" -p "$2" input_value
    else
      IFS= read -r -e -p "$2" input_value
    fi
    if [ "$input_value" = "" ]; then
      if [[ ! ' '${options_allow_empty[*]}' ' =~ ' '$3' ' ]]; then
        echo "Sorry, this field doesn't permit the value to be empty."
        continue
      fi
    fi
    # trim preceding and trailing whitespace
    input_value="$(echo -e "${input_value}" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
    if [[ ' '${options_check_cmd[*]}' ' =~ ' '$3' ' ]]; then
      cmd_check "$input_value" "" || { echo; continue; }
    fi
    if [[ ' '${options_check_dir[*]}' ' =~ ' '$3' ' ]]; then
      if [[ ' '${options_check_remote[*]}' ' =~ ' '$3' ' ]] &&  [ "$(yesno "$wp_cli_remote")" = "yes" ]; then
        # We are using remote wp-cli
        cmd_prefix=$(remote_command_prefix "$content")
        validate_dir "$input_value" "$cmd_prefix" || { echo; continue; }
      else
        validate_dir "$input_value" || { echo; continue; }
      fi
    fi
    if [[ ' '${options_check_url[*]}' ' =~ ' '$3' ' ]]; then
      invalid_http_reason= # description of invalid http status
      validate_url "$input_value" || { echo "The URL is invalid.  Please try again."; continue; }
      validate_url_range "$input_value" "input_value"
      if [ "$invalid_http_reason" != "" ]; then
        if [ "$run_unattended" = "yes" ]; then
          echo "$invalid_http_reason Aborting."; exit
        else
          echo "$invalid_http_reason"; continue
        fi
      fi
    fi
    if [[ ' '${options_check_yesno[*]}' ' =~ ' '$3' ' ]]; then
      validate_yesno "$input_value" || { echo; continue; }
    fi
    break
  done
}

validate_range() {
  minvalue="$1"; maxvalue="$2"; num="$3"
  # test that it is an integer and that it is in range
  if [[ $num =~ ^-?[0-9]+$ ]] && ((num >= minvalue && num <= maxvalue)); then
    return 0
  else
    return 1
  fi
}

# check URL for Wayback Machine service
# using two methods:
# 1. check list membership
# 2. check header response with cURL
#
# Expects two parameters:
# - URL being tested
# - Wayback list
# Optional parameter:
# - URL variable name (to allow updates)
check_wayback_url(){
  # Read parameters and assign to variables
  local url="$1"
  local wayback_list="$2"
  local host
  host=$(printf "%s" "$url" | awk -F/ '{print $3}' | awk -F: '{print $1}')
  host_wayback=no
  
  # Check list of known Wayback Machine hosts
  if printf "%s" ",$wayback_list," | grep -q ",$host,"; then
    host_wayback=yes
  elif [ "$wayback_memento_check" != "yes" ]; then
    return 1
  # cURL check (-I : header, -s: silent, -k: don't check SSL certs)
  elif curl -skI "$url" | grep -Fiq "$wayback_header"; then
    host_wayback=yes
  fi

  if [ "$host_wayback" = "yes" ]; then 
    # Make URL adjustment when target site missing http protocol
    wayback_date_from_to=$(printf "%s" "$url" | grep -o "/$wayback_datetime_regex/" | grep -o "$wayback_datetime_regex")
    doubleslashes_count=$(echo "$url" | grep -o '//' | wc -l)

    if (( doubleslashes_count < 2 )); then
      url=${url/"$wayback_date_from_to/"/"$wayback_date_from_to"/http://}
      if [ -n "${3+x}" ]; then
        echo "$msg_warning: updating value of URL variable ($3) from $1 to $url..."
        confirm_continue
        printf -v "$3" '%s' "$url"      
      fi 
    fi
    return 0
  fi

  # Failed both checks, so return error status
  return 1
}



