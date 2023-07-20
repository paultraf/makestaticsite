##########################################################################
# 
# MakeStaticSite --- a shell script to create and deploy static websites 
# Copyright 2022-2023 Paul Trafford <pt@ptworld.net>
# 
# mod_wayback.sh - Wayback Machine module for MakeStaticSite
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
# Notes
# This module retrieves an index to web content archived by a Wayback Machine
# using using the Wayback CDX Server API
# https://github.com/internetarchive/wayback/tree/master/wayback-cdx-server
# Scripting derived from:
# https://gist.github.com/lazanet/872f88c9874e4a7a78fd
##########################################################################



# Call Wayback Machine Downloader, a tool in Ruby
# https://github.com/hartator/wayback-machine-downloader
# Expects one parameter: URL
# optional parameters:
# - date from
# - date to
wmd_get_wayback_site() {
  local url="$1"
  [ -n "${2+x}" ] && wayback_date_from="$2" 
  [ -n "${3+x}" ] && wayback_date_to="$3" 

  wmd_get_options=()
  [ "$wayback_matchtype" = "exact" ] && wmd_get_options+=(-e)
  [ -n "${wayback_machine_only+x}" ] && [ "$wayback_machine_only" != "" ] && wmd_get_options+=(-o "$wayback_machine_only") 
  [ -n "${wayback_machine_excludes+x}" ] && [ "$wayback_machine_excludes" != "" ] && wmd_get_options+=(-x "$wayback_machine_excludes") 
  [ -n "${wayback_date_from+x}" ] && [ "$wayback_date_from" != "" ] && wmd_get_options+=(-f "$wayback_date_from") 
  [ -n "${wayback_date_to+x}" ] && [ "$wayback_date_to" != "" ] && wmd_get_options+=(-t "$wayback_date_to") 
  [ -n "${wayback_machine_statuscodes+x}" ] && [ "$wayback_machine_statuscodes" = "all" ] && wmd_get_options+=(-a)
  
  wmd_get_options+=(-d "$mirror_archive_dir" "$url")
  echo " "; echo "Executing: $wayback_machine_downloader_cmd ${wmd_get_options[*]}"
  $wayback_machine_downloader_cmd "${wmd_get_options[@]}"
}

# For Wayback URLs containing a date or date range
# extract the ('from' and) 'to' timestamps 
# and validate them. It also extracts the archived URL
# Expects one parameter: URL
process_wayback_url() {
  if [ -z ${1+x} ]; then
    echo "$msg_error: URL not supplied. Unable to check Wayback dates."
    echo "Aborting."
    exit
  else
    local url_stem_dates=${1%http*}
    local url_slashes=${url_stem_dates//[!\/]};
    local url_depth=$(( ${#url_slashes} ))
    wayback_date_from_to=$(echo "$1" | cut -d/ -f${url_depth})
    wayback_date_to_cut=$(echo "$wayback_date_from_to" | cut -d- -f2)
    if [ "$wayback_date_to_cut" != "$wayback_date_from_to" ]; then
      wayback_date_from=$(echo "$wayback_date_from_to" | cut -d- -f1)
      wayback_date_to="$wayback_date_to_cut"
      if ! validate_timestamp "$wayback_date_from"; then
        echo "$msg_error: The 'from' date, $wayback_date_from, in the range $wayback_date_from_to, is invalid. It needs to be a string of digits in the format: YYYYMMDDhhmmss (substrings starting with YYYY are allowed)." 
      fi
    else
      wayback_date_to="$wayback_date_from_to"
    fi
    if ! validate_timestamp "$wayback_date_to"; then
      echo "$msg_error: The 'to' date, $wayback_date_to, in the range $wayback_date_from_to, is invalid.  It needs to be a string of digits in the format: YYYYMMDDhhmmss (substrings starting with YYYY are allowed)." 
    fi

    # Assign the archived URL as URL and validate
    (( url_depth++ ))
    url=$(echo "$1" | cut -d/ -f"${url_depth}"-)
    if [ "$url_stem_dates" = "" ] || ! validate_url "$url"; then
      printf "%s: The extracted URL, %s, is considered invalid.\n" "$msg_error" "$url"
      printf "It is recommended that you modify the value of 'url' and re-run\n."
      echo "Aborting."
      exit
    fi
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
check_wayback_url(){
  # Read parameters and assign to variables
  local url="$1"
  local wayback_list="$2"
  local host
  host=$(printf "%s" "$url" | awk -F/ '{print $3}' | awk -F: '{print $1}')

  # Check list of known Wayback Machine hosts
  if echo ",$wayback_list," | grep -q ",$host,"; then
    return 0
  fi

  # cURL check (-I : header, -s: silent, -k: don't check SSL certs)
  wayback_header="Memento-Datetime:"
  if curl -skI "$url" | grep -Fiq "$wayback_header"; then
    return 0
  fi

  # Failed both checks, so return error status
  return 1
}

