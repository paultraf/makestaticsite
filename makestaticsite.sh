#!/usr/bin/env bash

##########################################################################
#
# MakeStaticSite --- a shell script to create and deploy static websites
# Copyright 2022-2024 Paul Trafford <pt@ptworld.net>
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
  (( phase < 4 )) && (( end_phase >= 3 )) && [ "$wget_extra_urls" = "yes" ] && wget_extra_urls

  # Phase 4: Refine the static site
  (( phase < 5 )) && (( end_phase >= 4 )) && [ "$site_post_processing" = "yes" ] && site_postprocessing

  # Phase 5: Further additions from an extras folder
  (( phase < 6 )) && (( end_phase >= 5 )) && [ "$add_extras" = "yes" ] && add_extras

  # Phase 6: Optimise the mirror
  (( phase < 7 )) && (( end_phase >= 6 )) && clean_mirror

  # Phase 7: Use snippets
  (( phase < 8 )) && (( end_phase >= 7 )) && [ "$use_snippets" = "yes" ] && process_snippets

  # Phase 7-8 Interval: MSS cut directories
  (( phase < 8 )) && (( end_phase >= 4 )) && [ "$mss_cut_dirs" = "yes" ] && cut_mss_dirs

  # Phase 8: Create an offline zip archive
  (( phase < 9 )) && (( end_phase >= 8 )) && [ "$upload_zip" = "yes" ] && create_zip || echo "Creation of ZIP archive skipped, as per preferences." "1"

  # Phase 9: Deploy
  (( end_phase >= 9 )) && [ "$deploy" = "yes" ] && deploy || echo "Runtime option for deployment set to 'no'; deployment skipped."

  # Phase 10: Finish
  conclude
}
################## END OF PHASES ##################


###################################################
#                Support functions
###################################################

# Override built-in echo and also write to log file
# This takes an optional priority parameter (number) to constrain output,
# stored in echo_num:
#  0 (liberal)    - echo unless output level is silent
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
    # For priority 2, only log and echo when verbose
    if [ "$log_level" != "verbose" ]; then
      echo_log=""
    fi
    if [ "$output_level" != "verbose" ]; then
      echo_tty=""
    fi
  fi
  if [ "$echo_tty" != "" ]; then
    env echo "${params[@]}"
  fi
  if [ "$echo_log" != "" ] && [ "$log_level" != "silent" ] && [ -n "${log_file+x}" ]; then
    env echo "${params[@]}" >> "$log_file"
  fi

  IFS="$temp_IFS"
}

read_config() {
  run_params="$*"
  myconfig=default
  phase=0
  end_phase=$max_phase_num
  mirror_archive_dir=
  config_flag=off # flag to denote whether or not -i option set
  mirror_id_flag=off # flag to denote whether or not -m option set

  local OPTIND
  while getopts "ui:p:q:m:L:vh" option; do
    case "$option" in
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

initialise_layout() {
  # Set up logging
  log_file_dir="$script_dir/log"
  [ -d "$log_file_dir" ] || mkdir -p "$log_file_dir"
  log_file="$log_file_dir/$log_filename"
  touchmod "$log_file"

  printf "Welcome to MakeStaticSite version %s\n" "$version"

  # Set up 'Run commands' file
  touchmod "$HOME/$credentials_rc_file"

  # Set up temporary directory
  tmp_dir_path="$script_dir/$tmp_dir"
  [ -d "$tmp_dir_path" ] || mkdir -p "$tmp_dir_path"
  tmp_mirror_path="$script_dir/$tmp_dir/mirror"
  [ -d "$tmp_mirror_path" ] || mkdir -p "$tmp_mirror_path"

  timestamp_start=$(timestamp "$timezone")
  { printf "Starting run of MakeStaticSite, version %s\n" "$version";
    printf "Timestamp: %s\n" "$timestamp_start";
    printf "Running with command line options: %s\n" "$run_params"; } >> "$log_file"

  # Local target directory and web server deployment
  mirror_dir="$script_dir/mirror"         # path to Wget output root folder
  [ -d "$mirror_dir" ] || { mkdir -p "$mirror_dir"; echo "Created folder for mirror files at $mirror_dir."; }

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
      echo "NOTICE: run_unattended=yes (to keep terminal output silent)" 0
    fi
    run_unattended=yes
  fi

  return 0
}

initialise_variables() {
  myconfig=${myconfig/.cfg/}

  # Read phase details
  validate_range 0 "$max_phase_num" "$phase" || { echo "Sorry, the phase number is out of range (it should be between 0 and $max_phase_num).  Please try again."; exit; }

  # Read phase details
  validate_range 1 "$max_phase_num" "$end_phase" || { echo "Sorry, the phase number for exiting the program is out of range (it should be between 1 and $max_phase_num).  Please try again."; exit; }

  ((phase>end_phase)) && { printf "%s: The (start) phase number cannot be greater than the end phase number.\nPlease rerun the program." "$msg_error"; exit; }

  # If the phase is nonzero, then check for -m option
  if ((phase > minvalue)) && [ "$mirror_id_flag" = "off" ]; then
    echo "$msg_error: Missing -m option (mirror archive folder name) is needed for the supplied start phase (p). Please refer to the help:"
    echo
    ./makestaticsite.sh -h
    exit
  fi

  # If the phase numbers are too small, then nothing much will be done
  if ((end_phase < 2)); then
    echo "$msg_warning: No site will be output because the supplied end phase (q) is too low."
  fi

  # Check that a mirror archive exists corresponding to the mirror identifier
  if [ "$mirror_id_flag" = "on" ]; then
     if [ ! -d "$mirror_dir/$mirror_archive_dir" ]; then
       echo "ATTENTION! No mirror archive was found at $mirror_dir/$mirror_archive_dir"
       echo "Here is a list of possible mirror IDs:"
       cd "$mirror_dir" || { printf "unable to enter directory %s.\nAborting.\n" "$mirror_dir"; exit; }
       pwd
       sh -c "ls -d */ | sed 's/\///'"
       echo "Please choose one from the list and rerun with -m option."
       cd "$script_dir" || { printf "unable to enter directory %s.\nAborting.\n" "$script_dir"; }
       exit
     else
       echo "Found mirror archive at $mirror_dir/$mirror_archive_dir"
     fi
  fi

  start_phase_desc=$(get_phase_desc "$phase")
  echo "Starting at phase $phase: $start_phase_desc."
  ((end_phase<=max_phase_num)) && { end_phase_desc=$(get_phase_desc "$end_phase"); echo "Ending at phase $end_phase: $end_phase_desc."; }

  # Check for mirror ID and, if necessary, derive input cfg file from it
  # (looking at the tail for the timestamp format)
  if [ "$myconfig" = "default" ] && [ "$mirror_id_flag" = "on" ]; then
    myconfig=$(printf "%s" "$mirror_archive_dir" | sed "s/20[[:digit:]]\{6\}_[[:digit:]]\{6\}$//")
  fi

  # Check we now have a valid config file and display it
  check_config_file "$myconfig"
  printf "Reading custom configuration data from config/%s ... " "$myconfig.cfg"

  # now augment Wget input files with .cfg label
  wget_inputs_main="$wget_inputs_main-$myconfig.txt"
  wget_inputs_extra="$wget_inputs_extra-$myconfig.txt"

  # Translate to output levels for rsync and Wget respectively
  if [ "$output_level" = 'silent' ] || [ "$output_level" = 'quiet' ]; then
    rvol=-q; wvol=-q; wpvol=--quiet
  elif [ "$output_level" = 'verbose' ]; then
    rvol=-v; wvol=; wpvol=--debug
  else
    rvol=; wvol=-nv; wpvol=
  fi

  add_search=$(yesno "$(config_get add_search "$myconfig")")
  deploy=$(yesno "$(config_get deploy "$myconfig")")
  deploy_remote=$(yesno "$(config_get deploy_remote "$myconfig")")
  use_snippets=$(yesno "$(config_get use_snippets "$myconfig")")
  snippets_count=0
  upload_zip=$(yesno "$(config_get upload_zip "$myconfig")")

  # Check system requirements for cURL, Wget and SSL
  msg_checking="Checking your system for Wget and other essential components ... "
  cmd_check "curl" || { printf "%s%s: Unable to find binary: curl ("'$'"PATH contains %s).\nThis command is essential for checking connectivity.  It may be downloaded from https://curl.se/.\nAborting.\n" "$msg_checking" "$msg_error" "$PATH"; exit; }
  cmd_check "$wget_cmd" "1" || { printf "%s: Unable to carry out a snapshot\nPlease review the value of the wget_cmd option.\nAborting.\n" "$msg_error"; exit; }
  echo "OK" "1"
  wget_cmd_version="$(which_version "$wget_cmd" "GNU Wget")"
  version_check "$wget_cmd_version" "$wget_version_atleast" || { printf "%s%s. The version of %s is %s, which is old, so some functionality may be lost.  Version %s or later is recommended.\n" "$msg_checking" "$msg_warning" "$wget_cmd" "$wget_cmd_version" "$wget_version_atleast";}
  ssl_checks=$(yesno "$(config_get ssl_checks "$myconfig")")
  [ "$ssl_checks" = "no" ] && wget_ssl="--no-check-certificate" || wget_ssl=''

  # Web server details (to be snapped by Wget, etc.)
  url="$(config_get url "$myconfig")"
  [[ ${url:length-1:1} != "/" ]] && url="$url/"; # ensure URL ends in trailing slash

  # Wayback Machine support
  use_wayback= 
  wayback_enable=$(yesno "$wayback_enable")
  if [ "$wayback_enable" = "yes" ]; then
# shellcheck source=lib/mod_wayback.sh
    source "lib/$mod_wayback";
    if (( phase < 4 )) && ! validate_internet; then
      echo " "; echo "$msg_error: Unable to establish Internet access. Please check your network connectivity."
      echo "Aborting."
      exit
    fi
    if check_wayback_url "$url" "$wayback_hosts"; then
      use_wayback=yes
      wget_extra_urls=no
      domain_wayback_machine=$(printf "%s" "$url" | awk -F/ '{print $3}' | awk -F: '{print $1}')
      printf "\nWayback Machine detected at %s, hosted on %s.\n" "$url" "$domain_wayback_machine."
      process_wayback_url "$url" # will change the value of $url to be that of the archived site
    fi
  fi

  url_domain=$(printf "%s\n" "$url" | awk -F/ '{print $3}' | awk -F: '{print $1}')
  url_path=$(printf "%s" "$url" | cut -d/ -f4- | sed s'/\/$//')
  if [ "$url_path" = "" ]; then
    url_path_depth=0
  else
    url_slashes=${url_path//[!\/]};
    url_path_depth=$(( ${#url_slashes}+1 ))
  fi

  # Additional, supported extensions and domains for stored assets
  asset_domains="$(config_get asset_domains "$myconfig")"
  page_element_domains="$(config_get page_element_domains "$myconfig")"

  # For backwards-compatibility check whether URL defined instead in url_base
  if [ "$url_domain" = "example.com" ]; then
    url="$(config_get url_base "$myconfig")"
    if [ "$url" = "" ]; then { printf "\n%s: the URL supplied in %s (example.com) needs to be changed!\nAborting.\n" "$msg_error" "$myconfig"; exit; }
    fi
  fi

  # Extract the host (domain or IP) and port, protocol, and hence the URL base (no path)
  hostport=$(printf "%s" "$url" | awk -F/ '{print $3}')
  domain=$(printf "%s" "$hostport" | awk -F: '{print $1}') # refer to this as the 'primary domain'

  # initialise list of all domains incorporated in the site
  extra_domains=
  all_domains="$domain"
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

  protocol=$(printf "%s" "$url" | awk -F/ '{print $1}' | awk -F: '{print $1}')
  url_base="$protocol://$hostport"
  
  require_login=$(yesno "$(config_get require_login "$myconfig")")
  [ "$require_login" = "yes" ] && { site_user="$(config_get site_user "$myconfig")";
    site_password="$(config_get site_password "$myconfig")";
    login_path="$(config_get login_path "$myconfig")"; 
    login_address="$url_base$login_path"; 
    login_user_field="$(config_get login_user_field "$myconfig")"; 
    login_pwd_field="$(config_get login_pwd_field "$myconfig")"; 
    cookie_session_string="$(config_get cookie_session_string "$myconfig")";   
  }

  # Local snapshot label
  local_sitename="$(config_get local_sitename "$myconfig")"

  # Options to support Wget
  input_urls_file="$(config_get input_urls_file "$myconfig")"

  [ "$use_wayback" != "yes" ] && wget_extra_urls=$(yesno "$(config_get wget_extra_urls "$myconfig")")
  site_post_processing=$(yesno "$(config_get site_post_processing "$myconfig")")
  archive=$(yesno "$(config_get archive "$myconfig")")
  wget_input_files=()  # Initialise array of additional Wget input URLs
  input_file_extra="$script_dir/$tmp_dir/$wget_inputs_extra"  # Input file for Wget extra assets (to be generated)
  wget_extra_options_tmp=$(wget_canonical_options "$(config_get wget_extra_options "$myconfig")")

  # If URL contains one or more directories, then ensure --no-parent option, subject to option settings
  if [ "$url" != "$url_base/" ] && [[ ! $wget_extra_options_tmp =~ "-np" ]] && [[ ! $wget_extra_options_tmp =~ "--no-parent" ]]; then
    if [ "$wget_no_parent" = "auto" ] || [ "$wget_no_parent" = "yes" ]; then
      wget_extra_options_tmp+=" -np"
    fi
  fi

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
  IFS=" " read -r -a wget_extra_options <<< "$wget_plus_ops"

  # Hide http basic authentication password
  IFS=" " read -r -a wget_extra_options_print <<< "$(printf "%s" "$wget_plus_ops" | sed "s/password[[:space:]][^[:space:]]*/password *********/")"

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

  htmltidy=$(yesno "$(config_get htmltidy "$myconfig")")
  add_extras=$(yesno "$(config_get add_extras "$myconfig")")

  # WP-CLI (or other CMS client) options, including source (server), as appropriate
  wp_cli=$(yesno "$(config_get wp_cli "$myconfig")")
  site_path="$(config_get site_path "$myconfig")"

  # Path of the mirror archive, if archive directory is already defined
  # check for -nH option in wget_extra_options
  hostport_dir=
  if [[ $wget_extra_options_tmp =~ "-nH" ]] || [[ $wget_extra_options_tmp =~ "--no-host-directories" ]]; then
    host_dir=
  fi

  if [ "$host_dir" != "" ] && [ "$(yesno "$host_dir")" != "no" ] && [ "$use_wayback" != "yes" ]; then
    hostport_dir="/$hostport"
  fi

  if [ "$mirror_archive_dir" != "" ]; then
    working_mirror_dir="$mirror_dir/$mirror_archive_dir$hostport_dir"
    zip_archive="$mirror_archive_dir.zip"
  fi

  mss_cut_dirs=$(yesno "$mss_cut_dirs" "1")
  cut_dirs=0
  if [[ $wget_extra_options_tmp =~ "--cut-dirs" ]]; then
    cut_dirs=$(echo "$wget_extra_options_tmp" | grep -o "cut-dirs=[0-9]*" | cut -d '=' -f2)
  fi

  # Zip file of the site snapshot
  zip_filename="$(config_get zip_filename "$myconfig")"
  zip_download_folder="$(config_get zip_download_folder "$myconfig")"

  # For deployment on a remote server
  if [ "$deploy_remote" != "yes" ]; then
    deploy_host="on your local computer"
  else
    deploy_remote_rsync=$(yesno "$(config_get deploy_remote_rsync "$myconfig")")
    deploy_netlify=$(yesno "$(config_get deploy_netlify "$myconfig")")
    if [ "$deploy_remote_rsync" = "yes" ]; then
      deploy_host="$(config_get deploy_host "$myconfig")"
      deploy_port="$(config_get deploy_port "$myconfig")"
      deploy_user="$(config_get deploy_user "$myconfig")"
    fi
    if [ "$deploy_netlify" = "yes" ]; then
      deploy_netlify_name="$(config_get deploy_netlify_name "$myconfig")"
    fi
  fi
  deploy_path="$(config_get deploy_path "$myconfig")"
  deploy_domain="$(config_get deploy_domain "$myconfig")"
  echo "Done."
  if [ "$cut_dirs" != "0" ]; then
    echo "$msg_warning: You have specified Wget --cut-dirs option. Ignoring mss_cut_dirs."
  fi

  # Define a timestamp
  timestamp=$(timestamp "$timezone")

  # Script sign-off message
  msg_signoff="Ending run of MakeStaticSite."
}

prepare_static_generation() {
  echo "Starting the static site generation ..."

  # Prepare WordPress site for static archive, if applicable
  if [ "$wp_cli" = "yes" ] && [ "$use_wayback" != "yes" ]; then
    wp_cli_remote=$(yesno "$(config_get wp_cli_remote "$myconfig")")
    source_host="$(config_get source_host "$myconfig")"
    source_protocol="$(config_get source_protocol "$myconfig")"
    source_port="$(config_get source_port "$myconfig")"
    source_user="$(config_get source_user "$myconfig")"
# shellcheck source=lib/mod_wp.sh
    source "lib/$mod_wp";
    wp_prep
  fi

  return 0
}

wget_error_codes() {
  echo "Done."
  case "$1" in
    "8")
      echo -n "$msg_warning: Wget ERROR code 8, i.e. the Web server gave an error on retrieving at least one file, probably HTTP 404 (file not found - possibly specified in the input file).  Less likely is a 500 (internal server error), which in the case of a CMS might be due to a plugin or module. ";
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
      echo "$err8_msg. "
      wget_error_check 8
      ;;
    "7")
      echo "Wget $msg_error code 7 - wget reports a protocol error, which probably means that it can't connect to the host.  Check that the web server (httpd) is running and also the host spelling."
      wget_error_check 7
      ;;
    "6")
      echo "Wget $msg_error code 6: Username/password authentication failure.  This can happen when fetching a login page or accessing an API.  Such errores can often be avoided by setting in wget_extra_options the -X option to exclude the relevant directory."
      wget_error_check 6
      ;;
    "5")
      echo "Wget $msg_error code 5: SSL verification failure.  If you trust the certificate, then you should set the configuration option, ssl_checks=no (for the wget option --no-check-certificate)."
      wget_error_check 5
      ;;
    "4")
      echo "Wget $msg_error code 4: Network failure.  It may be a network configuration issue.  Check in particular if there are any firewalls."
      wget_error_check 4
      ;;
    "3")
      echo "Wget $msg_error code 3: File I/O error.  Check that you have write access to $working_mirror_dir.  More commonly, this error can occur when wget tries to write to a file where there already exists a directory with the same name."
      wget_error_check 3
      ;;
    "2")
      echo "Wget $msg_error code 2: Parse error.  Check the command line options:"
      echo "$wget_options"
      wget_error_check 2
      ;;
    "1")
      echo "Wget $msg_error code 1: Generic error.  Check the command line options:"
      wget_error_check 1
      exit
      ;;
  esac
}


# Retrieve and process credentials
wget_process_credentials() {
  credentials_insert_path="${credentials_path_prefix}$domain/$wget_http_login_field/$wget_http_user"
  credentials_path="$credentials_home/$credentials_insert_path"
  if [ "$credentials_storage_mode" = "encrypt" ]; then
    if [ -z ${pass_check+x} ]; then
      cmd_check "$credentials_manage_cmd" || { printf "\n%s: Unable to find binary: $credentials_manage_cmd ("'$'"PATH contains %s).\nThis command is essential for working with encrypted credentials.  It may be downloaded from %s.  Alternatively,  modify the value of credentials_storage_mode in constants.sh to 'plain', and re-run the setup, but with less security. \nAborting.\n" "$msg_error" "$PATH" "$credentials_manage_cmd_url"; exit; }
      pass_check=1
    fi
    if [ ! -f "$credentials_path.$credentials_extension" ]; then
      input_encrypted_password "HTTP authentication: a password for $wget_http_user is required to access the web server"
    fi
    wget_http_password=$(pass show "$credentials_insert_path" 2>/dev/null) || { echo "$msg_error: Unable to retrieve the password from the credentials store at $credentials_insert_path. Aborting."; exit; }
  elif [ "$credentials_storage_mode" = "plain" ]; then
    if [ ! -f "$credentials_path" ]; then
      # Get user input for credentials (expected to be requested during setup; basically copy that code here)
      mkdir -p "$mss_dir_permissions" "$(dirname "$credentials_path")"
      touchmod "$credentials_path"

      # Read password and write to "$credentials_path"
      printf "\n"
      read -r -s -e -p "Please enter the password for $wget_http_user: " wget_http_password
      if [ "$wget_http_password" = "" ]; then
        echo "$msg_warning: No password was set!"
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
    # Search for credentials based on $site_user and $domain,
    # assuming they are defined on a single line with space-separated values
    if [ -f "$rc_file" ]; then
      # Check to see if an entry exists (with superfluous "''" inserted to pass Shellcheck SC1087)
      cred_pattern="machine[[:blank:]]\{1,\}$domain"''"[[:blank:]]\{1,\}login[[:blank:]]\{1,\}$wget_http_user"
      search_rc="$(grep -m 1 "$cred_pattern" "$rc_file")"
      if [ "$search_rc" != "" ]; then
        confirm=y
        if [ "$run_unattended" != "yes" ]; then
          # ask if want to replace (y/n)?
          printf "\n"
          echo "$msg_warning: HTTP authentication (username and password) credentials for user $wget_http_user have already been defined in $rc_file."
          read -r -e -p "Do you wish to overwrite (y/n)? " confirm
          confirm=${confirm:0:1}
        fi
        if [ "$confirm" = "y" ] || [ "$confirm" = "Y" ]; then
          # remove existing credentials
          replace_rc="$(grep -v "^[[:blank:]]\{0,\}$cred_pattern" "$rc_file")"
          printf "%s\n" "$replace_rc" > "$rc_file" || echo "$msg_warning: unable to remove existing credentials"
        else
          ## leave credentials and don't do any further processing
          rc_process=N
        fi
      fi
    else
      touchmod "$rc_file"
    fi
    if [ "$rc_process" = "Y" ]; then
      env echo "machine $domain login $wget_http_user password $wget_http_password" >> "$rc_file"
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
          echo "$msg_warning: a login has already been defined (as $search_rc).  Only one user/password pair may be defined."
          read -r -e -p "Do you wish to overwrite (y/n)? " confirm
          confirm=${confirm:0:1}
        fi
        if [ "$confirm" = "y" ] || [ "$confirm" = "Y" ]; then
          # remove existing credentials
          replace_rc="$(grep -v "^[[:blank:]]\{0,\}$cred_pattern\|^[[:blank:]]\{0,\}$cred_pattern_pwd" "$rc_file")"
          printf "%s\n" "$replace_rc" > "$rc_file" || echo "$msg_warning: unable to remove existing credentials"
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
    echo "$msg_warning: no recognisable (.netrc or .wgetrc) run commands file specified, assuming none."
    echo "This means that credentials will be included directly in Wget."
    confirm_continue
  fi
}


# Mirror a site using Wget (main site capture)
wget_mirror() {
  echo "Will capture snapshot from $url using $wget_cmd."

  # Test whether source host is available
  wget_test_options=(-q "$wget_ssl")
  if [ "$wget_user_agent" != "" ]; then
    if [ "$require_login" != "yes" ] || [ "$wget_cookies_nullify_user_agent" = "no" ]; then
      wget_test_options+=(-U "$wget_user_agent")
    fi
  fi
  wget_test_options+=(--spider --tries 3 "$url_base")
  if ! $wget_cmd "${wget_extra_options[@]}" "${wget_test_options[@]}"; then
    msg_error="Unable to connect to $url_base.  Please check: the spelling of the domain, the web server status (is it running?) and access restrictions, particularly if any http authentication credentials are required. "
    printf "GET http://google.com HTTP/1.0\n\n" | nc google.com 80 > /dev/null 2>&1 || msg_error+="Actually, there appears to be no Internet connectivity (tested with http://google.com). "
    msg_error+="Aborting."
    echo "$msg_error"
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
    echo "Reading list of additional URLs to crawl from $input_urls_file."
  fi

  # Wget configuration and its outputs
  input_options="--input-file=$input_file"

  if [ "$mirror_archive_dir" = "" ]; then
    mirror_archive_dir="$local_sitename"
    [ "$archive" = "yes" ] && mirror_archive_dir+="$timestamp"
    working_mirror_dir="$mirror_dir/$mirror_archive_dir$hostport_dir"
    zip_archive="$mirror_archive_dir.zip"
  fi

  # Overwrite an existing mirror only if the -m and wget_refresh_mirror flags are unset
  # and then only after run_unattended flag set or consent given
  if [ "$mirror_id_flag" = "off" ] && [ "$wget_refresh_mirror" = "yes" ]; then
    [ -d "$working_mirror_dir" ] && echo "$msg_warning: $working_mirror_dir already exists.";
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

  url_robots="$url/robots.txt"
  wget_robot_options=("$wget_ssl" --directory-prefix "$mirror_archive_dir$hostport_dir" "$url_robots")
  wget_sitemap_options=("$wget_ssl" --directory-prefix "$mirror_archive_dir$hostport_dir")

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

  if [ "$wget_user_agent" != "" ]; then
    if [ "$require_login" != "yes" ] || [ "$wget_cookies_nullify_user_agent" = "no" ]; then
      wget_extra_options+=(-U "$wget_user_agent")
      wget_extra_options_print+=(-U \""$wget_user_agent"\")
    fi
  fi

  # If access to site restricted then log in and fetch cookie as required
  if [ "$require_login" = "yes" ]; then
    wget_login_options+=("$login_address" --delete-after)
    site_user="$(config_get site_user "$myconfig" "$script_dir")"
    credentials_insert_path="${credentials_path_prefix}$domain/site_user/$site_user"
    credentials_path="$credentials_home/$credentials_insert_path"
    if [ "$credentials_storage_mode" = "encrypt" ]; then
      if [ ! -f "$credentials_path.$credentials_extension" ]; then
        input_encrypted_password "The website login requires a password for $site_user"
      fi
      site_password=$(pass show "$credentials_insert_path" 2>/dev/null) || { echo "$msg_error: $credentials_insert_path is not in the password store. Aborting."; exit; }
    elif [ "$credentials_storage_mode" = "plain" ]; then
      if [ ! -f "$credentials_path" ]; then
        # Get login password (usually entered during setup)
        mkdir -p "$mss_dir_permissions" "$(dirname "$credentials_path")"
        touchmod "$credentials_path"

        # Read password and write to "$credentials_path"
        read -r -s -e -p "Please enter the website login password for $site_user: " site_password
        if [ "$site_password" = "" ]; then
          echo "$msg_warning: No password was set!"
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
    echo "Logging in to the site at $login_address using credentials: ${login_user_field}=${site_user}&${login_pwd_field}=******* ${wget_login_options[*]} ... "
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
        echo "$empty_cookies_msg"
      elif [ "$cookie_session_string" = "" ]; then
        echo "Please define the cookie_session_string in constants.sh."
      else
        echo "note that it should be the same as the value of cookie_session_string (currently $cookie_session_string), as set in constants.sh."
      fi
      printf "Also check the username and password in %s.\n" "$myconfig.cfg"
      confirm_continue
    else
      echo "OK."
      # Add cookie as option for main Wget run
      wget_extra_options+=(--load-cookies "$cookies_path")
      wget_extra_options_print+=(--load-cookies "$cookies_path")
    fi
  fi

  echo "Running Wget with options:" "${wget_core_options[@]}" "${wget_extra_options_print[@]}" "${wget_options[@]}"

  # Remove previous zip upload
  zip_archive_old="$working_mirror_dir/$zip_download_folder/$zip_filename"
  if [ -f "$zip_archive_old" ]; then
    rm "$zip_archive_old" || echo "$msg_warning: Unable to delete existing zip file at $zip_archive_old"
  fi

  # Main run of Wget #
  printf "%s" "$msg_mirror_start"

  error_set +e  # override because error traps set specially for Wget
  if [ "$robots_create" != "yes" ]; then
    # Check for robots.txt file (will store in mirror directory as they are part of the crawl)
    if ! $wget_cmd "${wget_extra_options[@]}" "${wget_robot_options[@]}"; then
      printf " \n%s: Wget reported an error trying to retrieve the robots.txt file (likely not found).  Search engines expect this, so have made a note to create it.\n" "$msg_warning"
      robots_create=yes
    elif sitemap_line=$(grep "^[[:space:]]*Sitemap:" "$mirror_archive_dir$hostport_dir/robots.txt"); then
      # Read contents of robots.txt, checking for sitemap
      sitemap=$(printf "%s\n" "$sitemap_line" | grep -o 'http[s]*:\/\/.*.xml')
      $wget_cmd "${wget_extra_options[@]}" "${wget_sitemap_options[@]}" "$sitemap"
      # Wget any nested sitemaps
      wget_sitemap_options+=("$sitemap" --output-document -)
      $wget_cmd "${wget_extra_options[@]}" "${wget_sitemap_options[@]}" | grep -o "http[s]*://[^<]*.xml" | $wget_cmd "${wget_extra_options[@]}" --quiet "$wget_ssl" --directory-prefix "$mirror_archive_dir$hostport_dir" -i -
    else
      printf " \n%s: No sitemap found in robots.txt. Search engines expect this, so have made a note to generate one.\n" "$msg_warning"
      sitemap_create=yes
    fi
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
  cd "$mirror_dir" || { echo; echo "$msg_error: can't access working directory for the mirror ($mirror_dir)" >&2; exit 1; }

  if [ "$use_wayback" = "yes" ]; then
    echo "Retrieving archive for $domain... "
    mirror_archive_dir="$local_sitename"
    [ "$archive" = "yes" ] && mirror_archive_dir+="$timestamp"
    working_mirror_dir="$mirror_dir/$mirror_archive_dir"
    zip_archive="$mirror_archive_dir.zip"

    # Check for Wayback Machine Downloader binary, else report error (in the absence of an alternative)
    if cmd_check "$wayback_machine_downloader_cmd" "1"; then
      echo "Running Wayback Machine Downloader on $url ... "
      if [ "$domain_wayback_machine" != "web.archive.org" ]; then
        echo "$msg_error: The Wayback Machine Downloader only supports web.archive.org and we don't have any custom alternative.  You might be able to retrieve some files by setting wayback_enable=no in constants.sh (to treat like any other site) and then re-running, though this is not recommended. Aborting."
        exit
      else
        wmd_get_wayback_site "$url"
      fi
    else
      echo "$msg_error: Wayback Machine Downloader not found (wayback_machine_downloader_cmd is set to $wayback_machine_downloader_cmd) - please check that it is installed according to instructions at $wayback_machine_downloader_url. Aborting."
      exit
    fi
  else
    wget_mirror
  fi
}

# (A placeholder for) post mirror site review and analysis
post_get_site_checks() {
  echo
}

generate_extra_domains() {
# Generate search URL prefixes combining primary domain and extra domains
  if [ "$page_element_domains" = "auto" ]; then
    echo -n "Searching for extra asset domains (working in $working_mirror_dir) ... "
    domain_grep="https?:\\\?/\\\?/[^\"'/< ]+\.[^\"'/< ]+\\\?/[^\"'< ]+[^\"'/< ]+\.[^\"'/< ]+"
    domain_grep2="https?:\\\?/\\\?/[^\"'/< ]+\.[^\"'/< ]+\\\?/"
    domain_grep3="[^\"'/< ]+\.[^\"'/< ]+\\\?/"
    add_domains=()
    while IFS='' read -r line; do add_domains+=("$line"); done < <(grep -Eroh "$domain_grep" "$working_mirror_dir" --include "*\.html" | grep -Eo "$domain_grep2" | grep -Eo "$domain_grep3" )
    echo "add_domains array has ${#add_domains[@]} elements" "2"
    # Store unique elements only
    add_domains_unique=()
    while IFS='' read -r line; do add_domains_unique+=("$line"); done < <(for item in "${add_domains[@]}"; do printf "%s\n" "${item%/}"; done | sort -u)
    echo "add_domains_unique array has ${#add_domains_unique[@]} elements" "2"
    # Convert array to domain list (string), removing any trailing slashes
    page_element_domains=$(printf "%s" "${add_domains_unique[*]}" | sed 's/ /,/g' | sed 's/\\\?\/,/,/g' | sed "s/$domain,//g" | sed "s/,$domain//g" | sed 's/\/$//')
    echo "Done."
  fi
  if [ "$page_element_domains" != "" ]; then
    if [ "$extra_domains" != "" ]; then
      extra_domains+=","
    fi
    extra_domains+="$page_element_domains"
    all_domains+=",$extra_domains"
  fi

  IFS="," read -r -a page_element_domains_array <<< "$page_element_domains"
}

# Augment Wget's snapshot by retrieving missed URLs
# (this needs to be done before site_postprocessing)
# We use Wget instead of cURL to avoid repeated overwrites -
# target files are not expected to change during this site generation
wget_extra_urls() {
  cd "$mirror_dir" || { echo "Unable to enter $mirror_dir."; echo "Aborting."; exit; }
  echo "Pruning links to assets that have query strings appended" "1"
  IFS="," read -r -a accept_list <<< "$query_accept_list"
  for opt in "${accept_list[@]}"; do
    sed_subs=('s~\([\"'\''][^>]*\.'"$opt"'\)?[^'\''\"]*~\1~g')
    find "$working_mirror_dir" -type f \( -name '*.html' -o -name '*.xml' -o -name '*.txt' \) -print0 | xargs -0 sed "${sed_options[@]}" "${sed_subs[@]}"
  done
  echo " " "1"

  echo "Searching for additional URLs to retrieve with Wget (working in $working_mirror_dir) ... " "1"

  # Refresh file for Wget (generated)
  touchmod "$input_file_extra"; echo > "$input_file_extra"

  # Generate search URL prefixes combining primary domain and extra domains
  generate_extra_domains

  echo -n "Generating list of extra asset URLs ... "
  url_grep="$(assets_search_string "$all_domains" "[^\"'<) ]+")"

  webassets_all=()
  while IFS='' read -r line; do webassets_all+=("$line"); done < <(grep -Eroh "$url_grep" "$working_mirror_dir" --include "*\.html")
  echo "webassets_all array has ${#webassets_all[@]} elements" "1"

  # Return if empty (nothing further found)
  [ ${#webassets_all[@]} -eq 0 ] && { echo "None found. " "1"; echo "Done."; return 0; }
  [ "$output_level" != "quiet" ] && echo " "

  # Pick out unique items
  echo "Pick out unique items" "1"
  webassets_unique=()
  while IFS='' read -r line; do webassets_unique+=("$line"); done < <(for item in "${webassets_all[@]}"; do printf "%s\n" "${item}"; done | sort -u)
  echo "webassets_unique array has ${#webassets_unique[@]} elements" "2"

  # Filter out all items not starting http
  echo "Filter out all items not starting http" "1"
  webassets_http=()
  while IFS='' read -r line; do webassets_http+=("$line"); done < <(for item in "${webassets_unique[@]}"; do if [ "${item:0:4}" = "http" ]; then printf "%s\n" "${item}"; else continue; fi; done)
  [ ${#webassets_http[@]} -eq 0 ] && { echo "None found. " "1"; echo "Done."; return 0; }
  echo "webassets_http array has ${#webassets_http[@]} elements" "2"

  # Filter out web pages and newsfeeds (limit to non-HTML assets, such as images and JS files)
  echo "Filter out web pages and newsfeeds (limit to non-HTML assets, such as images and JS files)" "1"
  webassets_nohtml=()
  assets_or='\.('${asset_extensions//,/|}')'
  assets_or_external='\.('${asset_extensions_external//,/|}')'
  while IFS='' read -r line; do webassets_nohtml+=("$line"); done < <(for opt in "${webassets_http[@]}"; do
    if [ "$asset_extensions" != "" ]; then
      # Loop over an inclusion list of allowable extensions
      opt_domain=$(printf "%s\n" "$opt" | awk -F/ '{print $3}' | awk -F: '{print $1}')
      if [[ ' '${page_element_domains_array[*]}' ' =~ ' '$opt_domain' ' ]]; then
        echo "$opt" | grep -E "$assets_or_external" > /dev/null && printf "%s\n" "$opt";
      else
        echo "$opt" | grep -E "$assets_or" > /dev/null && printf "%s\n" "$opt";
      fi
    else
      # Remove HTML assets
      type=$(curl -skI "$opt" -o/dev/null -w '%{content_type}\n')
      if [[ "$type" != *"text/html"* ]] && [[ "$type" != *"application/rss+xml"* ]] && [[ "$type" != *"application/atom+xml"* ]]; then
        printf "%s\n" "$opt";
      fi
    fi
  done)
  [ ${#webassets_nohtml[@]} -eq 0 ] && { echo "None found. " "1"; echo "Done."; return 0; }
  echo "webassets_nohtml array has ${#webassets_nohtml[@]} elements" "2"

  if [ ${#wget_extra_options[@]} -ne 0 ]; then
    url_bas="$protocol://$hostport"
    # Filter out URLs whose paths match an excluded directory (via subloop)
    echo "Filter out URLs whose paths match an excluded directory (via subloop)" "1"
    # We assume that grep works as expected, but should really trap exit code 2
    exclude_dirs=$(printf "%s\n" "$wget_plus_ops"| grep -o "\-X[[:space:]]*[[:alnum:]/,\-]*" | grep -o "/.*"; exit 0)
    temp_IFS=$IFS; IFS=","; read -r -a exclude_arr <<< "$exclude_dirs"; IFS=$temp_IFS
    if [ ${#exclude_arr[@]} -eq 0 ]; then
      webassets_omissions=("${webassets_nohtml[@]}")
    else
      webassets_omissions=()
      while IFS='' read -r line; do webassets_omissions+=("$line"); done < <(for opt in "${webassets_nohtml[@]}"; do path="${opt/$url_bas/}"; for exclusion in "${exclude_arr[@]}"; do [ "$path" = "$exclusion" ] || [[ $path =~ ^$exclusion/.* ]] && continue 2; done; printf "%s\n" "$opt"; done)
    fi
  else
    webassets_omissions=("${webassets_nohtml[@]}")
  fi
  echo "webassets_omissions array has ${#webassets_omissions[@]} elements" "2"

  # Return if empty (nothing further found)
  [ ${#webassets_omissions[@]} -eq 0 ] && { echo "None found. " "1"; echo "Done."; return 0; }

  # Filter out URLs with query strings
  echo "Filter out URLs with query strings" "1"
  webassets=()
  while IFS='' read -r line; do webassets+=("$line"); done < <(for opt in "${webassets_omissions[@]}"; do if [[ "$opt" != *"?"* ]]; then printf "%s\n" "$opt"; else continue; fi; done)

  echo "webassets array has ${#webassets[@]} elements" "2"
  # Return if empty (all those found were filtered out)
  [ ${#webassets[@]} -eq 0 ] && { echo "None suitable found. " "1"; echo "Done."; return 0; }

  printf "%s\n" "${webassets[@]}" > "$input_file_extra"
  echo "Done."

  wget_asset_options=("$wget_ssl" --directory-prefix "$mirror_archive_dir")

  if [ "$wvol" != "-q" ] || [ "$output_level" = "silent" ]; then
    wget_progress_indicator=()
  fi

  if [ "$wvol" = "-q" ] && [ "$log_level" != "silent" ]; then
    wget_asset_options+=(-a "$log_file")
  else
    wget_extra_core_options+=("$wvol")
  fi

  echo "Running Wget on these additional URLs with options: " "${wget_extra_core_options[@]}" "${wget_extra_options[@]}" "${wget_asset_options[@]}"
  error_set +e
  if (( wget_threads > 1 )); then
    xargs -a "$input_file_extra" -n 1 -P $wget_threads $wget_cmd "${wget_extra_core_options[@]}" "${wget_progress_indicator[@]}" "${wget_extra_options[@]}" "${wget_asset_options[@]}"
  else
    wget_asset_options+=(--input-file="$input_file_extra")
    $wget_cmd "${wget_extra_core_options[@]}" "${wget_progress_indicator[@]}" "${wget_extra_options[@]}" "${wget_asset_options[@]}"
  fi
  wget_error_codes "$?"
  error_set -e
}


process_assets() {
  echo -n "Processing asset storage locations ... "

  # First, generate a list of all the web pages that contain relevant URLs to process
  # (makes subsequent sed replacements more targeted than searching all web pages).
  webpages=()

  # Ensure that $all_domains includes the extra domains
  if (( phase > 3 )); then
    generate_extra_domains
  fi

  [ -z ${url_grep+x} ] && url_grep="$(assets_search_string "$all_domains" "[^\"'<) ]+")" # define $url_grep as necessary
  for opt in "${url_grep[@]}"; do
    while IFS='' read -r line; do webpages+=("$line"); done < <(grep -Erl "$opt" . --include "*\.html")
  done

  # Prepare adjustment for relative paths with assets directory
  if [ "$assets_directory" != "" ] && [ "$cut_dirs" = "0" ]; then
    assets_dir_suffix=/
    # Also, check for duplication of assets directory label
    if [ "$(find . -name "$assets_directory" -type d -print)" != "" ]; then
      echo -n "$msg_warning: website already contains a directory, $assets_directory.  To avoid confusion (and errors), a timestamp is being appended to the MakeStaticSite-generated assets directory, but it is recommended that you modify the assets_directory constant and re-run. ... "
      assets_directory="$assets_directory$timestamp"
    fi
  else
    assets_dir_suffix=
  fi

  # Similarly, prepare adjustment for relative paths with imports directory
  if [ "$imports_directory" != "" ]; then
    imports_dir_suffix=/
    # Also, check for duplication of assets directory label
    if [ "$(find . -name "$imports_directory" -type d -print)" != "" ]; then
      echo -n "$msg_warning: website already contains a directory, $imports_directory.  To avoid confusion (and errors), a timestamp is being appended to the MakeStaticSite-generated imports directory, but it is recommended that you modify the imports_directory constant and re-run. ... "
      imports_directory="$imports_directory$timestamp"
    fi
  else
    imports_dir_suffix=
  fi

  # General case: conversion of absolute links to relative links
  if [ ${#webpages[@]} -eq 0 ]; then
    echo "No web pages to process.  Done." "1"
  elif [ "$cut_dirs" = "0" ]; then
    # Populate URLs array from Wget's additional input file
    urls_array=()
    if [ -f "$input_file_extra" ]; then
      if read -d '' -r -a urls_array; then :; fi < <(grep -v "//$domain" "$input_file_extra")
    fi

    # Convert absolute links to relative links
    for opt in "${webpages[@]}"; do
      # but don't process XML files in guise of HTML files
      if grep -q "<?xml version" "$opt"; then
        continue
      fi
      pathpref=
      depth=${opt//[!\/]};
      for ((i=1;i<${#depth};i++)); do
        pathpref+="../";
      done
      # Carry out universal search and replace on primary domain;
      # in the case of directory URL with --no-parent, we need to limit matches
      # to full URL and tweak the replacements
      if [ "$url" = "$url_base/" ] || { [ "$external_dir_links" != "" ] && [ "$external_dir_links" != "off" ]; }; then
        sed_subs=('s~https\?://'"$hostport/"'~'"$pathpref"'~g' "$opt")
        sed "${sed_options[@]}" "${sed_subs[@]}"
      fi

      # Loop over all non-primary-domain assets
      # if working with extra domains or a directory URL,
      if [ ${#urls_array[@]} -ne 0 ] && { [ "$extra_domains" != "" ] || [ "$url" != "$url_base/" ]; }; then
        for url_extra in "${urls_array[@]}"; do
          asset_rel_path=$(env echo "$url_extra" | cut -d/ -f3-)
          asset_rel_path="$assets_directory$assets_dir_suffix$imports_directory$imports_dir_suffix$asset_rel_path"
          sed_subs=('s~'"$url_extra"'~'"$asset_rel_path"'~g' "$opt")
          sed "${sed_options[@]}" "${sed_subs[@]}"
        done
      fi
    done

    if [ "$all_domains" != "$domain" ] && [ "$extra_assets_mode" = "contain" ]; then
      # Move folders
      IFS="," read -r -a extra_domains_array <<< "$extra_domains"
      if [ "$imports_directory" != "" ]; then
        mirror_imports_directory="$working_mirror_dir/$imports_directory"
        mkdir -p "$mirror_imports_directory"
      else
        mirror_imports_directory="$working_mirror_dir"
      fi
      for extra_dir in "${extra_domains_array[@]}"; do
        if [ -d "$mirror_dir/$mirror_archive_dir/$extra_dir" ]; then
          mirror_extra_dir="$mirror_dir/$mirror_archive_dir/$extra_dir"
          asset_move="$mirror_extra_dir to $mirror_imports_directory/"
          # Move only if mirror_imports_directory is not a subdirectory of mirror_extra_dir
          if [[ ! $mirror_imports_directory/ = $mirror_extra_dir/* ]]; then
            mv "$mirror_extra_dir" "$mirror_imports_directory/" || { echo "$msg_error: Unable to move $asset_move."; exit; }
            echo "Moved $asset_move." "1"
          fi
        fi
      done
    fi
  fi

  # Special case: mirroring a directory not a whole domain: readjust internal links
  if [ "$url" != "$url_base/" ] && [ "$cut_dirs" = "0" ]; then
    extra_dirs_list=()
    while IFS= read -r line; do extra_dirs_list+=("$line"); done <<<"$(find "." -name "*" -type d -print | grep -v "$url_path" | grep -vx "." | sed s'/^..//')"
    # Determine which web pages to search and replace (may as well fetch all)
    webpages=()
    while IFS= read -r line; do webpages+=("$line"); done <<<"$(find . -name "*.html" -print)"

    for opt in "${webpages[@]}"; do
      # but don't process XML files in guise of HTML files
      if grep -q "<?xml version" "$opt"; then
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
            IFS="/" read -r -a pd_array <<< "$pd"
            (( pathpref_length=${#pathpref}-(j*5) ))
            src_path=$(printf "%s" "$pathpref" | cut -b -"$pathpref_length" | tr -d '\n'; printf "%s" "${pd_array[$j]}")
            (( k=j+1 ))
            asset_path=$(env echo "$pd" | cut -d/ -f 1-$k)
            rep_path="$assetpref$assets_directory$assets_dir_suffix$asset_path/"
            if [ "$pd" != "" ] && [[ "$src_path" != */ ]]; then    # ensure the search is relative to a named directory
              sed_subs=('s~'"$src_path/"'~'"$rep_path"'~g' "$opt")
              sed "${sed_options[@]}" "${sed_subs[@]}"
            fi
          done
        done
      fi
    done

    # Move directories and files
    if [ ${#extra_dirs_list[@]} -ne 0 ] && [ "$parent_dirs_mode" = "contain" ]; then
      if [ "$assets_directory" != "" ]; then
        mirror_assets_directory="$working_mirror_dir/$url_path/$assets_directory"
        mkdir -p "$mirror_assets_directory"
      else
        mirror_assets_directory="$working_mirror_dir/$url_path"
      fi
      mkdir -p "$mirror_assets_directory/$url_path" # and avoid moving into itself later
      for extra_dir in "${extra_dirs_list[@]}"; do
        mv_dir="$working_mirror_dir/$extra_dir"
        if [ "$url_path" != "" ] && [[ $url_path =~ $extra_dir ]]; then
          # Move files
          cd "$extra_dir"
          for x in *; do
            mv_file="$mv_dir/$x"
            mv_params=("--" "$mv_file" "$mirror_assets_directory/$extra_dir/")
            # to do: if not in parent_file_omissions then ...
            if [ ! -d "$x" ]; then
              mv "${mv_params[@]}"
              echo "Moved file: $mv_file." "1"
            fi
          done
          cd "$working_mirror_dir"
        elif [ -d "$mv_dir" ]; then
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
            mv "$mv_dir" "$mirror_assets_directory/$extra_dir_stem" || { echo "$msg_error: Unable to move $asset_move."; exit; }
            echo "Moved directory: $asset_move." "1"
          fi
        fi
      done
    fi
  fi
  echo "Done."
}

# Carry out further processing of output:
#  1. For the primary domain, convert absolute paths to relative paths.
#  2. For extra domains, convert absolute paths to relatives paths and
#     optionally incorporate respective content in a designated assets folder.
#  3. Replace remaining occurrences of primary domain with the deployment domain
#     (subject to user confirmation).
#  4. If Wget --cut-dirs options set, then only carry out option 3.
site_postprocessing() {
  cd "$working_mirror_dir" || { printf "Unable to enter %s.\nAborting.\n" "$working_mirror_dir"; exit; }
  echo "Carrying out site postprocessing in $working_mirror_dir ... "

  # Adjust storage locations of assets, where applicable
  if [ -s "$input_file_extra" ] || [ "$url" != "$url_base/" ]; then
    process_assets
  fi

  # Check for occurrences of $domain as distinct from $deploy_domain.
  # Only stick with the domain in url_base if the user requests,
  # otherwise replace all occurrences with the deployment domain
  if [ "$deploy_domain" = "mydomain.com" ]; then
    deploy_domain="$domain"
  else
    num_domain_matches=$( find . -type f -name \* -exec grep "$domain" {} + | wc -l )
    if [ "$num_domain_matches" != "0" ]; then
      matches_s=$(pluralize "$num_domain_matches")
      confirm=y
      if [ "$deploy" = "no" ] && [ "$domain" != "$deploy_domain" ]; then
        echo "You have chosen not to deploy, with your source having domain $domain, different from the deployment domain, $deploy_domain. "
        if [ "$run_unattended" = "yes" ]; then
          echo "Assuming that you still wish to replace any occurrence of $domain with $deploy_domain."
        else
          read -r -e -p "For the static mirror, would you still like to replace any occurrence of $domain with $deploy_domain (y/n)? " confirm
          confirm=${confirm:0:1}
        fi
      elif [ "$deploy" = "yes" ] && [ "$force_domains" = "no" ] && [ "$run_unattended" != "yes" ]; then
        echo "Found $num_domain_matches matching line$matches_s."
        read -r -e -p "For the static mirror, would you still like to replace any occurrence of $domain with $deploy_domain (y/n)? " confirm
        confirm=${confirm:0:1}
      fi
      if [ "$confirm" == "y" ] || [ "$confirm" == "Y" ]; then
        echo -n "Replacing remaining occurrences of $domain with $deploy_domain ... "
        sed_subs=('s~'"$domain_match_prefix$domain"'~'"$domain_subs_prefix$deploy_domain"'~g')
        find . -type f \( -name '*.html' -o -name '*.xml' -o -name '*.txt' \) -print0 | xargs -0 sed "${sed_options[@]}" "${sed_subs[@]}"
        echo "Done."
      fi
    fi
  fi

  # Provisionally append index.html to internal anchors ending with trailing slash
  # The canonical form will be set later
  webpages=()
  while IFS='' read -r line; do webpages+=("$line"); done < <(find . -type f -name "*.html")
  for opt in "${webpages[@]}"; do
    sed_subs=('s/\(=["'\''][^:\\[:space:]"'\'']*\/\)\([\"'\'']\)/\1index.html\2/g' "$opt")
    sed "${sed_options[@]}" "${sed_subs[@]}"
  done
  printf "Converting feed files and references from index.html to index.xml ... "
  find ./ -depth -type f -path "*feed/index.html" -exec sh -c 'mv "$1" "${1%.html}.xml"' _ '{}' \;
  IFS=" " read -r -a webpages <<< "$(find_web_pages "." "$feed_html")"
  if [ ${#webpages[@]} -ne 0 ]; then
    for opt in "${webpages[@]}"; do
      sed_subs=('s~'"$feed_html"'~'"$feed_xml"'~g' "$opt")
      sed "${sed_options[@]}" "${sed_subs[@]}"
    done
  fi
  echo "Done."

  sed_subs1=('s/href="http:\/\/'"${deploy_domain}"'/href="https:\/\/'"${deploy_domain}"'/g')
  sed_subs2=("s/href='http:\/\/${deploy_domain}/href='https:\/\/${deploy_domain}/g")
  if [ "$protocol" = "https" ] && [ "$force_ssl" = "yes" ]; then
    printf "Updating anchors for %s from http: to https: ... " "$deploy_domain"
    find . -type f \( -name '*.html' -o -name '*.htm' \) -print0 | xargs -0 sed "${sed_options[@]}" "${sed_subs1[@]}"
    find . -type f \( -name '*.html' -o -name '*.htm' \) -print0 | xargs -0 sed "${sed_options[@]}" "${sed_subs2[@]}"
    echo "Done."
  fi

  cd "$mirror_dir" || { printf "Unable to enter %s.\nAborting.\n" "$mirror_dir"; exit; }
}

add_extras() {
  # For archival, copy subs files into the respective mirror directory
  extras_src="$script_dir/$extras_dir/$hostport"
  extras_dest="$working_mirror_dir"
  echo "Copying additional files from $extras_src to $extras_dest, the static mirror (for distribution) ... "

  # Create necessary directories
  if [ ! -d "$extras_src" ]; then
    printf "\n";
    echo "Your configuration file specifies 'add_extras=y', but the folder for extra files, $extras_src, doesn't exist."
    read -r -e -p "Do you wish to create it (y/n)? " confirm
    confirm=${confirm:0:1}
    if [ "$confirm" = "y" ] || [ "$confirm" = "Y" ]; then
      mkdir -p "$extras_src"
      echo "Created folder for extra files at $extras_src."
      read -r -e -p "If you wish to manually copy some files into this folder then please do so now and hit 'y' to confirm, any other key to skip: " confirm
      confirm=${confirm:0:1}
      if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then
        echo "Skipping extra files."
        return 0
      else
        echo "OK. Proceeding with copy of extra files."
      fi
    fi
  fi

  [ "$rvol" != "" ] && rsync_options+=("$rvol")
  error_set +e

  # First, try with rsync, otherwise use cp, to make the copy
  if ! rsync "${rsync_options[@]}" "$extras_src/" "$extras_dest"; then
    printf "%s: there was a problem running rsync.  Using 'cp' command ... " "$msg_error"
    cp -r "$extras_src/." "$extras_dest/." || { printf "%s: copy failed.\n" "$msg_error"; return; }
  fi
  error_set -e
  echo "Done."
}

clean_mirror() {
  cd "$working_mirror_dir" || { printf "Unable to enter %s.\nAborting.\n" "$working_mirror_dir"; exit; }

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
    sed_subs_canonical=('/<code>.*<\/code>/b
     s~="canonical" href="index.html"'~'="canonical" href="'"$url_canonical"'"~g' "$opt")
    sed "${sed_options[@]}" "${sed_subs_canonical[@]}"
  done <   <(find . -type f -name "*.html" -print0)
  echo "Done."

  error_set +e
  html_errors_file="$script_dir/$tmp_dir/${htmltidy_errors_file}-$myconfig.txt"
  if [ "$htmltidy" = "yes" ]; then
    if ! cmd_check "$htmltidy_cmd" "1"; then
      printf "Unable to run HTML Tidy (htmltidy_cmd is set to %s) - please check that it is installed according to instructions at %s. Skipping.\n" "$htmltidy_cmd" "$htmltidy_url";
    else
      printf "Running HTML Tidy on html files with options %s ... " "${htmltidy_options[*]}"
      htmltidy_options+=(-f "$html_errors_file")
      while IFS= read -r -d '' fname
      do
        $htmltidy_cmd "${htmltidy_options[@]}" "$fname"
      done <   <(find . -type f \( -name "*.html" -o -name "*.htm" \) -print0)
      echo "Done."
    fi
  fi
  error_set -e

  # Rename Wget temporary files
  if [ "$rename_wget_tmps" = "yes" ]; then
    find ./ -depth -type f -name "*.tmp.html" -exec sh -c 'mv "$1" "${1%.tmp.html}"' _ {} \;
  fi

  # Remove unwanted system files
  find . -type f -name ".DS_Store" -delete
#rm "$input_file_extra"

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
      echo "Tidy up: no cookies_path at $cookies_path" "1"
    fi

    # Delete temporary post data file
    if [ -f "$post_tmppath" ]; then
      rm "$post_tmppath"
    fi
  fi

  # Create robots file, where necessary
  if [ "$robots_create" = "yes" ]; then
    robots_path="$mirror_dir/$mirror_archive_dir$hostport_dir/robots.txt"
    robots_default="$script_dir/$lib_files/$robots_default_file"
    if [ -f "$robots_default" ]; then
      cp "$robots_default" "$robots_path"
    else
      touchmod "$robots_path"
    fi
    printf "\nSitemap: %s\n" "https://$deploy_domain/$sitemap_file" >> "$robots_path"
  fi

  # Create sitemap, where necessary
  if [ "$sitemap_create" = "yes" ]; then
    sitemap_path="$mirror_dir/$mirror_archive_dir$hostport_dir/sitemap.xml"
    touch "$sitemap_path"
    sitemap_content="$(sitemap_header)"$'\n';
    sitemap_loc_files=()

    # Generate find params string based on $sitemap_file_extensions
    IFS="," read -r -a sitemap_file_exts <<< "$sitemap_file_extensions"
    for ext in "${sitemap_file_exts[@]}"; do
      while IFS='' read -r line; do sitemap_loc_files+=("$line"); done < <(find . -type f  -name "*.$ext")
    done
    for loc in "${sitemap_loc_files[@]}"; do
      # and exclude case where loc contains '?', i.e. query strings
      if [[ "$loc" == *"?"* ]]; then
        continue;
      fi
      sitemap_content+="$tab<url>"$'\n'
      loc=$(echo "$loc" | sed "s/index.html//" | sed "s/.\///") # remove any trailing filename from $loc
      sitemap_content+="$tab$tab<loc>https://$deploy_domain/$loc</loc>"$'\n'
      sitemap_content+="$tab</url>"$'\n'
    done
    sitemap_content+="</urlset>"$'\n'
  fi

  echo "$sitemap_content" > "$sitemap_path"
  echo "Created a sitemap file at $sitemap_path"

  # Wrap lines that end in '='
  printf "Wrap lines that end in '=' ... "
  sed_subs=(-e ':a' -e 'N' -e '$!ba' -e 's/=[\r\n][\r\n]*[[:space:]]*/=/g')
  find . -type f -name "*.html" -exec sed "${sed_options[@]}" "${sed_subs[@]}" {} +
  # and ensure that the title is on one line
  sed_subs=(-e ':a' -e 'N' -e '$!ba' -e 's/[\r\n][\r\n]*[[:space:]]*\([^<]*<\/title>\)/ \1/g')
  find . -type f -name "*.html" -exec sed "${sed_options[@]}" "${sed_subs[@]}" {} +
  echo "Done."

  # Remove files ending with query strings, as required
  if [ "$deploy_netlify" = "yes" ]; then
    clean_query_extensions="yes"
    echo "Cleaning file names with question marks for Netlify." "1"
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
      # Search for credentials based on $site_user and $domain,
      # assuming they are defined on a single line with space-separated values
      if [ -f "$rc_file" ]; then
        # Check to see if an entry exists (with superfluous "''" inserted to pass Shellcheck SC1087)
        cred_pattern="machine[[:blank:]]\{1,\}$domain"''"[[:blank:]]\{1,\}login[[:blank:]]\{1,\}$wget_http_user"
        replace_rc="$(grep -v "$cred_pattern" "$rc_file")"
        printf "%s\n" "$replace_rc" > "$rc_file" || echo "$msg_warning: unable to remove existing credentials"
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
        printf "%s\n" "$replace_rc" > "$rc_file" || echo "$msg_warning: unable to remove existing credentials"
        touchmod "$rc_file"
      fi
    fi
  fi

  cd "$mirror_dir" || { printf "Unable to enter %s.\nAborting.\n" "$mirror_dir"; exit; }
}

process_snippets() {
  # Create necessary directories for substitution files and snippets
  [ -d "$sub_files_path" ] || { mkdir -p "$sub_files_path"; echo "Created folders for substitute files at $sub_files_path."; }
  [ -d "$snippets_dir" ] || { mkdir -p "$snippets_dir"; echo "Created folder for snippet files at $snippets_dir."; }

  # Change to subs directory
  cd "$script_dir/$sub_dir" || { echo "$msg_error: can't access substitutes directory ($script_dir/$sub_dir)" >&2; echo "No substitutions can be made." >&2;exit 1; }

  # Create a substitutions area replicating the mirrored folder
  [ -d "$mirror_archive_dir" ] || mkdir -p "$mirror_archive_dir"

  # Replicate the mirrored folder for the host [and port]
  subs_hostport_dir="$mirror_archive_dir$hostport_dir"
  [ -d "$subs_hostport_dir" ] || mkdir -p "$subs_hostport_dir"

  # Carry out snippet substitutions:
  echo "current directory: $(pwd)" "1"
  if [ ! -f "$snippets_data_file" ]; then
    echo "$msg_warning: Unable to find snippets data file $snippets_data_file"
    echo 'Skipping substitutions'
  else
    echo "Snippets data file found at: $snippets_data_file"
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
        read -r -a strarr <<< "$line"
        src_file=${strarr[0]}
        sub_input_file=$sub_files_dir'/'$src_file
        echo -e "input file $sub_input_file" "1"

        # Create the necessary subdirectories containing modified files
        src="$subs_hostport_dir/$src_file"
        sub_input_dir="$(dirname "${sub_input_file}")"
        src_dir="$(dirname "${src}")"
        mkdir -p "$src_dir"

        # Freshen the files to be updated by copying across from the latest mirror
        echo "local source: $working_mirror_dir/$src_file copied to $sub_input_dir/" "1"
        mkdir -p "$sub_input_dir" && cp "$working_mirror_dir/$src_file" "$sub_input_dir/"

        # Loop through the snippet IDs for this file, read and apply changes for each
        # (uses the /r command to read input from a file)
        id_list=${strarr[1]}
        for i in ${id_list//,/$IFS}
        do
          id_num=$(printf "%0*d" 3 "$i")
          snippet_id="SNIPPET"$id_num
          echo "$snippet_id" "1"
          snippet_file_id=$(printf "%s" "$snippet_id" | tr '[:upper:]' '[:lower:]')
          snippet_file=$snippets_dir'/'$snippet_file_id'.html'
          start='<!--'$snippet_id'BEGIN'
          end='<!--'$snippet_id'END'
          sed -i'.original.'"$i" -e '/'"$end"'/r '"$snippet_file" -e '/'"$start"'/,/'"$end"'/d' "$sub_input_file"
        done
        (( snippets_count+=1 ))
        cp "$sub_input_file" "$src_dir"
      fi
    done < "$snippets_data_file"
  fi
  IFS=$temp_IFS # restore IFS to defaults

  if (( snippets_count==0 )); then
    echo "$msg_warning: No snippets were found."
  elif (( snippets_count==1 )); then
    echo "Processed one snippet."
  else
    echo "Processed $snippets_count snippets."
  fi

  # Copy any snippets across to mirror
  if [ "$snippets_count" != 0 ]; then
    snippets_src="$script_dir/$sub_dir/$subs_hostport_dir"
    dest="$working_mirror_dir"
    echo "Copying from: $snippets_src" "1"
    echo "To: $dest" "1"
    cp -r "$snippets_src/." "$dest/." || { printf ".\n%s: Unable to copy the snippets to the mirror.\n" "$msg_error"; }
  fi

  cd "$script_dir" || echo "$msg_warning: cannot change directory to $script_dir."
}

#  If Wget --cut-dirs not specified, then move top-level index.html to root directory.
cut_mss_dirs() {
  if [ "$url" = "$url_base/" ]; then
    echo "$msg_info: You have specified mss_cut_dirs to cut directories, but this is only effective for a URL with a directory path. No action taken."
    return 0
  fi
  if [ "$cut_dirs" != "0" ]; then
    return 0
  fi
  cd "$working_mirror_dir" || { printf "Unable to enter %s.\nAborting.\n" "$working_mirror_dir"; exit; }
  dir_path="$working_mirror_dir/$url_path"
  mv "$dir_path/"* "$working_mirror_dir/"
  echo "Moved files and folders from $dir_path to $working_mirror_dir/." "1"
  # remove top-level folder of $url_path
  url_root_dir=$(echo "$url_path" | cut -d/ -f1)
  if [ -d "$url_root_dir" ]; then
    rm -rf "$url_root_dir"
  fi
}

create_zip() {
  cd "$mirror_dir" || { printf "%s: Unable to enter directory %s.\nSkipping the creation of the zip file.\n" "$msg_error" "$mirror_dir"; return; }
  echo "Creating a ZIP archive ... "
  if [ -f "$zip_archive" ]; then
    zip_backup="$zip_archive.backup"
    mv "$zip_archive" "$zip_backup" || echo "$msg_warning: unable to create a backup for $zip_archive"
    echo "Backed up $zip_archive to $zip_backup" "1"
  fi
  zip_options="-q -r $zip_archive $mirror_archive_dir"
  zip_omit_download=$(yesno "$zip_omit_download")
  [ "$zip_omit_download" = "yes" ] && zip_options+=" -x $mirror_archive_dir$hostport_dir/$zip_download_folder/*" 
  IFS=" " read -r -a zip_options_all <<< "$zip_options"
  zip "${zip_options_all[@]}"
  cd "$script_dir"
  echo "ZIP archive created at $mirror_dir/$zip_archive."
}

deploy_on_netlify() {
  echo "Deploying on Netlify ... "

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
      echo "$msg_error: Failed to deploy to Netlify."
    fi
  fi
  echo
}

prep_rsync() {
  echo "Deploying on a remote server using rsync over ssh ... "

  # Test network connection to remote server host using netcat
  if ! nc -w2 -z "$deploy_host" "$deploy_port"; then
    echo "Unable to connect to the remote server, $deploy_host, on port $deploy_port, needed for rsync."
    echo "Use of rsync aborted."
    echo "Static archive created, but not deployed remotely using rsync."
    echo "$msg_signoff"
    exit
  else
    dest=$deploy_user'@'$deploy_host':'$deploy_path'/'
    echo "Sync to remote server"
  fi
}

deploy() {
  cd "$working_mirror_dir" || { printf "Unable to enter %s.\nAborting.\n" "$working_mirror_dir"; exit; }

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

  echo "Done."
  cd "$script_dir" || echo "$msg_warning: cannot change directory to $script_dir."

  # Copy zip file into site uploads folder, ready for deployment
  mkdir -p "$working_mirror_dir/$zip_download_folder"
  local_dest="$working_mirror_dir/$zip_download_folder/$zip_filename"
  if [ "$upload_zip" = "yes" ]; then
    cp "$mirror_dir/$zip_archive" "$local_dest" || { echo "$msg_error: can't copy zip archive into the site uploads area, $local_dest" >&2; exit 1; }
  fi

  cmd_check "rsync" "1" || { printf "%s: The rsync command is not available.\nCheck that it is installed and is within PATH.\nAborting.\n" "$msg_error"; exit; }

  src="$working_mirror_dir"
  comment_status=0   # Host entry commented out? (0 for no, 1 for yes)
  toggle_flag=0      # Has status been toggled?  (0 for no, 1 for yes)

  # if source and deployment domains are the same, then call Hosts function
  if [ "$deploy_host" = "$domain" ]; then
    echo "NOTICE: Your source and deployment domains are the same."
    # Check /etc/hosts - if it exists, search for the domain and then offer choice ...
    if [ -f "$etc_hosts" ]; then
      hosts_toggle
    else
      echo "However, you do not appear to have an entry in $etc_hosts."
      # Check whether paths are the same
      echo "Source site path: $site_path"
      echo "Deployment path: $deploy_path"
      [ "$site_path" != "$deploy_path" ] && echo "The paths appear to be distinct, so deployment should not overwrite" || echo "$msg_warning: The paths appear to be the same - about to overwrite the source folder with the static mirror!"
      confirm_continue
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
    echo "Deploying locally, using 'cp' command ... "
    dest="$deploy_path"
    echo "From: $src/"
    echo "To: $dest"
    mkdir -p "$dest"
    cp -r "$src/." "$dest/." || { echo "$msg_error: unable to make the copy."; msg_deploy="The site was not deployed locally."; }
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
  printf "Completed in "; stopclock SECONDS
  msg_done=$(msg_ink "ok" 'All done.')
  printf "%s\nA static mirror of %s has been created in %s\n" "$msg_done" "$url" "$working_mirror_dir"
  if [ -n "${msg_deploy+x}" ]; then
    printf "%s\n\n" "$msg_deploy"
  fi
  printf "\nThank you for using MakeStaticSite, free software released under the %s. The latest version is available from %s.\n" "$mss_license" "$mss_download"
  echo " "
  timestamp_end=$(timestamp "$timezone")
  printf "%s\n" "$msg_signoff" >> "$log_file"
  printf "Timestamp: %s\n\n" "$timestamp_end" >> "$log_file"
}

################# END OF FUNCTIONS ################

# Run the script
main "$@"
