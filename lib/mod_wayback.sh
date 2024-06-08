##########################################################################
# 
# MakeStaticSite --- a shell script to create and deploy static websites 
# Copyright 2022-2024 Paul Trafford <pt@ptworld.net>
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
# This module supports two methods of retrieving web content archived
# by a Wayback Machine:
#  - native support (web scraping)
#  - a dedicated client, the Wayback Machine Downloader, a tool in Ruby
#    https://github.com/hartator/wayback-machine-downloader/
##########################################################################



# Call Hartator's Wayback Machine Downloader
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
    url_original=$(echo "$1" | cut -d/ -f"${url_depth}"-)
    if [ "$url_stem_dates" = "" ] || ! validate_url "$url_original"; then
      printf "%s: The extracted URL, %s, is considered invalid.\n" "$msg_error" "$url_original"
      printf "It is recommended that you modify the value of 'url' and re-run\n."
      echo "Aborting."
      exit
    fi
  fi  
}

# Determine runtime configuration for Wayback URL.
initialise_wayback() {
  wayback_url=yes  # Wayback Machine URL established
  url_wildcard_capture=no # reset as the Wayback Machine doesn't yet have a means to handle this; also note that it will refer to all external assets under its own host name.
  domain_wayback_machine=$(printf "%s" "$url" | awk -F/ '{print $3}' | awk -F: '{print $1}')
  process_wayback_url "$url" # will set the value of $url_original to be that of the archived site
  printf "\nWayback Machine detected at %s, hosted on %s.\n" "$url" "$domain_wayback_machine."
  if [ "$wayback_timestamp_policy" = "exact" ] && [ "$wayback_date_from" != "" ]; then
    echo "$msg_warning: you have specified a date range for the Wayback Machine, but the constant wayback_timestamp_policy is set to 'exact'."
    echo "To resolve this conflict, MakeStaticSite will only download assets for the most recent timestamp, $wayback_date_to. But you may like to set wayback_timestamp_policy=range."
    confirm_continue "Y" "OK. Please change the URL or review the Wayback settings in constants.sh."
    url=${url/$waybackdatefrom-/}
    wayback_date_from="$wayback_date_to"
  fi
  if [ "$wayback_assets_mode" = "original" ]; then
    # Prepare to save a copy
    wget_inputs_wayback_all="$wget_inputs_extra-${myconfig}-wayback-all.txt" # cumulative input file
    wget_inputs_wayback_extra="$wget_inputs_extra-${myconfig}-wayback.txt" # single run input file
    input_file_wayback_extra="$script_dir/$tmp_dir/$wget_inputs_wayback_extra"  # Input file for a single run of Wget extra assets (to be generated)
    input_file_wayback_extra_all="$script_dir/$tmp_dir/$wget_inputs_wayback_all"  # Input file for Wget extra assets accumulated over multiple runs (to be generated)
    touchmod "$input_file_wayback_extra_all"
    if (( phase < 3 )); then
      echo > "$input_file_wayback_extra_all" # Initialise as an empty file
    fi
  fi
  if [ "$wayback_cli" = "yes" ]; then
    if (( phase < 4 )) && ! validate_internet; then
      echo " "; echo "$msg_error: Unable to establish Internet access. Please check your network connectivity."
      echo "Aborting."
      exit
    fi
    use_wayback_cli=yes
    wget_extra_urls=no
    wget_extra_urls_depth=0
    wget_extra_urls_count=1
    url="$url_original"
  fi
}

# Apply Wayback-specific filters to determine web assets (URLs)
get_webassets_wayback() {
  webassets_wayback=()
  if [ "$wayback_assets_mode" = "original" ] && (( wget_extra_urls_count == 1 )); then
    # Pick out unique items, accepting multiple snapshots for the same file and write out
    echo "Pick out unique items, no snapshot filter" "1"
    webassets_unique_snapshots=()
    while IFS='' read -r line; do webassets_unique_snapshots+=("$line"); done < <(for item in "${webassets[@]}"; do printf "%s\n" "${item}"; done |
      sort -u;)
    echo "webassets_unique_snapshots array has ${#webassets_unique_snapshots[@]} elements" "2"
    printf "%s\n" "${webassets_unique_snapshots[@]}" > "$input_file_wayback_extra"
  fi
  # Apply filters
  while IFS='' read -r line; do webassets_wayback+=("$line"); done < <(for item in "${webassets[@]}"; do printf "%s\n" "${item}"; done |
    if [ "$wayback_timestamp_policy" = "exact" ]; then
      # Only match (and hence download) assets with given timestamp
      grep "$wayback_date_to" | sort -u | sed 's/\/http/ /g' | sort -u -t ' ' -k 2 | sed 's/ /\/http/g'; # Remove duplicate asset captures, select only those from given timestamp, and ignore any non-Memento URLs
    elif [ "$wayback_assets_mode" = "original" ]; then
      sort -u | sed 's/\/http/ /g' | sort -u -t ' ' -k 2 | sed 's/ /\/http/g'; # remove duplicate asset captures, selecting first according to timestamp, and ignore any non-Memento URLs
    else 
      sort -u;
    fi
  )
  webassets=("${webassets_wayback[@]}")
}

# Consolidate snapshot assets in a single location,
# reflecting the original layout.
consolidate_assets() {
  echo -n "Consolidating snapshot assets in a single location, reflecting original layout ... "

  # Locate source directories to copy
  url_path_snapshot="${url_path/$wayback_date_to/ }"
  url_path_snapshot_prefix=$(echo "$url_path_snapshot" | cut -d' ' -f1 | cut -d'/' -f1 )
  url_path_snapshot=$(echo "$url_path_snapshot" | cut -d' ' -f2- )
  url_path_snapshot="$wayback_date_to$url_path_snapshot"
  url_path_sibling="$url_path_snapshot"
  for ((i=1;i<url_path_depth;i++)); do
    url_path_sibling="../$url_path_sibling"
  done
  src_path_snapshot="$working_mirror_dir/$url_path_snapshot_prefix"
  cd "$src_path_snapshot" || echo "Unable to enter $src_path_snapshot"
  snapshot_exclude_dirs=()
  snapshot_list=("$wayback_date_to")
  for item in "${snapshot_list[@]}"; do
    snapshot_exclude_dirs+=(-not -path "." -not -path "./$item" -not -path "./$item/"\* ) # this needs to be a full path
  done

  while IFS= read -r line; do
    line="${line#./}"
    snapshot_list+=("$line")
  done <<<"$(find "." -maxdepth 1 -type d ! -empty "${snapshot_exclude_dirs[@]}" -print)"

  cd "$working_mirror_dir" || { echo "msg_error: Unable to return to $working_mirror_dir. Aborting."; exit; } 

  urlpath_chunk=$(printf "%s" "$url_path" | cut -d/ -f3-) 
  # Initialised source and destination paths (trunks)
  dest_path="$working_mirror_dir/$url_path"

  for opt in "${webpages[@]}"; do
    for item in "${snapshot_list[@]}"; do
      snapshot_src_path=${url_path_sibling/$wayback_date_to/$item}
      snapshot_src_path=$(regex_escape "$snapshot_src_path")
      sed_subs=('s~'"$snapshot_src_path/"'~'""'~g' "$opt")
      sed "${sed_options[@]}" "${sed_subs[@]}"
    done
  done

  cd "$src_path_snapshot" || { echo "$msg_error: Unable to enter $src_path_snapshot.  Aborting"; exit; }

  for snapshot in "${snapshot_list[@]}"; do
    snapshot_dir="$snapshot/$urlpath_chunk"
    echo "Entering $snapshot_dir" "1"
    if [ -d "$snapshot_dir" ]; then
      cd "$snapshot_dir"
    else
      echo "$msg_warning: unable to enter directory $snapshot_dir" "1"; continue
    fi

    while IFS= read -r copy_dir; do
      copy_dir="${copy_dir#./}"
      if [ "$copy_dir" != "" ]; then
        echo "mkdir -p $dest_path/$copy_dir" "1"
        mkdir -p "$dest_path/$copy_dir"

        # loop over files in subdirectory
        while IFS= read -r item; do
          # check if file already exists in destination
          file_dest="$dest_path/$item"
          if [ -f "$file_dest" ]; then
            echo "File exists at $file_dest" "2"
          elif [ "$item" != "" ]; then
            echo "Move file $item to $file_dest" "1"
            mv "$item" "$file_dest" || echo "Unable to move $item to $file_dest!"  
          fi
        done <<<"$(find "$copy_dir/" -maxdepth 1 -type f ! -empty -print)"
      fi
      # Loop over files in directory
      while IFS= read -r item; do
        if [ "$item" != "" ]; then
          # check if file already exists in destination
          item="${item#./}"
          file_dest="$dest_path/$item"
          if [ -f "$file_dest" ]; then
            echo "File exists at $file_dest" "2"
          else
            echo "Move file $item to $file_dest" "1"
            mv "$item" "$file_dest" || echo "Unable to move $item to $file_dest!"  
          fi
        fi
      done <<<"$(find "." -maxdepth 1 -type f ! -empty -print)"
    done <<<"$(find "." -type d ! -empty -not -path "." -not -path "" -print)"
    cd "$src_path_snapshot" || { echo "Unable to cd back to $src_path_snapshot"; exit; }
  done
  cd "$working_mirror_dir" || echo "Unable to enter $working_mirror_dir"
}
