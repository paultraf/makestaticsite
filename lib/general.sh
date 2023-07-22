##########################################################################
#
# MakeStaticSite --- a shell script to create and deploy static websites 
# Copyright 2022 Paul Trafford <pt@ptworld.net>
#
# general.sh - general functions library for MakeStaticSite
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

if [ "$trap_errors" = "yes" ]; then
# Stop the script if any command [in a pipeline] fails, variable unset; 
# then report 'system error'.  Also disable globbing
  trap 'if [ "$?" != "0" ]; then env echo "An unexpected system error occurred in function ${FUNCNAME} called from line $BASH_LINENO.  Aborting."; fi' EXIT
  set -euf -o pipefail
fi

error_set() {
  if [ "$trap_errors" = "yes" ]; then
    set "$1"
  fi
}

# Return canonical form for on/off, yes/no.
# Assume that any option (first parameter) that 
# starts with 'n' or 'off' (as lower case) is a 'no';
# or 'yes' if it starts with 'y' or 'on' (as lower case) 
# or if second (optional) parameter is not set.
# Otherwise, return original value.
yesno() {
  a=$(echo "$1" | tr '[:upper:]' '[:lower:]')
  if [ "${a:0:1}" = "n" ] || [ "${a:0:3}" = "off" ]; then
    printf "no"
  elif [ -z ${2+x} ] || [ "${a:0:1}" = "y" ] || [ "${a:0:2}" = "on" ]; then
    printf "yes"
  else
    printf "%s" "$1"
  fi
}

pluralize() {
  if [ "$1" != "1" ]; then
    printf "s"
  else
    printf ""
  fi
}

colorize() {
  if [ -z "$TERM" ] || [ "$TERM" = "dumb" ]; then
    printf ""; return 0;
  fi
  case "$1" in
    black)
      printf "%s" "$(tput setaf 0)"
      ;;
    red)
      printf "%s" "$(tput setaf 1)"
      ;;
    green)
      printf "%s" "$(tput setaf 2)"
      ;;
    yellow)
      printf "%s" "$(tput setaf 3)"
      ;;
    blue)
      printf "%s" "$(tput setaf 4)"
      ;;
    magenta)
      printf "%s" "$(tput setaf 5)"
      ;;
    cyan)
      printf "%s" "$(tput setaf 6)"
      ;;
    white)
      printf "%s" "$(tput setaf 7)"
      ;;
    amber)
      printf "%s" "$(tput setaf 130)"
      ;;
    paleblue)
      printf "%s" "$(tput setaf 153)"
      ;;
    lime)
      printf "%s" "$(tput setaf 190)"
      ;;
    reset)
      printf "%s" "$(tput sgr0)"
      ;;
  esac
}

get_inks(){
  colour_reset=$(colorize "reset")
  colour_error=$(colorize $ink_error)
  colour_warning=$(colorize $ink_warning)
  colour_ok=$(colorize $ink_ok)
  colour_info=$(colorize $ink_info)
  # message constants
  msg_info=${colour_info}INFO${colour_reset}
  msg_error=${colour_error}ERROR${colour_reset}
  msg_warning=${colour_warning}WARNING${colour_reset}
  msg_ok=${colour_ok}OK${colour_reset}
}

msg_ink() {
  # expects two parameters: message type and string
  # (info/error/warning/ok)

  case "$1" in
    ok)
      printf "%s%s%s" "$colour_ok" "$2" "$colour_reset"
      ;;
    info)
      printf "%s%s%s" "$colour_info" "$2" "$colour_reset"
      ;;
    warning)
      printf "%s%s%s" "$colour_warning" "$2" "$colour_reset"
      ;;
    error)
      printf "%s%s%s" "$colour_error" "$2" "$colour_reset"
      ;;
    *)
      ;;
  esac
}

whichos() {
  if [[ "$OSTYPE" == "darwin"* ]] || [[ "$OSTYPE" == "freebsd"* ]]; then
    ostype="BSD"
    LC_CTYPE=C && LANG=C
    sed_options=(-i '')
  else
    ostype=""
    sed_options=(-i)
  fi
}

which_version() {
  # expects two parameters: command and unique search string for line containing version number
  "$1" --version | grep "$2" | grep -o -m 1 -- "[0-9]\{1,2\}\.[0-9]\{1,2\}\(\.[0-9]\{1,2\}\)*[ \-]" | head -1 | tr -d '[:space:]-'
}

wget_error_check() {
  # expects one parameters: error level (integer)
  if [ "$wget_error_level" -le "$1" ]; then
    confirm_continue
  else
    echo "Aborting due to wget_error_level setting in constants.sh. To allow continuation, please set its value to less than $1 and rerun."; exit
  fi
}

confirm_continue() {
  if [ "$run_unattended" != "yes" ]; then
    read -r -e -p "Do you wish to continue (y/n)? " confirm
    confirm=${confirm:0:1}
    [ "$confirm" != "y" ] && [ "$confirm" != "Y" ] && { printf "Please review the settings.\nAborting.\n"; exit; } || printf "OK. Continuing.\n"
  else
    echo "Continuing (to run unattended)."
  fi
}

get_phase_desc() {
  for opt in "${all_phases[@]}"; do
    var=$(expr "$opt" : '\([^=]*\)')              # Everything up to '='
    phase_desc=$(expr "$opt" : '[^=]*.\(.*\)')    # Everything after '='
    if [ "$var" = "$1" ];then
      printf "%s" "$phase_desc"; return
    fi
  done
}

# Make some wget options canonical
# Expects wget options string as parameter
wget_canonical_options() {
  wget_options=$1

# exclude directories 
# (note that wget, as of 1.21.3, will not parse --exclude_directories=/some_dir)
  wget_options=${wget_options/--exclude/-X}
  wget_options=${wget_options/exclude_directories=/-X}

# include directories
  wget_options=${wget_options/--include/-I}
  wget_options=${wget_options/include_directories=/-I}

# reject files
  wget_options=${wget_options/--reject/-R}

  env echo "$wget_options"
}

wget_level_comment() {
  if [ "$output_level" = "quiet" ] && [ "$log_level" != "silent" ]; then
    echo "More details are available in the log file"
  fi
}


# Build composite search string for Web assets
# Expects two parameters: comma-separated list of domains, path
assets_search_string() {
  local path="$2"
  local url_path=

  # build up a list of URLs from the domains list for the search
  if [ "$1" != "" ]; then
    IFS="," read -r -a other_domains <<< "$1" 
    for opt in "${other_domains[@]}"; do
      url_path+="|https?://$opt/$path" # the '?' is ERE 0 or 1
    done
  fi
  echo "$url_path"
}

# Generate a list of web pages according to given criteria
# Expects two parameters: directory, search query
# returns a string with a space-separated list of pages
find_web_pages() {
  local webpages=()
  while IFS='' read -r line; do webpages+=("$line"); done < <(grep -Erl "$2" "$1" --include "*\.html")
  echo "${webpages[@]}"
}

# Write contents of a string to a given file
# Expects one parameter: a list with all but the last containing lines and the final one containing a filepath
print_to_file() {
  local a=("$@")
  ((last_idx=${#a[@]} - 1))
  local output_file=${a[last_idx]}
  unset 'a[last_idx]'
  touch "$output_file" || { echo "ERROR: Unable to write to file at $output_file. Please check the directory and file permissions."; exit; }
#  printf "%s\n" "${a[@]}" | sort -u > "$output_file"
  printf "%s\n" "${a[@]}" > "$output_file"
}

# Comment out or uncomment lines that contain the supplied string
# N.B. By default, in the examples below sed replaces every occurrence
comment_uncomment() {
  myfile="$1"
  mystring="$2"
  if [ "$comment_status" = "1" ]; then
    # Assume $mystring= starts with zero or more whitespace chars followed by '#'; 
    # what follows becomes the replacement string (whitespace trimmed at tail)
    replacement_string=$(env echo "$mystring"|tr -s '#'|xargs)
    replacement_string="${replacement_string:1}"
    echo "enable entry in $myfile for $mystring"
  else
    # Trim $mystring of leading and trailing whitespace;
    # the replacement string is this preceded by '#'
    replacement_string=$(env echo "$mystring"|xargs)
    replacement_string="#$replacement_string"
    echo "disable entry in $myfile for $mystring"
  fi
  echo "search for: $mystring, replace with $replacement_string"

  # sed -i creates a temporary file in the same folder
  # which may cause a file permission problem. So, 
  # make the change locally and copy across
  backup_dir="$script_dir/backup"
  [ -d "$backup_dir" ] || mkdir -p "$backup_dir"
  cp "$myfile" "$backup_dir/"
  file_name=$(basename "${myfile}")
  edited_file="$backup_dir/$file_name"
  sed -i'.backup' "s/$mystring/$replacement_string/" "$edited_file"

  # If hosts file not writeable, then offer sudo for copy operation
  sudo_tee="tee"
  if [ ! -w "$myfile" ]; then
    echo "Cannot write to the file"
    read -r -e -p "Do you wish to try using sudo (y/n)? " confirm
    confirm=${confirm:0:1}
    if [ "$confirm" == "y" ] || [ "$confirm" == "Y" ]; then
      sudo_tee="sudo tee"
      echo "OK. You may be asked for your sudo password ..."
    fi
  fi

  < "$edited_file" $sudo_tee "$myfile" > /dev/null || { print "Error: unable to copy $edited_file to $myfile.\nPlease check that file permissions.  Aborting"; exit; }
  #  backup_file="$backup_dir/${file_name}.backup"
  toggle_flag=$(( 1 - toggle_flag ))
  comment_status=$(( 1 - comment_status ))
}

# Offer to update Hosts file (typically /etc/hosts) if there's an entry for the domain
hosts_toggle() {
  entry="$(grep -e "$ip4re$domain" -e "$ip6re$domain" "$etc_hosts")"
  if [ "$entry" != "" ]; then
    entry_count=$(env echo "$entry"| wc -l | xargs)
    if [ "$entry_count" = "1" ]; then
      echo "You have the following entry for the domain in $etc_hosts:"
    else
      echo "WARNING: You have $entry_count entries for the domain in $etc_hosts, but we will only look at the first one to determine the action:"
    fi
    env echo "$entry"
    entry_backup=$entry
    entry=$(env echo "${entry}"| head -1)

    # Determine whether or not the entry is commented out
    comment_prefix="^[[:space:]]*#.*$domain"
    if [[ $entry =~ $comment_prefix ]]; then
      echo "It appears this entry is commented out." "1"
      comment_status=1
      comment_mode="uncomment"
    else
      echo "It appears this entry is active." "1"
      comment_status=0
      comment_mode="comment out"
    fi

    # and invite the user to invert
    read -r -e -p "Do you wish to temporarily $comment_mode this entry to allow rsync to transfer to the remote server (it may be restored on completion) (y/n)? " confirm
    confirm=${confirm:0:1}
    if [ "$confirm" == "y" ] || [ "$confirm" == "Y" ]; then
      comment_uncomment "$etc_hosts" "$entry"
    else
      read -r -e -p "Stop here without deploying (y/n)? " confirm
      confirm=${confirm:0:1}
      if [ "$confirm" == "y" ] || [ "$confirm" == "Y" ]; then
        echo "OK. Stopping here."; exit
      elif [ "$site_path" = "$deploy_path" ]; then
        printf "WARNING: The paths appear to be the same - would mean overwriting the source folder with the static mirror!\nAborting."; exit
      else
        printf "The paths appear to be distinct, so deployment should not overwrite\nContinuing without commenting out the entry."
      fi
    fi
    entry=$entry_backup
  fi
}

sitemap_header() {
  read -r -d "" sitemap_contents << EOT
<?xml version="1.0" encoding="UTF-8"?>
<urlset xmlns="$sitemap_schema">

EOT

  printf "%s\n" "$sitemap_contents"
}

# stopclock receives one parameter (number of seconds)
# and outputs time in hours, minutes and seconds
stopclock() {
  timer_seconds=$1
  (( hrs=timer_seconds/3600, mins=(timer_seconds%3600)/60, secs=(timer_seconds%3600)%60 ))
  hour_s=$(pluralize $hrs); min_s=$(pluralize $mins); sec_s=$(pluralize $secs);
  (( hrs > 0 )) && printf "%s" "$hrs hour$hour_s"
  if (( mins > 0 )); then
    if (( hrs > 0 )); then
      (( secs > 0 )) && printf ", " || printf " and "
    fi
    printf "%s" "$mins minute$min_s"
  fi
  if (( secs > 0 )); then
    if (( hrs > 0 )) || (( mins > 0 )); then
      printf " and "
    fi
    printf "%s" "$secs second$sec_s"
  fi
  (( timer_seconds == 0 )) && echo "no time at all!" || echo "."
}

# Generate timestamp
# One optional parameter:
#  - timezone
timestamp() {
  if [ -n "${1+x}" ]; then
    timezone="$1"
  else
    timezone="utc"
  fi
  if [ "$timezone" != "utc" ]; then
    timestamp=$(date "+%Y%m%d_%H%M%S")
    if [ "$timezone" = "utclocal" ]; then
      timestamp+=$(date +"%z")
    fi
  else
    timestamp=$(TZ=UTC date "+%Y%m%d_%H%M%S")"Z"
  fi
  printf "%s" "$timestamp"
}
