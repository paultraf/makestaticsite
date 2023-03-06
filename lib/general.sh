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
#
# Override built-in echo and also write to log file
# This takes an optional priority parameter (number) to constrain output, 
# stored in echo_num:
#  0 (liberal)    - echo unless level is silent
#  1 (normal)     - echo normally 
#  2 (restricted) - echo only for full logging (this priority is meant for 
#                   internal processing)
#

echo() {
  echo_num=
  temp_IFS="$IFS"; IFS="|"
  params=("$@")
  if [ -z ${1+x} ]; then
    echo_txt=
  elif [ "$1" = "-e" ] || [ "$1" = "-n" ]; then
    echo_opt="$1"
    echo_txt="$2"
    if [ -n "${3+x}" ]; then
      echo_num="$3"
    fi
  else
    echo_opt=
    echo_txt="$1"
    if [ -n "${2+x}" ]; then
      echo_num="$2"
    fi
  fi
  echo_tty="$echo_txt"
  echo_log="$echo_txt"
  # Now remove the priority parameter (if supplied)
  if [ "$#" = "3" ] || { [ "$#" = "2" ] && [ "$echo_opt" = "" ]; }; then
    unset "params["${#params[@]}-1"]"
  fi

  if [ "$echo_num" = "0" ]; then
  # For priority 0, don't echo anything to terminal when level is silent
    if [ "$output_level" = "silent" ]; then
      echo_tty=""
    fi
  elif [ "$echo_num" = "1" ]; then
    # For priority 1, don't echo anything unless runtime level is normal or verbose
    if [ "$output_level" != "normal" ] && [ "$output_level" != "verbose" ]; then
      echo_tty=""
    fi;
  elif [ "$echo_num" = "2" ]; then
    # For priority 2, log only when verbose
    if [ "$log_level" != "verbose" ]; then
      echo_log=""
    fi
  fi
  if [ "$echo_tty" != "" ] || [ "$echo_num" = "2" ]; then
    env echo "${params[@]}"
  fi
  if [ "$echo_log" != "" ] && [ "$log_level" != "silent" ]; then
    env echo "${params[@]}" >> "$log_file"
  fi

  IFS="$temp_IFS"
}

error_set() {
  if [ "$trap_errors" = "yes" ]; then
    set "$1"
  fi
}

# Assume that any option that starts with 'n' or 'N' is a 'no', otherwise 'yes'
yesno() {
  if [ "${1:0:1}" = "n" ] || [ "${1:0:1}" = "N" ]; then
    env echo "no"
  else
    env echo "yes"
  fi
}

pluralize() {
  if [ "$1" != "1" ]; then
    env echo "s"
  else
    env echo
  fi
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

confirm_continue() {
  if [ "$run_unattended" != "yes" ]; then
    read -r -e -p "Do you wish to continue (y/n)? " confirm
    confirm=${confirm:0:1}
    [ "$confirm" != "y" ] && [ "$confirm" != "Y" ] && { printf "Please review the settings.\nAborting.\n"; exit; } || echo "OK. Continuing."
  else
    echo "Continuing (to run unattended)."
  fi
}

get_phase_desc() {
  for opt in "${all_phases[@]}"; do
    var=$(expr "$opt" : '\([^=]*\)')              # Everything up to '='
    phase_desc=$(expr "$opt" : '[^=]*.\(.*\)')    # Everything after '='
    if [ "$var" = "$1" ];then
      env echo "$phase_desc"; return
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

  echo "$sitemap_contents"
}

# stopclock receives one parameter (number of seconds)
# and outputs time in hours, minutes and seconds
stopclock() {
  timer_seconds=$1
  (( hrs=timer_seconds/3600, mins=(timer_seconds%3600)/60, secs=(timer_seconds%3600)%60 ))
  hour_s=$(pluralize $hrs); min_s=$(pluralize $mins); sec_s=$(pluralize $secs);
  (( hrs > 0 )) && echo -n "$hrs hour$hour_s"
  if (( mins > 0 )); then
    if (( hrs > 0 )); then
      (( secs > 0 )) && echo -n ", " || echo -n " and "
    fi
    echo -n "$mins minute$min_s"
  fi
  if (( secs > 0 )); then
    if (( hrs > 0 )) || (( mins > 0 )); then
      echo -n " and "
    fi
    echo -n "$secs second$sec_s"
  fi
  (( timer_seconds == 0 )) && echo "no time at all!" || echo "."
}

