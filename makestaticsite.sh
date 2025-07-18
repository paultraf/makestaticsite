#!/usr/bin/env bash

##########################################################################
#
# MakeStaticSite --- a shell script to create and deploy static websites
# Copyright 2022-2025 Paul Trafford <pt@ptworld.net>
#
# makestaticsite.sh - main script for MakeStaticSite
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

# Prerequisites
# Bash 3 and write permissions in this directory and in the target deployment directories

# shellcheck disable=SC2015,SC2119,SC2154

SECONDS=0                  # start timer

source lib/constants.sh    # load constants, particularly runtime defaults
source lib/general.sh      # load general functions library
source lib/validate.sh     # load the validation functions library
source lib/config.sh       # load the config functions library

main() {
  # Local context - this directory
  script_dir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"

  # Phase 0: Initialisation
  ((max_phase_num=${#all_phases[@]}-1)) # Number of phases minus one
  get_inks
  whichos
  read_config "$@"
  initialise_layout
  initialise_variables

  # Phase 1: Prepare the CMS
  (( phase < 2 )) && (( end_phase >= 1 )) && prepare_static_generation

  # Phase 2: Generate a static mirror
  (( phase < 3 )) && (( end_phase >= 2 )) && mirror_site

  # Phase 3: Augment the static site
  (( phase < 4 )) && (( end_phase >= 3 )) && augment_mirror

  # Phase 4: Refine the static site
  (( phase < 5 )) && (( end_phase >= 4 )) && [ "$site_post_processing" = "yes" ] && site_postprocessing

  # Ensure that if 'no host directory' is set, the working directories are set accordingly after postprocessing
  if [ "$host_dir_mode" = "" ] || [ "$host_dir_mode" = "no" ]; then
    host_dir=
    working_mirror_dir="$mirror_dir/$mirror_archive_dir"
  fi

  # Phase 5: Further additions from an extras folder
  (( phase < 6 )) && (( end_phase >= 5 )) && [ "$add_extras" = "yes" ] && add_extras

  # Phase 6: Optimise the mirror
  (( phase < 7 )) && (( end_phase >= 6 )) && clean_mirror

  # Phase 7: Use snippets
  (( phase < 8 )) && (( end_phase >= 7 )) && [ "$use_snippets" = "yes" ] && process_snippets

  # Phase 7-8 Interval: Organise site layout and mapping
  (( phase < 8 )) && (( end_phase >= 4 )) && site_layout

  # Phase 8: Create an offline zip archive
  (( phase < 9 )) && (( end_phase >= 8 )) && [ "$upload_zip" = "yes" ] && create_zip || { echolog "Creation of ZIP archive skipped, as per preferences." "1"; }

  # Phase 9: Deploy
  (( end_phase >= 9 )) && [ "$deploy" = "yes" ] && deploy || echolog "Runtime option for deployment set to 'no'; deployment skipped."

  # Phase 10: Finish
  conclude
}
################## END OF PHASES ##################


###################################################
#                Support functions
###################################################

read_config() {
  run_params="$*"
  myconfig=default
  phase=0
  end_phase=$max_phase_num
  mirror_archive_dir=
  config_flag=off # flag to denote whether or not -i option set
  mirror_id_flag=off # flag to denote whether or not -m option set

  local OPTIND
  while getopts "ui:f:p:q:m:L:vh" option; do
    case "$option" in
      f)
        batch_file="$OPTARG"
        [ -f "$batch_file" ] || { printf "%s\n" "$msg_error: Sorry, unable to read from the batch file, $batch_file; it doesn't appear to exist.  Please try again."; exit; }
        mss_batch; exit
        ;;
      u)
        run_unattended=yes
        ;;
      i)
        myconfig="$OPTARG"
        config_flag=on
        ;;
      m)
        mirror_archive_dir="$OPTARG"
        mirror_id_flag=on
        ;;
      p)
        phase="$OPTARG"
        ;;
      q)
        end_phase="$OPTARG"
        ;;
      v)
        echo "$version_header"
        exit
        ;;
      L)
        log_filename="$OPTARG"
        ;;
      h)
        echo "$version_header"
        echo "Usage: ./makestatic.sh [OPTIONS]"
        echo
        echo "Allowable options are:"
        echo " -u                 Run unattended."
        echo " -f FILENAME        Batch file listing configuration file names."
        echo " -i FILENAME        Input configuration file name."
        echo " -p NUMBER          Run from phase NUMBER, where"
        echo "    0 (default)     Initialisation"
        echo "    1               Prepare the CMS"
        echo "    2               Generate static site"
        echo "    3               Augment static site"
        echo "    4               Refine static site"
        echo "    5               Add extras"
        echo "    6               Optimise"
        echo "    7               Use snippets"
        echo "    8               Create offline zip"
        echo "    9               Deploy"
        echo "                  and"
        echo " -m MIRROR_ID       use mirror with identifier MIRROR_ID."
        echo " -q NUMBER          End at phase NUMBER (default is 9, end)."
        echo " -L FILENAME        log file name."
        echo " -v                 Display MakeStaticSite version number."
        echo " -h                 Display help."
        echo
        echo "Please refer to the README file for further information."
        exit
        ;;
      : )
        echo "Invalid option: $OPTARG requires an argument" 1>&2
        echo "Please try again."
        exit
        ;;
      \? )
        echo "Invalid option: $OPTARG" 1>&2
        echo "Allowable options are:"
        echo " -u                 Run unattended."
        echo " -f FILENAME        Batch file listing configuration file names."
        echo " -i FILENAME        Input configuration file."
        echo " -p NUMBER          Run from phase NUMBER (default is 0, start)."
        echo " -q NUMBER          End at phase NUMBER (default is 9, end)."
        echo " -m MIRROR_ID       Use mirror with identifier MIRROR_ID."
        echo " -L FILENAME        log file name."        
        echo " -v                 Display MakeStaticSite version number."
        echo " -h                 Display help."
        echo "Please try again."
        exit
      ;;
    esac
  done
  shift $((OPTIND-1))
}

mss_batch() {
  # Read and process batch_file, line by line
  while IFS= read -r cfg_line; do
    echolog -n "Running makestaticsite.sh with configuration file $cfg_line ..."$'\n'
    [ ! -f "config/$cfg_line" ] && { echolog -n "$msg_error: URL $cfg_line not found, so skipping it."$'\n'; continue; }
    ./makestaticsite.sh -i "$cfg_line" -u
    echo -n "---------------------------------------"$'\n'
  done < "$batch_file"
  echolog -n "Batch run complete."$'\n'
}

initialise_include_excludes() {
  # Directories to exclude from processing
  # -not -path "/full/path/to/directory/*"
  asset_exclude_dirs=()
  IFS=',' read -ra list <<< "$web_source_exclude_dirs"
  for item in "${list[@]}"; do
    asset_exclude_dirs+=( -not -path "${working_mirror_dir}/$item/"\* ) # this needs to be a full path
  done
}

initialise_mirror_archive_dir() {
  if [ "$mirror_archive_dir" = "" ]; then
    mirror_archive_dir="$local_sitename"
    [ "$archive" = "yes" ] && mirror_archive_dir+="$timestamp"
    
    # Rename existing mirror_archive_dir if it already exists
    if [ -d "$mirror_dir/$mirror_archive_dir" ]; then
      # determine what the backup file should be
      archive_dir_current="$mirror_dir/$mirror_archive_dir"
      archive_dir_backup="$archive_dir_current"
      i=1
      while [ -d "$archive_dir_backup" ]
      do
        archive_dir_backup="${archive_dir_current}_$i"
        (( i++ ))
      done
      echolog "$msg_warning: a mirror archive directory, $archive_dir_current, already exists! It will be renamed $archive_dir_backup." 
      confirm_continue
      if ! mv "$archive_dir_current" "$archive_dir_backup"; then
        echolog "$msg_error: unable to rename!"
        confirm_continue "no"
      fi
    fi
  fi
  working_mirror_dir="$mirror_dir/$mirror_archive_dir$host_dir"
  working_mirror_lock=

 # For Wayback Machine mirrors, optionally rename archive folder
  if [ "$wayback_url" = "yes" ] && (( phase < 3 )); then
    cd_check "$mirror_dir" 1
    # (re-)name archive directory in terms of constants wayback_sitename_hosts and wayback_sitename_timestamps
    mirror_archive_dir_old="$mirror_archive_dir"
    mirror_archive_dir=
    if [ "$wayback_sitename_hosts" = "primary" ]; then
      mirror_archive_dir="$hostname_original"
    elif [ "$wayback_sitename_hosts" = "both" ]; then
      mirror_archive_dir="$hostname-$hostname_original"
    else
      mirror_archive_dir="$hostname"
    fi

    if [ "$wayback_sitename_timestamps" = "mss" ]; then
      mirror_archive_dir+="$timestamp"
    elif [ "$wayback_sitename_timestamps" = "both" ]; then
      if [ "$wayback_sitename_hosts" != "both" ]; then
        echolog "$msg_warning: setting wayback_sitename_hosts=both to support your setting of wayback_sitename_timestamps=both"
      fi
      mirror_archive_dir="$hostname$timestamp-$hostname_original$wayback_date_from_to"
    elif [ "$wayback_sitename_timestamps" = "wayback" ] || [ "$wayback_sitename_timestamps" = "" ]; then
      mirror_archive_dir+="$wayback_date_from_to"
    fi
    mirror_archive_dir="${mirror_archive_dir//\./_}"
    if (( phase > 2 )); then
      if mv "$mirror_archive_dir_old" "$mirror_archive_dir"; then
        echolog "Renamed $working_mirror_dir to $mirror_dir/$mirror_archive_dir$host_dir." "1"
      else
        echolog "$msg_warning: Unable to rename mirror_archive_dir $mirror_dir/$mirror_archive_dir"
      fi
    fi
    # Update mirror variable
    working_mirror_dir="$mirror_dir/$mirror_archive_dir$host_dir"
  fi

  # Define a temporary area inside working mirror directory
  tmp_working_dir="$working_mirror_dir/_tmpfiles"

  if (( phase == 4 )) && [ ! -d "$working_mirror_dir/$url_path_dir" ]; then
    if [ -d "$working_mirror_dir" ]; then
      msg_compare=" and compare with the actual contents of $working_mirror_dir"
    else
      msg_compare=" (and also why $working_mirror_dir doesn't exist)"
    fi
    echolog "$msg_error: Directory $working_mirror_dir/$url_path_dir not found. Please check $myconfig.cfg$msg_compare, especially that the value of url ($url) is compatible. If there was originally a URL redirect involved, then url should be assigned that value.  Aborting"; exit 
  fi
  
  zip_archive="$mirror_archive_dir.zip"
  initialise_include_excludes
}

initialise_layout() {
  # Set up logging
  log_file_dir="$script_dir/log"
  mkdir -p "$log_file_dir"
  log_file="$log_file_dir/$log_filename"
  touchmod "$log_file"

  printf "Welcome to MakeStaticSite version %s\n" "$version"
  # Set up 'Run commands' file
  touchmod "$HOME/$credentials_rc_file"

  # Set up temporary directory
  tmp_dir_path="$script_dir/$tmp_dir"
  tmp_mirror_path="$tmp_dir_path/mirror"
  mkdir -p "$tmp_mirror_path"

  timestamp_start=$(timestamp "$timezone")
  timestamp_human=$(date)
  { printf "Starting run of MakeStaticSite, version %s\n" "$version";
    printf "Timestamp: %s\n" "$timestamp_start";
    printf "Running with command line options: %s\n" "$run_params"; } >> "$log_file"

  # Local target directory and web server deployment
  mirror_dir="$script_dir/mirror"         # path to Wget output root folder
  if [ ! -d "$mirror_dir" ]; then
    mkdir -p "$mirror_dir"; echolog "Created folder for mirror files at $mirror_dir."
  fi

  # Substitute files for zip download (used for embeds, etc.)
  sub_dir=subs                            # This must be sit under $script_dir
  sub_files_dir=files                     # This must be sit under $sub_dir
  sub_files_path="$script_dir/$sub_dir/$sub_files_dir"

  snippets_dir="$script_dir/snippets"     # directory storing snippets (.html files)
  snippets_data_file="$snippets_dir/snippets.data" # list of directories/files relative to
                                          # zip root inside the $sub_files_dir
                                          # (separated by space)
                                          # Default is just the home page
                                          # Script will generate this dynamically
                                          # using this data file where each row is
                                          # path_to_html_file:<list of snippet ids>
  snippets_count=0                        # Initialise number of snippets found

  lib_files=lib/files                     # library files (defaults/templates) directory

  if [ "$log_level" = "silent" ]; then
    exec 2>/dev/null
  else
    exec 2> >(tee -a "$log_file" >&2) # additionally, append stderr to logfile
  fi

  # If output_level is silent, then don't echo anything to the terminal
  # and set run un_attended=yes
  if [ "$output_level" = "silent" ]; then
    exec 1>/dev/null
    if [ "$run_unattended" = "no" ]; then
      echolog "NOTICE: run_unattended=yes (to keep terminal output silent)" 0
    fi
    run_unattended=yes
  fi

  return 0
}

initialise_variables() {
  myconfig=${myconfig/.cfg/}
  # Session data (to be built up as we go along, starting with MakeStaticSite version information)
  session_data=("System|$version_header") 
  session_data+=("Run on|$timestamp_human")

  # Read phase details
  validate_range 0 "$max_phase_num" "$phase" || { echolog "Sorry, the phase number is out of range (it should be between 0 and $max_phase_num).  Please try again."; exit; }

  # Read phase details
  validate_range 1 "$max_phase_num" "$end_phase" || { echolog "Sorry, the phase number for exiting the program is out of range (it should be between 1 and $max_phase_num).  Please try again."; exit; }

  ((phase>end_phase)) && { printf "%s: The (start) phase number cannot be greater than the end phase number.\nPlease rerun the program." "$msg_error"; exit; }

  # If the phase is nonzero, then check for -m option
  if ((phase > minvalue)) && [ "$mirror_id_flag" = "off" ]; then
    echolog "$msg_error: Missing -m option (mirror archive folder name) is needed for the supplied start phase (p). Please refer to the help:"
    echo
    ./makestaticsite.sh -h
    exit
  fi

  # If the phase numbers are too small, then nothing much will be done
  if ((end_phase < 2)); then
    echolog "$msg_warning: No site will be output because the supplied end phase (q) is too low."
  fi

  # Check that a mirror archive exists corresponding to the mirror identifier
  if [ "$mirror_id_flag" = "on" ]; then
     if [ ! -d "$mirror_dir/$mirror_archive_dir" ]; then
       echolog "ATTENTION! No mirror archive was found at $mirror_dir/$mirror_archive_dir"
       echolog "Here is a list of possible mirror IDs:"
       cd_check "$mirror_dir" 1
       pwd
       sh -c "ls -d */ | sed 's/\///'"
       echolog "Please choose one from the list and rerun with -m option."
       cd_check "$script_dir" 1
       exit
     else
       echolog "Found mirror archive at $mirror_dir/$mirror_archive_dir"
     fi
  fi

  start_phase_desc=$(get_phase_desc "$phase")
  echolog "Starting at phase $phase: $start_phase_desc."
  ((end_phase<=max_phase_num)) && { end_phase_desc=$(get_phase_desc "$end_phase"); echolog "Ending at phase $end_phase: $end_phase_desc."; }

  # Check for mirror ID and, if necessary, derive input cfg file from it
  # (looking at the tail for the timestamp format)
  if [ "$myconfig" = "default" ] && [ "$mirror_id_flag" = "on" ]; then
    myconfig=$(printf "%s" "$mirror_archive_dir" | sed "s/20[[:digit:]]\{6\}_[[:digit:]]\{6\}$//")
  fi

  # Check we now have a valid config file and display it
  check_config_file "$myconfig"
  printf "Reading custom configuration data from config/%s ...\n" "$myconfig.cfg"

  # Assign option variables for those that have no dependencies
  assign_option_variables "options_nodeps_load"

  # now augment Wget input files with .cfg label
  wget_inputs_main="$wget_inputs_main_stem-$myconfig.txt"
  wget_inputs_extra_all="$wget_inputs_extra_stem-${myconfig}-all.txt" # cumulative input file
  wget_inputs_extra="$wget_inputs_extra_stem-$myconfig.txt" # single run input file
  wget_long_filenames="$wget_long_filenames-$myconfig.txt"
  wget_extra_urls_count=1 # Initialise recursive calls to wget_extra_urls()

  # Translate to output levels for rsync and Wget respectively
  if [ "$output_level" = 'silent' ] || [ "$output_level" = 'quiet' ]; then
    rvol=-q; wvol=-q; wpvol=--quiet
  elif [ "$output_level" = 'verbose' ]; then
    rvol=-v; wvol=; wpvol=--debug
  else
    rvol=; wvol=-nv; wpvol=
  fi

  # Check system requirements for cURL, Wget and SSL
  msg_checking="Checking your system for Wget and other essential components ... "
  cmd_check "curl" || { printf "%s%s: Unable to find binary: curl ("'$'"PATH contains %s).\nThis command is essential for checking connectivity. It may be downloaded from https://curl.se/.\nAborting.\n" "$msg_checking" "$msg_error" "$PATH"; exit; }
  cmd_check "$wget_cmd" "1" || { printf "%s: Unable to carry out a snapshot\nPlease review the value of the wget_cmd option.\nAborting.\n" "$msg_error"; exit; }
  echolog "OK" "1"
  echo "$msg_checking"
  wget_cmd_version="$(which_version "$wget_cmd" "GNU Wget")"
  version_status=
  version_check "$wget_cmd_version" "$wget_version_atleast" || { version_status=error; echo "$msg_warning The version of $wget_cmd is $wget_cmd_version, which is old, so some functionality may be lost. Version $wget_version_atleast or later is recommended for full functionality.";}
  version_check "$wget_cmd_version" "$wget_version_secure_atleast" ||
  {
    security_notice="has known security issues, depending on your usage (see advisory $wget_version_security_ref)"
    if [ "$version_status" = "error" ]; then
      echo "$msg_warning This version also $security_notice. Version $wget_version_secure_atleast or later is recommended to improve security.";
    else
      echo "$msg_warning The version of $wget_cmd is $wget_cmd_version, which $security_notice. Version $wget_version_secure_atleast or later is recommended to improve security.";
    fi
  }  
  [ "$ssl_checks" = "no" ] && wget_ssl="--no-check-certificate" || wget_ssl=''
  session_data+=("Wget version|$wget_cmd_version")

  # Generate user agent when option set to 'mss'
  if [ "$wget_user_agent" = "mss" ]; then
    wget_user_agent="MakeStaticSite/$version (Wget/$wget_cmd_version; +$mss_site)"
  fi

  # Web server details (to be snapped by Wget, etc.)
  IFS="," read -ra webpage_file_exts <<< "$webpage_file_extensions"

  url_add_slash=no # Should we add a trailing '/' to URL (yes/no)?  Initially assume no.
  if [[ ${url:length-1:1} != "/" ]]; then
    url_add_slash=yes # Now assume yes, unless ...
    for ext in "${webpage_file_exts[@]}"; do
      url_noquery=${url%\?*}
      ext_length=${#ext}
      (( ext_length++ ))
      if [[ ${url_noquery:length-$ext_length:$ext_length} = ".$ext" ]]; then # URL ends in a recognised file extension that can't have slash added.
        url_add_slash=avoid; break
      fi
    done
  fi
  [ "$url_add_slash" = "yes" ] && url="$url/"; # ensure URL ends in trailing slash

  # Check HTTP connectivity and specifically Wayback URLs with ranges
  invalid_http_reason= # initialise reason for failure (initially none)
  validate_url_range "$url" "url"
  if [ "$invalid_http_reason" != "" ]; then
    echolog "$invalid_http_reason Aborting."; exit
  fi

  # Wayback Machine support
  use_wayback_cli=no # Initially assume not using Wayback client
  if check_wayback_url "$url" "$wayback_hosts" "url"; then
# shellcheck source=lib/mod_wayback.sh
    source "lib/$mod_wayback";
    initialise_wayback
    session_data+=("Wayback URL|$url")
  else
    wayback_url=no
    session_data+=("URL|$url")
  fi

  url_hostname=$(printf "%s\n" "$url" | awk -F/ '{print $3}' | awk -F: '{print $1}')
  url_path=$(printf "%s" "$url" | cut -d/ -f4- | sed s'|/$||')
  if [ "$url_path" = "" ]; then
    url_path_depth=0
  else
    if [ "$path_doubleslash_workaround" = "yes" ]; then
      # Replace double slashes in URL paths with single slashes
      url_path=${url_path//\/\//\/}
    fi
    url_slashes=${url_path//[!\/]}
    url_path_depth=$(( ${#url_slashes}+1 ))
    [ "$url_add_slash" = "avoid" ] && (( url_path_depth-- )) # need to adjust for extra '/' not being added because of valid web file extension
  fi

  # Validate additional, supported extensions and domains (hosts) for stored assets
  asset_domains="$(printf "%s" "$asset_domains" | tr -d '[:space:]')"
  IFS=',' read -ra list <<< "$asset_domains"
  c=0; for asset_domain in "${list[@]}"; do
    validate_domain "$asset_domain" || {
      asset_domains=$(printf "%s" "$asset_domains" | sed 's~'"$asset_domain"',~~' | sed 's~',"$asset_domain"'~~' )
      c=1; echolog -n $'\n'"$msg_warning: removed invalid asset domain $asset_domain from list."
    }
  done
  [ "$c" = "1" ] && echolog -n $'\n'
  if [ "$wayback_url" = "yes" ] && [ "$wayback_mementos_only" = "yes" ]; then  
    page_element_domains=
  else
    page_element_domains="$(printf "%s" "$page_element_domains" | tr -d '[:space:]')"
  fi
  IFS=',' read -ra list <<< "$page_element_domains"
  if [ "$page_element_domains" != "auto" ]; then
    c=0; for page_element_domain in "${list[@]}"; do
      validate_domain "$page_element_domain" || {
        c=1; echolog -n $'\n'"$msg_warning: removing invalid page element domain $page_element_domain from list."
        page_element_domains=$(printf "%s" "$page_element_domains" | sed 's~'"$page_element_domain"',~~' | sed 's~',"$page_element_domain"'~~' )
      }
    done
    [ "$c" = "1" ] && echolog -n $'\n'
  fi
  asset_grep_includes=()
  asset_find_names=()
  IFS=',' read -ra list <<< "$web_source_extensions"
  for item in "${list[@]}"; do
    asset_grep_includes+=( --include \*."$item" )
    asset_find_names+=( \*."$item" )
  done

  # Static web page file extensions
  IFS=',' read -ra list <<< "$static_webpage_file_extensions"
  html_file_exts=()
  for item in "${list[@]}"; do
    html_file_exts+=(  \*."$item" )
  done
  
  # Extensions supported by HTML Tidy
  IFS=',' read -ra list <<< "$htmltidy_source_extensions"
  htmltidy_file_exts=()
  for item in "${list[@]}"; do
    htmltidy_file_exts+=(  \*."$item" )
  done

  # For backwards-compatibility check whether URL defined instead in url_base
  if [ "$url_hostname" = "example.com" ]; then
    url="$(config_get url_base "$myconfig")"
    if [ "$url" = "" ]; then { printf "\n%s: Unable to determine a URL. Please check the arguments you have supplied at the command line and then the value of url in %s.cfg (if it's example.com, then it needs to be changed!)\nAborting.\n" "$msg_error" "$myconfig"; exit; }
    fi
  fi

  # Extract the host (IP address or domain plus port and protocol), and hence the URL base (no path)
  # Reference: https://developer.mozilla.org/en-US/docs/Web/API/Location
  host=$(printf "%s" "$url" | awk -F/ '{print $3}') # the hostname and port (if any)
  hostname=$(printf "%s" "$host" | awk -F: '{print $1}') # the hostname only

  # initialise list of all domains incorporated in the site
  extra_domains=
  all_domains="$hostname"
  if [ "$asset_domains" != "" ]; then
    all_domains+=",$asset_domains"
    extra_domains="$asset_domains"
  fi
  if [ "$page_element_domains" != "" ] && [ "$page_element_domains" != "auto" ]; then
    all_domains+=",$page_element_domains"
    if [ "$extra_domains" != "" ]; then
      extra_domains+=",$page_element_domains"
    else
      extra_domains="$page_element_domains"
    fi
  fi
  # strip out any whitespace from domain lists
  page_element_domains=$(printf "%s" "$page_element_domains" | tr -d '[:space:]')
  extra_domains=$(printf "%s" "$extra_domains" | tr -d '[:space:]')
  all_domains=$(printf "%s" "$all_domains" | tr -d '[:space:]')
  
  # assign URL-related variables
  protocol=$(printf "%s" "$url" | awk -F/ '{print $1}' | awk -F: '{print $1}')
  url_base="$protocol://$host"
  url_base_regex=$(regex_apply "$url_base")
  if [ "$url" != "$url_base/" ]; then
    url_has_path=yes
  else
    url_has_path=no
  fi

  if [ "$url_add_slash" = "avoid" ]; then
    if [[ $url_path != */* ]]; then
      url_path_dir=''                 # Set to empty directory if there is no slash
    else
      url_path_dir="${url_path%\/*}"  # Remove anything after last '/' for URLs not ending in '/'.
    fi
  else
    url_path_dir="$url_path"
  fi

  deploy_domain="$(config_get deploy_domain "$myconfig")"
  # Define URL to be used in robots.txt file
  if [ "$wayback_url" = "yes" ] && [ "$wayback_host_original_sitemap" = "yes" ]; then
    if [ "$mss_cut_dirs" = "no" ]; then
      url_original_root="$url_original"
      if [ "$url_add_slash" != "no" ]; then
        url_original_root="${url_original_root%\/*}/"  # Remove anything after last '/' for URLs not ending in '/'.
      fi
    else
      url_original_root="$url_original_base/"
    fi
    url_robots="$url_original_base/robots.txt"
    url_sitemap="$url_original_base/$sitemap_file"
  else
    url_robots="https://$deploy_domain/robots.txt"
    url_sitemap="https://$deploy_domain/$sitemap_file"
  fi
    
  [ "$require_login" = "yes" ] && {
    # Assign additional option variables for login sessions
    require_login_list=$(get_options_list "require_login")
# shellcheck disable=SC2034
    IFS=" " read -ra require_login_array <<< "$require_login_list" # convert string to array 
    assign_option_variables "require_login_array"
    login_address="$url_base$login_path";
  }

  # Options to support Wget
  [ "$use_wayback_cli" != "yes" ] && wget_extra_urls=$(yesno "$(config_get wget_extra_urls "$myconfig")")
  wget_input_files=()  # Initialise array of additional Wget input URLs
  input_long_filenames="$script_dir/$tmp_dir/$wget_long_filenames"  # List of URLs with very long filenames (to be generated)
  input_file_extra="$script_dir/$tmp_dir/$wget_inputs_extra"  # Input file for a single run of Wget extra assets (to be generated)
  input_file_extra_all="$script_dir/$tmp_dir/$wget_inputs_extra_all"  # Input file for Wget extra assets accumulated over multiple runs (to be generated)
  touchmod "$input_file_extra_all"
  if (( phase < 3 )); then
    echo > "$input_file_extra_all" # Initialise as an empty file
  fi
  wget_extra_options_tmp=$(wget_canonical_options "$(config_get wget_extra_options "$myconfig")")

  # If URL contains one or more directories, then ensure --no-parent option, subject to option settings
  if [ "$url_has_path" = "yes" ] && [[ ! $wget_extra_options_tmp =~ "-np" ]] && [[ ! $wget_extra_options_tmp =~ "--no-parent" ]]; then
    if [ "$wget_no_parent" = "auto" ] || [ "$wget_no_parent" = "yes" ]; then
      wget_extra_options_tmp+=" -np"
    fi
  fi

  # check for -nH option in wget_extra_options
  if [[ $wget_extra_options_tmp =~ "-nH" ]] || [[ $wget_extra_options_tmp =~ "--no-host-directories" ]]; then
    # remove the argument, but set host_dir_mode, so that it becomes effective later
    wget_extra_options_tmp=${wget_extra_options_tmp//-nH /}
    if [ "$host_dir_mode" = "yes" ]; then
      echolog "$msg_warning: Resetting constant, host_dir_mode=no, as you have specified '-nH' as an argument to Wget."
    fi
    host_dir_mode=no
    (( phase < 4 )) && echolog "$msg_info: Wget will be run with without '-nH' argument; host directory will be removed after post-processing."
  else
    host_dir_mode=yes
  fi
  host_dir="/$host"

  # Ensure that login pages are rejected by appending Wget --reject clause
  grep_clause="\-R[[:space:]][^[:space:]]*\|\-\-reject[[:space:]][^[:space:]]*"
  rmatch0=$({ printf "%s" "$wget_extra_options_tmp" | grep -o "$grep_clause"; } || echo )
  if [ "$rmatch0" = "" ]; then
    rmatch="$rmatch0"
    vmatch="$wget_extra_options_tmp"
  else
    rmatch=${rmatch0//\*/\\*}
    vmatch=$(printf "%s" "$wget_extra_options_tmp" | sed 's/'"$rmatch"'//')
  fi
  wget_plus_ops=$(printf "%s" "$vmatch" | xargs)
  if [[ ! "$rmatch0" =~ "-R " ]] && [[ ! "$rmatch0" =~ "--reject " ]]; then
    wget_plus_ops+=" -R $wget_reject_clause"
  else
    wget_plus_ops="$wget_plus_ops $rmatch0,$wget_reject_clause"
  fi
  IFS=" " read -ra wget_extra_options <<< "$wget_plus_ops"

  # Hide http basic authentication password
  IFS=" " read -ra wget_extra_options_print <<< "$(printf "%s" "$wget_plus_ops" | sed "s/password[[:space:]][^[:space:]]*/password *********/")"

  # If $wget_plus_ops contains '--spider' then don't deploy, use snippets or postprocess
  [[ "$wget_plus_ops" == *"--spider"* ]] && { use_snippets="no"; wget_extra_urls="no"; site_post_processing="no"; }

  # Retrieve any credentials from relevant credentials store and process
  if [ "$credentials_storage_mode" != "config" ]; then
    re_user='\-\-'"$wget_http_login_field"' ([^ \-]*)'
    if [[ $wget_extra_options_tmp =~ $re_user ]]; then
      wget_http_user="${BASH_REMATCH[1]}" # determined by last expression in conditional
      wget_process_credentials
    fi
  fi

  cut_dirs=0
  if [[ $wget_extra_options_tmp =~ "--cut-dirs" ]]; then
    cut_dirs=$(printf "%s" "$wget_extra_options_tmp" | grep -o "cut-dirs=[0-9]*" | cut -d '=' -f2)
  fi

  # Define a timestamp and then initialise (generate the name of) the mirror archive directory
  timestamp=$(timestamp "$timezone")
  initialise_mirror_archive_dir

  # WARC support
  wget_warc_options=()
  (( warc_count=0 ))
  if [ "$warc_output" = "yes" ]; then
    # Remove remove timestamping as a core option for Wget when fetching URLs
# shellcheck disable=SC2034
    wget_core_removals=("--timestamping" "-N")
    array_elements_delete wget_core_options wget_core_removals
    wget_core_options=("${array_reduced[@]}")

    if [ "$warc_cdx" = "yes" ]; then
      wget_warc_entry "option" "warc-cdx"
    fi
    if [ "$warc_compress" = "no" ]; then
      wget_warc_entry "option" "no-warc-compression"
    fi    
    if [ "$warc_header_format" = "mss" ]; then
      wget_warc_entry "header" "software: $wget_user_agent"
      wget_warc_entry "header" "operator: $USER"
      wget_warc_entry "header" "hostname: $HOSTNAME"
    elif [ "$warc_header_format" != "default" ]; then
      IFS="|" read -ra warc_header_list <<< "$warc_header_format"
      for warc_header in "${warc_header_list[@]}"; do
        wget_warc_entry "header" "$warc_header"
      done
    fi
    wget_warc_entry "file"
    if [ "$archive" = "no" ]; then
      archive=yes
      echo "$msg_warning: To support WARC, have changed the constant 'archive' to be 'yes'."
    fi
    wget_core_options+=("${wget_warc_options[@]}")
  fi

  # Apply MS Windows file name restrictions, if needed
  if [ "$offline_file_system" = "windows" ]; then
    wget_core_options+=(--restrict-file-names=windows)
    wget_extra_core_options+=(--restrict-file-names=windows)
  fi

  # For site captures with fixed directories, enable timestamping for efficient Wget mirroring
  if [ "$archive" = "no" ]; then
    wget_core_options+=(--timestamping)
  fi
  
  # For deployment on a remote server
  if [ "$deploy_remote" != "yes" ]; then
    deploy_host="on your local computer"
  else
    deploy_remote_rsync=$(yesno "$(config_get deploy_remote_rsync "$myconfig")")
    deploy_netlify=$(yesno "$(config_get deploy_netlify "$myconfig")")
    if [ "$deploy_remote_rsync" = "yes" ]; then
      # Assign additional option variables for deployment
      deploy_remote_rsync_list=$(get_options_list "deploy_remote_rsync")
# shellcheck disable=SC2034
      IFS=" " read -ra deploy_remote_rsync_array <<< "$deploy_remote_rsync_list" # convert string to array
      assign_option_variables "deploy_remote_rsync_array"
    fi
    if [ "$deploy_netlify" = "yes" ]; then
      deploy_netlify_name="$(config_get deploy_netlify_name "$myconfig")"
    fi
  fi
  deploy_path="$(config_get deploy_path "$myconfig")"
  [ "$wayback_url" != "yes" ] && echolog "Done."
  if [ "$cut_dirs" != "0" ]; then
    echolog "$msg_warning: You have specified Wget --cut-dirs option. Ignoring mss_cut_dirs."
  fi

  # Further variable initialisation for Wayback URLs
  if [ "$wayback_url" = "yes" ]; then
    wayback_url_paths
    # Check that the principal timestamp of the mirror matches the URL in the config file
    wayback_primary_snapshot_dir="$mirror_dir/$mirror_archive_dir$host_dir/$url_path_snapshot_prefix/$wayback_date_from"
    if (( phase == 3 )) && [ ! -d "$wayback_primary_snapshot_dir" ]; then
      echolog "$msg_error: The mirror does not have a timestamp that matches the 'from' date in the URL of the configuration (.cfg) file you have supplied. Suggest changing the -i or -m argument."
      confirm_continue "no" 
    fi
  fi

  # Script sign-off message
  msg_signoff="Ending run of MakeStaticSite."
}

prepare_static_generation() {
  echolog "Starting the static site generation ..."

  # Prepare WordPress site for static archive, if applicable
  if [ "$wp_cli" = "yes" ]  && [ "$use_wayback_cli" != "yes" ]; then
    wp_cli_remote=$(yesno "$(config_get wp_cli_remote "$myconfig")")
    wp_cli_remote_list=$(get_options_list "wp_cli_remote")
# shellcheck disable=SC2034
    IFS=" " read -ra wp_cli_remote_array <<< "$wp_cli_remote_list" # convert string to array
    assign_option_variables "wp_cli_remote_array"
# shellcheck source=lib/mod_wp.sh
    source "lib/$mod_wp";
    wp_prep
  fi

  return 0
}

wget_error_codes() {
  echolog "Done." "1"
  case "$1" in
    "8")
      echolog -n "$msg_warning: Wget ERROR code 8, i.e. the Web server gave an error on retrieving at least one file, probably HTTP 404 (file not found - possibly specified in the input file).  Less likely is a 500 (internal server error), which in the case of a CMS might be due to a plugin or module. ";
      local err8_msg="It should be safe to proceed, but you may like to rerun and/or review the output"
      if [ "$output_level" = "quiet" ]; then
        if [ "$log_level" != "silent" ] && [ "$log_level" != "quiet" ]; then
          err8_msg+=" by referring to the log file, which has more detail"
        else
          err8_msg+=" and try setting the output_level constant to 'normal' or 'verbose'"
        fi
      elif [ "$output_level" = "normal" ]; then
        err8_msg+=" and consider setting the output_level constant to 'verbose'"
      fi
      echolog "$err8_msg. "
      wget_error_check 8
      ;;
    "7")
      echolog "Wget $msg_error code 7 - wget reports a protocol error, which probably means that it can't connect to the host.  Check that the web server (httpd) is running and also the host spelling."
      wget_error_check 7
      ;;
    "6")
      echolog "Wget $msg_error code 6: Username/password authentication failure.  This can happen when fetching a login page or accessing an API.  Such errores can often be avoided by setting in wget_extra_options the -X option to exclude the relevant directory."
      wget_error_check 6
      ;;
    "5")
      echolog "Wget $msg_error code 5: SSL verification failure.  If you trust the certificate, then you should set the configuration option, ssl_checks=no (for the wget option --no-check-certificate)."
      wget_error_check 5
      ;;
    "4")
      echolog "Wget $msg_error code 4: Network failure.  It may be a network configuration or authentication issue.  Check in particular if there are any firewalls."
      wget_error_check 4
      ;;
    "3")
      echolog "Wget $msg_error code 3: File I/O error.  Check that you have write access to $working_mirror_dir.  More commonly, this error can occur when wget tries to write to a file where there already exists a directory with the same name."
      wget_error_check 3
      ;;
    "2")
      echolog "Wget $msg_error code 2: Parse error.  Check the command line options:"
      echolog "$wget_options"
      wget_error_check 2
      ;;
    "1")
      echolog "Wget $msg_error code 1: Generic error.  Check the command line options:"
      wget_error_check 1
      exit
      ;;
  esac
}


# Retrieve and process credentials
wget_process_credentials() {
  credentials_insert_path="${credentials_path_prefix}$hostname/$wget_http_login_field/$wget_http_user"
  credentials_path="$credentials_home/$credentials_insert_path"
  if [ "$credentials_storage_mode" = "encrypt" ]; then
    if [ -z ${pass_check+x} ]; then
      cmd_check "$credentials_manage_cmd" || { printf "\n%s: Unable to find binary: $credentials_manage_cmd ("'$'"PATH contains %s).\nThis command is essential for working with encrypted credentials.  It may be downloaded from %s.  Alternatively,  modify the value of credentials_storage_mode in constants.sh to 'plain', and re-run the setup, but with less security. \nAborting.\n" "$msg_error" "$PATH" "$credentials_manage_cmd_url"; exit; }
      pass_check=1
    fi
    if [ ! -f "$credentials_path.$credentials_extension" ]; then
      input_encrypted_password "HTTP authentication: a password for $wget_http_user is required to access the web server"
    fi
    wget_http_password=$(pass show "$credentials_insert_path" 2>/dev/null) || { echolog "$msg_error: Unable to retrieve the password from the credentials store at $credentials_insert_path. Aborting."; exit; }
  elif [ "$credentials_storage_mode" = "plain" ]; then
    if [ ! -f "$credentials_path" ]; then
      # Get user input for credentials (expected to be requested during setup; basically copy that code here)
      mkdir -p "$mss_dir_permissions" "$(dirname "$credentials_path")"
      touchmod "$credentials_path"

      # Read password and write to "$credentials_path"
      printf "\n"
      read -r -s -e -p "Please enter the password for $wget_http_user: " wget_http_password
      if [ "$wget_http_password" = "" ]; then
        echolog "$msg_warning: No password was set!"
      fi
      printf "%s" "$wget_http_password" > "$credentials_path"
      printf "\n"
    fi
    wget_http_password=$(<"$credentials_path")
  fi

  # Write credentials to run commands file
  rc_process=Y # initially assume we are going to write to a rc file
  rc_file="$HOME/$credentials_rc_file"
  if [ "$credentials_rc_file" = ".netrc" ]; then
    # Search for credentials based on $site_user and $hostname,
    # assuming they are defined on a single line with space-separated values
    if [ -f "$rc_file" ]; then
      # Check to see if an entry exists (with superfluous "''" inserted to pass Shellcheck SC1087)
      cred_pattern="machine[[:blank:]]\{1,\}$hostname"''"[[:blank:]]\{1,\}login[[:blank:]]\{1,\}$wget_http_user"
      search_rc="$(grep -m 1 "$cred_pattern" "$rc_file")"
      if [ "$search_rc" != "" ]; then
        confirm=y
        if [ "$run_unattended" != "yes" ]; then
          # ask if want to replace (y/n)?
          printf "\n"
          echolog "$msg_warning: HTTP authentication (username and password) credentials for user $wget_http_user have already been defined in $rc_file."
          read -r -e -p "Do you wish to overwrite (y/n)? " confirm
          confirm=${confirm:0:1}
        fi
        if [ "$confirm" = "y" ] || [ "$confirm" = "Y" ]; then
          # remove existing credentials
          replace_rc="$(grep -v "^[[:blank:]]\{0,\}$cred_pattern" "$rc_file")"
          printf "%s\n" "$replace_rc" > "$rc_file" || echolog "$msg_warning: unable to remove existing credentials"
        else
          ## leave credentials and don't do any further processing
          rc_process=N
        fi
      fi
    else
      touchmod "$rc_file"
    fi
    if [ "$rc_process" = "Y" ]; then
      printf "%s\n" "machine $hostname login $wget_http_user password $wget_http_password" >> "$rc_file"
      chmod 0600 "$rc_file"
    fi
  elif [ "$credentials_rc_file" = ".wgetrc" ]; then
    # Search for credentials based on $site_user, assuming that it and
    # the password are on separate lines
    if [ -f "$rc_file" ]; then
      # Check to see if an entry exists
      cred_pattern="http_user="
      cred_pattern_pwd="http_password="
      search_rc="$(grep -m 1 "^[[:blank:]]\{0,\}$cred_pattern" "$rc_file")"
      if [ "$search_rc" != "" ]; then
        confirm=y
        if [ "$run_unattended" != "yes" ]; then
          printf "\n"
          # ask if want to replace (y/n)?
          echolog "$msg_warning: a login has already been defined (as $search_rc).  Only one user/password pair may be defined."
          read -r -e -p "Do you wish to overwrite (y/n)? " confirm
          confirm=${confirm:0:1}
        fi
        if [ "$confirm" = "y" ] || [ "$confirm" = "Y" ]; then
          # remove existing credentials
          replace_rc="$(grep -v "^[[:blank:]]\{0,\}$cred_pattern\|^[[:blank:]]\{0,\}$cred_pattern_pwd" "$rc_file")"
          printf "%s\n" "$replace_rc" > "$rc_file" || echolog "$msg_warning: unable to remove existing credentials"
        else
          ## leave credentials and don't do any further processing
          rc_process=N
        fi
      fi
    else
      touchmod "$rc_file"
    fi
    if [ "$rc_process" = "Y" ]; then
      printf "http_user=%s\nhttp_password=%s\n" "$wget_http_user" "$wget_http_password " >> "$rc_file"
      chmod 0600 "$rc_file"
    fi
  else
    # No run commands file defined
    echolog "$msg_warning: no recognisable (.netrc or .wgetrc) run commands file specified, assuming none."
    echolog "This means that credentials will be included directly in Wget."
    confirm_continue
  fi
}


# Mirror a site using Wget (main site capture)
wget_mirror() {
  echolog "Will capture snapshot from $url using $wget_cmd."

  # Test whether source host is available
  wget_test_options=(-q "$wget_ssl")
  if [ "$wget_user_agent" != "" ] && [ "$wget_user_agent" != "wget" ]; then
    if [ "$require_login" != "yes" ] || [ "$wget_cookies_nullify_user_agent" = "no" ]; then
      wget_test_options+=(-U "$wget_user_agent")
    fi
  fi
  wget_test_options+=(--spider --tries 3 "$url_base")
  if ! $wget_cmd "${wget_extra_options[@]}" "${wget_test_options[@]}"; then
    msg_error="Unable to connect to $url_base.  Please check: the spelling of the domain, the web server status (is it running?) and access restrictions, particularly if any http authentication credentials are required. "
    msg_error+="Aborting."
    echolog "$msg_error"
    exit
  fi

  # Input file for Wget (generated)
  input_file="$script_dir/$tmp_dir/$wget_inputs_main"
  touchmod "$input_file"
  printf "%s\n" "$url" > "$input_file"

  # Generate the input-file option for Wget from the corresponding array.
  for opt in "${wget_input_files[@]}"; do
    printf "%s\n" "$opt" >> "$input_file"
  done

  # Append user URLs inputs
  input_urls_file_path="$script_dir/$tmp_dir/$input_urls_file"
  if [ "$input_urls_file" != "" ] && [ -f "$input_urls_file_path" ]; then
    cat "$input_urls_file_path" >> "$input_file"
    echolog "Reading list of additional URLs to crawl from $input_urls_file."
  fi

  # Wget configuration and its outputs
  input_options="--input-file=$input_file"

  # Overwrite an existing mirror only if the -m and wget_refresh_mirror flags are unset
  # and then only after run_unattended flag set or consent given
  if [ "$mirror_id_flag" = "off" ] && [ "$wget_refresh_mirror" = "yes" ]; then
    [ -d "$working_mirror_dir" ] && echolog "$msg_warning: $working_mirror_dir already exists.";
    confirm=Y
    if [ "$run_unattended" != "yes" ]; then
      read -r -e -p "Do you wish to delete and recreate $working_mirror_dir (y/n)? " confirm
      confirm=${confirm:0:1}
      printf "OK. "
    fi
    if [ "$confirm" = "y" ] || [ "$confirm" = "Y" ]; then
      rm -rf "$working_mirror_dir"
    fi
  fi

  msg_mirror_start="Creating a mirror of $url in $working_mirror_dir ... "
  wget_options=("$wget_ssl" --directory-prefix "$mirror_archive_dir" "$input_options")
  wget_cookies+="-${myconfig}_${timestamp_start}.txt"
  cookies_path="$tmp_dir_path/$wget_cookies"; touchmod "$cookies_path"
  cookies_tmppath="$tmp_dir_path/tmp$wget_cookies"; touchmod "$cookies_tmppath"
  wget_login_options=("$wget_ssl" --directory-prefix "$tmp_mirror_path" --save-cookies "$cookies_path" --keep-session-cookies)

  wget_robot_options=("$wget_ssl" --directory-prefix "$mirror_archive_dir$host_dir" "$url_robots")
  wget_sitemap_options=("$wget_ssl" --directory-prefix "$mirror_archive_dir$host_dir")

  if [ "$wvol" != "-q" ] || [ "$output_level" = "silent" ]; then
    wget_progress_indicator=()
  fi

  if [ "$wvol" = "-q" ] && [ "$log_level" != "silent" ]; then
    wget_options+=(-a "$log_file")
    wget_login_options+=(-a "$log_file")
    wget_robot_options+=(-a "$log_file")
    wget_sitemap_options+=(-a "$log_file")
  else
    wget_core_options+=("$wvol")
    wget_login_options+=("$wvol")
    wget_robot_options+=("$wvol")
    wget_sitemap_options+=("$wvol")
  fi

  if [ "$wget_user_agent" != "wget" ]; then
    if [ "$require_login" != "yes" ] || [ "$wget_cookies_nullify_user_agent" = "no" ]; then
      wget_extra_options+=(-U "$wget_user_agent")
      wget_extra_options_print+=(-U \""$wget_user_agent"\")
    fi
  fi

  # If access to site restricted then log in and fetch cookie as required
  if [ "$require_login" = "yes" ]; then
    wget_login_options+=("$login_address" --delete-after)
    site_user="$(config_get site_user "$myconfig" "$script_dir")"
    credentials_insert_path="${credentials_path_prefix}$hostname/site_user/$site_user"
    credentials_path="$credentials_home/$credentials_insert_path"
    if [ "$credentials_storage_mode" = "encrypt" ]; then
      if [ ! -f "$credentials_path.$credentials_extension" ]; then
        input_encrypted_password "The website login requires a password for $site_user"
      fi
      site_password=$(pass show "$credentials_insert_path" 2>/dev/null) || { echolog "$msg_error: $credentials_insert_path is not in the password store. Aborting."; exit; }
    elif [ "$credentials_storage_mode" = "plain" ]; then
      if [ ! -f "$credentials_path" ]; then
        # Get login password (usually entered during setup)
        mkdir -p "$mss_dir_permissions" "$(dirname "$credentials_path")"
        touchmod "$credentials_path"

        # Read password and write to "$credentials_path"
        read -r -s -e -p "Please enter the website login password for $site_user: " site_password
        if [ "$site_password" = "" ]; then
          echolog "$msg_warning: No password was set!"
        fi
        printf "%s" "$site_password" > "$credentials_path"
        printf "\n"
      fi
      site_password=$(<"$credentials_path")
    elif [ "$credentials_storage_mode" = "config" ]; then
      site_password="$(config_get site_password "$myconfig")"
    else
      printf "\n%s: A login is required, but unable to determine the username for Wget.\nAborting.\n" "$msg_error"; exit;
    fi

    # Generate a temporary file with credentials
    wget_post+="-${myconfig}_${timestamp_start}.txt"
    post_tmppath="$tmp_dir_path/$wget_post"; touchmod "$post_tmppath"

    printf "%s=%s&%s=%s&testcookie=1" "$login_user_field" "$site_user" "$login_pwd_field" "$site_password" > "$post_tmppath" || { printf "\n%s: Unable to prepare credentials for Wget.\nAborting.\n" "$msg_error"; exit; }

    # Now log in with supplied credentials
    wget_credentials=(--post-file="$post_tmppath")
    echolog "Logging in to the site at $login_address using credentials: ${login_user_field}=${site_user}&${login_pwd_field}=******* ${wget_login_options[*]} ... "
    $wget_cmd "${wget_credentials[@]}" "${wget_extra_options[@]}" "${wget_login_options[@]}"

    # Determine whether login has succeeded by checking cookies file for addition
    valid_cookie_session=${cookie_session_string//[,]/|}
    cookie_match=$(awk '$6 ~ /'"$valid_cookie_session"'/' "$cookies_path")
    if [ "$cookie_match" == "" ]; then
      printf "\n"
      printf "%s: Unable to identify a login/session cookie in the generated cookie file, %s. " "$msg_error" "$cookies_path"
      cookies_file_length=$(wc -l < "$cookies_path")
      if (( cookies_file_length < wget_cookies_min_filelength )); then
        empty_cookies_msg="DIAGNOSIS: Wget generated an empty cookies file. This may be due to problems with the value of wget_user_agent, defined in constants.sh. ";
        if [ "$wget_user_agent" != "" ]; then
          empty_cookies_msg+="You may try changing it to a more typical user agent string, as used by a desktop browser"
          if [ "$wget_cookies_nullify_user_agent" != "yes" ]; then
            empty_cookies_msg+=" OR to the empty string OR set wget_cookies_nullify_user_agent=yes."
          else
            empty_cookies_msg+="."
          fi
        else
          empty_cookies_msg+="You may try setting wget_user_agent to a typical user agent string, as used by a desktop browser."
        fi
        empty_cookies_msg+=$'\n'
        echolog "$empty_cookies_msg"
      elif [ "$cookie_session_string" = "" ]; then
        echolog "Please define the cookie_session_string in constants.sh."
      else
        echolog "note that it should be the same as the value of cookie_session_string (currently $cookie_session_string), as set in constants.sh."
      fi
      printf "Also check the username and password in %s.\n" "$myconfig.cfg"
      confirm_continue
    else
      echolog "OK."
      # Add cookie as option for main Wget run
      wget_extra_options+=(--load-cookies "$cookies_path")
      wget_extra_options_print+=(--load-cookies "$cookies_path")
    fi
  fi

  # Main run of Wget #
  printf "%s\n" "$msg_mirror_start"
  echolog "Running Wget with options:" "${wget_core_options[@]}" "${wget_extra_options_print[@]}" "${wget_options[@]}"

  # Remove previous zip upload
  zip_archive_old="$working_mirror_dir/$zip_download_folder/$zip_filename"
  if [ -f "$zip_archive_old" ]; then
    rm "$zip_archive_old" || echolog "$msg_warning: Unable to delete existing zip file at $zip_archive_old"
  fi

  error_set +e  # override because error traps set specially for Wget
  if [ "$robots_create" != "yes" ]; then
    # Check for robots.txt file (will store in mirror directory as they are part of the crawl)
    if ! $wget_cmd "${wget_extra_options[@]}" "${wget_robot_options[@]}"; then
      printf " \n%s: Wget reported an error trying to retrieve the robots.txt file (likely not found).  Search engines expect this, so have made a note to create it.\n" "$msg_warning"
      robots_create=yes
    elif sitemap_line=$(grep "^[[:space:]]*Sitemap:" "$mirror_archive_dir$host_dir/robots.txt"); then
      # Read contents of robots.txt, checking for sitemap
      sitemap=$(printf "%s\n" "$sitemap_line" | grep -o 'http[s]*:\/\/.*.xml')
      $wget_cmd "${wget_extra_options[@]}" "${wget_sitemap_options[@]}" "$sitemap"
      # Wget any nested sitemaps
      wget_sitemap_options+=("$sitemap" --output-document -)
      $wget_cmd "${wget_extra_options[@]}" "${wget_sitemap_options[@]}" | grep -o "http[s]*://[^<]*.xml" | $wget_cmd "${wget_extra_options[@]}" --quiet "$wget_ssl" --directory-prefix "$mirror_archive_dir$host_dir" -i -
    else
      printf " \n%s: No sitemap found in robots.txt. Search engines expect this, so have made a note to generate one.\n" "$msg_warning"
      sitemap_create=yes
    fi
  fi

  if [ "$warc_output" = "yes" ]; then
    echolog "$msg_warning: The progress bars may display oddly, as dots and spaces. This is a known technical issue when supplying Wget with both the -q (quiet) option and WARC options."
  fi
  $wget_cmd "${wget_core_options[@]}" "${wget_progress_indicator[@]}" "${wget_extra_options[@]}" "${wget_options[@]}"
  wget_error_codes "$?"
  error_set -e
}


# Capture a site
# The method used depends on the service;
# currently two kinds are supported:
# - Wayback Machine (Wayback Machine Downloader)
# - the rest (Wget)
mirror_site() {
  cd_check "$mirror_dir" 1 "Can't access working directory for the mirror ($mirror_dir)."

  if [ "$use_wayback_cli" = "yes" ]; then
    echolog "Retrieving archive for $hostname... "

    # Check for Wayback Machine Downloader binary, else report error (in the absence of an alternative)
    if cmd_check "$wayback_machine_downloader_cmd" "1"; then
      echolog "Running Wayback Machine Downloader on $url ... "
      if [ "$host_wayback_machine" != "web.archive.org" ]; then
        echolog "$msg_error: The Wayback Machine Downloader only supports web.archive.org.  You might be able to retrieve some files by setting wayback_cli=no in constants.sh (to treat like any other site) and then re-running, though file retrieval is currently limited to the specified Wayback Machine timestamp. Aborting."
        exit
      else
        wmd_args=("$url")
        if [ "$wayback_date_from" != "" ]; then
          wmd_args+=("$wayback_date_from")
          [ "$wayback_date_to" != "" ] && wmd_args+=("$wayback_date_to")
        fi
        wmd_get_wayback_site "${wmd_args[@]}"
      fi
    else
      echolog "$msg_error: Wayback Machine Downloader not found (wayback_machine_downloader_cmd is set to $wayback_machine_downloader_cmd) - please check that it is installed according to instructions at $wayback_machine_downloader_url. Aborting."
      exit
    fi
  else
    wget_mirror
    if [ "$wayback_url" = "yes" ]; then
      wayback_wget_postprocess
      cd_check "$mirror_dir" 1 "Can't access working directory for the mirror ($mirror_dir)."
    fi
  fi
}

generate_extra_domains() {
# Generate search URL prefixes combining host and extra domains
  if [ "$page_element_domains" = "auto" ]; then
    echo
    echolog -n "Searching for extra asset domains (working in $working_mirror_dir) ... "
    domain_grep="[\"'=]https?:\\\?/\\\?/[^\"'/< ]+\.[^\"'/< ]+\\\?/[^\"'< ]+[^\"'/< ]+\.[^\"'/< ]+"
    domain_grepv="[\"'=]https?:\\\?/\\\?/[^\"'/< ]+\.[^\"'/< ]+\\\?/[^\"'< ]+[^\"'/< ]+\.html?[^\"'/< ]*"
    domain_grep2="https?:\\\?/\\\?/[^\"'/< ]+\.[^\"'/< ]+\\\?/"
    domain_grep3="[^\"'/< ]+\.[^\"'/< ]+\\\?/"
    add_domains=()
    while IFS='' read -r line; do add_domains+=("$line"); done < <(grep -Eroh "$domain_grep" "$working_mirror_dir" "${asset_grep_includes[@]}" | grep -Ev "$domain_grepv" | grep -Eo "$domain_grep2" | grep -Eo "$domain_grep3" )

    echolog "add_domains array has ${#add_domains[@]} elements" "2"
    # Store unique elements only
    add_domains_unique=()
    while IFS='' read -r line; do add_domains_unique+=("$line"); done < <(for item in "${add_domains[@]}"; do printf "%s\n" "${item%/}"; done | sort -u)
    echolog "add_domains_unique array has ${#add_domains_unique[@]} elements" "2"
    # Convert array to domain list (string), removing any slashes
    page_element_domains=$(printf "%s" "${add_domains_unique[*]}" | sed 's/ /,/g' | sed 's/\\\?\/,/,/g' | sed "s/^$hostname,//g" | sed "s/,$hostname//g" | sed 's/\///g' | sed 's/\\//g')
    echolog "Done."
  fi
  if [ "$page_element_domains" != "" ]; then
    if [ "$extra_domains" != "" ]; then
      extra_domains+=","
    fi
    extra_domains+="$page_element_domains"
    all_domains+=",$extra_domains"
  fi

  IFS="," read -ra page_element_domains_array <<< "$page_element_domains"
}

# Optimise list of URL candidates by generating a temporary directory with
# minimal set of web pages yet to be processed for candidate URLs.
generate_file_candidates(){
  echolog "Generating list of file candidates... " "1"
  file_candidates=()
  while IFS= read -r -d '' opt
  do
    file_candidates+=( "$opt" )
  done <   <(for file_ext in "${asset_find_names[@]}"; do find "$working_mirror_dir" -type f -name "$file_ext" -print0; done)
  if (( wget_extra_urls_count != 1 )); then
# shellcheck disable=SC2207
    file_candidate_diffs=($(arraydiff file_candidates0[@] file_candidates[@]))
    if [[ ${#file_candidate_diffs[@]} -ne 0 ]]; then
      file_candidates0=( "${file_candidates0[@]}" "${file_candidate_diffs[@]}" )
      file_candidates=( "${file_candidate_diffs[@]}" )
    else
      file_candidates=()
    fi
  else
    file_candidates0=( "${file_candidates[@]}" )
  fi

  # Return if file candidates array is empty
  [ "${file_candidates[*]}" == "" ] && return 0

  # (re-)Generate a fresh, temporary empty directory with symbolic links to candidate files
  if [ ! -d "$tmp_working_dir" ]; then
    mkdir "$tmp_working_dir"
  fi
  for file in "${file_candidates[@]}"; do
    dest_dir="${file%\/*}"
    dest_dir=${dest_dir/"$working_mirror_dir"/"$working_mirror_dir"\/_tmpfiles}
    mkdir -p "$dest_dir"
    ln -s "$file" "$dest_dir/" || echolog "$msg_warning: Unable to create symbolic link from $file to $dest_dir/."
  done
}

# Augment Wget's snapshot by retrieving missed URLs
# (this needs to be done before site_postprocessing)
# We use Wget instead of cURL to avoid repeated overwrites -
# target files are not expected to change during this site generation
wget_extra_urls() {
  cd_check "$mirror_dir" 1

  if (( wget_extra_urls_count == 1 )); then

    if [ "$wget_protocol_relative_urls" = "yes" ]; then
      echolog "Prefixing protocol-relative URLs with $wget_protocol_prefix" "1"
      # Define BRE version of domain_bre0 
      domain_bre0=$(regex_apply "$domain_re0")
      sed_subs=('s|\([\"'\'']\)//\('"$domain_bre0"'\)|\1'"$wget_protocol_prefix"'://\2|g')
      for file_ext in "${asset_find_names[@]}"; do 
        find "$working_mirror_dir" -type f -name "$file_ext" "${asset_exclude_dirs[@]}" -print0 | xargs "${xargs_options[@]}" sed "${sed_options[@]}" "${sed_subs[@]}"
      done
      echolog " " "1"
    fi

    touchmod "$input_long_filenames"; echo > "$input_long_filenames"
    echolog "Searching for additional URLs to retrieve with Wget (working in $working_mirror_dir) ... " "1"
  
  fi

  # Refresh files for Wget (generated)
  touchmod "$input_file_extra"; echo > "$input_file_extra"

  # Generate search URL prefixes combining primary domain and extra domains
  generate_extra_domains

  echolog "Generating a list of extra asset URLs for Wget (run number $wget_extra_urls_count out of $wget_extra_urls_depth max) ... "
  if [ "$extra_assets_allow_query_strings" = "no" ]; then
    url_grep_search_pattern_qy=${url_grep_search_pattern//[^/[^\?}
    url_grep="$(assets_search_string "$all_domains" "${url_grep_search_pattern_qy}+")" # ERE notation
  else
    url_grep="$(assets_search_string "$all_domains" "${url_grep_search_pattern}+")" # ERE notation
  fi

  (( num_webasset_steps=9*10 )) # 9 phases with multiplier of 10 for granularity
  webasset_step_count=1
  count=0

  webassets_all=()
  url_grep_array=()
  IFS='|' read -ra url_grep_array <<< "$url_grep"
  url_grep_array_count=${#url_grep_array[@]}; (( url_grep_array_count=num_webasset_steps*url_grep_array_count ))
  if [ "$wayback_url" = "yes" ]; then
# shellcheck disable=SC1087
    url_grep_array+=( "$url_timeless_nodomain_ere[^\"'<) ]+" )
  fi

  if [ "$wget_url_candidates_optimisation" = "yes" ]; then
    generate_file_candidates

    # Return if empty (no further web sources to search)
    [ "${file_candidates[*]}" == "" ] && { echolog "No further candidate URLs found. " "1"; (( wget_extra_urls_count=wget_extra_urls_depth+1 )); print_progress; echolog "Done."; return 0; }
    
    grep_working_dir="$tmp_working_dir"
  else
    grep_working_dir="$working_mirror_dir"
  fi

  # In generating list of asset URLs, strip out initial characters 
  # such as a quote or '=' arising from url_grep match condition.
  # Also remove internal anchors at end of URL (with '#' appended)
  # Remove lines with primary domain if not relativising such assets URLs.
  for item in "${url_grep_array[@]}"; do
    while IFS='' read -r line; do
      line=${line//&#/123456789|} # retain entity references that begin '&#'
      trimmed_line="${line#"${line%%[![:space:],:\'\"=(]*}"}" # trim preceding quotes and other characters (any combination)
      trimmed_line="${trimmed_line%#*}"
      trimmed_line=${trimmed_line//123456789|/&#}
      webassets_all+=("$trimmed_line")
    done < <(
      if [ "$relativise_host_assets" = "no" ]; then
        grep -ERoha "$item" "$grep_working_dir" "${asset_grep_includes[@]}" | grep -v "//$hostname"
      else
        grep -ERoha "$item" "$grep_working_dir" "${asset_grep_includes[@]}"
      fi)
    print_progress "$count" "$url_grep_array_count"
    (( count++ ))
  done
  [ "$wget_url_candidates_optimisation" = "yes" ] && [ -d "$tmp_working_dir" ] && rm -rf "$tmp_working_dir"

  webassets_max_length=$(printf "%s\n" "${webassets_all[@]}" | wc -L)
  if (( webassets_max_length > url_max_chars )); then
    echolog "$msg_warning: generation of candidate URLs produced at least one line with $webassets_max_length characters exceeding url_max_chars ($url_max_chars)." "1"
# shellcheck disable=SC2207
    webassets_all=($(printf "%s\n" "${webassets_all[@]}" | sed '/.\{'"$url_max_chars"'\}/d'))
  fi

  # Call routines specific to Wayback Machine to augment list of candidate URLs
  if [ "$wayback_url" = "yes" ]; then
    wayback_augment_urls
  fi

  webassets_all_count=${#webassets_all[@]}
  echolog "webassets_all array has $webassets_all_count elements" "1"

  # Return if empty (nothing further found)
  [ ${#webassets_all[@]} -eq 0 ] && { echolog "None found. " "1"; (( wget_extra_urls_count=wget_extra_urls_depth+1 )); print_progress; echolog "Done."; return 0; }
  [ "$output_level" != "quiet" ] && echolog " "

  # Pick out unique items
  echolog "Pick out unique items" "1"
  webassets_unique=()
  (( webasset_step_count++ ))
  print_progress "$webasset_step_count" "$num_webasset_steps"
  while IFS='' read -r line; do webassets_unique+=("$line"); done < <(for item in "${webassets_all[@]}"; do printf "%s\n" "${item}"; done | sort -u)
  echolog "webassets_unique array has ${#webassets_unique[@]} elements" "2"
  (( webasset_step_count++ ))
  print_progress "$webasset_step_count" "$num_webasset_steps"
  if [ "$wayback_url" = "yes" ]; then
    webassets_unique2=();
    # prepend /web Memento absolute paths with Wayback host
    while IFS='' read -r line; do
      if [[ $line =~ ^$url_timeless_nodomain_ere ]]; then
        line="$url_base$line"
      fi    
    webassets_unique2+=("$line");
    done < <(for item in "${webassets_unique[@]}"; do printf "%s\n" "$item"; done)
  else
    webassets_unique2=("${webassets_unique[@]}")
  fi

  # Filter out all invalid URLs 
  echolog "Filter out invalid URLs" "1"
  webassets_http=()
  while IFS='' read -r line; do webassets_http+=("$line"); done < <(for item in "${webassets_unique2[@]}"; do if [[ $item =~ ^$url_re$ ]]; then printf "%s\n" "${item}"; else continue; fi; done)
  [ ${#webassets_http[@]} -eq 0 ] && { echolog "None found. " "1"; (( wget_extra_urls_count=wget_extra_urls_depth+1 )); print_progress; echolog "Done."; return 0; }
  num_webassets_http="${#webassets_http[@]}"
  echolog "webassets_http array has $num_webassets_http elements" "2"
  (( webasset_step_count++ ))
  print_progress "$webasset_step_count" "$num_webasset_steps"

  # Define assets clauses for greps
  assets_or='\.('${asset_extensions//,/|}')'
  assets_or_external='\.('${asset_extensions_external//,/|}')'

  # For Wayback URLs, carry out special filtering
  if [ "$wayback_url" = "yes" ]; then
    echolog "Carry out Wayback-specific filtering." "1"
    src_path_snapshot="$working_mirror_dir/$url_path_snapshot_prefix"
    wayback_filter_domains
  fi

  # Filter out web pages and newsfeeds; limit to non-HTML assets, such as images and JS files
  # (this filter is the most process-intensive, so progress bar has more steps than others)
  echolog "Filter out web pages and newsfeeds (limit to non-HTML assets, such as images and JS files)" "1"
  webassets_filter_html=()
  (( num_webasset_steps_nohtml=num_webasset_steps-5 ))
  (( count=0 ))
  while IFS='' read -r line; do
    count=$(printf "%s" "$line" | awk -F'|' '{print $1}')
    assetline=$(printf "%s" "$line" | awk -F'|' '{print $2}')
    if [ "${assetline:0:4}" = "http" ]; then
      webassets_filter_html+=("$assetline");
    fi
    (( subcount=webasset_step_count+(num_webasset_steps_nohtml*count/num_webassets_http) ))
    print_progress "$subcount" "$num_webasset_steps"
  done < <(for i in "${!webassets_http[@]}"; do
    opt="${webassets_http[$i]}"
    if [ "$wayback_url" = "yes" ]; then
      # Wayback URLs have already been filtered for asset extensions, etc., we assume all such URLs are valid candidates for mirroring.
      printf "%s|%s\n" "$i" "$opt";    
    elif [ "$asset_extensions" != "" ]; then
      # Loop over an inclusion list of allowable extensions, accommodating query strings
      opt_domain=$(printf "%s\n" "$opt" | awk -F/ '{print $3}' | awk -F: '{print $1}')
      if [[ ' '${page_element_domains_array[*]}' ' =~ ' '$opt_domain' ' ]]; then # satisfied vacuously for all Wayback URLs
# Dev note: probably should also support percent-encoded '?', i.e., %3F  ...
        echo "$opt" | grep -Ei "$assets_or_external\??[^\"'[:space:]]*$" > /dev/null && printf "%s|%s\n" "$i" "$opt"
      else
        echo "$opt" | grep -Ei "$assets_or\??[^\"'[:space:]]*$" > /dev/null && printf "%s|%s\n" "$i" "$opt";
      fi
    else
      # When no allowable extensions specified, remove HTML assets according to content type.
      type=$(curl -skI "$opt" -o/dev/null -w '%{content_type}\n')
      if [[ "$type" != *"text/html"* ]] && [[ "$type" != *"application/rss+xml"* ]] && [[ "$type" != *"application/atom+xml"* ]]; then
        printf "%s|%s\n" "$i" "$opt"
      fi
    fi
  done)
  (( webasset_step_count=subcount+1 ))

  [ ${#webassets_filter_html[@]} -eq 0 ] && { echolog "None found. " "1"; (( wget_extra_urls_count=wget_extra_urls_depth+1 )); print_progress; echolog "Done."; return 0; }
  echolog "webassets_filter_html array has ${#webassets_filter_html[@]} elements" "2"
  (( webasset_step_count++ ))
  print_progress "$webasset_step_count" "$num_webasset_steps"
  if [ ${#wget_extra_options[@]} -ne 0 ]; then
    url_bas="$protocol://$host"
    # Filter out URLs whose paths match an excluded directory (via subloop)
    echolog "Filter out URLs whose paths match an excluded directory (via subloop)" "1"
    # We assume that grep works as expected, but should really trap exit code 2
    exclude_dirs=$(printf "%s\n" "$wget_plus_ops"| grep -o "\-X[[:space:]]*[[:alnum:]/,\-]*" | grep -o "/.*"; exit 0)
    temp_IFS="$IFS"; IFS=","; read -ra exclude_arr <<< "$exclude_dirs"; IFS="$temp_IFS"
    if [ ${#exclude_arr[@]} -eq 0 ]; then
      webassets_omissions=("${webassets_filter_html[@]}")
    else
      webassets_omissions=()
      while IFS='' read -r line; do webassets_omissions+=("$line"); done < <(for opt in "${webassets_filter_html[@]}"; do path="${opt/$url_bas/}"; for exclusion in "${exclude_arr[@]}"; do [ "$path" = "$exclusion" ] || [[ $path =~ ^$exclusion/.* ]] && continue 2; done; printf "%s\n" "$opt"; done)
    fi
  else
    webassets_omissions=("${webassets_filter_html[@]}")
  fi
  num_webassets_omissions="${#webassets_omissions[@]}"
  echolog "webassets_omissions array has $num_webassets_omissions elements" "2"
  (( webasset_step_count++ ))
  print_progress "$webasset_step_count" "$num_webasset_steps"

  # Return if empty (nothing further found)
  [ "$num_webassets_omissions" -eq 0 ] && { echolog "None found. " "1"; (( wget_extra_urls_count=wget_extra_urls_depth+1 )); print_progress; echolog "Done."; return 0; }

  if (( extra_assets_query_strings_limit < num_webassets_omissions )); then
    # Filter out URLs with query strings
    echolog "$msg_warning: too many asset URLs found, so filtering out those with query strings. If you need them, consider increasing the value of extra_assets_query_strings_limit from its current value, $extra_assets_query_strings_limit."
    webassets=()
    while IFS='' read -r line; do webassets+=("$line"); done < <(for opt in "${webassets_omissions[@]}"; do if [[ "$opt" != *"?"* ]]; then printf "%s\n" "$opt"; else continue; fi; done)
  else
    webassets=("${webassets_omissions[@]}")
  fi
  (( webasset_step_count++ ))
  print_progress "$webasset_step_count" "$num_webasset_steps"

  echolog "webassets array has ${#webassets[@]} elements" "2"
  # Return if empty (all those found were filtered out)
  [ ${#webassets[@]} -eq 0 ] && { echolog "None suitable found. " "1"; (( wget_extra_urls_count=wget_extra_urls_depth+1 )); print_progress; echolog "Done."; return 0; }

  if [ "$wayback_url" = "yes" ]; then
    wayback_filter_snapshots
  fi

  # URL decode for Wget calls: revert &amp; to & 
  webassets_filtered=("${webassets[@]//&amp;/&}")

  if [[ ${webassets_filtered[*]} =~ '&#' ]]; then
    echolog "Converting ISO 8859-1 character entities to percent encoding." "1" # Entities cannot be used in Wget input file because of hash '#'
    for ((i=32;i<126;i++)); do
      j=$(printf '%x\n' "$i")
      webassets_filtered=("${webassets_filtered[@]//&#"$i";/%"$j"}")
    done
  fi

  if [ "$wayback_url" = "yes" ] && [ "$wayback_timestamp_policy" = "range" ]; then
    echolog "Applying to/from timestamp restrictions to Wayback URLs." "1"
    webassets_date_filtered=()
    for line in "${webassets_filtered[@]}"; do
      wayback_date_check=$(printf "%s" "$line" | grep -o "/$wayback_datetime_regex/" | grep -o "[0-9]\+")
      if (( wayback_date_check >= wayback_date_from_earliest )) && (( wayback_date_check <= wayback_date_to_latest )); then
        webassets_date_filtered+=("$line")
      fi
    done
    webassets_filtered=("${webassets_date_filtered[@]}")
  fi

  [ "${#webassets_filtered[@]}" -eq 0 ] && { echolog "None found (webassets_filtered). " "1"; (( wget_extra_urls_count=wget_extra_urls_depth+1 )); print_progress; echolog "Done."; return 0; }

  # Remove URLs from list that already have a corresponding file download
  webassets_no_file_duplicates=()
  for line in "${webassets_filtered[@]}"; do
    filepath=$(echo "$line"|sed 's~^http[s]\?://~~'|sed 's~\(http[s]\?:/\)/~\1~');
    if [ ! -f "$mirror_archive_dir/$filepath" ]; then
      # asset not already downloaded, so retain it in list
      webassets_no_file_duplicates+=("$line")
    fi
  done
  [ "${#webassets_no_file_duplicates[@]}" -eq 0 ] && { echolog "None found (webassets_no_file_duplicates). " "1"; (( wget_extra_urls_count=wget_extra_urls_depth+1 )); print_progress; echolog "Done."; return 0; }
  printf "%s\n" "${webassets_no_file_duplicates[@]}" > "$input_file_extra"

  if (( wget_extra_urls_count == 1 )); then
    if [ "$wayback_url" = "yes" ] && [ ${#wget_extra_core_options[@]} -ne 0 ]; then
      wget_extra_core_options+=("${wget_wayback_core_options[@]}")
    fi
    cp_check "$input_file_extra" "$input_file_extra_all" "unable to make a copy of the Wget input file, $input_file_extra, to $input_file_extra_all."
  else
    # generate a diff and store result as $input_file_extra
    diff "$input_file_extra_all" "$input_file_extra" | grep "> " | grep -o "http[^[:space:]]*" > "${input_file_extra}.tmp"
    if [ -s "${input_file_extra}.tmp" ]; then
      # update input file
      mv "${input_file_extra}.tmp" "$input_file_extra"
      # augment the running list of extra URLs
      cat "$input_file_extra" >> "$input_file_extra_all"
    else
      # file empty - nothing further to process
      (( wget_extra_urls_count = wget_extra_urls_depth+1 )); print_progress; echolog "No further URLs found.  Done."; return 0; 
    fi
  fi
  (( webasset_step_count++ ))
  print_progress "$webasset_step_count" "$num_webasset_steps"
  wget_asset_options=("$wget_ssl" --directory-prefix "$mirror_archive_dir")
  
  if [ "$wvol" != "-q" ] || [ "$output_level" = "silent" ]; then
    wget_progress_indicator=()
  fi

  if [ "$wvol" = "-q" ] && [ "$log_level" != "silent" ]; then
    wget_asset_options+=(-a "$log_file")
  else
    wget_extra_core_options+=("$wvol")
  fi

  echolog "Checking URLs for very long filenames ... " "1"
  # Read the file line by line and store it in the array
  while IFS= read -r line; do
    # check Wget report for occurrence of string: The destination name is too long (M), reducing to N
    output_file=$(basename "$line")
    if [ ${#output_file} -gt "$long_filename_threshold" ]; then
      wget_longfilename_options=("$wget_ssl" --spider "$line")
      report_dest_name_length=$($wget_cmd "${wget_extra_options[@]}" "${wget_longfilename_options[@]}" 2>&1 | grep -m 1 "destination name is too long")
      if [ "$report_dest_name_length" != "" ]; then
        shortername_length=$(printf "%s" "$report_dest_name_length" | grep -o "reducing to [0-9]*" | grep -o "[0-9]*")
        full_filename=$(basename "$line")
        # truncate string accordingly
        shorter_name=${full_filename:0:shortername_length}
        shorter_name2=${full_filename: -shortername_length}  # this alternative includes the correct extension 
        printf '%s\t%s\t%s\n' "$line" "$shorter_name" "$shorter_name2" >> "$input_long_filenames"
      fi
    fi
  done < "$input_file_extra"
  (( webasset_step_count++ ))
  print_progress
  echolog "Done." "1"

  # Insert WARC options, where applicable
  if [ "$warc_output" = "yes" ]; then
    if (( warc_count < 10 )); then
      warc_prefix="warc0$warc_count"
    else
      warc_prefix="warc$warc_count"
    fi
    wget_warc_options=("${wget_warc_options[@]/--warc-file="warc"*$mirror_archive_dir/--warc-file="$warc_prefix-$mirror_archive_dir"}")
    (( warc_count++ ))
    wget_extra_core_options+=("${wget_warc_options[@]}")
    # Remove --no-clobber from Wget options when fetching extra URLs
# shellcheck disable=SC2034
    wget_extra_core_removals=("--no-clobber" "-nc")
    array_elements_delete wget_extra_core_options wget_extra_core_removals
    wget_extra_core_options=("${array_reduced[@]}")
  fi

  echolog "Running Wget on these additional URLs with options:" "${wget_extra_core_options[@]}" "${wget_extra_options[@]}" "${wget_asset_options[@]}"
  if [ "$warc_output" = "yes" ] && (( phase >2 )); then
    echolog "$msg_warning: The progress bars may display oddly. This is a known technical issue with Wget when WARC and other options are supplied together."
  fi 
  error_set +e
  if (( wget_threads > 1 )); then
    xargs -a "$input_file_extra" -n 1 -P $wget_threads $wget_cmd "${wget_extra_core_options[@]}" "${wget_progress_indicator[@]}" "${wget_extra_options[@]}" "${wget_asset_options[@]}"
  else
    wget_asset_options+=(--input-file="$input_file_extra")
    $wget_cmd "${wget_extra_core_options[@]}" "${wget_progress_indicator[@]}" "${wget_extra_options[@]}" "${wget_asset_options[@]}"
  fi
  wget_error_codes "$?"
  error_set -e
  ((wget_extra_urls_count++))
  if [ "$wayback_url" = "yes" ]; then
    wayback_wget_postprocess
  fi

}

# Post Wget mirror site review: checks
# (and placeholder for analysis)
mirror_checks() {
  echolog -n "Carrying out checks on mirror ... "

  if [ "$offline_file_system" != "unix" ]; then
    # Run file system checks
    (( match_count = 0 ))
    for (( i=0;i<${#windows_filename_illegal_chars}; i++ )); do
      file_matches=()
      char="${windows_filename_illegal_chars:$i:1}"
      char2=$(glob_escape "$char")
      # search for files with that character
      while IFS='' read -r line; do file_matches+=("$line"); done < <(find "$working_mirror_dir" -type f -name "*$char2*" -print)
      if [ "${#file_matches[@]}" != "0" ]; then
        if (( match_count == 0 )); then
          echolog $'\n'"$msg_warning: You have set the constant offline_file_system to $offline_file_system. Whereas all the files should be fine here, for distribution, note that the file names include one or more characters that are illegal in Microsoft Windows file systems. You can prevent this by setting offline_file_system=windows or else manually set Wget with the option --restrict-file-names=windows. Then rerun."
        fi
        match_pluralise=
        num_matches="${#file_matches[@]}"
        (( num_matches > 1 )) && match_pluralise='s'
        echolog "Found ${#file_matches[@]} file$match_pluralise containing illegal character '$char'." "1"
        for match in "${file_matches[@]}"; do
          (( match_count++ ))
          echolog "$match" "1"
        done
      fi
    done
    if (( match_count > 0 )); then
      match_pluralise=
      (( match_count > 1 )) && match_pluralise='s'
      echolog "There were a total of $match_count file$match_pluralise with illegal characters."
      if [ "$output_level" != "normal" ] && [ "$output_level" != "verbose" ]; then
        echo "(See log file for details.)"
      fi
    fi
  fi
  echolog "Done."
}

augment_mirror() {
  if [ "$wget_extra_urls" = "yes" ]; then
    [ "$wget_url_candidates_optimisation" = "yes" ] && file_candidates0=()
    while (( wget_extra_urls_count <= wget_extra_urls_depth )); do
      wget_extra_urls;
    done
  fi

  mirror_checks
  
  if [ "$warc_output" = "yes" ]; then
    # Concatenate WARC files
    warc_location="$mirror_dir/warc-$mirror_archive_dir.warc.gz"
    cat "$mirror_dir/warc"*"-$mirror_archive_dir.warc.gz" > "$warc_location"
    msg_warc="A WARC web archive has also been generated, saved at $warc_location. "    
  fi
}

process_assets() {
  echolog "Processing asset storage locations ... "

  # Generate a list of all the web pages that contain relevant URLs to process
  # (makes subsequent sed replacements more targeted than searching all web pages).
  extra_domains_array=()
  while IFS= read -r line; do
    if [ "$line" != "$hostname" ]; then
      extra_domains+="$line,"
      extra_domains_array+=("$line");
    fi
  done <<<"$(find "$mirror_dir/$mirror_archive_dir/" -maxdepth 1 -type d -name "*.*" -exec basename {} \; )"
# shellcheck disable=SC2001
  extra_domains=$(printf "%s" "$extra_domains" | sed 's/.$//') # remove final character
  if (( phase > 3 )); then
    # Ensure variables are assigned when starting run at postprocessing phase
    # - that $all_domains includes the extra domains
    # - that $url_grep is built correspondingly
    if [ "$url_wildcard_capture" != "yes" ]; then
      generate_extra_domains
      if [ "$extra_assets_allow_query_strings" = "no" ]; then
        url_grep="$(assets_search_string "$all_domains" "[^\?\"'<) ]+")"
      else
        url_grep="$(assets_search_string "$all_domains" "[^\"'<) ]+")"
      fi
    else
      if [ "$extra_assets_allow_query_strings" = "no" ]; then
        url_grep="$(assets_search_string "$domain_re0" "[^\?\"'<) ]+")"
      else
        url_grep="$(assets_search_string "$domain_re0" "[^\"'<) ]+")"
      fi
    fi
  fi

  [ -z ${url_grep+x} ] && url_grep="$(assets_search_string "$all_domains" "[^\"'<) ]+")" # define $url_grep as necessary

  # Find pages where there are relevant assets (relative paths)
  webpages0=() # to stores paths, duplication likely
  url_grep_array=()
  IFS='|' read -ra url_grep_array <<< "$url_grep"
  num_url_grep_array="${#url_grep_array[@]}";
  count=1
  echolog "Generating list of pages with relevant assets ... "
  for item in "${url_grep_array[@]}"; do
    print_progress "$count" "$num_url_grep_array"; (( count++ ))
    while IFS='' read -r line; do
    webpages0+=("$line"); done < <(grep -Erl "$item" . "${asset_grep_includes[@]}")
  done
  # Filter out duplicates
  webpages=() # to store unique paths
  while IFS='' read -r line; do webpages+=("$line"); done < <(for item in "${webpages0[@]}"; do printf "%s\n" "${item}"; done | sort -u; )
  printf "\n"

  num_webpages=${#webpages[@]}
  # Split long lines to reduce processing time
  if [ "$shorten_longlines" != "off" ] && (( num_webpages != 0 )); then
    echolog "Splitting long lines in files to speed up processing ... "
    (( count=0 ))
    for item in "${webpages[@]}"; do
      print_progress "$count" "$num_webpages"
      if [ "$shorten_longlines" = "auto" ]; then
        item_chars=$(wc -m "$item" | awk '{print $1}')
        item_newlines=$(wc -l "$item" | awk '{print $1}')
        item_longest_line=$(longest_line "$item")
        if { (( item_newlines == 0 )) || [ "$item_newlines" = "" ]; }; then
         (( count++ )); continue
        fi
        if (( item_chars/item_newlines <= average_linelength_max )) && (( item_longest_line <= longest_linelength_max )); then { (( count++ )); continue; }
        else
          echolog "Shortening lines in $item" "1"
        fi
      fi
      file_contents=$(<"$item")
      for item_replace in "${newline_inserts[@]}"; do
        file_contents_cmd=(file_contents=\"\$'{'file_contents//"$item_replace"'}'\")
        eval "${file_contents_cmd[0]}"  # Security note (eval): the input source for $item_replace is $newline_inserts, which is defined in constants.sh; it is safe.
      done
      printf "%s\n" "$file_contents" > "$item"
      (( count++ ))
    done
    print_progress
  fi

  echolog "Converting paths to become relative to imports and assets directories ... " 

  # Prepare adjustment for relative paths with assets directory
  if [ "$assets_directory" != "" ] && [ "$cut_dirs" = "0" ]; then
    assets_dir_suffix=/
    # Also, check for duplication of assets directory label
    if [ "$(find . -name "$assets_directory" -type d -print)" != "" ]; then
      echolog -n "$msg_warning: website already contains a directory, $assets_directory.  To avoid confusion (and errors), a timestamp is being appended to the MakeStaticSite-generated assets directory, but it is recommended that you modify the assets_directory constant and re-run. ... "
      assets_directory="$assets_directory$timestamp"
    fi
  else
    assets_dir_suffix=
  fi

  # Similarly, prepare adjustment for relative paths with imports directory
  if [ "$imports_directory" != "" ]; then
    imports_dir_suffix=/
    # Also check for duplication of assets directory label
    if [ "$(find . -name "$imports_directory" -type d -print)" != "" ]; then
      echolog -n "$msg_warning: website already contains a directory, $imports_directory.  To avoid confusion (and errors), a timestamp is being appended to the MakeStaticSite-generated imports directory, but it is recommended that you modify the imports_directory constant and re-run. ... "
      imports_directory="$imports_directory$timestamp"
    fi
  else
    imports_dir_suffix=
  fi

  # General case: conversion of absolute links to relative links
  if [ ${#webpages[@]} -eq 0 ]; then
    echolog "No web pages to process.  Done." "1"
  elif [ ! -s "$input_file_extra_all" ] && [ "$url_wildcard_capture" != "yes" ]; then
    echolog "No URLs to apply in search and replace.  Done." "1"
  elif [ "$cut_dirs" = "0" ]; then
    # Initialise URLs array
    urls_array=()
    if [ "$url_wildcard_capture" = "yes" ]; then
      # create URLs array via directory names (domain names) from file system
      for item in "${extra_domains_array[@]}"; do
        # Append a regex to match file paths
        item=$(regex_escape "$item" "BRE")
        urls_array+=("https\?://$item/\([^\\\"\'<) ]\+\)")
        urls_array2+=("//$item/\([^\\\"\'<) ]\+\)")
      done
    else
      # Produce a copy of input_file_extra_all ready for sed to process with basic regular expressions
      input_string_extra=$(<"$input_file_extra_all") || echolog "$msg_error: no file $input_file_extra_all found!  No further absolute links will be converted to relative links."
      input_string_extra_all=$(regex_escape "$input_string_extra" "BRE")
      input_file_extra_all_BRE="${input_file_extra_all}.BRE"
      printf "%s\n" "$input_string_extra_all" > "$input_file_extra_all_BRE"

      # Populate URLs array from Wget's additional input file
      if [ -f "$input_file_extra_all" ]; then
        domain_BRE=$(regex_escape "$hostname" "BRE")
        domain_BRE=${domain_BRE//\\/\\\\\\} # need to escape \, so replace \ with \\\ .
        if [ "$url_has_path" = "no" ] || [ "$relativise_host_assets" = "no" ]; then
          while IFS= read -r line; do line=${line//&/&amp;}; urls_array+=("$line"); done < <(grep -v "//$domain_BRE" "$input_file_extra_all_BRE")
        else
          while IFS= read -r line; do
            line=${line//&/&amp;}
            [ "$line" != "" ] && urls_array+=("$line")
          done < "$input_file_extra_all_BRE"
        fi
      fi
    fi

    # Derive another URLs array with scheme relative URLs
    urls_array_2=()
    for i in "${urls_array[@]}"; do urls_array_2+=("${i/http*:/}"); done

    # Convert absolute links to relative links
    count=0
    print_progress "$count" "$num_webpages"
    for opt in "${webpages[@]}"; do

      # but don't process XML files in guise of HTML files
      if grep -q "<?xml version" "$opt"; then
        continue
      fi

      # Generate a path prefix to traverse higher directories in relative paths
      pathpref=
      depth=${opt//[!\/]};
      depth_num=${#depth}
      if [ "$url_has_path" = "yes" ]; then
        (( depth_num=depth_num-url_path_depth ))
        dir_pathpref=
        for ((i=1;i<depth_num;i++)); do
          dir_pathpref+="../";
        done
      fi
      for ((i=1;i<depth_num;i++)); do
        pathpref+="../";
      done

      # Carry out universal search and replace on primary domain;
      # Case: no URL path
      if [ "$url_has_path" = "no" ] || { [ "$external_dir_links" != "" ] && [ "$external_dir_links" != "off" ]; }; then
        sed_subs1=('s|\([a-zA-Z0_9][[:space:]]*=[[:space:]]*["'"']"'\?\)https\?://'"$host/"'|'"\1$pathpref"'|g' "$opt") # trims strictly
        sed "${sed_options[@]}" "${sed_subs1[@]}"
        if (( url_asset_capture_level > 2 )); then
          sed_subs2=('s|\([[:space:]]*'"$url_separator_chars"'[[:space:]]*["'"']"'\?\)https\?://'"$host/"'|'"\1$pathpref"'|g' "$opt") # trims loosely
          sed "${sed_options[@]}" "${sed_subs2[@]}"
        fi
      # Case: URL path
      #  with --no-parent, we need to limit matches to be within the tree
      elif [ "$url_has_path" = "yes" ]; then
       sed_subs1=('s|\([a-zA-Z0_9][[:space:]]*=[[:space:]]*["'"']"'\?\)https\?://'"$host/$url_path_dir/"'|'"\1$dir_pathpref"'|g' "$opt") # trims strictly
        sed "${sed_options[@]}" "${sed_subs1[@]}"
        if (( url_asset_capture_level > 2 )); then
          sed_subs2=('s|\([[:space:]]*'"$url_separator_chars"'[[:space:]]*["'"']"'\?\)https\?://'"$host/$url_path_dir/"'|'"\1$dir_pathpref"'|g' "$opt") # trims loosely
          sed "${sed_options[@]}" "${sed_subs2[@]}"
        fi
      fi

      # Loop over all assets if working with extra domains or a directory URL.
      # (Note this will generate erroneous paths for primary domain assets, fixed later on.)
      if [ ${#urls_array[@]} -ne 0 ] && { [ "$extra_domains" != "" ] || [ "$url_has_path" = "yes" ]; }; then
        urls_type=(urls_array urls_array_2) # standard and scheme relative URLs respectively (for use below with indirect references)
        for url_type in "${urls_type[@]}"; do
          url_nameref="$url_type"
          url_type_array="${url_nameref}[@]"
          for url_extra in "${!url_type_array}"; do
            asset_rel_path=$(printf "%s" "${url_extra#*//}")
            if [ "$url_wildcard_capture" = "yes" ]; then
              asset_rel_path=$(printf "%s" "${asset_rel_path%%/*}")
              asset_rel_path="$pathpref$imports_directory$imports_dir_suffix$asset_rel_path"
              asset_rel_path=$(url_percent_encode "$asset_rel_path")
              asset_rel_path=$(regex_escape "$asset_rel_path\/" "BRE")
              if [ "$path_doubleslash_workaround" = "yes" ]; then
                # Replace double slashes in paths with single slashes
                asset_rel_path=${asset_rel_path//\/\//\/}
              fi
              asset_rel_path=$(sed_rhs_escape "$asset_rel_path")
              # url_extra itself contains a bracketed regular expression - hence backreference \2 below
              sed_subs1=('s|\([a-zA-Z0_9][[:space:]]*=[[:space:]]*["'"']"'\?\)'"$url_extra"'|'"\1$asset_rel_path\2"'|g' "$opt") # trims strictly
              sed_subs2=('s|\([[:space:]]*'"$url_separator_chars"'[[:space:]]*["'"']"'\?\)'"$url_extra"'|'"\1$asset_rel_path\2"'|g' "$opt") # trims loosely
              sed "${sed_options[@]}" "${sed_subs1[@]}"
              if (( url_asset_capture_level > 2 )); then
                sed "${sed_options[@]}" "${sed_subs2[@]}"
              fi
            else
              if [ "$url_has_path" = "yes" ]; then
                asset_rel_path="$pathpref$assets_directory$assets_dir_suffix$imports_directory$imports_dir_suffix$asset_rel_path"
              else
                asset_rel_path="$pathpref$imports_directory$imports_dir_suffix$asset_rel_path"
              fi
              asset_rel_path=$(url_percent_encode "$asset_rel_path")
              asset_rel_path=$(regex_escape "$asset_rel_path" "BRE")
              if [ "$path_doubleslash_workaround" = "yes" ]; then
                # Replace double slashes in paths with single slashes
                asset_rel_path=${asset_rel_path//\/\//\/}
              fi
              asset_rel_path=$(sed_rhs_escape "$asset_rel_path")
              sed_subs1=('s|\([a-zA-Z0_9][[:space:]]*=[[:space:]]*["'"']"'\?\)'"$url_extra"'|'"\1$asset_rel_path"'|g' "$opt") # trims strictly
              sed_subs2=('s|\([[:space:]]*'"$url_separator_chars"'[[:space:]]*["'"']"'\?.*\)'"$url_extra"'|'"\1$asset_rel_path"'|g' "$opt") # trims loosely
              sed "${sed_options[@]}" "${sed_subs1[@]}"
              if (( url_asset_capture_level > 2 )); then
                sed "${sed_options[@]}" "${sed_subs2[@]}"
              fi
            fi
          done
        done
      fi
      (( count++ ))
      print_progress "$count" "$num_webpages"
    done
    print_progress

    num_domain_dirs=$(find "$mirror_dir/$mirror_archive_dir/" -maxdepth 1 -type d -name "*.*" | wc -l )
    if [ "$num_domain_dirs" != "1" ] && [ "$extra_assets_mode" = "contain" ]; then
      # Move folders
      if [ "$imports_directory" != "" ]; then
        mirror_imports_directory="$working_mirror_dir/$imports_directory"
        mkdir -p "$mirror_imports_directory"
      else
        mirror_imports_directory="$working_mirror_dir"
      fi
      for extra_dir in "${extra_domains_array[@]}"; do
        if [ -d "$mirror_dir/$mirror_archive_dir/$extra_dir" ] && [ "$extra_dir" != "" ]; then
          mirror_extra_dir="$mirror_dir/$mirror_archive_dir/$extra_dir"
          asset_move="$mirror_extra_dir to $mirror_imports_directory/"
          # Move only if mirror_imports_directory is not a subdirectory of mirror_extra_dir
          if [[ ! $mirror_imports_directory/ = $mirror_extra_dir/* ]]; then
            mv "$mirror_extra_dir" "$mirror_imports_directory/" || { echolog "$msg_error: Unable to move $asset_move."; exit; }
            echolog "Moved $asset_move." "1"
          fi
        fi
      done
    fi
  fi

  # Special case: convert long file names to shorter forms determined previously
  if [ ${#webpages[@]} -ne 0 ] && [ -s "$input_long_filenames" ]; then
    while IFS= read -r line; do
      if [ "$line" != "" ]; then
        full_URL="$(printf "%s" "$line" | awk -F'\t' '{print $1}')"
        full_filename=$(basename "$full_URL")
        shorter_name=$(printf "%s\n" "$line" | awk -F'\t' '{print $2}')
        # search and replace
        for opt in "${webpages[@]}"; do
          sed_subs=('s~'"$full_filename"'~'"$shorter_name"'~g' "$opt")
          sed "${sed_options[@]}" "${sed_subs[@]}"
        done
      fi
    done < "$input_long_filenames"
  fi

  # Special case: mirroring a directory not a whole domain: readjust internal links
  if [ "$url_has_path" = "yes" ] && [ "$cut_dirs" = "0" ]; then
    IFS='/' read -ra url_path_dir_list <<< "$url_path_dir"
    extra_dirs_list=("${url_path_dir_list[0]}")
    url_path_dir_prefix=
    for ((i=0;i<url_path_depth;i++)); do
      child_dir=${url_path_dir_list[$i]}
      while IFS= read -r line; do [ "$line" != "" ] && extra_dirs_list+=("$url_path_dir_prefix$line"); done <<<"$(find "." -maxdepth 1 -name "*" -type d -print | ( [ "$url_path_dir" != "" ] && grep -v "^$child_dir$" || cat ) | grep -vx "." | sed s'/^..//')"
      url_path_dir_prefix+="$child_dir/"
      cd_check "$child_dir"
    done
    cd_check "$working_mirror_dir" 1 "Unable to return after traversing URL path directories."

    # Determine which web pages to search and replace
    find_web_pages '.'
    count=1
    echolog "Additional processing for mirroring a directory, not a domain ... "
    for opt in "${webpages[@]}"; do
      { [ -z ${opt+x} ] || [ "$opt" = "" ]; } && continue; # trap the case there are no web pages to process
      print_progress "$count" "$num_webpages"; (( count++ ))
      # but don't process XML files in guise of HTML files
      # (assume document type specified in first non-empty line)
      if grep -m 1 . "$opt" | grep -q "<?xml version"; then
        continue
      fi
      pathpref=
      assetpref=
      dpth=${opt//[!\/]}; depth=${#dpth}
      for ((i=1;i<depth;i++)); do
        pathpref+="\.\./"; # need to escape for sed search else treated as glob
      done
      i="$url_path_depth"
      while (( i+1 < depth )); do
        assetpref+="../";
        ((i++))
      done
      # Loop over all parent paths and carry out universal search and replace
      if [ ${#extra_dirs_list[@]} -ne 0 ]; then
        for pd in "${extra_dirs_list[@]}"; do
          for ((j=0;j<depth-1;j++)); do
            IFS="/" read -ra pd_array <<< "$pd"
            (( pathpref_length=${#pathpref}-(j*5) ))
            src_path=$(printf "%s" "$pathpref" | cut -b -"$pathpref_length" | tr -d '\n'; printf "%s" "${pd_array[$j]}")
            (( k=j+1 ))
            asset_path=$(printf "%s" "$pd" | cut -d/ -f 1-$k)
            rep_path="$assetpref$assets_directory$assets_dir_suffix$asset_path/"
            if [ "$pd" != "" ] && [[ "$src_path" != */ ]]; then    # ensure the search is relative to a named directory
              sed_subs=('s|'"$src_path/"'|'"$rep_path"'|g' "$opt")
              sed "${sed_options[@]}" "${sed_subs[@]}"
            fi
          done
        done
      fi
      # Rectify main domain paths
      domain_assets_search="$assets_directory$assets_dir_suffix$imports_directory$imports_dir_suffix$hostname"
      domain_assets_replace="$assets_directory"
      sed_subs=('s|'"$domain_assets_search"'|'"$domain_assets_replace"'|g' "$opt")
      sed "${sed_options[@]}" "${sed_subs[@]}"
    done
    printf "\n"

    # Move directories and files
    if [ ${#extra_dirs_list[@]} -ne 0 ] && [ "$parent_dirs_mode" = "contain" ]; then
      if [ "$assets_directory" != "" ]; then
        mirror_assets_directory="$working_mirror_dir/$url_path_dir/$assets_directory"
      else
        mirror_assets_directory="$working_mirror_dir/$url_path_dir"
      fi
      mkdir -p "$mirror_assets_directory"
      for extra_dir in "${extra_dirs_list[@]}"; do
        mv_dir="$working_mirror_dir/$extra_dir"
         if [ "$url_path_dir" != "" ] && [[ $url_path_dir =~ $extra_dir/ ]] && [ "$extra_dir" != "" ]; then
          # Move files
          cd_check "$extra_dir" 1
          for x in *; do
            mv_file="$mv_dir/$x"
            mv_params=("--" "$mv_file" "$mirror_assets_directory/$extra_dir/")
            # to do: if not in parent_file_omissions then ...
            if [ ! -d "$x" ]; then
              mv "${mv_params[@]}"
              echolog "Moved file: $mv_file." "1"
            fi
          done
          cd_check "$working_mirror_dir" 1
        elif [ -d "$mv_dir" ] && [[ ! $extra_dir =~ $url_path_dir ]]; then
          # Move directories
          asset_move="$mv_dir to $mirror_assets_directory/"
          # special case: when the directory is a parent, ensure we make corresponding directory in destination
          extra_dir_stem=
          if [[ $extra_dir =~ "/" ]]; then
            extra_dir_stem=$(dirname "$extra_dir");
            mkdir -p "$mirror_assets_directory/$extra_dir_stem"
          fi
          # Move only if mirror_assets_directory/$extra_dir_stem is not a subdirectory of mv_dir
          if [[ ! $mirror_assets_directory/$extra_dir_stem = $mv_dir/* ]]; then
            mv "$mv_dir" "$mirror_assets_directory/$extra_dir_stem" || { echolog "$msg_error: Unable to move $asset_move."; exit; }
            echolog "Moved directory: $asset_move." "1"
          fi
        fi
      done
    fi
  fi

  echolog "Done."
}

# Carry out further processing of output:
#  1. For the primary domain, convert absolute paths to relative paths.
#  2. For extra domains, convert absolute paths to relatives paths and
#     optionally incorporate respective content in a designated assets folder.
#  3. Replace remaining occurrences of primary domain with the deployment domain
#     (subject to user confirmation).
#  4. If Wget --cut-dirs options set, then only carry out option 3.
site_postprocessing() {
  cd_check "$working_mirror_dir" 1
  echolog "Carrying out site postprocessing in $working_mirror_dir ... "

  echolog " " "1"
  if [ "$prune_query_strings" != "no" ]; then
    IFS="," read -ra prune_list <<< "$query_prune_list"
    echolog -n "Pruning links to assets that have query strings appended ... " "1"
  else
    IFS="," read -ra prune_list <<< "$query_prune_always_list"
    echolog -n "Pruning links to asset files of certain types where query strings must be removed ... " "1"
  fi
  for opt in "${prune_list[@]}"; do
    # Prune URLs in input_file_extra_all
    sed_subs0=('s|\(\.'"$opt"'\)%3F[^'\''\"[:space:]]*$|\1|g' "$input_file_extra_all")
    sed_subs=('s|\(\.'"$opt"'\)?[^'\''\"[:space:]]*$|\1|g' "$input_file_extra_all")
    sed "${sed_options[@]}" "${sed_subs0[@]}"
    sed "${sed_options[@]}" "${sed_subs[@]}"

    # Prune file names on disk
    find "$mirror_dir/$mirror_archive_dir" -type f -name "*\.$opt\?*" -exec sh -c 'opt_noquery="${0%%\?*}"; [ ! -f "$opt_noquery" ] && mv "$0" "${0%%\?*}" || rm "$0"' {} \;

    # Prune the corresponding links
    sed_subs0=('s|\([\"'\''][^>\"'\'']*\.'"$opt"'\)%3F[^'\''\"[:space:]]*|\1|g')
    sed_subs=('s|\([\"'\''][^>\"'\'']*\.'"$opt"'\)?[^'\''\"[:space:]]*|\1|g')
    for file_ext in "${asset_find_names[@]}"; do
      find "$mirror_dir/$mirror_archive_dir" -type f -name "$file_ext" "${asset_exclude_dirs[@]}" -print0 | xargs "${xargs_options[@]}" sed "${sed_options[@]}" "${sed_subs0[@]}"
      find "$mirror_dir/$mirror_archive_dir" -type f -name "$file_ext" "${asset_exclude_dirs[@]}" -print0 | xargs "${xargs_options[@]}" sed "${sed_options[@]}" "${sed_subs[@]}"
    done
  done
  echolog "Done." "1"

  if [ "$prune_filename_extensions_querystrings" = "yes" ]; then
    # Remove file name extensions added by Wget where filenames have query strings appended
    IFS=',' read -ra prune_wget_extensions <<< "$wget_adjust_extensions"
    for opt in "${prune_wget_extensions[@]}"; do
      # Rename files
      find "$working_mirror_dir" -type f -name "*\.$opt\?*\.$opt" -exec sh -c 'mv "$0" "${0%\.$opt*}"' {} \;
      find "$working_mirror_dir" -type f -name "*\.$opt%3F*\.$opt" -exec sh -c 'mv "$0" "${0%\.$opt*}"' {} \;
      # Prune the corresponding links
      sed_subs0=('s|\([\"'\''][^>\"'\'']*\.'"$opt"'%3F[^'\''\"[:space:]]*\)\.'"$opt"'|\1|g')
      sed_subs=('s|\([\"'\''][^>\"'\'']*\.'"$opt"'?[^'\''\"[:space:]]*\)\.'"$opt"'|\1|g')
      for file_ext in "${asset_find_names[@]}"; do
        find "$working_mirror_dir" -type f -name "$file_ext" "${asset_exclude_dirs[@]}" -print0 | xargs "${xargs_options[@]}" sed "${sed_options[@]}" "${sed_subs0[@]}"
        find "$working_mirror_dir" -type f -name "$file_ext" "${asset_exclude_dirs[@]}" -print0 | xargs "${xargs_options[@]}" sed "${sed_options[@]}" "${sed_subs[@]}"
      done
    done
  fi

  # Adjust storage locations of assets, where applicable
  if [ "$wayback_url" = "yes" ] && [ "$use_wayback_cli" != "yes" ] && [ "$wayback_assets_mode" = "original" ]; then
    src_path_snapshot="$working_mirror_dir/$url_path_snapshot_prefix"
    consolidate_assets
    process_asset_anchors
    wayback_output_clean 
  elif [ -s "$input_file_extra_all" ] || [ "$url_has_path" = "yes" ]; then
    process_assets
  fi

  # Check for occurrences of $hostname as distinct from $deploy_domain.
  # Only stick with the hostname in url_base if the user requests,
  # otherwise replace all occurrences with the deployment domain
  if [ "$deploy_domain" = "mydomain.com" ]; then
    deploy_domain="$hostname"
  else
    num_domain_matches=$( find . -type f -name \* -exec grep "$hostname" {} + | wc -l )
    if [ "$num_domain_matches" != "0" ]; then
      matches_s=$(pluralize "$num_domain_matches")
      confirm=y
      if [ "$deploy" = "no" ] && [ "$hostname" != "$deploy_domain" ]; then
        echolog "You have chosen not to deploy, with your source hosted at $hostname, different from the deployment domain, $deploy_domain. "
        if [ "$run_unattended" = "yes" ]; then
          echolog "Assuming that you still wish to replace any occurrence of $hostname with $deploy_domain."
        else
          read -r -e -p "For the static mirror, would you still like to replace any occurrence of $hostname with $deploy_domain (y/n)? " confirm
          confirm=${confirm:0:1}
        fi
      elif [ "$deploy" = "yes" ] && [ "$force_domains" = "no" ] && [ "$run_unattended" != "yes" ]; then
        echolog "Found $num_domain_matches matching line$matches_s."
        read -r -e -p "For the static mirror, would you still like to replace any occurrence of $hostname with $deploy_domain (y/n)? " confirm
        confirm=${confirm:0:1}
      fi
      if [ "$confirm" = "y" ] || [ "$confirm" = "Y" ]; then
        domain_match_prefix_esc=${domain_match_prefix//\//\\\\\/}        # \\\\\ to insert a backslash in search pattern
        domain_match_prefix_esc=${domain_match_prefix_esc//\\\\/\\\\\\?} # to make backslash match optional
        echolog -n "Replacing remaining occurrences of $hostname with $deploy_domain ... "
        sed_subs=('s|'"\($domain_match_prefix_esc\)$hostname"'|'"\1$deploy_domain"'|g')
        for file_ext in "${asset_find_names[@]}"; do
          find . -type f -name "$file_ext" "${asset_exclude_dirs[@]}" -print0 | xargs "${xargs_options[@]}" sed "${sed_options[@]}" -e "${sed_subs[@]}"
        done
        echolog "Done."
      fi
    fi
  fi

  # Global search and replace across web pages
  webpages=()
  feed_html_regex=$(regex_escape "$feed_html")
  feed_xml_regex=$(regex_escape "$feed_xml")
  if [ "$wayback_newsfeed_clean" = "yes" ]; then
    newsfeed_domain="$url_original_base/"
  else
    newsfeed_domain=
  fi
  while IFS='' read -r line; do webpages+=("$line"); done <<<"$(for file_ext in "${html_file_exts[@]}"; do find . -type f -name "$file_ext" -print; done)"
  for opt in "${webpages[@]}"; do

    # Remove any <base> tags
    if [ "$base_tags_remove" = "yes" ]; then
      sed_subs=('s/<base[[:space:]][[:space:]]*href[^>][^>]*>//gi' "$opt")
      sed "${sed_options[@]}" "${sed_subs[@]}"
    fi
  
    # Provisionally append index.html to internal anchors ending with trailing slash
    # The canonical form will be set later
    sed_subs=('s|\(=["'\''][^:\\[:space:]"'\'']*/\)\([\"'\'']\)|\1index.html\2|g' "$opt")
    sed "${sed_options[@]}" "${sed_subs[@]}"

    # If CORS is enabled then remove (any restrictions stipulated in) HTML crossorigin tag
    if [ "$cors_enable" = "yes" ]; then
      sed_subs=('s/[[:space:]][[:space:]]*crossorigin[^[:space:]]*[[:space:]]/ /gi' "$opt")
      sed "${sed_options[@]}" "${sed_subs[@]}"
    fi

    # Adjust links to newsfeeds
    if [ "$wayback_url" = "yes" ] && [ "$wayback_newsfeed_clean" != "no" ]; then
      sed_subs1=('s~'"$url_base_timeless\([^[:space:]\'\"]*\)$feed_xml_regex"'~'"$newsfeed_domain\1$feed_xml"'~g' "$opt")
      sed_subs2=('s~'"$url_base_timeless\([^[:space:]\'\"]*\)$feed_html_regex"'~'"$newsfeed_domain\1$feed_html"'~g' "$opt")
      sed "${sed_options[@]}" "${sed_subs1[@]}"
      sed "${sed_options[@]}" "${sed_subs2[@]}"
    fi
    
  done

  printf "Converting feed files and references from index.html to index.xml ... "
  find ./ -depth -type f -path "*feed/index.html" -exec sh -c 'mv "$1" "${1%.html}.xml"' _ '{}' \;
  IFS=" " read -ra webpages <<< "$(grep_web_pages "." "$feed_html")"
  if [ ${#webpages[@]} -ne 0 ]; then
    for opt in "${webpages[@]}"; do
      sed_subs=('s~'"$feed_html_regex"'~'"$feed_xml"'~g' "$opt")
      sed "${sed_options[@]}" "${sed_subs[@]}"
    done
  fi
  echolog "Done."

  sed_subs1=('s|href="http://'"${deploy_domain}"'|href="https://'"${deploy_domain}"'|g')
  sed_subs2=("s|href='http://${deploy_domain}|href='https://${deploy_domain}|g")
  if [ "$protocol" = "https" ] && [ "$force_ssl" = "yes" ]; then
    printf "Updating anchors for %s from http: to https: ... " "$deploy_domain"
    for file_ext in "${asset_find_names[@]}"; do 
      find . -type f -name "$file_ext" -print0 | xargs "${xargs_options[@]}" sed "${sed_options[@]}" "${sed_subs1[@]}"
    done
    for file_ext in "${asset_find_names[@]}"; do 
      find . -type f -name "$file_ext" -print0 | xargs "${xargs_options[@]}" sed "${sed_options[@]}" "${sed_subs2[@]}"
    done
    echolog "Done."
  fi

  # Apply host directory directive, as appropriate
  if [ "$host_dir_mode" = "" ] || [ "$host_dir_mode" = "no" ]; then
    # Shift content up one level and removed host directory.
    if ! mv "$working_mirror_dir/"* "$mirror_dir/$mirror_archive_dir/"; then
      echolog "$msg_error: Unable to move files to the root directory."
    else
      if ! rmdir "$working_mirror_dir"; then
        echolog "$msg_error: Unable to remove the working mirror directory, $working_mirror_dir."
      else
        echolog "Shifted content up one level and removed host directory." "1"
      fi
    fi
  fi

  cd_check "$mirror_dir" 1
}

add_extras() {
  # For archival, copy subs files into the respective mirror directory
  extras_src="$script_dir/$extras_dir/$host"
  extras_dest="$working_mirror_dir"
  echolog "Copying additional files from $extras_src to $extras_dest, the static mirror (for distribution) ... "

  # Create necessary directories
  if [ ! -d "$extras_src" ]; then
    printf "\n";
    echolog "Your configuration file specifies 'add_extras=y', but the folder for extra files, $extras_src, doesn't exist."
    read -r -e -p "Do you wish to create it (y/n)? " confirm
    confirm=${confirm:0:1}
    if [ "$confirm" = "y" ] || [ "$confirm" = "Y" ]; then
      mkdir -p "$extras_src"
      echolog "Created folder for extra files at $extras_src."
      read -r -e -p "If you wish to manually copy some files into this folder then please do so now and hit 'y' to confirm, any other key to skip: " confirm
      confirm=${confirm:0:1}
      if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then
        echolog "Skipping extra files."
        return 0
      else
        echolog "OK. Proceeding with copy of extra files."
      fi
    fi
  fi

  [ "$rvol" != "" ] && rsync_options+=("$rvol")
  error_set +e

  # First, try with rsync, otherwise use cp, to make the copy
  if ! rsync "${rsync_options[@]}" "$extras_src/" "$extras_dest"; then
    printf "%s: there was a problem running rsync.  Using 'cp' command ... " "$msg_error"
    cp -r "$extras_src/." "$extras_dest/." || { echolog "$msg_error: copy failed."; return; }
  fi
  error_set -e
  echolog "Done."
}

sitemap_creation() {
  sitemap_dir="$mirror_dir/$mirror_archive_dir$host_dir"
  cd_check "$sitemap_dir" 1 "Can't access $sitemap_dir to create a sitemap."

  sitemap_path="$sitemap_dir/sitemap.xml"
  touch "$sitemap_path"
  sitemap_content="$(sitemap_header)"$'\n';
  sitemap_loc_files=()

  # Generate find params string based on $sitemap_file_extensions
  IFS="," read -ra sitemap_file_exts <<< "$sitemap_file_extensions"
  for ext in "${sitemap_file_exts[@]}"; do
    while IFS='' read -r line; do sitemap_loc_files+=("$line"); done < <(find . -type f  -name "*.$ext")
  done
  for loc in "${sitemap_loc_files[@]}"; do
    # and exclude case where loc contains '?', i.e. query strings
    if [[ "$loc" == *"?"* ]]; then
      continue;
    fi
    sitemap_content+="$tab<url>"$'\n'
    loc=$(printf "%s" "$loc" | sed "s/index.html//" | sed "s/.\///") # remove any trailing filename from $loc
    if [ "$wayback_url" = "yes" ] && [ "$wayback_host_original_sitemap" = "yes" ]; then
      loc_full="$url_original_base/$loc" 
    else  
      loc_full="https://$deploy_domain/$loc"
    fi
    sitemap_content+="$tab$tab<loc>$loc_full</loc>"$'\n'
    sitemap_content+="$tab</url>"$'\n'
  done
  sitemap_content+="</urlset>"$'\n'
  echo "$sitemap_content" > "$sitemap_path"
  echolog "Created a sitemap file at $sitemap_path"
}

clean_mirror() {
  cd_check "$working_mirror_dir" 1

  # Reconstruct the canonical URL and replace index.html, the default output from Wget
  url_base_deploy="$protocol://$deploy_domain"
  printf "Updating canonical URLs in document headers ... "
  while IFS= read -r -d '' opt
  do
    url_canonical="${opt/\./${url_base_deploy}}"

    # with further tweak on the tail to ensure correct canonical url
    if [ "$link_href_tail" = "" ] || [ "$link_href_tail" = "/" ]; then
      url_canonical="${url_canonical/index\.html/}"
    fi
    url_canonical=$(sed_rhs_escape "$url_canonical")
    sed_subs_canonical=('/<code>.*<\/code>/b
     s|="canonical" href="index.html|="canonical" href="'"$url_canonical"'|g' "$opt")
    sed "${sed_options[@]}" "${sed_subs_canonical[@]}"
  done <   <(for file_ext in "${asset_find_names[@]}"; do find . -type f -name "$file_ext" -print0; done)
  echolog "Done."

  # Run HTML Tidy (option)
  error_set +e
  if [ "$htmltidy" = "yes" ]; then
    html_errors_file="$script_dir/$tmp_dir/${htmltidy_errors_file}-$myconfig.txt"
    if ! cmd_check "$htmltidy_cmd" "1"; then
      printf "Unable to run HTML Tidy (htmltidy_cmd is set to %s) - please check that it is installed according to instructions at %s. Skipping.\n" "$htmltidy_cmd" "$htmltidy_url";
    else
      printf "Running HTML Tidy on html files with options %s ... " "${htmltidy_options[*]}"
      while IFS= read -r -d '' fname
      do
        $htmltidy_cmd "${htmltidy_options[@]}" "$fname" 2>>"$html_errors_file"
      done <   <(for file_ext in "${htmltidy_file_exts[@]}"; do find . -type f -name "$file_ext" -print0; done)
      echolog "Done."
    fi
  fi
  error_set -e

  # Run link checker (option)
  if [ "$linkchecker" = "yes" ]; then
    linkchecker_options=()
    if ! cmd_check "$linkchecker_cmd" "1"; then
      printf "%s: Unable to run link checker (linkchecker_cmd is set to %s) - please check that it is installed according to instructions at %s. Skipping.\n" "$msg_error" "$linkchecker_cmd" "$linkchecker_url";
    else
      links_log_file="$script_dir/$tmp_dir/${linkchecker_log_file}-$myconfig.txt"
      echolog "Checking links (logging in $linkchecker_log_file) ... "
      msg_linkcheck=
      get_home_page
      [ "$linkchecker_check_external" = "yes" ] && linkchecker_options+=( --check-extern )
      $linkchecker_cmd "${linkchecker_options[@]}" "$home_page_path" > "$links_log_file"
      # Carry out error analysis on log file
      errors_local=$(grep -o "$linkchecker_errors_match_file" "$links_log_file" | wc -l)
      errors_remote=$(grep -o "$linkchecker_errors_match_http" "$links_log_file" | wc -l)
      links_error_flag=
      if [ "$linkchecker_check_external" = "no" ]; then
        if (( errors_local == 0 )); then
          msg_linkcheck+="No broken links found"
        else
          msg_linkcheck+="$msg_error: $errors_local broken links found"
          links_error_flag=on
        fi
        msg_linkcheck+=" (only local links were checked)"
      else
        if (( errors_local == 0 )) && (( errors_remote == 0 )); then
          msg_linkcheck+="No broken links found (both local and remote links were checked)"
        elif (( errors_local == 0 )); then
          msg_linkcheck+="$msg_error: No local broken links, but $errors_remote remote broken links found"
          links_error_flag=on
        elif (( errors_local == 1 )) && (( errors_remote == 1 )); then
          msg_linkcheck+="$msg_error: $errors_local local and $errors_remote remote broken links found"
          links_error_flag=on
        else
          msg_linkcheck+="$msg_error: $errors_local local broken links, though no remote broken links found"
          links_error_flag
        fi
      fi
      [ "$links_error_flag" != "" ] && msg_linkcheck+=". Details are in the file $links_log_file"
      msg_linkcheck+=". Done."
      echolog "$msg_linkcheck"
    fi
  fi

  # Rename Wget temporary files (option)
  if [ "$rename_wget_tmps" = "yes" ]; then
    find ./ -depth -type f -name "*.tmp.html" -exec sh -c 'mv "$1" "${1%.tmp.html}"' _ {} \;
  fi

  # Remove unwanted system files
  files_to_delete=()
  IFS=',' read -ra files_to_delete <<< "$system_files_cleanup"
  for item in "${files_to_delete[@]}"; do
    find . -type f -name "$item" -delete
  done
## optionally,
# rm "$input_file_extra" "$input_file_extra_all"

  # Conclude login session (expire and delete cookie)
  if [ "$require_login" = "yes" ]; then
    # Set an arbitrary date in the past for cookie expiry
    expire_date="Mon, 21 Nov 2022 00:00:01 GMT"
    awk -v expire_date="$expire_date" -F '\t' -v OFS='\t' '{sub(0,expire_date,$5)}1' "$cookies_path" > "$cookies_tmppath" && mv "$cookies_tmppath" "$cookies_path"

    # Access logout (or any) page with expired cookie -
    # should receive HTTP Error: 403 (Forbidden)
    wget_options_logout=(--spider "$wget_ssl" --directory-prefix "$mirror_archive_dir" "$url_base$logout_path")
    $wget_cmd "${wget_credentials[@]}" "${wget_extra_options[@]}" "${wget_options_logout[@]}"
    # Delete cookies
    if [ -f "$cookies_path" ]; then
      rm "$cookies_path"
    else
      echolog "Tidy up: no cookies_path at $cookies_path" "1"
    fi

    # Delete temporary post data file
    if [ -f "$post_tmppath" ]; then
      rm "$post_tmppath"
    fi
  fi

  # Create robots file, where necessary
  if [ "$robots_create" = "yes" ]; then
    robots_path="$mirror_dir/$mirror_archive_dir$host_dir/robots.txt"
    robots_default="$script_dir/$lib_files/$robots_default_file"
    if [ -f "$robots_default" ]; then
      cp_check "$robots_default" "$robots_path"
    else
      touchmod "$robots_path"
    fi
    printf "\nSitemap: %s\n" "$url_sitemap" >> "$robots_path"
  fi

  # Wrap lines that end in '='
  echolog -n "Wrap lines that end in '=' ... "
  sed_subs=(-e ':a' -e 'N' -e '$!ba' -e 's/=[\r\n][\r\n]*[[:space:]]*/=/g')
  find . -type f -name "*.html" -exec sed "${sed_options[@]}" "${sed_subs[@]}" {} +
  # and ensure that the title is on one line
  sed_subs=(-e ':a' -e 'N' -e '$!ba' -e 's/[\r\n][\r\n]*[[:space:]]*\([^<]*<\/title>\)/ \1/g')
  find . -type f -name "*.html" -exec sed "${sed_options[@]}" "${sed_subs[@]}" {} +
  echolog "Done."

  # Rename files ending with query strings, as required
  if [ "$deploy_netlify" = "yes" ]; then
    clean_query_extensions="yes"
    echolog "Cleaning file names with question marks for Netlify." "1"
  fi
  if [ "$clean_query_extensions" = "yes" ]; then
    find "$working_mirror_dir" -type f -name "*\?*" -exec sh -c 'mv "$0" "${0%%\?*}"' {} \;
  fi

  # Remove empty directories
  find . -type d -empty -delete

  # Tidy up basic authentication entries - need to ensure we are updating only when required
  if [ -n "${wget_http_user+x}" ] && [ "$credentials_cleanup" = "yes" ]; then
    rc_file="$HOME/$credentials_rc_file"
    if [ "$credentials_rc_file" = ".netrc" ]; then
      # Search for credentials based on $site_user and $hostname,
      # assuming they are defined on a single line with space-separated values
      if [ -f "$rc_file" ]; then
        # Check to see if an entry exists (with superfluous "''" inserted to pass Shellcheck SC1087)
        cred_pattern="machine[[:blank:]]\{1,\}$hostname"''"[[:blank:]]\{1,\}login[[:blank:]]\{1,\}$wget_http_user"
        replace_rc="$(grep -v "$cred_pattern" "$rc_file")"
        printf "%s\n" "$replace_rc" > "$rc_file" || echolog "$msg_warning: unable to remove existing credentials"
        chmod 0600 "$rc_file"
      fi
    elif [ "$credentials_rc_file" = ".wgetrc" ]; then
      # Search for credentials based on $site_user, assuming that it and
      # the password are on separate lines
      if [ -f "$rc_file" ]; then
        # Check to see if an entry exists
        cred_pattern="http_user="
        cred_pattern_pwd="http_password="
        # remove existing credentials
        replace_rc="$(grep -v "^[[:blank:]]\{0,\}$cred_pattern\|^[[:blank:]]\{0,\}$cred_pattern_pwd" "$rc_file")"
        printf "%s\n" "$replace_rc" > "$rc_file" || echolog "$msg_warning: unable to remove existing credentials"
        touchmod "$rc_file"
      fi
    fi
  fi

  # For Wayback Machine mirrors, optionally rename host directory
  if [ "$wayback_url" = "yes" ] && [ "$wayback_host_original_dir" = "yes" ]; then
    cd_check "$mirror_dir/$mirror_archive_dir" 1
    working_mirror_dir_old="$working_mirror_dir"
    host_dir="/$hostname_original"
    working_mirror_dir="$mirror_dir/$mirror_archive_dir$host_dir"
    if [ -d "$hostname_original" ]; then
      echolog "$msg_warning: The working mirror directory is already in place, using the original domain, at $working_mirror_dir. Leaving as is, but you should consider renaming the existing output and running afresh."
      working_mirror_lock=yes
    elif [ -d "$hostname" ]; then
      if mv "$hostname" "$hostname_original"; then
        echolog "Renamed $working_mirror_dir_old to $working_mirror_dir." "1"
      else
        echolog "$msg_warning: Unable to rename the working mirror directory to $working_mirror_dir."
      fi
    else
      echolog "$msg_error: Expected either a $hostname/ or $hostname_original/ directory inside $mirror_dir/$mirror_archive_dir, but neither found. Aborting."; exit
    fi
  fi

  # Optionally append MakeStaticSite session information
  if [ "$web_print_runtime_data" = "yes" ]; then
    # Generate session data comment
    mss_summary="The output was generated by MakeStaticSite"
    if [ "$wayback_url" = "yes" ]; then
      mss_summary+=" from web requests to the Wayback Machine"
    fi
    mss_summary+="."
    makestaticsite_session_comment=$(printf "<!-- %-93s -->\n" "$mss_summary")
    makestaticsite_session_comment+="\n"
    old_ifs="$IFS"
    for datum in "${session_data[@]}"; do
      IFS='|' read -ra list <<< "$datum"
      datum_key="${list[0]}"
      datum_value="${list[1]}"
      makestaticsite_session_comment+=$(printf "<!-- %-12s %-80s %s" "$datum_key:" "$datum_value" "-->")
      makestaticsite_session_comment+="\n"
    done
    IFS="$old_ifs"
    cd_check "$mirror_dir/$mirror_archive_dir/" 1
    # Regenerate list of web pages
    while IFS= read -r line; do webpages_final+=("$line"); done <<<"$(for file_ext in "${html_file_exts[@]}"; do find . -type f -name "$file_ext" "${asset_exclude_dirs[@]}" -print; done)"
    for opt in "${webpages_final[@]}"; do
      printf "%b" "\n$makestaticsite_session_comment" >> "$opt"
    done
  fi
  
  cd_check "$mirror_dir" 1
}

process_snippets() {
  # Create necessary directories for substitution files and snippets
  mkdir -p "$sub_files_path"; echolog "Created folders for substitute files at $sub_files_path."
  mkdir -p "$snippets_dir"; echolog "Created folder for snippet files at $snippets_dir."

  # Change to subs directory
  cd_check "$script_dir/$sub_dir" 1 "Can't access substitutes directory ($script_dir/$sub_dir). No substitutions can be made."

  # Create a substitutions area replicating the mirrored folder
  mkdir -p "$mirror_archive_dir"

  # Replicate the mirrored folder for the host [and port]
  subs_host_dir="$mirror_archive_dir$host_dir"
  mkdir -p "$subs_host_dir"

  # Carry out snippet substitutions:
  echolog "current directory: $(pwd)" "1"
  if [ ! -f "$snippets_data_file" ]; then
    echolog "$msg_warning: Unable to find snippets data file $snippets_data_file"
    echolog 'Skipping substitutions'
  else
    echolog "Snippets data file found at: $snippets_data_file"
    temp_IFS=$IFS; IFS=":" # file_path:list

    # Clear the contents of files/ for this run
    find $sub_files_dir -type f -delete

    # Clear (non-archived) site folder for this run
    [ "$archive" = "no" ] && rm -rf "$local_sitename"

    # Read the snippets data for $localsite_name, line by line
    read_data=false
    while read -r line;
    do
      # Look for opening tag for $localsite_name
      if [ "${line:0:1}" = "<" ] && [ "${line:1:1}" != "/" ]; then
        tag=$(printf "%s\n" "$line" | awk -F '[<>]' '{print $2}')
        [ "$tag" = "$local_sitename" ] && read_data=true
        continue
      # Look for closing tag and exit loop
      elif [ "${line:1:1}" = "/" ]; then
        tag=$(printf "%s\n" "$line" | awk -F '[/<>]' '{print $3}')
        read_data=false
        [ "$tag" = "$local_sitename" ] && break
      # Read data
      elif [[ "$read_data" = true ]]; then
        read -ra strarr <<< "$line"
        src_file=${strarr[0]}
        sub_input_file=$sub_files_dir'/'$src_file
        echolog -e "input file $sub_input_file" "1"

        # Create the necessary subdirectories containing modified files
        src="$subs_host_dir/$src_file"
        sub_input_dir="$(dirname "${sub_input_file}")"
        src_dir="$(dirname "${src}")"
        mkdir -p "$src_dir"

        # Freshen the files to be updated by copying across from the latest mirror
        echolog "local source: $working_mirror_dir/$src_file copied to $sub_input_dir/" "1"
        mkdir -p "$sub_input_dir" && cp_check "$working_mirror_dir/$src_file" "$sub_input_dir/"

        # Loop through the snippet IDs for this file, read and apply changes for each
        # (uses the /r command to read input from a file)
        id_list=${strarr[1]}
        for i in ${id_list//,/$IFS}
        do
          id_num=$(printf "%0*d" 3 "$i")
          snippet_id="SNIPPET"$id_num
          echolog "$snippet_id" "1"
          snippet_file_id=$(printf "%s" "$snippet_id" | tr '[:upper:]' '[:lower:]')
          snippet_file=$snippets_dir'/'$snippet_file_id'.html'
          start='<!--'$snippet_id'BEGIN'
          end='<!--'$snippet_id'END'
          sed -i'.original.'"$i" -e '/'"$end"'/r '"$snippet_file" -e '/'"$start"'/,/'"$end"'/d' "$sub_input_file"
        done
        (( snippets_count+=1 ))
        cp_check "$sub_input_file" "$src_dir"
      fi
    done < "$snippets_data_file"
  fi
  IFS=$temp_IFS # restore IFS to defaults

  if (( snippets_count==0 )); then
    echolog "$msg_warning: No snippets were found."
  elif (( snippets_count==1 )); then
    echolog "Processed one snippet."
  else
    echolog "Processed $snippets_count snippets."
  fi

  # Copy any snippets across to mirror
  if [ "$snippets_count" != 0 ]; then
    snippets_src="$script_dir/$sub_dir/$subs_host_dir"
    dest="$working_mirror_dir"
    echolog "Copying from: $snippets_src" "1"
    echolog "To: $dest" "1"
    cp -r "$snippets_src/." "$dest/." || { printf ".\n%s: Unable to copy the snippets to the mirror.\n" "$msg_error"; }
  fi

  cd_check "$script_dir" 0 "Cannot change directory to $script_dir."
}

#  If Wget --cut-dirs not specified, then move top-level index.html to root directory.
cut_mss_dirs() {
  if [ "$url_has_path" = "no" ]; then
    echolog "$msg_info: You have specified mss_cut_dirs to cut directories, but this is only effective for a URL with a directory path. No action taken."
    return 0
  fi
  if [ "$cut_dirs" != "0" ]; then
    return 0
  fi
  cd_check "$working_mirror_dir" 1
  dir_path="$working_mirror_dir/$url_path_dir"
  if [ "$mss_cut_dirs" = "no" ]; then
    dest_path="$working_mirror_dir/$url_path_original"
    mkdir -p "$dest_path"
  else
    dest_path="$working_mirror_dir"
  fi
  if (( phase < 5 )) && [ "$dir_path" != "$dest_path" ] && [ "$working_mirror_lock" != "yes" ]; then
    if mv "$dir_path/"* "$dest_path/"; then 
      echolog "Moved files and folders from $dir_path to $dest_path/" "1"
    else
      echolog "$msg_error: unable to move the contents of $dir_path/ to $dest_path/"
      confirm_continue
    fi
  fi
  # remove top-level folder of $url_path
  url_root_dir=$(printf "%s" "$url_path_dir" | cut -d/ -f1)
  if [ -d "$url_root_dir" ]; then
    rm -rf "$url_root_dir"
  fi
}

add_pagefind_search(){
  cd_check "$mirror_dir" 0 "Unable to enter directory $mirror_dir"$'\n'"Skipping the addition of Pagefind search." || { return; }
  pagefind_log_file="$script_dir/$tmp_dir/${pagefind_log_file}-$myconfig.txt"
  echolog -n "Running Pagefind to build a search (logging in $pagefind_log_file) ... "
  if ! cmd_check "$pagefind_cmd" "1"; then
    echolog " "
    echolog "$msg_error: Unable to run Pagefind (pagefind_cmd is set to $pagefind_cmd) - please check that it is installed according to instructions at $pagefind_url. Skipping.\n"; return 1;
  fi
  pagefind_options=()
  pagefind_options+=(-l "$pagefind_log_file")
  [ "$output_level" = 'quiet' ] && pagefind_options+=(-q)
  [ "$output_level" = 'silent' ] && pagefind_options+=(-s)
  [ "$output_level" = 'verbose' ] && pagefind_options+=(-v)
  pagefind_options+=(--glob "$pagefind_options_glob")
  pagefind_options+=(--site "$working_mirror_dir")
  $pagefind_cmd "${pagefind_options[@]}"
  echolog "Running $pagefind_cmd with options ${pagefind_options[*]}"

  # Add a search box
  if [ "$pagefind_pages" = "home" ]; then
    if [ "$pagefind_home_page" != "" ]; then
      home_page="$pagefind_home_page"
    else
      [ -z "${home_page+x}" ] && get_home_page
    fi
    sed_subs=('s|\('"$pagefind_insert_after_re"'\)|'"\1$pagefind_code"'|' "$working_mirror_dir/$home_page") 
    sed "${sed_options[@]}" "${sed_subs[@]}"
  elif [ "$pagefind_pages" = "all" ]; then
    while IFS= read -r -d '' opt
    do
      sed_subs=('s|\('"$pagefind_insert_after_re"'\)|'"\1$pagefind_code"'|' "$opt")
      sed "${sed_options[@]}" "${sed_subs[@]}"
    done <   <(for file_ext in "${html_file_exts[@]}"; do find "$working_mirror_dir" -type f -name "$file_ext" -print0; done)
  elif [[ $pagefind_pages == *,* ]]; then
    IFS=',' read -ra list <<< "$pagefind_pages"
    for opt in "${list[@]}"; do
      sed_subs=('s|\('"$pagefind_insert_after_re"'\)|'"\1$pagefind_code"'|' "$working_mirror_dir/$opt")
      sed "${sed_options[@]}" "${sed_subs[@]}"
    done
  fi
  echolog "Done."
  msg_pagefind="A search facility has been added, created using Pagefind."
}

site_layout(){
  # MSS cut directories
  if [ "$mss_cut_dirs" = "yes" ] || [ "$wayback_url" = "yes" ]; then
    cut_mss_dirs
  fi
  # Create sitemap (optional)
  if [ "$sitemap_create" = "yes" ]; then
    sitemap_creation
  fi
  # Add Pagefind search facility (optional)
  if [ "$pagefind" = "yes" ]; then
    add_pagefind_search
  fi
}

create_zip() {
  cd_check "$mirror_dir" 0 "Unable to enter directory $mirror_dir"$'\n'"Skipping the creation of the zip file." || { return; }
  echolog "Creating a ZIP archive ... "
  if [ -f "$zip_archive" ]; then
    zip_backup="$zip_archive.backup"
    mv "$zip_archive" "$zip_backup" || echolog "$msg_warning: unable to create a backup for $zip_archive"
    echolog "Backed up $zip_archive to $zip_backup" "1"
  fi
  zip_options="-q -r $zip_archive $mirror_archive_dir"
  [ "$zip_omit_download" = "yes" ] && zip_options+=" -x $mirror_archive_dir$host_dir/$zip_download_folder/*" 
  IFS=" " read -ra zip_options_all <<< "$zip_options"
  zip "${zip_options_all[@]}"
  cd_check "$script_dir"
  echolog "ZIP archive created at $mirror_dir/$zip_archive."
}

deploy_on_netlify() {
  echolog "Deploying on Netlify ... "

  # Check Netlify is installed
  if ! cmd_check "netlify" "1"; then
    # Check Node JS is installed
    node_msg=
    cmd_check "npm" "1" || { node_msg=' Also, the prerequisite, Node.JS, is not installed.'; }
    printf "%s: The netlify command is not available.\nCheck that it is installed and is within PATH.%s\nFor installation instructions, please refer to https://docs.netlify.com/cli/get-started/#installation.\nSkipping Netlify.\n" "$msg_error" "${node_msg}";
  else
    # Remove any current link to Netlify
    netlify unlink || { netlify login; }
    # Link to Netlify site name (else log in)
    netlify link --name "$deploy_netlify_name" || { netlify login; }
    # Deploy site to Netlify
    netlify_options=(deploy --dir="$working_mirror_dir" --prod)
    if ! netlify "${netlify_options[@]}"; then
      echolog "$msg_error: Failed to deploy to Netlify."
    fi
  fi
  echo
}

prep_rsync() {
  echolog "Deploying on a remote server using rsync over ssh ... "

  # Test network connection to remote server host using netcat
  if ! nc -w2 -z "$deploy_host" "$deploy_port"; then
    echolog "Unable to connect to the remote server, $deploy_host, on port $deploy_port, needed for rsync."
    echolog "Use of rsync aborted."
    echolog "Static archive created, but not deployed remotely using rsync."
    echolog "$msg_signoff"
    exit
  else
    dest=$deploy_user'@'$deploy_host':'$deploy_path'/'
    echolog "Sync to remote server"
  fi
}

deploy() {
  cd_check "$working_mirror_dir" 1

  # Final tweaks for canonical URL links ahead of deployment
  printf "Updating internal anchors to conform with canonical URLs ... "
  [ "$a_href_tail" = "" ] && a_href_tail="\/"
  if [ "$a_href_tail" = "html" ] || [ "$a_href_tail" = "index.html" ]; then
    a_href_tail="\/index.html"
  fi

  if [ "$a_href_tail" = "\/" ]; then
    sed_subs=(-e ':a' -e 'N' -e '$!ba' -e 's/\(=\)\([\n]*[[:space:]]*\)\(["'\'']\)index.html\([\"'\'']\)/\1\3'"#"'\4/g')
    find . -type f -name "*.html" -exec sed "${sed_options[@]}" "${sed_subs[@]}" {} +
  fi
  sed_subs=(-e ':a' -e 'N' -e '$!ba' -e 's/\(=\)\([\n]*[[:space:]]*\)\(["'\''][^:\\"'\'']*\)\/index.html\([\"'\'']\)/\1\3'"$a_href_tail"'\4/g')
  find . -type f -name "*.html" -exec sed "${sed_options[@]}" "${sed_subs[@]}" {} +

  echolog "Done."
  cd_check "$script_dir" 0 "Cannot change directory to $script_dir."

  # Copy zip file into site uploads folder, ready for deployment
  mkdir -p "$working_mirror_dir/$zip_download_folder"
  local_dest="$working_mirror_dir/$zip_download_folder/$zip_filename"
  if [ "$upload_zip" = "yes" ]; then
    if ! cp_check "$mirror_dir/$zip_archive" "$local_dest" "can't copy zip archive into the site uploads area, $local_dest"; then
      exit 1
    fi
  fi

  cmd_check "rsync" "1" || { echolog "$msg_error: the rsync command is not available."$'\n'"Check that it is installed and is within PATH."$'\n'"Aborting."; exit; }

  src="$working_mirror_dir"
  comment_status=0   # Host entry commented out? (0 for no, 1 for yes)
  toggle_flag=0      # Has status been toggled?  (0 for no, 1 for yes)

  # if source and deployment domains are the same, then call Hosts function
  if [ "$deploy_host" = "$hostname" ]; then
    echolog "NOTICE: Your source and deployment domains are the same."
    # Check /etc/hosts - if it exists, search for the domain and then offer choice ...
    if [ -f "$etc_hosts" ]; then
      hosts_toggle
    else
      echolog "However, you do not appear to have an entry in $etc_hosts."
      # Check whether paths are the same
      echolog "Source site path: $site_path"
      echolog "Deployment path: $deploy_path"
      [ "$site_path" != "$deploy_path" ] && echolog "The paths appear to be distinct, so deployment should not overwrite" || echolog "$msg_warning: The paths appear to be the same - about to overwrite the source folder with the static mirror!"
      confirm_continue ""
    fi
  fi

  if [ "$deploy_remote" = "yes" ]; then
    # Deployment on Netlify
    if [ "$deploy_netlify" = "yes" ]; then
      deploy_on_netlify
    fi
    # Deployment with rsync over ssh
    if [ "$deploy_remote_rsync" = "yes" ]; then
      prep_rsync
      rsync_src=("$src/")
      rsync_dest=("$dest")
      [ "$rvol" != "" ] && rsync_options+=("$rvol")
      if ! rsync "${rsync_options[@]}" "${rsync_src[@]}" "${rsync_dest[@]}"; then
        printf "%s: there was a problem running rsync" "$msg_error"
        msg_deploy="The site was not deployed."
      else
        msg_deploy+="The site has been deployed on $deploy_host, for web access at http[s]://$deploy_domain."
      fi
    fi
  else
    # Deploy on local server (a single instance that gets overwritten at each run)
    echolog "Deploying locally, using 'cp' command ... "
    dest="$deploy_path"
    echolog "From: $src/"
    echolog "To: $dest"
    mkdir -p "$dest"
    cp -r "$src/." "$dest/." || { echolog "$msg_error: unable to make the copy."; msg_deploy="The site was not deployed locally."; }
  fi
  
  if [ "$toggle_flag" = "1" ]; then
    # Invite user to restore Hosts file as it was
    read -r -e -p "The transfer is complete.  Would you like to restore $etc_hosts as it was (y/n)? " confirm
    confirm=${confirm:0:1}
    if [ "$confirm" = "y" ] || [ "$confirm" = "Y" ]; then
      [ "$comment_status" = "1" ] && entry="#$entry"
      comment_uncomment "$etc_hosts" "$entry"
    fi
  fi
}

conclude() {
  echolog -n "Completed in "; stopclock SECONDS
  msg_done=$(msg_ink "ok" 'All done.')
  echolog "$msg_done"
  echolog "A static mirror of $url has been created in $working_mirror_dir"
  if [ "$wayback_url" = "yes" ] && [ -n "${msg_wayback+x}" ]; then
    echolog $'\n'"$msg_wayback"
  fi
  if [ "$warc_output" = "yes" ] && [ -n "${msg_warc+x}" ]; then
    echolog $'\n'"$msg_warc"
  fi
  if [ "$pagefind" = "yes" ] && [ -n "${msg_pagefind+x}" ]; then
    echolog $'\n'"$msg_pagefind"
  fi
  if [ -n "${msg_deploy+x}" ]; then
    echolog $'\n'"$msg_deploy"
  fi

  if [ "$webserver_preview" = "yes" ]; then
    if ! cmd_check "$webserver_preview_cmd" "1"; then
      echolog "$msg_error: Unable to launch a local web server (webserver_preview_cmd is set to $webserver_preview_cmd) - please review. Skipping.\n"
    else
      echolog -n $'\n'"Launching a local web server for previewing the site... "$'\n'
      cd_check "$working_mirror_dir"
      $webserver_preview_cmd & pid=$!
      webserver_port=${webserver_preview_cmd//[![:digit:]]/}
      echolog "The web server is running and your site should be accessible. Try http://localhost:$webserver_port."
      echolog "To stop the server, run: kill -TERM $pid"
      cd_check "$mirror_dir"
    fi
  fi

  echolog $'\n'"Thank you for using MakeStaticSite, free software released under the $mss_license. The latest version is available from $mss_download".  
  echolog " "
  timestamp_end=$(timestamp "$timezone")
  printf "%s\n" "$msg_signoff" >> "$log_file"
  printf "Timestamp: %s\n\n" "$timestamp_end" >> "$log_file"
}

################# END OF FUNCTIONS ################

# Run the script
main "$@"
