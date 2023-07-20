##########################################################################
#
# MakeStaticSite --- a shell script to create and deploy static websites 
# Copyright 2022 Paul Trafford <pt@ptworld.net>
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
    echo "Just checking your system ..."
    echo -n "Attention! This script is written in Bash and you are currently using $shell_path, at version $BASH_VERSION. "
    if [ "$BASH_VERSION" = "3" ]; then
      echo "This is sufficient, but entering setup options will take more effort. "
    else
      echo " Sorry, this version is not supported, at least 3 is required. "
    fi
    echo "Looking for other Bash versions in /etc/shells ... "
    alt_bash=$(grep bash /etc/shells | grep -vw "$shell_path")
    if [ "$alt_bash" != "" ]; then
      echo "You could try updating the default version or else replace the path in the first line of this script (setup.sh) with one of the following alternatives:"
      echo "$alt_bash"
    else
      echo -n "Unable to find alternative versions. So, "
      if [ "$BASH_VERSION" -lt "3" ]; then
        echo -n "in order to proceed please use/install"
      else
        echo -n "we recommend using/installing"
      fi
      echo " another version of Bash and add it to /etc/shells"
    fi
    read -r -e -p "Please press Enter to continue ... " confirm
  fi
}

cmd_check() {
  [ -z ${1+x} ] && echo "Checking command: $1" "$2"
  if ! command -v "$1" 1> /dev/null; then
    [ -z ${1+x} ] && echo "There doesn't appear to be a valid command at $1"
    return 1
  fi
}

version() {
  env echo "$@" | awk -F. '{ printf("%d%03d%03d%03d\n", $1,$2,$3,$4); }';
}

version_check() {
  if [ "$(version "$2")" -gt "$(version "$1")" ]; then
    [ -z ${2+x} ] && echo "The version $1 is older than the recommended version $2"
    return 1
  fi
}

validate_dir() {
  echo "$1"
  [ -d "$1" ] || { echo "There doesn't appear to be a valid directory at $1"; return 1; }
}

# Timestamp validation (up to year 2999)
# Expected format: YYYYMMDDhhmmss
# Allows substring matches (YYYY, YYYYMM, and so on)
validate_timestamp() {
  # First, test special cases: YYYY, YYYYMM
  local y="^[0-2][0-9]{3}"
  local t_y="${1:0:4}"
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

validate_url() {
  url_regex='(https?|ftp|file)://[-[:alnum:]\+&@#/%?=~_|!:,.;]+'
  if [[ ! $1 =~ $url_regex ]]; then
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

validate_http() {
  echo "Checking connection to $1 ..."
  status="$(curl -s -k --head -w "%{http_code}" "$1" -o /dev/null)"
  if [ "$status" = "200" ]; then
    echo "Connection established OK."
  elif [ "$status" = "301" ] || [ "$status" = "302" ]; then
    echo "WARNING: redirect detected (HTTP code $status), proceed with caution."
  elif [ "$status" = "401" ]; then
    echo "WARNING: unauthorised (HTTP code $status).  This means that you will need to enter a username and password as wget parameters for wget_extra_options (which you can set a bit later)."
  else
    echo "ERROR – failed to connect; the response code was $status. Please try again."
    return 1
  fi
}

validate_yesno() {
  # Assume that any option that starts with 'n' or 'N' is a 'no', similarly for 'yes'
  if [ "${1:0:1}" != "n" ] && [ "${1:0:1}" != "N" ] && [ "${1:0:1}" != "y" ] && [ "${1:0:1}" != "Y" ]; then
    echo "Error: please enter 'y' for yes or 'n' for no."
    return 1
  fi
}

validate_input() {
  while true; do
    if [ "$1" != "" ]; then
      IFS= read -r -e "$1" -p "$2" input_value
    else
      IFS= read -r -e -p "$2" input_value
    fi
    if [ "$input_value" = "" ]; then
      if [[ ! " ${options_allow_empty[*]} " =~ " $3 " ]]; then
        echo "Sorry, this field doesn't permit the value to be empty."
        continue
      fi
    fi
    # trim preceding and trailing whitespace
    input_value="$(echo -e "${input_value}" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
    if [[ " ${options_check_cmd[*]} " =~ " $3 " ]]; then
      cmd_check "$input_value" "" || { echo; continue; }
    fi
    if [[ " ${options_check_dir[*]} " =~ " $3 " ]]; then
      validate_dir "$input_value" || { echo; continue; }
    fi
    if [[ " ${options_check_url[*]} " =~ " $3 " ]]; then
      validate_http "$input_value" || { echo; continue; }
    fi
    if [[ " ${options_check_yesno[*]} " =~ " $3 " ]]; then
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

