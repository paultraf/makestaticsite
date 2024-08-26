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
    wayback_date_from_to=$(printf "%s" "$1" | cut -d/ -f${url_depth})
    wayback_date_to_cut=$(printf "%s" "$wayback_date_from_to" | cut -d- -f2)
    if [ "$wayback_date_to_cut" != "$wayback_date_from_to" ]; then
      wayback_date_from=$(printf "%s" "$wayback_date_from_to" | cut -d- -f1)
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
    url_original=$(printf "%s" "$1" | cut -d/ -f"${url_depth}"-)

    # assign URL-related variables
    protocol_original=$(printf "%s" "$url_original" | awk -F/ '{print $1}' | awk -F: '{print $1}')
    hostport_original=$(printf "%s" "$url_original" | awk -F/ '{print $3}')
    url_original_base="$protocol_original://$hostport_original"
    url_original_base_singleslash=${url_original_base/:\/\//:\/}  # adjust for Wget directory mapping
    url_path_original=$(printf "%s" "$url_original" | cut -d/ -f4-)
    url_path_original="${url_path_original%\/*}"  # remove anything after last '/'

    if [ "$url_stem_dates" = "" ] || ! validate_url "$url_original"; then
      printf "%s: The extracted URL, %s, is considered invalid.\n" "$msg_error" "$url_original"
      printf "It is recommended that you modify the value of 'url' and re-run\n."
      echo "Aborting."
      exit
    fi
    domain_original=$(printf "%s\n" "$url_original" | awk -F/ '{print $3}' | awk -F: '{print $1}')
  fi  
}

# Determine runtime configuration for Wayback URL.
initialise_wayback() {
  wayback_url=yes  # Wayback Machine URL established
  url_wildcard_capture=no # reset as the Wayback Machine doesn't yet have a means to handle this; also note that it will refer to all external assets under its own host name.
  domain_wayback_machine=$(printf "%s" "$url" | awk -F/ '{print $3}' | awk -F: '{print $1}')
  process_wayback_url "$url" # will set the value of $url_original to be that of the archived site
  printf "\nWayback Machine detected at %s, hosted on %s.\n" "$url" "$domain_wayback_machine"
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
    touchmod "$input_file_wayback_extra"
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


# Various Wayback-related URLs and paths
wayback_url_paths() {
  # Wayback-related URLs
  url_timeless=${url/${wayback_date_from_to}/[0-9]+[a-z]\{0,2\}_\?} # This could be tightened - use $wayback_datetime_regex
  url_timeless=$(regex_escape "$url_timeless")
  url_timeless=$(regex_apply "$url_timeless")
  url_timeless=${url_timeless//\\[/[} # final adjustment to remove '\' in front of '['
  url_base_timeless=${url_base/${wayback_date_from_to}/[0-9]+[a-z]\{0,2\}_\?}
  url_base_timeless=$(regex_escape "$url_base_timeless")
  url_base_timeless=$(regex_apply "$url_base_timeless")
  url_base_timeless=${url_base_timeless//\\[/[} # final adjustment to remove '\' in front of '['
  
  url_base_regex=$(regex_escape "$url_base")
  url_timeless_nodomain=${url_timeless/"$url_base_regex"/}   # Truncated version
  url_base_timeless_nodomain=${url_base_timeless/"$url_base_regex"/}   # Truncated version
  
  # Locate source directories to copy
  url_path_snapshot="${url_path/$wayback_date_to/ }"
  url_path_snapshot_prefix=$(printf "%s" "$url_path_snapshot" | cut -d' ' -f1 | cut -d'/' -f1 )
  url_path_snapshot=$(printf "%s" "$url_path_snapshot" | cut -d' ' -f2- )
  url_path_snapshot="$wayback_date_to$url_path_snapshot"
  url_path_prefix=
  for ((i=1;i<url_path_depth;i++)); do
    url_path_prefix+="../"
  done
}


# Apply filters on candidate Wayback URLs based on domains and paths,
# and remove URLs originally from external domains.
# (Currently, there is no filtering based on wayback_timestamp_policy.)
wayback_filter_domains() {
  webassets_wayback=()
  url_regex=$(printf "%s" "$url"|sed 's|\(/\)'"$wayback_datetime_regex"'|\1'"$wayback_datetime_regex"'|') # turn original URL into wildcard expression
  url_regex=${url_regex/"$url_base"/} # trim the URL base to support relative links

  # Add a constraint on Wget searches
  if (( wget_extra_urls_count == 1 )); then
    wget_extra_core_options+=( "--accept-regex" "\"$url_regex\"" ) # Every link in the Wayback Machine is to an absolute URL
    wget_extra_options+=("--max-redirect=1") # Reduce the risk of Wget fetching external resources whilst allowing the possibility for a standard internal redirect to fetch nearest timestamp 
  fi

  # Constrain further Wget runs to Wayback URLs involving the primary domain
  # and not got a valid asset extension
  for opt in "${webassets_http[@]}"; do
    opt_regex=$(printf "%s" "$opt"|sed 's|\(/\)'"$wayback_datetime_regex"'|\1'"$wayback_datetime_regex"'|') # turn original URL into wildcard expression
    # Add a further condition to check whether asset already in list modulo timestamps
    if [[ $opt =~ $url_regex ]] && [[ ! ${webassets_wayback0[@]} =~ $opt_regex ]]; then
      opt=$(printf "%s" $opt | sed 's/#[[:alnum:]]*$//') # remove internal anchors
      webassets_wayback0+=("$opt") 
    else
      continue                  # URL is not allowed, so drop
    fi
  done

  # Add further filters based on a list of existing downloaded URLs.
  # Wget run 1 will only generate one timestamped folder with web pages,
  # but subsequent runs will potentially generate many more, depending on
  # the URLs harvested from the initially downloaded pages.
  # For web pages, timestamped folder names contain only numbers.
  cd "$src_path_snapshot" || { echo "$msg_error: Unable to enter $src_path_snapshot.  Aborting"; exit; }

  snapshot_path_list=()
  while IFS= read -r line; do
    line="${line#./}"
    snapshot_path_list+=("$line")
  done <<<"$(find . -mindepth $wayback_snapshot_path_depth -maxdepth $wayback_snapshot_path_depth -print)"

  wayback_domain_exceptions=()
  for snapshot_dir in "${snapshot_path_list[@]}"; do
    while IFS= read -r item; do
      item="${item#.}"
      # To reconstruct a Memento URL from a Wget-generated path,
      # need to insert a '/' after the second protocol instance
      item="${item/\/http:\//\/http:\/\/}" 
      item="${item/\/https:\//\/https:\/\/}"

      # Now generate wildcard version
      item_regex=$(printf "%s" "$item"|sed 's|\(/\)'"$wayback_datetime_regex"'|\1'"$wayback_datetime_regex"'|')

      # If the candidate item is not already in the list of Wayback domain-based exceptions, then add it
      if [[ ! ${wayback_domain_exceptions[@]} =~ $item_regex ]]; then
        wayback_domain_exceptions+=("$item_regex")
      fi

      # Take account of index pages implicit by requests to URLs ending in '/'
      # by truncating Wget default page (usually index.html), as appropriate
      if [[ $item =~ $wget_default_page$ ]]; then
        item_regex="${item_regex/%\/$wget_default_page/\/}" # (need to avoid false positives such as cindex.html and index.htmlx)
        if [[ ! " ${wayback_domain_exceptions[*]} " =~ [[:space:]]${item_regex}[[:space:]] ]]; then
          wayback_domain_exceptions+=("$item_regex")
        fi
      fi
    done <<<"$(find "." -type f ! -empty -print)"
  done

  temp_IFS="$IFS"
  IFS=$'\n' wayback_exceptions=($(sort -u <<<"${wayback_domain_exceptions[*]}"))
  IFS="$temp_IFS"
  
  ## Apply filter
  webassets_wayback=()
  while IFS= read -r line; do
    webassets_wayback+=("$line");
  done < <(
  for opt in "${webassets_wayback0[@]}"; do
    for exception in "${wayback_exceptions[@]}"; do
      if [[ $opt =~ $exception$ ]]; then
        continue 2              # URL is not allowed, so drop
      fi
    done
    printf "%s\n" "$opt"
  done)

  temp_IFS="$IFS"
  IFS=$'\n' webassets_http=($(sort -u <<<"${webassets_wayback[*]}"))
  IFS="$temp_IFS"
  
  webassets_http=($(sort -u <<<"${webassets_wayback[*]}"))
  cd "$mirror_dir"
}

# Apply Wayback snapshot-related filters to determine web assets (URLs)
wayback_filter_snapshots() {
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
  # Apply timestamp-related filters
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
  echo "Consolidating snapshot assets in a single location, reflecting original layout ... "
  print_progress "0" "100";

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

  snapshot_path_list=()
  while IFS= read -r line; do
    line="${line#./}"
    snapshot_path_list+=("$line")
  done <<<"$(find . -mindepth $wayback_snapshot_path_depth -maxdepth $wayback_snapshot_path_depth -type d -not -path "./$wayback_date_to" -not -path "./$wayback_date_to/"\* -print)"

  cd "$working_mirror_dir" || { echo "msg_error: Unable to return to $working_mirror_dir. Aborting."; exit; } 

  # Initialised source and destination paths (trunks)
  dest_path="$working_mirror_dir/$url_path"
  if [ "$url_path_original" != "" ]; then
    [ "$url_add_slash" = "avoid" ] && dest_path="${dest_path%\/*}/"  # remove anything after last '/'
    dest_path="${dest_path%\/$url_path_original\/*}"  # remove $url_path_original from tail
    dest_path="${dest_path%\/$url_path_original*}"  # remove $url_path_original from tail
  fi

  # Replace the relative links created by Wget (that point to levels higher up in the directory hierarchy)
  count=0
  for opt in "${webpages[@]}"; do
    print_progress "$count" "$num_webpages";
    depth=${opt//[!\/]};
    depth_num=${#depth}
    (( depth_num-- )) # adjustment of 1 needs to be made 
    (( depth_num-=url_path_depth )) # whereas url_path_prefix is fixed,
    pathpref=                       # pathpref denotes the relative path to get from current directory to the snapshot content root 
    for ((i=1;i<=depth_num;i++)); do
      pathpref+="../";
    done

    opt_item="${opt##*$url_original_base_singleslash\/}" # extract only the relevant path and then add this on to snapshot_src_path
    opt_item="${opt_item%\/*}" # remove everything after trailing slash
    for item in "${snapshot_path_list[@]}"; do
      snapshot_src_path="$pathpref$url_path_prefix$item"      
      snapshot_src_path=$(regex_escape "$snapshot_src_path")
      snapshot_src_path=$(printf "%s" "$snapshot_src_path" | sed 's|'"$wayback_datetime_regex"'|'"$wayback_datetime_regex"'|g') 
      snapshot_src_path=$(regex_apply "$snapshot_src_path")
      if [ "$url_path_original" != "" ]; then
        opt_item_slashes=${opt_item//[!\/]};
        opt_item_slashes_num=${#opt_item_slashes};
        this_path="$opt_item"
        this_path_prefix=
        this_path_regex=$(regex_apply "$this_path")
        for ((j=1;j<=opt_item_slashes_num;j++)); do
          snapshot_src_path0="$snapshot_src_path/$this_path_regex" # this variants targets specifically URLs that contain the URL path
          sed_subs0=('s|'"$snapshot_src_path0/"'|'"$this_path_prefix"'|g' "$opt")
          sed "${sed_options[@]}" "${sed_subs0[@]}"
          this_path="${this_path%\/*}" # delete everything after last /
          this_path_prefix+="../"
        done
      fi
      sed_subs1=('s|'"$snapshot_src_path/"'|'""'|g' "$opt")
      sed "${sed_options[@]}" "${sed_subs1[@]}"
    done
    (( count++ ))
  done

  cd "$src_path_snapshot" || { echo "$msg_error: Unable to enter $src_path_snapshot.  Aborting"; exit; }

  for snapshot_dir in "${snapshot_path_list[@]}"; do
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
  print_progress
  cd "$working_mirror_dir" || echo "Unable to enter $working_mirror_dir"
}

# Convert absolute URLs to relative URLs for internal anchors
process_asset_anchors() {
  echo "Converting absolute URLs to relative URLs for Wayback internal anchors ... "
  print_progress "0" "100";

  # Generate lists of webasset paths
  cd "$url_path_dir"
  webpages_output1=() # to store file paths to web pages only
  webpaths_output1=() # to store file paths to web assets for internal links
  webpaths_output2=() # to store directory paths for internal links

  while IFS='' read -r line; do
    webpages_output1+=("$line")
    line=${line:2}
  done < <(
  for file_ext in "${asset_find_names[@]}"; do
    find "." -type f -name "$file_ext" "${asset_exclude_dirs[@]}" -print
  done)
  num_webpages1="${#webpages_output1[@]}"

  while IFS='' read -r line; do
    line=${line:2}
    webpaths_output1+=("$line")
  done < <(find "." -type f "${asset_exclude_dirs[@]}" -print)

  while IFS='' read -r line; do
    webpaths_output2+=("$line")
    line=${line:2}
  done < <(find "." -type d "${asset_exclude_dirs[@]}" -print)

  # Carry out substitutions in web pages
  count=0
  for opt in "${webpages_output1[@]}"; do
    print_progress "$count" "$num_webpages1";  
    pathpref=
    opt_path_stem=${opt:2}
    [ "$url_path_original" != "" ] && opt_path_stem=${opt_path_stem##*$url_path_original}  # Path (directory hierarchy) relative to the original URL
    opt_rel_depth=${opt_path_stem//[!\/]};
    opt_rel_depth_num=${#opt_rel_depth} # measure the relative depth of opt_path_stem
    for ((i=1;i<=opt_rel_depth_num;i++)); do
      pathpref+="../";
    done
    for item in "${webpaths_output1[@]}"; do
      item="${item##*$domain_original\/}"
      item=$(regex_escape "$item")
      sed_subs1=('s|\('"$url_timeless"'\)\('"$item"'\)|'"$pathpref\2"'|g' "$opt")
      sed_subs2=('s|\([\"'\'']\)\('"$url_timeless_nodomain"'\)\('"$item"'\)|'"\1$pathpref\3"'|g' "$opt")
      sed "${sed_options[@]}" "${sed_subs1[@]}"
      sed "${sed_options[@]}" "${sed_subs2[@]}"
    done
    # Conversion of anchors make implicit index pages explicit, to assist in internal navigation
    # (1) Empty case
    sed_subs1=('s|\('"$url_timeless"'\)\([\"'\'']\)|'"${pathpref}index.html\2"'|g' "$opt")
    sed_subs2=('s|\([\"'\'']\)\('"$url_timeless_nodomain"'\)\([\"'\'']\)|'"\1${pathpref}index.html\3"'|g' "$opt")
    sed "${sed_options[@]}" "${sed_subs1[@]}"
    sed "${sed_options[@]}" "${sed_subs2[@]}"
    # (2) Non-empty case
    for item in "${webpaths_output2[@]}"; do
      item=${item:2}
      item=$(regex_escape "$item")
      sed_subs1=('s|\('"$url_timeless"'\)\('"$item"'\)\([\"'\'']\)|'"$pathpref\2index.html\3"'|g' "$opt")
      sed_subs2=('s|\([\"'\'']\)\('"$url_timeless_nodomain"'\)\('"$item"'\)\([\"'\'']\)|'"\1$pathpref\3index.html\4"'|g' "$opt")
      sed "${sed_options[@]}" "${sed_subs1[@]}"
      sed "${sed_options[@]}" "${sed_subs2[@]}"
    done
    (( count++ ))
  done
  print_progress
  cd "$working_mirror_dir"
}

# Postprocessing of Wget output
# generated by requests to Wayback Machine
wayback_wget_postprocess() {
  # Insert Wayback Machine domain for relative links to the root directory
  cd "$working_mirror_dir" || { printf "Unable to enter %s.\nAborting.\n" "$working_mirror_dir"; exit; }
  while IFS='' read -r opt; do
    # Carry out search and replace
    sed_subs=('s|\([\"'\'']\)\('"$url_timeless_nodomain"'\)|'"\1$url_base\2"'|g' "$opt")
    sed "${sed_options[@]}" "${sed_subs[@]}"
  done < <(for file_ext in "${asset_find_names[@]}"; do
    find "." -type f -name "$file_ext" -print
  done) 
}


# Clean the HTML output generated by the Wayback Machine
# We have to deal with newlines, so use awk rather than sed
# Specify as record separator an ASCII character that is not used in files (in this case: bell alert) 
wayback_output_clean() {
  echo -n "Cleaning the HTML output generated by the Wayback Machine ... "
  if [ "$wayback_code_clean" = "yes" ]; then
    # Delete (JavaScript) Playback code inserted by Wayback Machine
    echo "Delete (JavaScript) Playback code inserted by Wayback Machine ... " "1"
    for opt in "${webpages[@]}"; do
      tmp_file="$opt.tmp"
      if [ -f "$opt" ]; then
        awk -v RS='\x7' '{sub(/'"$wayback_code_re"'/,"<head>"); print}' "$opt" > "$tmp_file" && mv "$tmp_file" "$opt"
      else
        echo "$msg_warning: File $opt not found, so not running awk on it." "1"
      fi
    done
  fi

  if [ "$wayback_comments_clean" = "yes" ]; then
    # Delete HTML comments inserted by Wayback Machine
    echo "Delete HTML comments inserted by Wayback Machine ... " "1"
    for opt in "${webpages[@]}"; do
      tmp_file="$opt.tmp"
      if [ -f "$opt" ]; then
        awk -v RS='\x7' '{sub(/'"$wayback_comments_re"'/,"</html>"); print}' "$opt" > "$tmp_file" && mv "$tmp_file" "$opt"
      else
        echo "$msg_warning: File $opt not found, so not running awk on it." "1"
      fi
    done
  fi
}
