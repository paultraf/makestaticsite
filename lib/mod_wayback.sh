##########################################################################
# 
# MakeStaticSite --- a shell script to create and deploy static websites 
# Copyright 2022-2025 Paul Trafford <pt@ptworld.net>
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
  [ -n "${2+x}" ] && wmd_wayback_date_from="$2" 
  [ -n "${3+x}" ] && wmd_wayback_date_to="$3" 

  wmd_get_options=()
  [ "$wayback_matchtype" = "exact" ] && wmd_get_options+=(-e)
  [ -n "${wayback_machine_only+x}" ] && [ "$wayback_machine_only" != "" ] && wmd_get_options+=(-o "$wayback_machine_only") 
  [ -n "${wayback_machine_excludes+x}" ] && [ "$wayback_machine_excludes" != "" ] && wmd_get_options+=(-x "$wayback_machine_excludes") 
  [ -n "${wmd_wayback_date_from+x}" ] && [ "$wmd_wayback_date_from" != "" ] && wmd_get_options+=(-f "$wmd_wayback_date_from") 
  [ -n "${wmd_wayback_date_to+x}" ] && [ "$wmd_wayback_date_to" != "" ] && wmd_get_options+=(-t "$wmd_wayback_date_to") 
  [ -n "${wayback_machine_statuscodes+x}" ] && [ "$wayback_machine_statuscodes" = "all" ] && wmd_get_options+=(-a)
  
  wmd_get_options+=(-d "$mirror_archive_dir" "$url")
  echolog " "; echolog "Executing: $wayback_machine_downloader_cmd ${wmd_get_options[*]}"
  $wayback_machine_downloader_cmd "${wmd_get_options[@]}"
}

# Validate Wayback dates
# Assumes wayback_date_from, wayback_date_to,
# and wayback_date_from_to are all defined.
validate_wayback_dates() {
  [ "$wayback_date_to_earliest" = "" ] && wayback_date_from_earliest=19881231123456
  [ "$wayback_date_to_latest" = "" ] && wayback_date_to_latest=29991231123456

  if [ "$wayback_timestamp_policy" = "$range" ] && ! validate_timestamp "$wayback_date_to"; then
    if [ "$wayback_date_to" = "" ]; then
      error_notice="The 'to' date cannot be empty. "
    else
      error_notice="The 'to' date, $wayback_date_to, in the range $wayback_date_from_to, is invalid. "
    fi
    echolog $'\n'"$msg_error: $error_notice It needs to be a string of digits in the format: YYYYMMDDhhmmss (substrings starting with YYYY are allowed). Aborting."; exit
  fi

  if ! validate_timestamp "$wayback_date_from"; then
    if [ "$wayback_date_from" = "" ]; then
      error_notice="The 'from' date cannot be empty. "
    else
      error_notice="The 'from' date, $wayback_date_from, in the range $wayback_date_from_to, is invalid."
    fi
    echolog $'\n'"$msg_error: $error_notice It needs to be a string of digits in the format: YYYYMMDDhhmmss (substrings starting with YYYY are allowed). Aborting."; exit
  fi

  if [ "$wayback_timestamp_policy" = "range" ] && (( wayback_date_from_earliest > wayback_date_from )); then
    echolog $'\n'"$msg_error: the 'from' date specified by wayback_date_from_earliest, $wayback_date_from_earliest, in constants.sh, should not be later than the 'from' date, $wayback_date_from, in the URL range entered!  Aborting."; exit
  fi

  if [ "$wayback_date_to" != "" ]; then
    (( wayback_date_to_latest > wayback_date_to )) && wayback_date_to_latest="$wayback_date_to"
    if (( wayback_date_from > wayback_date_to )); then
      echolog $'\n'"$msg_error: the 'from' date, $wayback_date_from, should not be later than the 'to' date, $wayback_date_to!  Aborting."; exit
    fi
  fi
}

# For Wayback URLs containing a date or date range
# extract the ('from' and) 'to' timestamps 
# and validate them. It also extracts the archived URL
# Expects one parameter: URL
process_wayback_url() {
  if [ -z ${1+x} ]; then
    echolog "$msg_error: URL not supplied. Unable to check Wayback dates."
    echolog "Aborting."
    exit
  else
    local url_stem_dates=${1%http*}
    local url_slashes=${url_stem_dates//[!\/]};
    local url_depth=$(( ${#url_slashes} ))
    wayback_date_from_to=$(echo "$1" | cut -d/ -f${url_depth})
    [ "$wayback_date_from" = "" ] && wayback_date_from="$wayback_date_from_to"
    validate_wayback_dates

    # Remove any 'to' timestamp from url (having extracted from/to dates) 
    url=${url/$wayback_date_from_to/$wayback_date_from}

    # Assign the archived URL as url_original
    (( url_depth++ ))
    url_original=$(printf "%s" "$1" | cut -d/ -f"${url_depth}"-)

    # Assign other variables related to url_original
    protocol_original=$(printf "%s" "$url_original" | awk -F/ '{print $1}' | awk -F: '{print $1}')
    host_original=$(printf "%s" "$url_original" | awk -F/ '{print $3}')
    url_original_base="$protocol_original://$host_original"
    url_original_base_regex=$(regex_escape "$url_original_base")
    url_original_base_singleslash=${url_original_base/:\/\//:\/}  # adjust for Wget directory mapping

    if [ "$url_stem_dates" = "" ] || ! validate_url "$url_original"; then
      printf "%s: The extracted URL, %s, is considered invalid.\n" "$msg_error" "$url_original"
      printf "It is recommended that you modify the value of 'url' and re-run\n."
      echolog "Aborting."
      exit
    fi
    hostname_original=$(printf "%s\n" "$url_original" | awk -F/ '{print $3}' | awk -F: '{print $1}')
  fi

  # Define a hostname variant that supports subdomain spanning
  if [ "$wget_span_subdomains" = "yes" ]; then
    wget_span_subdomains_only=${wget_span_subdomains_expr/|)/)}
    if [[ $hostname_original =~ ^$wget_span_subdomains_only ]]; then
      # Already has a prefix, so trim and reapply
      primaryhostname=$(echo "${hostname_original#*.}")
    else
      # No recognised prefix, so will append
      primaryhostname="$hostname_original"
    fi
    primaryhostname_regex=$(regex_escape "$primaryhostname")
    hostname_original_span=$(echo "$wget_span_subdomains_expr$primaryhostname")
    subdomain_wildcard="://[-[:alnum:]+\\\.]*$primaryhostname_regex"
    if [ "$wayback_merge_httphttps" = "yes" ]; then
    # Allow support for http and https links
      primaryhost_regex_span="https\\\?$subdomain_wildcard"
      primaryhost_ere_span="https\?$subdomain_wildcard"
    else
      primaryhost_regex_span="$protocol_original$subdomain_wildcard"
    fi
  else
    hostname_original_span="$hostname_original"
  fi
}

# Determine runtime configuration for Wayback URL.
initialise_wayback() {
  wayback_url=yes  # Wayback Machine URL established
  url_wildcard_capture=no # reset as the Wayback Machine doesn't yet have a means to handle this; also note that it will refer to all external assets under its own host name.
  host_wayback_machine=$(printf "%s" "$url" | awk -F/ '{print $3}' | awk -F: '{print $1}')
  process_wayback_url "$url" # will set the value of $url_original to be that of the archived site
  printf "Wayback Machine detected at %s, hosted on %s.\n" "$url" "$host_wayback_machine"
  if [ "$wayback_timestamp_policy" = "exact" ] && [ "$wayback_date_to" != "" ]; then
    echolog "$msg_warning: you have specified a date range for the Wayback Machine, but the constant wayback_timestamp_policy is set to 'exact'."
    echolog "To resolve this conflict, MakeStaticSite will only download assets for the earliest timestamp, $wayback_date_from. But you may like to set wayback_timestamp_policy=range."
    confirm_continue "Y" "OK. Please change the URL or review the Wayback settings in constants.sh."
    url=${url/-$waybackdatefrom/}
    wayback_date_to="$wayback_date_from"
  elif [ "$wayback_timestamp_policy" = "range" ] && { (( wayback_date_from < wayback_date_from_earliest)) || (( wayback_date_to > wayback_date_to_latest)); }; then
    msg_wayback_notice="the URL supplied contains a date that is outside of the allowable range specified by the values you have specified for wayback_date_from_earliest and/or wayback_date_to_latest in constants.sh."
    if (( phase < 4 )); then
      echolog "$msg_warning: $msg_wayback_notice  If you proceed, the resulting mirror may likewise contain content captured on a date outside this range."
      confirm_continue
    else
      echolog "$msg_error: $msg_wayback_notice  Please review.  Aborting"; exit
    fi
  fi
  if [ "$wayback_assets_mode" = "original" ]; then
    # Prepare to save a copy
    wget_inputs_wayback_all="$wget_inputs_extra_stem-$myconfig"'-wayback-all.txt' # cumulative input file
    wget_inputs_wayback_extra="$wget_inputs_extra_stem-${myconfig}-wayback.txt" # single run input file
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
      echolog " "; echolog "$msg_error: Unable to establish Internet access. Please check your network connectivity."
      echolog "Aborting."
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
  url_base_regex=$(regex_escape "$url_base")
  url_path_original=$(printf "%s" "$url_original" | cut -d/ -f4-)
  if [ "$url_add_slash" = "avoid" ]; then
    if [[ $url_path_original != */* ]]; then
      url_path_original_dir=''       # set to empty directory if there is no slash
    else
      url_path_original_dir="${url_path_original%\/*}"  # Remove anything after last '/' for URLs not ending in '/'.
    fi
  else
    url_path_original_dir="$url_path_original"
  fi
  [[ ${url_path_original_dir:length-1:1} = "/" ]] && url_path_original_dir=$(echo ${url_path_original_dir::-1}) # Ensure no trailing slash for the directory
  url_path_original_regex=$(regex_escape "$url_path_original_dir")
  url_timeless=${url/\/${wayback_date_from}/\/[0-9]+[a-z]\{0,2\}_\?} # This could be tightened - use $wayback_datetime_regex
  if [ "$wayback_merge_httphttps" = "yes" ]; then
    # Allow support for http and https links
    url_timeless=${url_timeless/\/http:/\/https\?:} 
    url_timeless=${url_timeless/\/https:/\/https\?:} 
  fi
  url_timeless=$(regex_escape "$url_timeless")
  url_timeless=$(regex_apply "$url_timeless")
  url_timeless=${url_timeless//\\[/[} # final adjustment to remove '\' in front of '['
  url_timeless_slash="$url_timeless"
  [ "$url_add_slash" = "avoid" ] && url_timeless_slash="${url_timeless_slash%\/*}/" # Remove anything after last '/' for URLs not ending in '/'
  url_timeless_nodomain=${url_timeless/"$url_base_regex"/}   # Truncated version (note that the pattern is not treated as regex)
  url_timeless_nodomain_slash="$url_timeless_nodomain"
  [ "$url_add_slash" = "avoid" ] && url_timeless_nodomain_slash="${url_timeless_nodomain_slash%\/*}/" # Remove anything after last '/' for URLs not ending in '/'
  url_base_timeless=${url_timeless_slash/"$url_path_original_regex/"/}
  url_base_timeless_nodomain=${url_timeless_nodomain_slash/"$url_path_original_regex/"/}
  url_base_timeless_generic=${url_base_timeless/"$url_original_base_regex/"/}
  url_base_timeless_generic=$(echo "$url_base_timeless_generic" | sed 's|\(https\?:/\)\([^/]\)|\1/\2|') # Ensure http[s] is followed by a colon and two slashes
  url_base_timeless_nodomain_original="${url_base_timeless%\/*\/*}/" # strip everything after the second protocol, removing reference to any original domain

  # Locate source directories to copy
  url_path_root=$(printf "%s" "$url_path" | cut -d'/' -f1,2 )
  url_path_root="$url_path_root/$url_original_root"
  url_path_root=${url_path_root//\/\//\/} # replace double slashes with single slash
  if [ "$url_path_original" != "" ]; then
    [ "$url_add_slash" = "avoid" ] && url_path_root="${url_path_root%\/*}"  # Remove anything after last '/' for URLs not ending in '/'.
    url_path_root="${url_path_root/$url_path_original/}" 
  fi
  [ "${url_path_root: -1}" = "/" ] && url_path_root="${url_path_root:O:-1}" # Remove any trailing '/'
  url_path_snapshot_root=$(printf "%s" "$url_path_root" | cut -d'/' -f2- )
  url_path_snapshot_prefix=$(printf "%s" "${url_path/$wayback_date_from/ }" | cut -d' ' -f1 | cut -d'/' -f1 )
  url_path_prefix=
  for ((i=1;i<url_path_depth;i++)); do
    url_path_prefix+="../"
  done
  wayback_url_re0='https\\?:\/\/'"$domain_re0"
  wayback_url_re0_sed='https\\?://[[:alnum:]][-[:alnum:]+\\.]*'
  url_timeless_nodomain_ere=${url_timeless_nodomain/\/${wayback_url_re0}/\/$primaryhost_ere_span}
  url_timeless_nodomain_ere=$(sed_bre_unescape "$url_timeless_nodomain_ere")
}

# Augment list of candidate URLs
# by determining absolute URLs from relative links
wayback_augment_urls(){
  src_path_snapshot="$working_mirror_dir/$url_path_snapshot_prefix"
  cd_check "$src_path_snapshot" 1
  snapshot_path_list=()
  while IFS= read -r line; do
    line="${line#./}"
    snapshot_path_list+=("$line")
  done <<<"$(find . -mindepth $wayback_snapshot_path_depth -maxdepth $wayback_snapshot_path_depth -print)"

  find_web_pages
  href_matches=()
  wayback_search_regex2="url($url_base_timeless[^)]\+)"
  for opt in "${webpages[@]}"; do
    opt_item=${opt:2}
    opt_filename="${opt##*\/}"
    depth=${opt//[!\/]};
    depth_num=${#depth}
    (( depth_num-- )) # adjustment of 1 needs to be made 
    (( depth_num-=url_path_depth )) # whereas url_path_prefix is fixed,
    pathpref=                       # pathpref denotes the relative path to get from current directory to the snapshot content root 
    for ((i=1;i<=depth_num;i++)); do
      pathpref+="../";
    done

    opt_item2=${opt_item//:\//:\/\/}
    url_stem="$url_base/$url_path_snapshot_prefix/$opt_item2"
    url_stem="${url_stem%\/*}/"  # Remove anything after last '/', then add '/'
    url_stem_slashes=${url_stem//[!\/]}
    url_stem_depth=${#url_stem_slashes}
    while IFS= read -r line; do
      line=${line//[ >\'\"]/}
      line=${line//href=/}
      line=${line//src=/}
      line="${line%#*}" # remove internal anchors
      [ "$line" = "$opt_filename" ] && continue;
      # count number of ../ prefix cuts
      dir_prefix_slash="../"
      dir_prefix_slashes=${line//..\/}
      dir_prefix_depth="$(((${#line} - ${#dir_prefix_slashes}) / ${#dir_prefix_slash} ))"
      this_url="$url_stem"
      if (( dir_prefix_depth != 0 )); then
        # trim URL
        (( trim_depth = url_stem_depth - dir_prefix_depth + 1))
        this_url=$(printf "%s" "$this_url" | cut -d/ -f"$trim_depth"- --complement )
        line="$this_url/$dir_prefix_slashes"
      else
        line="$this_url$line"
      fi
      # remove any trailing slashes
      [ "${line: -1}" = "/" ] && line=${line::-1}
      # percent encode whitespace
      line=${line//[[:space:]]/%20}
      href_matches+=("$line")
    done < <(grep -o -E "$wayback_search_regex" "$opt")

    while IFS= read -r line; do
      line=$(echo "$line" | grep -o -E "$url_re[^\)]")
      href_matches+=("$line")
    done < <(grep -o "$wayback_search_regex2" "$opt")
    
    webassets_all=("${webassets_all[@]}" "${href_matches[@]}")
  done
}

# Apply filters on candidate Wayback URLs based on domains and paths,
# and remove URLs originally from external domains.
# (Currently, there is no filtering based on wayback_timestamp_policy.)
wayback_filter_domains() {
  url_regex=$(printf "%s" "$url"|sed 's|\(/\)'"$wayback_datetime_regex"'|\1'"$wayback_datetime_regex"'|') # turn original URL into wildcard expression
  # Remove anything after last '/'
  if [ "$url_original" != "$url_original_base/" ]; then
    url_regex="${url_regex%\/*}"  
    url_regex+="/"
  fi
  url_regex=${url_regex/"$url_base"/} # trim the URL base to support relative links

  # Further modification when spanning domains
  if [ "$wget_span_subdomains" = "yes" ]; then
    url_regex=${url_regex/"$hostname_original"/"$hostname_original_span"}
  fi
  if [ "$wayback_merge_httphttps" = "yes" ]; then
    # Allow support for http and https links
    url_regex=${url_regex/\/https:/\/https?:} 
    url_regex=${url_regex/\/http:/\/https?:}
  fi

  # Add a constraint on Wget searches
  if (( wget_extra_urls_count == 1 )); then
    wget_extra_core_options+=( "--accept-regex" "\"$url_regex\"" ) # Every link in the Wayback Machine is to an absolute URL
    wget_extra_options+=("--max-redirect=$wget_wayback_max_redirects") # Reduce the risk of Wget fetching external resources whilst allowing the possibility for standard internal redirects to fetch nearest timestamp 
  fi

  # Constrain candidate Wayback URLs for Wget to those that have 
  # a valid asset extension and/or involve the host.
  webassets_wayback0=()
  for opt in "${webassets_http[@]}"; do
    opt_regex=$(printf "%s" "$opt"|sed 's|\(/\)'"$wayback_datetime_regex"'|\1'"$wayback_datetime_regex"'|') # turn original URL into wildcard expression
    # First check if we are fetching a page requisite
    opt_noquery="${opt%\?*}"    # remove any query string
    wayback_ext="$(printf "%s" ".${opt_noquery##*.}" | grep -Ei "$assets_or$")"
    if [ "$wayback_ext" != "" ]; then
      webassets_wayback0+=("$opt")
    # Or if the asset satisfies a no-parent condition
    # and not already in the list modulo timestamps.
    elif [[ $opt =~ $url_regex ]] && [[ ! ${webassets_wayback0[*]} =~ $opt_regex ]]; then
      opt=$(printf "%s" "$opt" | sed 's/#[[:alnum:]]*$//') # remove internal anchors
      webassets_wayback0+=("$opt") 
    else
      continue                  # URL is not allowed, so drop
    fi
  done

  # Filter out any candidate URL that ends with a pair of braces or parenthesis
  webassets_wayback1=()
  for opt in "${webassets_wayback0[@]}"; do
    opt_filter=$(echo "$opt" | sed 's|/[{(][^/]*[})][^/]*$|/|')
    if [ "$opt" = "$opt_filter" ]; then
      webassets_wayback1+=("$opt")
    fi
  done

  # Add further filters based on a list of existing downloaded URLs.
  # Wget's first run only generates one timestamped folder with web pages,
  # but subsequent runs will potentially generate many more, depending on
  # the URLs harvested from the initially downloaded pages.
  # For web pages, timestamped folder names contain only numbers.
  cd_check "$src_path_snapshot" 1

  snapshot_path_list=()
  while IFS= read -r line; do
    line="${line#./}"
    snapshot_path_list+=("$line")
  done <<<"$(find . -mindepth $wayback_snapshot_path_depth -maxdepth $wayback_snapshot_path_depth -print)"

  wayback_download_exceptions=()
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
      if [[ ! ${wayback_download_exceptions[*]} =~ $item_regex ]]; then
        wayback_download_exceptions+=("$item_regex")
      fi

      # Take account of index pages implicit by requests to URLs ending in '/'
      # by truncating Wget default page (usually index.html), as appropriate
      if [[ $item =~ $wget_default_page$ ]]; then
        item_regex="${item_regex/%\/$wget_default_page/\/}" # (need to avoid false positives such as cindex.html and index.htmlx)
        if [[ ! " ${wayback_download_exceptions[*]} " =~ [[:space:]]${item_regex}[[:space:]] ]]; then
          wayback_download_exceptions+=("$item_regex")
        fi
      fi
    done <<<"$(find "." -type f ! -empty -print)"
  done

# shellcheck disable=SC2207
  temp_IFS="$IFS"; IFS=$'\n'; wayback_exceptions=($(sort -u <<<"${wayback_download_exceptions[*]}")); IFS="$temp_IFS"

  ## Apply filter
  webassets_wayback=()
  while IFS= read -r line; do
    webassets_wayback+=("$line");
  done < <(
  for opt in "${webassets_wayback1[@]}"; do
    for exception in "${wayback_exceptions[@]}"; do
      if [[ $opt =~ $exception$ ]]; then
        continue 2              # URL is not allowed, so drop
      fi
    done
    printf "%s\n" "$opt"
  done)

# shellcheck disable=SC2207
  temp_IFS="$IFS"; IFS=$'\n' webassets_http=($(sort -u <<<"${webassets_wayback[*]}")); IFS="$temp_IFS" 
  cd_check "$mirror_dir"
}

# Apply Wayback snapshot-related filters to determine web assets (URLs)
wayback_filter_snapshots() {
  webassets_wayback=()
  if [ "$wayback_assets_mode" = "original" ] && (( wget_extra_urls_count == 1 )); then
    # Pick out unique items, accepting multiple snapshots for the same file and write out
    echolog "Pick out unique items, no snapshot filter" "1"
    webassets_unique_snapshots=()
    while IFS='' read -r line; do webassets_unique_snapshots+=("$line"); done < <(for item in "${webassets[@]}"; do printf "%s\n" "${item}"; done |
      sort -u;)
    echolog "webassets_unique_snapshots array has ${#webassets_unique_snapshots[@]} elements" "2"
    printf "%s\n" "${webassets_unique_snapshots[@]}" > "$input_file_wayback_extra"
  fi
  # Apply timestamp-related filters
  while IFS='' read -r line; do webassets_wayback+=("$line"); done < <(for item in "${webassets[@]}"; do printf "%s\n" "${item}"; done |
    if [ "$wayback_timestamp_policy" = "exact" ]; then
      # Only match (and hence download) assets with given timestamp
      grep "$wayback_date_from" | sort -u | sed 's/\/http/ /g' | sort -u -t ' ' -k 2 | sed 's/ /\/http/g'; # Remove duplicate asset captures, select only those from given timestamp, and ignore any non-Memento URLs
    elif [ "$wayback_assets_mode" = "original" ]; then
      sort -u | sed 's/\/http/ /g' | sort -u -t ' ' -k 2 | sed 's/ /\/http/g'; # remove duplicate asset captures, selecting first according to timestamp, and ignore any non-Memento URLs
    else 
      sort -u;
    fi
  )
  webassets=("${webassets_wayback[@]}")
}

# Postprocessing of Wget output
# generated by requests to Wayback Machine
wayback_wget_postprocess() {
  cd_check "$working_mirror_dir" 1
  # Carry out various search and replaces ahead of MakeStaticSite link conversions
  while IFS='' read -r opt; do
    # Insert Wayback Machine domain for relative links to the root directory
    sed_subs1=('s|\([\"'\'']\)\('"$url_timeless_nodomain"'\)|'"\1$url_base\2"'|g' "$opt")
    # Remove URLs erroneously inserted in template code by Wget via 
    # href or src link conversion.
    sed_subs2a=('s|\(href=['\''"]\)[^'\''"]*/\([{(][^/'\''"]*\)\([)}]\)\(['\''"]\)|\1\2\3\4|g' "$opt")
    sed_subs2b=('s|\(src=['\''"]\)[^'\''"]*/\([{(][^/'\''"]*\)\([)}]\)\(['\''"]\)|\1\2\3\4|g' "$opt")
    # In template or code render blocks, replace space character entity number with a space
    sed_subs3=('s|\([{(][{(]*\)\&\#32;\([^})]*\)\&#32;\([})][})]*\)|\1 \2 \3|g' "$opt")
    sed "${sed_options[@]}" "${sed_subs1[@]}"
    sed "${sed_options[@]}" "${sed_subs2a[@]}"
    sed "${sed_options[@]}" "${sed_subs2b[@]}"
    sed "${sed_options[@]}" "${sed_subs3[@]}"
  done < <(for file_ext in "${asset_find_names[@]}"; do
    find "." -type f -name "$file_ext" -print
  done)
}

# Consolidate snapshot assets in a single location,
# reflecting the original layout.
consolidate_assets() {
  echolog "Consolidating snapshot assets in a single location, reflecting original layout ... "
  print_progress "0" "100";

  webpages=()
  while IFS= read -r line; do webpages+=("$line"); done <<<"$(for file_ext in "${asset_find_names[@]}"; do find . -type f -name "$file_ext" "${asset_exclude_dirs[@]}" -print; done)"
  [ "${webpages[*]}" = "" ] && echolog "$msg_warning: no web pages found for processing."
  num_webpages="${#webpages[@]}"
  
  cd_check "$src_path_snapshot"
  snapshot_exclude_dirs=()
  snapshot_list=("$wayback_date_from")
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
    [ "$line" != "$url_path_snapshot_root" ] && snapshot_path_list+=("$line")
  done <<<"$(find . -mindepth $wayback_snapshot_path_depth -maxdepth $wayback_snapshot_path_depth -type d -print)"

  # Check for mixed http and https snapshots and advise accordingly
  if [ "$protocol_original" = "https" ]; then
    url_path_snapshot_root2=${url_path_snapshot_root/\/https:/\/http:}
  else
    url_path_snapshot_root2=${url_path_snapshot_root/\/http:/\/https:}
  fi
  if [ -d "$url_path_snapshot_root2" ] && ls "$url_path_snapshot_root2" >/dev/null 2>&1; then
    msg_mixed_content="The snapshots that have been have downloaded by the Wayback Machine include both encrypted and unencrypted content, i.e. they have been retrieved from https://$hostname_original and http://$hostname_original."
    if [ "$wayback_merge_httphttps" = "yes" ]; then
      echolog "$msg_info: $msg_mixed_content Will proceed to merge the snapshots under the main branch."
    else        
      echolog "$msg_warning: $msg_mixed_content However, in the main branch, only the content under $url_path_snapshot_root will be processed because in constants.sh, wayback_merge_httphttps is set to $wayback_merge_httphttps.  To incorporate all the snapshot content, please set it to 'yes' and re-run."
      confirm_continue "no"
    fi
  fi
  
  # Log snapshots info
  snapshot_path_list_sorted=()
  snapshot_path_list_plus=("$wayback_date_from" "${snapshot_path_list[@]}")
  while IFS='' read -r line; do snapshot_path_list_sorted+=("$line"); done < <(for item in "${snapshot_path_list_plus[@]}"; do printf "%s\n" "${item%%\/*}"; done | sort -u)
  num_snapshot_dirs="${#snapshot_path_list_sorted[@]}"
  first_snapshot_dir="${snapshot_path_list_sorted[0]}"
  first_snapshot_dir_root="${first_snapshot_dir//[[:alpha:]\_]/}"
  (( last_snapshot_dir_index=num_snapshot_dirs-1 ))
  last_snapshot_dir="${snapshot_path_list_sorted[$last_snapshot_dir_index]}"
  last_snapshot_dir_root="${last_snapshot_dir//[[:alpha:]\_]/}"
  date_from_readable="$(timestamp_readable "$first_snapshot_dir_root")"
  date_to_readable="$(timestamp_readable "$last_snapshot_dir_root")"
  msg_wayback="The site was generated from a Wayback Machine and used $num_snapshot_dirs snapshots, ranging from $wayback_date_from to $last_snapshot_dir, i.e. from $date_from_readable to $date_to_readable."

  cd_check "$working_mirror_dir" 1 "Unable to return to $working_mirror_dir."

  # Initialised source and destination paths (trunks)
  dest_path="$working_mirror_dir/$url_path_dir"
  dest_path_root="$working_mirror_dir/$url_path_root"
  if [ "$url_path_original" != "" ]; then
    if [ "$(find . -name "$assets_directory" -type d -print)" != "" ]; then
      echolog -n "$msg_warning: website already contains a directory, $assets_directory.  To avoid confusion (and errors), a timestamp is being appended to the MakeStaticSite-generated assets directory, but it is recommended that you modify the assets_directory constant and re-run. ... "
      assets_directory="$assets_directory$timestamp"
    fi
    mkdir "$dest_path/$assets_directory" || echolog "Unable to create directory"
  fi

  # Replace the relative links created by Wget (that point to levels higher up in the directory hierarchy)
  count=0
  if (( "${#snapshot_path_list[@]}" > 0 )); then
    if [ -d "$dest_path/$imports_directory" ]; then
      echolog "$msg_warning: A directory at $dest_path/$imports_directory already exists, so not creating it."
    else
      mkdir "$dest_path/$imports_directory" || echolog "$msg_error: Unable to create the 'imports' directory."
    fi
  fi
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

    opt_item="${opt##*"$url_original_base_singleslash"\/}" # extract only the relevant path and then add this on to snapshot_src_path
    opt_item="${opt_item%\/*}" # remove everything after trailing slash
    for item in "${snapshot_path_list[@]}"; do
      this_host="${item##*/}" # remove everything before trailing slash
      snapshot_src_path="$pathpref$url_path_prefix$item"
      snapshot_src_path=$(regex_escape "$snapshot_src_path")
      snapshot_src_path=$(printf "%s" "$snapshot_src_path" | sed 's|'"$wayback_datetime_regex"'|'"$wayback_datetime_regex"'|g') 
      snapshot_src_path=$(regex_apply "$snapshot_src_path")
      if [ "$url_path_original_dir" != "" ]; then
        # this variants targets specifically URLs that contain the URL path
        opt_item_slashes=${opt_item//[!\/]};
        opt_item_slashes_num=${#opt_item_slashes};
        this_path="$opt_item"
        if [[ ! $this_host =~ ^$hostname_original_span$ ]]; then
          this_path_prefix="$imports_directory/$this_host"
        elif [[ ! $url_path_original_dir == $opt_item* ]]; then
          this_path_prefix="$assets_directory"
        else
          this_path_prefix=
        fi
        this_path_regex=$(regex_apply "$this_path")
        for ((j=1;j<=opt_item_slashes_num;j++)); do
          snapshot_src_path0="$snapshot_src_path/$this_path_regex"
          sed_subs0=('s|'"$snapshot_src_path0/"'|'"$this_path_prefix"'|g' "$opt")
          sed "${sed_options[@]}" "${sed_subs0[@]}"
          this_path="${this_path%\/*}" # delete everything after last /
          this_path_prefix="../$this_path_prefix"
        done
      fi
      this_folder_path=
      if [[ ! $this_host =~ ^$hostname_original_span$ ]]; then
        this_folder_path="$imports_directory/$this_host/"
      elif [ "$url_path_original_dir" != "" ]; then
        # First substitute on any match under url_path_original
        sed_subs1=('s|'"$snapshot_src_path/$url_path_original/"'|'""'|g' "$opt") # first convert assets that are underneath the trunk
        sed "${sed_options[@]}" "${sed_subs1[@]}"
        this_folder_path="$assets_directory/"
      fi
      sed_subs1=('s|'"$snapshot_src_path/"'|'"$this_folder_path"'|g' "$opt")
      sed "${sed_options[@]}" "${sed_subs1[@]}"
    done
    (( count++ ))
  done

  cd_check "$src_path_snapshot" 1

  ## Copy over directories and files to URL Path.
  for snapshot_dir in "${snapshot_path_list[@]}"; do
    this_host="${snapshot_dir##*/}" # remove everything before trailing slash
    # Create a directory for $this_host inside the 'imports' directory under the 'destination' path.
    if [[ ! $this_host =~ ^$hostname_original_span$ ]]; then
      mkdir -p "$dest_path/$imports_directory/$this_host" || echolog "$msg_error: Unable to create the external domain directory $this_host inside $dest_path/$imports_directory."
    fi
    echolog "Entering $snapshot_dir" "1"
    if [ -d "$snapshot_dir" ]; then
      cd_check "$snapshot_dir"
    else
      echolog "$msg_warning: the $snapshot_dir isn't present, so unable to enter it." "1"; continue
    fi

    while IFS= read -r copy_dir; do
      copy_dir="${copy_dir#./}"
      if [ "$copy_dir" != "" ] && { [[ ! $url_path_original_dir == $copy_dir/* ]] || [ "$url_path_original_dir" != "" ]; }; then
        if [[ ! $this_host =~ ^$hostname_original_span$ ]]; then
          this_dest_path="$dest_path/$imports_directory/$this_host/$copy_dir"
        elif [[ $copy_dir == $url_path_original_dir* ]]; then
          this_dest_path="$dest_path_root/$copy_dir"
        else
          this_dest_path="$dest_path/$assets_directory/$copy_dir"
        fi
        echolog "mkdir -p $this_dest_path" "1"
        mkdir -p "$this_dest_path" || echolog "$msg_error: Unable to create directory $this_dest_path."

        # loop over files in subdirectory
        while IFS= read -r item; do
          [ "$item" = "" ] && continue
          # check for internal URL path copying and adjust accordingly
          if [[ ! $this_host =~ ^$hostname_original_span$ ]]; then
            file_dest="$dest_path/$imports_directory/$this_host/$item"
          elif [[ $item == $url_path_original_dir* ]]; then
            file_dest="$dest_path_root/$item"
          elif [[ ! $copy_dir == $url_path_original_dir* ]]; then
            file_dest="$dest_path/$assets_directory/$item"
          else
            file_dest="$dest_path/$item"
          fi
          # check if file already exists in destination
          if [ -f "$file_dest" ]; then
            echolog "File exists at $file_dest" "2"
          else
            echolog "Move file $item to $file_dest" "1"
            mv "$item" "$file_dest" || echolog "$msg_warning: Unable to move $item to $file_dest."
          fi
        done <<<"$(find "$copy_dir/" -maxdepth 1 -type f ! -empty -print)"
      fi
      # Loop over files in directory
      while IFS= read -r item; do
        if [ "$item" != "" ]; then
          # check if file already exists in destination
          item="${item#./}"
          if [[ ! $this_host =~ ^$hostname_original_span$ ]]; then
            file_dest="$dest_path/$imports_directory/$this_host/$item"
          elif [[ ! $copy_dir == $url_path_original_dir* ]] || { [ "$copy_dir" = "" ] && [ "$url_path_original_dir" != "" ]; }; then
            file_dest="$dest_path/$assets_directory/$item"
          else
            file_dest="$dest_path/$item"
          fi
          if [ -f "$file_dest" ]; then
            echolog "File exists at $file_dest" "2"
          else
            echolog "Move file $item to $file_dest" "1"
            mv "$item" "$file_dest" || echolog "$msg_warning: Unable to move $item to $file_dest."
          fi
        fi
      done <<<"$(find "." -maxdepth 1 -type f ! -empty -print)"
    done <<<"$(find "." -type d ! -empty -not -path "." -not -path "" -print)"
    cd_check "$src_path_snapshot" 1 "Unable to change directory back to $src_path_snapshot"
  done

  cd_check "$working_mirror_dir"
  cd_check "$url_path_dir"
  webpaths_output2=() # to store directory paths for internal links, creating array before moving supporting assets here
  while IFS='' read -r line; do
    line=${line:2} # remove any ./ prefix
    webpaths_output2+=("$line")    
  done < <(find "." -type d "${asset_exclude_dirs[@]}" -print)
  cd_check "$src_path_snapshot" 1
  if [ "$url_path_original_dir" != "" ]; then
    folder_exclude="$url_path_original_dir"
    [[ ${url_path_original_dir:length-1:1} = "/" ]] && folder_exclude="${folder_exclude%\/*}"  # remove trailing '/'
    folder_exclude_not_path="-not -path ./$folder_exclude"
  else
    folder_exclude_not_path=
  fi

  cd_check "$url_path_snapshot_root"
  if [ "$url_path_original_dir" != "" ]; then
    while IFS= read -r line; do
      line="${line#./}"
      parent_assets_path="$url_path_original_dir"
      [[ ! $url_path_original_dir == $line* ]] && parent_assets_path+="/$assets_directory"
      if [ "$line" != "" ] && [[ ! $url_path_original_dir == $line/* ]]; then
        if [ -d "$parent_assets_path/$line" ]; then
          echolog "$msg_info: the directory $parent_assets_path/$line already exists." "1"
          cp -n -r "$line/"* "$parent_assets_path/$line/" || true; echolog "$msg_warning: An error occurred in copying files/directories under $line to $parent_assets_path/" "1"
        else
          cp -n -r "$line" "$parent_assets_path/" || true; echolog "$msg_warning: Unable to copy $line to $parent_assets_path/" "1"
        fi
      fi
    done <<<"$(find . -maxdepth 1 -type d ! -empty -not -path "." $folder_exclude_not_path -print)"
  fi
  print_progress
  cd_check "$working_mirror_dir" 0 "Unable to enter $working_mirror_dir"
}

# Convert absolute URLs or paths to relative URLs for internal anchors
process_asset_anchors() {
  echolog "Converting absolute URLs to relative URLs for Wayback internal anchors ... "
  print_progress "0" "100";

  # Generate lists of webasset paths
  cd_check "$url_path_dir" 1 "Unable to enter $working_mirror_dir"
  webpages_output=() # to store file paths to web pages only
  webpaths_output=() # to store file paths to web assets for internal links

  while IFS='' read -r line; do
    line=${line:2}
    webpages_output+=("$line")
  done < <(
  for file_ext in "${asset_find_names[@]}"; do
    find "." -type f -name "$file_ext" "${asset_exclude_dirs[@]}" -print
  done)
  num_webpages_output="${#webpages_output[@]}"

  while IFS='' read -r line; do
    line=${line:2}
    # Percent encode spaces
    line=${line// /%20}
    # Escape dots
    line=${line//./\\.}
    # Escape sed delimiter, pipe (dev note: should use a constant)
    line=${line//|/\\|}
    webpaths_output+=("$line")
  done < <(find "." -type f "${asset_exclude_dirs[@]}" -print)

  # URL stems to be used in replacements
  url_stem_timeless_nodomain1="$url_timeless_nodomain_slash"
  url_stem_timeless_nodomain2="$url_base_timeless_nodomain"
  if [ "$wayback_links_relative_rewrite" = "yes" ]; then
    # With Wayback (Memento) URLs, replace the original URL with primaryhost_regex_span (regular expression based on original host)
    # - absolute URLs
    url_timeless=$(echo "$url_timeless" | sed 's|'"/$wayback_url_re0_sed"'|'"/$primaryhost_regex_span"'|g');
    # - relative URLs
    url_stem_timeless_nodomain1=$(echo "$url_stem_timeless_nodomain1" | sed 's|'"/$wayback_url_re0_sed"'|'"/$primaryhost_regex_span"'|g');
    url_stem_timeless_nodomain2=$(echo "$url_stem_timeless_nodomain2" | sed 's|'"/$wayback_url_re0_sed"'|'"/$primaryhost_regex_span"'|g');    
  fi

  # Carry out substitutions in web pages
  count=0
  for opt in "${webpages_output[@]}"; do
    print_progress "$count" "$num_webpages_output";  

    if grep -q '&#' "$opt"; then 
      # Convert character entities to percent-encoded equivalents
      for ((i=32;i<126;i++)); do
        j=$(printf '%x\n' "$i")
        sed_subs=('s|&#'"$i"';|%'"$j"'|g' "$opt")
        sed "${sed_options[@]}" "${sed_subs[@]}"
      done
    fi

    pathpref=
    opt_path_stem=${opt:2}
    [ "$url_path_original_dir" != "" ] && opt_path_stem=${opt_path_stem##*"$url_path_original_dir"}  # Path (directory hierarchy) relative to the original URL
    opt_rel_depth=${opt_path_stem//[!\/]};
    opt_rel_depth_num=${#opt_rel_depth} # measure the relative depth of opt_path_stem
    for ((i=1;i<=opt_rel_depth_num;i++)); do
      pathpref+="../";
    done
    for item in "${webpaths_output[@]}"; do
      # Start with a replacement based on a search pattern that strips .html extension from asset path.
      if [ "${item: -6}" = "\.html" ]; then
        item_no_dot_html="${item:0:-6}"
        item2a=".html"
      else
        item_no_dot_html="$item"
        item2a=""
      fi
      sed_subs1=('s|\('"$url_timeless"'\)\('"$item_no_dot_html"'\)\([\"'\'']\)|'"$pathpref\2$item2a\3"'|g' "$opt")
      sed_subs2=('s|\([\"'\'']\)\('"$url_timeless_nodomain"'\)\('"$item_no_dot_html"'\)\([\"'\'']\)|'"\1$pathpref\3$item2a\4"'|g' "$opt")
      sed "${sed_options[@]}" "${sed_subs1[@]}"
      sed "${sed_options[@]}" "${sed_subs2[@]}"

      url_stem_timeless_nodomain="$url_stem_timeless_nodomain1"
      if [[ $item == $imports_directory* ]]; then
        prefix_replace="$imports_directory/"
        item="${item#"$imports_directory"\/*}"   # remove initial imports directory
      elif [[ $item == $assets_directory* ]]; then
        url_stem_timeless_nodomain="$url_stem_timeless_nodomain2"
        prefix_replace="$assets_directory/"
        item="${item#"$assets_directory"\/*}"    # remove initial assets directory
      else
        prefix_replace=
      fi
      item="${item##*"$hostname_original"\/}"
      item=$(regex_escape "$item")
      if [ "$prune_query_strings" = "no" ]; then
        item2=$(url_percent_encode "$item")
      else
        item2="$item"
      fi
      # For converting links with Wayback host, simply prepend host to url_stem_timeless_nodomain (and its search pattern)
      url_stem_timeless="$url_base_regex$url_stem_timeless_nodomain"

      sed_subs1=('s|'"$url_stem_timeless$item"'|'"$pathpref$prefix_replace$item2"'|g' "$opt")
      sed_subs2=('s|\([\"'\'']\)\('"$url_stem_timeless_nodomain$item"'\)|'"\1$pathpref$prefix_replace$item2"'|g' "$opt")
      sed "${sed_options[@]}" "${sed_subs1[@]}"
      sed "${sed_options[@]}" "${sed_subs2[@]}"

      # For imported assets with Wayback host, strip everything after the second protocol, removing reference to any original domain    
      sed_subs3=('s|\([\"'\'']\)\('"$url_base_timeless_nodomain_original"'\)\('"$item2"'\)\([\"'\'']\)|'"\1$pathpref$prefix_replace\3\4"'|g' "$opt")
      sed "${sed_options[@]}" "${sed_subs3[@]}"

      # Refine search pattern further to handle items that are missing .html extension whilst preserving items that have the extension 
      item2=${item/%\\.html/}
      item2=${item2//&/\\&amp;} # sed escape and convert to entity reference
      # Only add \.html to the replacement if the file extension of $item is .html
      if [[ ${item:length-6:6} = "\.html" ]]; then
        item2a="${item2/\?/%3F}\.html"
      else
        item2a="${item2/\?/%3F}"
      fi
      sed_subs1=('s|\('"$url_stem_timeless"'\)\('"$item2\)\([\'\"[:space:]]\)"'|'"$pathpref$prefix_replace$item2a\3"'|g' "$opt")
      sed_subs2=('s|\([\"'\'']\)\('"$url_stem_timeless_nodomain"'\)\('"$item2"'\)\('"[\'\"[:space:]]"'\)|'"\1$pathpref$prefix_replace$item2a\4"'|g' "$opt")
      sed_subs3=('s|\([\"'\'']\)\('"$item2"'\)\('"[\'\"[:space:]]"'\)|'"\1$pathpref$prefix_replace$item2a\3"'|g' "$opt")
      sed "${sed_options[@]}" "${sed_subs1[@]}"
      sed "${sed_options[@]}" "${sed_subs2[@]}"
      sed "${sed_options[@]}" "${sed_subs3[@]}"
      # If $item is index.html or ends in /index.html, then use a search pattern that removes everything after the final /
      if [[ ! $prefix_replace =~ "imports/" ]] && { [[ ${item:length-12:12} = "/index\.html" ]] || [ "$item" = "index\.html" ]; }; then
        item3="${item:0:length-11}"
        sed_subs4=('s|\('"$url_stem_timeless"'\)\('"$item3\)\([\'\"[:space:]]\)"'|'"$pathpref$prefix_replace$item2a\3"'|g' "$opt")
        sed_subs5=('s|\([\"'\'']\)\('"$url_stem_timeless_nodomain"'\)\('"$item3"'\)\('"[\'\"[:space:]]"'\)|'"\1$pathpref$prefix_replace$item2a\4"'|g' "$opt")
        sed "${sed_options[@]}" "${sed_subs4[@]}"
        sed "${sed_options[@]}" "${sed_subs5[@]}"
        if [ "$item3" != "" ]; then
          sed_subs6=('s|\([\"'\'']\)\('"$item3"'\)\('"[\'\"[:space:]]"'\)|'"\1$pathpref$prefix_replace$item2a\3"'|g' "$opt")
          sed "${sed_options[@]}" "${sed_subs6[@]}"
        fi
      fi
    done
    # Conversion of Wayback anchors make implicit index pages explicit, to assist in internal navigation
    # (1) Empty case
    sed_subs1=('s|\('"$url_timeless"'\)\([\"'\'']\)|'"${pathpref}index.html\2"'|g' "$opt")
    sed_subs2=('s|\([\"'\'']\)\('"$url_timeless_nodomain"'\)\([\"'\'']\)|'"\1${pathpref}index.html\3"'|g' "$opt")
    sed "${sed_options[@]}" "${sed_subs1[@]}"
    sed "${sed_options[@]}" "${sed_subs2[@]}"
    # (2) Non-empty case
    for item in "${webpaths_output2[@]}"; do
      item=$(regex_escape "$item")
      [[ ${item:length-1:1} != "/" ]] && item+="/"
      sed_subs1=('s|\('"$url_timeless"'\)\('"$item"'\)\([\"'\'']\)|'"$pathpref\2index.html\3"'|g' "$opt")
      sed_subs2=('s|\([\"'\'']\)\('"$url_timeless_nodomain"'\)\('"$item"'\)\([\"'\'']\)|'"\1$pathpref\3index.html\4"'|g' "$opt")
      sed "${sed_options[@]}" "${sed_subs1[@]}"
      sed "${sed_options[@]}" "${sed_subs2[@]}"
    done
    (( count++ ))
  done
  print_progress
  cd_check "$working_mirror_dir"
}

# Clean the HTML output generated by the Wayback Machine
wayback_output_clean() {
  webpages_clean_find=()
  while IFS= read -r line; do webpages_clean_find+=("$line"); done <<<"$(for file_ext in "${asset_find_names[@]}"; do find "." -type f \( -name "$file_ext" -o -name "$file_ext"\?\* -o -name "$file_ext"@\* \) "${asset_exclude_dirs[@]}" -print; done)"
  webpages_clean=()
  while IFS='' read -r line; do webpages_clean+=("$line"); done < <(for item in "${webpages_clean_find[@]}"; do printf "%s\n" "${item%/}"; done | sort -u)
  num_webpages_clean="${#webpages_clean[@]}"
  if [ "$num_webpages_clean" = "0" ]; then
    echolog "$msg_warning: no web pages found for cleaning."
  else
    echolog -n "Cleaning the HTML output generated by the Wayback Machine ... "
  fi

  if [ "$wayback_code_clean" = "yes" ] && [ "$num_webpages_clean" != "0" ]; then
    # Delete (JavaScript) Playback code inserted by Wayback Machine.
    # We have to deal with blocks containing newlines, so use awk rather than sed.
    # Specify as record separator an ASCII character that is not used in files (in this case: bell alert).
    echolog "Delete (JavaScript) Playback code inserted by Wayback Machine ... " "1"
    for opt in "${webpages_clean[@]}"; do
      tmp_file="$opt.tmp"
      if [ -f "$opt" ]; then
        awk -v RS='\x7' '{sub(/'"$wayback_code_toolbar_re"'/,""); print}' "$opt" > "$tmp_file" && mv "$tmp_file" "$opt"
        wayback_tags_list=()
        IFS=',' read -ra wayback_tags_list <<< "$wayback_code_tags"
        for tag in "${wayback_tags_list[@]}"; do
# shellcheck disable=SC1087
          tag_full=$(grep -m 1 -o "<$tag[[:space:]]*[^>]*>" "$opt")  # Get the tag, including any attributes
# shellcheck disable=SC1087
          awk -v RS='\x7' -v var="$tag_full" '{sub(/<'"$tag[^>]*>$wayback_code_re"'/,var); print}' "$opt" > "$tmp_file" && mv "$tmp_file" "$opt"
        done
      else
        echolog "$msg_warning: File $opt not found, so not running awk on it." "1"
      fi
    done
  fi

  if [ "$num_webpages_clean" != "0" ]; then
    # Delete Wayback host URL prefix inserted by Wayback Machine
    search_pattern="$url_base_timeless_generic"
    replace_pattern=
    # or at least fix mailto: links
    if [ "$wayback_links_clean" != "yes" ]; then 
       search_pattern+="mailto:"
       replace_pattern+="mailto:"
    fi
    echolog "Delete Wayback host URL prefix inserted by Wayback Machine ... " "1"
    for opt in "${webpages_clean[@]}"; do
      if [ -f "$opt" ]; then
        sed_subs=('s|'"$search_pattern"'|'"$replace_pattern"'|g' "$opt")
        sed "${sed_options[@]}" "${sed_subs[@]}"
      else
        echolog "$msg_warning: File $opt not found, so not running awk on it." "1"
      fi
    done
  fi

  if [ "$wayback_comments_clean" = "yes" ] && [ "$num_webpages_clean" != "0" ]; then
    # Delete HTML comments inserted by Wayback Machine
    # As per JavaScript processing, use awk rather than sed to deal with blocks containing newlines.
    echolog "Delete HTML comments inserted by Wayback Machine ... " "1"
    for opt in "${webpages_clean[@]}"; do
      tmp_file="$opt.tmp"
      if [ -f "$opt" ]; then
        awk -v RS='\x7' '{sub(/'"\/\*$wayback_comments_re\*\/"'/,""); print}' "$opt" > "$tmp_file" && mv "$tmp_file" "$opt"
        awk -v RS='\x7' '{sub(/'"<\/html>[^<]*<!--$wayback_comments_re-->"'/,"</html>"); print}' "$opt" > "$tmp_file" && mv "$tmp_file" "$opt"
      else
        echolog "$msg_warning: File $opt not found, so not running awk on it." "1"
      fi
    done
  fi

  if [ "$wayback_folders_clean" = "yes" ]; then
    IFS=',' read -ra wayback_folders_list <<< "$wayback_folders"
    for wayback_folder in "${wayback_folders_list[@]}"; do
      wayback_folder_path="$working_mirror_dir/$wayback_folder"
      if ls -l "$wayback_folder_path" >> /dev/null 2>&1; then
        rm -rf "$wayback_folder_path"
        echolog "Removed Wayback folder $wayback_folder_path" "1"
      else
        echolog "No Wayback folder $wayback_folder_path found for deletion." "1"
      fi
    done
  fi

  if [ "$wayback_relative_links_clean" = "original" ]; then
    url_wayback_host_prefix="${url_timeless%%'/http'*}/"
    url_wayback_hostless_prefix="${url_timeless_nodomain%%'/http'*}/"
    for opt in "${webpages_clean[@]}"; do
      sed_subs=('s|'"$url_wayback_host_prefix"'||g' "$opt")
      sed "${sed_options[@]}" "${sed_subs[@]}"
    done
    for opt in "${webpages_clean[@]}"; do
      sed_subs=('s|'"$url_wayback_hostless_prefix"'||g' "$opt")
      sed "${sed_options[@]}" "${sed_subs[@]}"
    done
    echolog "Restored original host in URLs, removing references to the Wayback Machine host." "1"
  elif [ "$wayback_relative_links_clean" = "wayback" ]; then
    url_wayback_hostless_prefix="${url_timeless_nodomain%%'/http'*}/"
    for opt in "${webpages_clean[@]}"; do
      sed_subs=('s|\([\"'\'']\)\('"$url_wayback_hostless_prefix"'\)|\1'"$url_base"'\2|g' "$opt")
      sed "${sed_options[@]}" "${sed_subs[@]}"
    done
    echolog "Converted residual Wayback Machine relative links to absolute links." "1"  
  fi

  if [ "$num_webpages_clean" != "0" ]; then
    echolog "Done."
  fi
}
