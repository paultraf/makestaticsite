#!/usr/bin/env bash

##########################################################################
#
# MakeStaticSite --- a shell script to create and deploy static websites
# Copyright 2022-2023 Paul Trafford <pt@ptworld.net>
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

source "lib/constants.sh"  # load constants, particularly runtime defaults
source "lib/general.sh"    # load general functions library
source "lib/validate.sh"   # load the validation functions library
source "lib/config.sh";    # load the config functions library

main() {
  # Phase 0: Initialisation
  whichos
  initialise_layout
  read_config "$@"
  initialise_variables

  # Phase 1: Prepare the CMS
  (( phase < 2 )) && (( end_phase >= 1 )) && prepare_static_generation

  # Phase 2: Generate a static mirror using Wget
  (( phase < 3 )) && (( end_phase >= 2 )) && wget_mirror

  # Phase 3: Augment the static site
  (( phase < 4 )) && (( end_phase >= 3 )) && [ "$wget_extra_urls" = "yes" ] && wget_extra_urls

  # Phase 4: Refine the static site
  (( phase < 5 )) && (( end_phase >= 4 )) && [ "$wget_post_processing" = "yes" ] && { wget_postprocessing; }

  # Phase 5: Further additions from an extras folder
  (( phase < 6 )) && (( end_phase >= 5 )) && [ "$add_extras" = "yes" ] && add_extras

  # Phase 6: Optimise the mirror
  (( phase < 7 )) && (( end_phase >= 6 )) && clean_mirror;

  # Phase 7: Use snippets
  (( phase < 8 )) && (( end_phase >= 7 )) && [ "$use_snippets" = "yes" ] && process_snippets

  # Phase 8: Create an offline zip archive
  (( phase < 9 )) && (( end_phase >= 8 )) && [ "$upload_zip" = "yes" ] && create_zip || echo "Creation of ZIP archive skipped, as per preferences." "1"

  # Phase 9: Deploy
  (( end_phase >= 9 )) && [ "$deploy" = "yes" ] && deploy || echo "Runtime option for deployment set to 'no'; deployment skipped."

  # Phase 10: Finish
  conclude
}
################## END OF STEPS ###################


###################################################
#                Support functions
###################################################

initialise_layout() {
  # Local context - this directory
  script_dir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"

  # Set up temporary directory
  tmp_dir_path="$script_dir/$tmp_dir"
  [ -d "$tmp_dir_path" ] || mkdir -p "$tmp_dir_path"
  tmp_mirror_path="$script_dir/$tmp_dir/mirror"
  [ -d "$tmp_mirror_path" ] || mkdir -p "$tmp_mirror_path"

  # Set up logging
  log_file_dir="$script_dir/log"
  [ -d "$log_file_dir" ] || mkdir -p "$log_file_dir"
  log_file="$log_file_dir/$log_filename"
  touch "$log_file"

  # Local target directory and web server deployment
  mirror_dir="$script_dir/mirror"         # path to Wget output root folder

  # Substitute files for zip download (used for embeds, etc.)
  sub_dir='subs'                          # This must be sit under $script_dir
  sub_files_dir='files'                   # This must be sit under $sub_dir
  sub_files_path="$script_dir/$sub_dir/$sub_files_dir"

  snippets_dir=$script_dir'/snippets'     # directory storing snippets (.html files)
  snippets_data_file="$snippets_dir/snippets.data" # list of directories/files relative to
                                          # zip root inside the $sub_files_dir 
                                          # (separated by space)
                                          # Default is just the home page
                                          # Script will generate this dynamically
                                          # using this data file where each row is
                                          # path_to_html_file:<list of snippet ids>

  msg_done=$'All done!\n'

  if [ "$log_level" = "silent" ]; then
    exec 2>/dev/null
  else
    exec 2> >(tee -a "$log_file" >&2) # additionally, append stderr to logfile
  fi

  # If output_level is silent, then don't echo anything to the terminal
  if [ "$output_level" = "silent" ]; then
    exec 1>/dev/null
  fi

  return 0
}

read_config() {
  local run_params="$*"
  myconfig=default
  phase=0
  end_phase=$max_phase_num
  mirror_archive_dir=
  mirror_id_flag=off # flag to denote whether or not -m option set

  local OPTIND
  while getopts ":i:p:q:m:vh" option; do
    case "${option}" in
      i)
        myconfig="${OPTARG}"
        ;;
      m)
        mirror_archive_dir="${OPTARG}"
        mirror_id_flag=on
        ;;
      p)
        phase="${OPTARG}"
        ;;
      q)
        end_phase="${OPTARG}"
        ;;
      v)
        echo "$version_header"
        exit
        ;;
      h)
        echo "$version_header"
        echo "Usage: ./makestatic.sh [OPTIONS]"
        echo
        echo "Allowable options are:"
        echo " -i FILENAME        Input configuration file."
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
        echo " -i FILENAME        Input configuration file."
        echo " -p NUMBER          Run from phase NUMBER (default is 0, start)."
        echo " -q NUMBER          End at phase NUMBER (default is 9, end)."
        echo " -m MIRROR_ID       Use mirror with identifier MIRROR_ID."
        echo " -v                 Display MakeStaticSite version number."
        echo " -h                 Display help."
        echo "Please try again."
        exit
      ;;
    esac
  done
  shift $((OPTIND-1))

  echo "Welcome to MakeStaticSite version $version"
  echo "Running with command line options: $run_params" 1>/dev/null
}

initialise_variables() {
  myconfig=${myconfig/.cfg/}

  # Check for configuration file
  check_config_file "$myconfig"

  # Read phase details
  validate_range 0 "$max_phase_num" "$phase" || { echo "Sorry, the phase number is out of range (it should be between 0 and $max_phase_num).  Please try again."; exit; }

  # Read phase details
  validate_range 1 "$max_phase_num" "$end_phase" || { echo "Sorry, the phase number for exiting the program is out of range (it should be between 1 and $max_phase_num).  Please try again."; exit; }

  ((phase>end_phase)) && { echo "$msg_error: The (start) phase number cannot be greater than the end phase number."; echo "Please rerun the program."; exit; }

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
       cd "$mirror_dir" || { echo "unable to enter directory $mirror_dir."; echo "Aborting."; exit; }
       pwd
       sh -c "ls -d */ | sed 's/\///'"
       echo "Please choose one from the list and rerun with -m option."
       cd "$script_dir" || { echo "unable to enter directory $script_dir."; echo "Aborting."; }
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
    myconfig=$(env echo "$mirror_archive_dir" | sed "s/20[[:digit:]]\{6\}_[[:digit:]]\{6\}$//")
  fi

  echo -n "Reading custom configuration data from config/$myconfig.cfg ... "

  # Define a timestamp function
  if [ "$timezone" != "utc" ]; then
    timestamp=$(date "+%Y%m%d_%H%M%S")
    if [ "$timezone" = "utclocal" ]; then
      timestamp+=$(date +"%z")
    fi
  else
    timestamp=$(TZ=UTC date "+%Y%m%d_%H%M%S")"Z"
  fi

  # Translate to output levels for rsync and Wget respectively
  if [ "$output_level" = 'silent' ] || [ "$output_level" = 'quiet' ]; then
    rvol="-q"; wvol="-q"; wpvol="--quiet"
  elif [ "$output_level" = 'verbose' ]; then
    rvol="-v"; wvol=""; wpvol="--debug"
  else
    rvol=""; wvol="-nv"; wpvol=""
  fi

  add_search=$(yesno "$(config_get add_search "$myconfig")")
  deploy=$(yesno "$(config_get deploy "$myconfig")")
  deploy_remote=$(yesno "$(config_get deploy_remote "$myconfig")")
  use_snippets=$(yesno "$(config_get use_snippets "$myconfig")")
  snippets_count=0
  upload_zip=$(yesno "$(config_get upload_zip "$myconfig")")

  # Check system requirements for cURL, Wget and SSL
  msg_checking="Checking your system for Wget and other essential components ... "
  cmd_check "curl" || { echo -n "$msg_checking"; printf "%s: Unable to find binary: curl ("'$'"PATH contains %s).\nThis command is essential for checking connectivity.  It may be downloaded from https://curl.se/.\nAborting.\n" "$msg_error" "$PATH"; exit; }
  cmd_check "$wget_cmd" "1" || { printf "%s: Unable to carry out a snapshot\nPlease review the value of the wget_cmd option.\nAborting.\n" "$msg_error"; exit; }
  echo "OK" "1"
  wget_cmd_version="$(which_version "$wget_cmd" "GNU Wget")"
  version_check "$wget_cmd_version" "$wget_version_atleast" || { echo "$msg_checking";  printf "%s. The version of %s is %s, which is old, so some functionality may be lost.  Version %s or later is recommended.\n" "$msg_warning" "$wget_cmd" "$wget_cmd_version" "$wget_version_atleast";}
  ssl_checks=$(yesno "$(config_get ssl_checks "$myconfig")")
  [ "$ssl_checks" = "no" ] && wget_ssl="--no-check-certificate" || wget_ssl=''

  # Options to support Wget
  input_urls_file="$(config_get input_urls_file "$myconfig")"
  wget_extra_urls=$(yesno "$(config_get wget_extra_urls "$myconfig")")
  wget_post_processing=$(yesno "$(config_get wget_post_processing "$myconfig")")
  archive=$(yesno "$(config_get archive "$myconfig")")
  wget_input_files=()  # Initialise array of additional Wget input URLs
  wget_extra_options_tmp=$(wget_canonical_options "$(config_get wget_extra_options "$myconfig")")

  # Ensure that login pages are rejected, i.e. ensure we have --reject *login*,*logout*
  # Append Wget --reject clause
  grep_clause="\-R[[:space:]][^[:space:]]*\|\-\-reject[[:space:]][^[:space:]]*"
  rmatch0=$({ env echo "$wget_extra_options_tmp" | grep -o "$grep_clause"; } || echo )
  if [ "$rmatch0" = "" ]; then
    rmatch="$rmatch0"
    vmatch="$wget_extra_options_tmp"
  else
    rmatch=${rmatch0//\*/\\*}
    vmatch=$(env echo "$wget_extra_options_tmp" | sed 's/'"$rmatch"'//')
  fi
  wget_plus_ops=$(env echo "$vmatch" | xargs)
  if [[ ! "$rmatch0" =~ "-R " ]] && [[ ! "$rmatch0" =~ "--reject " ]]; then
    wget_plus_ops+=" -R $wget_reject_clause"
  else
    wget_plus_ops="$wget_plus_ops $rmatch0,$wget_reject_clause"
  fi
  IFS=" " read -r -a wget_extra_options <<< "$wget_plus_ops"

  # Hide http basic authentication password
  IFS=" " read -r -a wget_extra_options_print <<< "$(env echo "$wget_plus_ops" | sed "s/password[[:space:]][^[:space:]]*/password *********/")"

  # If $wget_plus_ops contains '--spider' then don't deploy, use snippets or postprocess
  [[ "$wget_plus_ops" == *"--spider"* ]] && { use_snippets="no"; wget_extra_urls="no"; wget_post_processing="no"; }

  htmltidy=$(yesno "$(config_get htmltidy "$myconfig")")
  add_extras=$(yesno "$(config_get add_extras "$myconfig")")

  # Web server details (to be snapped by Wget)
  url="$(config_get url "$myconfig")"
  url_domain=$(env echo "$url" | awk -F/ '{print $3}' | awk -F: '{print $1}')

  # For backwards-compatibility check whether URL defined instead in url_base
  if [ "$url_domain" = "example.com" ]; then
    url="$(config_get url_base "$myconfig")"
    if [ "$url" = "" ]; then { echo; echo "$msg_error: the URL supplied in $myconfig (example.com) needs to be changed!"; echo "Aborting."; exit; }
    fi
  fi

  # Extract the host (domain or IP) and port, protocol, and hence the URL base (no path)
  hostport=$(env echo "$url" | awk -F/ '{print $3}')
  domain=$(env echo "$hostport" | awk -F: '{print $1}')
  protocol=$(env echo "$url" | awk -F/ '{print $1}' | awk -F: '{print $1}')
  url_base="$protocol://$hostport"
  login_address="$url_base$login_path"
  require_login=$(yesno "$(config_get require_login "$myconfig")")
  [ "$require_login" = "yes" ] && { site_user="$(config_get site_user "$myconfig")"; site_password="$(config_get site_password "$myconfig")"; }

  # WP-CLI (or other CMS client) options, including source (server), as appropriate
  wp_cli=$(yesno "$(config_get wp_cli "$myconfig")")
  site_path="$(config_get site_path "$myconfig")"

  # Local snapshot label
  local_sitename="$(config_get local_sitename "$myconfig")"

  # Path of the mirror archive, if archive directory is already defined
  [ "$mirror_archive_dir" != "" ] && working_mirror_dir=$mirror_dir'/'$mirror_archive_dir'/'$hostport && zip_archive=$mirror_archive_dir'.zip'

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
}

prepare_static_generation() {
  echo "Starting the static site generation ..."
  echo "Will capture snapshot from $url using $wget_cmd."

  # Prepare WordPress site for static archive, if applicable
  if [ "$wp_cli" = "yes" ]; then
    wp_cli_remote=$(yesno "$(config_get wp_cli_remote "$myconfig")")
    source_host="$(config_get source_host "$myconfig")"
    source_protocol="$(config_get source_protocol "$myconfig")"
    source_port="$(config_get source_port "$myconfig")"
    source_user="$(config_get source_user "$myconfig")"
    source "lib/mod_wp.sh";
    wp_prep
  fi

  return 0
}

wget_error_codes() {
  echo "Done."
  case "$1" in
    "8")
      printf "%s: Wget ERROR code 8, i.e. the Web server gave an error on retrieving at least one file, probably HTTP 404 (file not found - possibly specified in the input file).  Less likely is a 500 (internal server error), which in the case of a CMS might be due to a plugin or module. " "$msg_warning";
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

wget_mirror() {
  # First, test source host is available
  local wget_test_options=(-q "$wget_ssl" --spider --tries 1 "$url_base")
  if ! $wget_cmd "${wget_extra_options[@]}" "${wget_test_options[@]}"; then
    echo "Unable to connect to $url_base.  Please check the spelling of the domain, that the web server is running and that the website exists. "
    env echo -e "GET http://google.com HTTP/1.0\n\n" | nc google.com 80 > /dev/null 2>&1 ||  echo "Also, there appears to be no Internet connectivity (tested with http://google.com)."
    echo "Aborting."
    exit
  fi

  # Create necessary directories
  [ -d "$mirror_dir" ] || { mkdir -p "$mirror_dir"; echo "Created folder for mirror files at $mirror_dir."; }

  # Input file for Wget (generated)
  input_file="$script_dir/$tmp_dir/$wget_inputs_main"
  touch "$input_file"
  env echo "$url" > "$input_file"

  # Generate the input-file option for Wget from the corresponding array.
  for opt in "${wget_input_files[@]}"; do
    env echo "$opt" >> "$input_file"
  done

  # Append user URLs inputs
  if [ "$input_urls_file" != "" ] && [ -f "$input_urls_file" ]; then
    cat "$input_urls_file" >> "$input_file"
    echo "Reading list of additional URLs to crawl from $input_urls_file."
  fi

  # Wget configuration and its outputs
  input_options="--input-file=$input_file"

  if [ "$mirror_archive_dir" = "" ]; then
    mirror_archive_dir="$local_sitename"
    [ "$archive" = "yes" ] && mirror_archive_dir+="$timestamp"
    working_mirror_dir=$mirror_dir'/'$mirror_archive_dir'/'$hostport
    zip_archive=$mirror_archive_dir'.zip'
  fi

  # Overwrite an existing mirror only if the -m and wget_refresh_mirror flags are unset 
  # and then only after run_unattended flag set or consent given
  if [ "$mirror_id_flag" = "off" ] && [ "$wget_refresh_mirror" = "yes" ]; then
    [ -d "$working_mirror_dir" ] && echo "$msg_warning: $working_mirror_dir already exists.";
    confirm=Y
    if [ "$run_unattended" != "yes" ]; then
      read -r -e -p "Do you wish to delete and recreate $working_mirror_dir (y/n)? " confirm
      confirm=${confirm:0:1}
      echo -n "OK. "
    fi
    if [ "$confirm" = "y" ] || [ "$confirm" = "Y" ]; then
      rm -rf "$working_mirror_dir"
    fi
  fi

  msg_mirror_start="Creating a mirror of $url in $working_mirror_dir ... "
  wget_options=("$wget_ssl" --directory-prefix "$mirror_archive_dir" "$input_options")

  cookies_path="$tmp_dir_path/$wget_cookies"
  cookies_tmppath="$tmp_dir_path/tmp$wget_cookies"
  wget_login_options=("$wget_ssl" --directory-prefix "$tmp_mirror_path" --save-cookies "$cookies_path" --keep-session-cookies "$login_address" --delete-after)

  url_robots="$url/robots.txt"
  wget_robot_options=("$wget_ssl" --directory-prefix "$mirror_archive_dir/$hostport" "$url_robots")
  wget_sitemap_options=("$wget_ssl" --directory-prefix "$mirror_archive_dir/$hostport")

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

  if [ "$wget_user_agent" != "" ];then
    wget_core_options+=(-U "\"$wget_user_agent\"")
  fi

  # if access to site restricted then log in and fetch cookie as required
  if [ "$require_login" = "yes" ]; then

    # Now log in with supplied credentials
    wget_credentials=(--post-data="${login_user_field}=${site_user}&${login_pwd_field}=${site_password}&testcookie=1")
    echo -n "Logging in to the site at $login_address using credentials: ${login_user_field}=${site_user}&${login_pwd_field}=******* ${wget_login_options[*]} ... "
    $wget_cmd "${wget_credentials[@]}" "${wget_extra_options[@]}" "${wget_login_options[@]}"

    # Determine whether login has succeeded by checking cookies file for addition
    cookie_match=$(awk '$6 ~ /'"$cookie_session_string"'/' "$cookies_path")
    if [ "$cookie_match" == "" ]; then
      env echo
      env echo -n "$msg_error: Unable to identify a login/session cookie in the generated cookie file, $cookies_path.  Please check the username and password in $myconfig.cfg"
      if [ "$cookie_session_string" = "" ]; then
        echo " and to avoid this prompt, define the cookie_session_string in constants.sh."
      else
        echo ", and also the value of cookie_session_string in constants.sh."
      fi
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

  ####################
  # Main run of Wget #
  ####################
  echo -n "$msg_mirror_start"
  cd "$mirror_dir" || { echo; echo "$msg_error: can't access working directory for the mirror ($mirror_dir)" >&2; exit 1; }

  error_set +e  # override because error traps set specially for Wget
  if [ "$robots_create" != "yes" ]; then
    # Check for robots.txt file (will store in mirror directory as they are part of the crawl)
    if ! $wget_cmd "${wget_extra_options[@]}" "${wget_robot_options[@]}"; then
      echo " "; echo "$msg_warning: Wget reported an error trying to retrieve the robots.txt file (likely not found).  Search engines expect this, so have made a note to create it."
      robots_create=yes
    elif sitemap_line=$(grep "^[[:space:]]*Sitemap:" "$mirror_archive_dir/$hostport/robots.txt"); then
      # read contents of robots.txt, checking for sitemap
      sitemap=$(env echo "$sitemap_line" | grep -o 'http[s]*:\/\/.*.xml')
      $wget_cmd "${wget_extra_options[@]}" "${wget_sitemap_options[@]}" "$sitemap"
      # Wget any nested sitemaps
      wget_sitemap_options+=("$sitemap" --output-document -)
      $wget_cmd "${wget_extra_options[@]}" "${wget_sitemap_options[@]}" | grep -o "http[s]*://[^<]*.xml" | $wget_cmd "${wget_extra_options[@]}" --quiet "$wget_ssl" --directory-prefix "$mirror_archive_dir/$hostport" -i -
    else
      echo " "; echo "$msg_warning: No sitemap found in robots.txt. Search engines expect this, so have made a note to generate one."
      sitemap_create=yes
    fi
  fi

  $wget_cmd "${wget_core_options[@]}" "${wget_extra_options[@]}" "${wget_options[@]}"
  wget_error_codes "$?"
  error_set -e
  msg_done+="A static mirror of $url has been created in $working_mirror_dir"
  msg_done+=$'\n'
}

# (A placeholder for) post-Wget review and analysis
post_wget_checks() {
  echo
}

# Augment Wget's snapshot by retrieving missed URLs
# (this needs to be done before wget_postprocessing)
# We use Wget instead of cURL to avoid repeated overwrites -
# target files are not expected to change during this site generation
wget_extra_urls() {
  cd "$mirror_dir" || { echo "Unable to enter $mirror_dir."; echo "Aborting."; exit; }
  echo -n "Searching for additional URLs to retrieve with Wget (working in $working_mirror_dir) ... "
  webassets_all=()
  while IFS='' read -r line; do webassets_all+=("$line"); done < <(grep -Eroh "$url_base/[^\"'< ]+" "$working_mirror_dir" --include "*\.html")

  # Return if empty (nothing further found)
  [ ${#webassets_all[@]} -eq 0 ] && { echo "None found. " "1"; echo "Done."; return 0; }
  [ "$output_level" != "quiet" ] && echo " "

  # Pick out unique items
  echo "Pick out unique items" "1"
  webassets_unique=()
  while IFS='' read -r line; do webassets_unique+=("$line"); done < <(for item in "${webassets_all[@]}"; do env echo "${item}"; done | sort -u)

  # Filter out all items not starting http
  echo "Filter out all items not starting http" "1"
  webassets_http=()
  while IFS='' read -r line; do webassets_http+=("$line"); done < <(for item in "${webassets_unique[@]}"; do if [ "${item:0:4}" = "http" ]; then env echo "${item}"; else continue; fi; done)
  [ ${#webassets_http[@]} -eq 0 ] && { echo "None found. " "1"; echo "Done."; return 0; }

  # Filter out web pages and newsfeeds (limit to non-HTML assets, such as images and JS files)
  echo "Filter out web pages and newsfeeds (limit to non-HTML assets, such as images and JS files)" "1"
  webassets_nohtml=()
  while IFS='' read -r line; do webassets_nohtml+=("$line"); done < <(for opt in "${webassets_http[@]}"; do type=$(curl -skI "$opt" -o/dev/null -w '%{content_type}\n'); if [[ "$type" != *"text/html"* ]] && [[ "$type" != *"application/rss+xml"* ]] && [[ "$type" != *"application/atom+xml"* ]]; then env echo "$opt"; fi; done)
  [ ${#webassets_nohtml[@]} -eq 0 ] && { echo "None found. " "1"; echo "Done."; return 0; }
  if [ "${wget_extra_options[*]}" != "" ]; then
    url_bas="$protocol://$hostport"
    # Filter out URLs whose paths match an excluded directory (via subloop)
    echo "Filter out URLs whose paths match an excluded directory (via subloop)" "1"
    # We assume that grep works as expected, but should really trap exit code 2
    exclude_dirs=$(env echo "$wget_plus_ops"| grep -o "\-X[[:space:]]*[[:alnum:]/,\-]*" | grep -o "/.*"; exit 0)
    temp_IFS=$IFS; IFS=","; exclude_arr=("$exclude_dirs"); IFS=$temp_IFS
    if [ ${#exclude_arr[@]} -eq 0 ]; then
      webassets_omissions=("${webassets_nohtml[@]}")
    else
      webassets_omissions=()
      while IFS='' read -r line; do webassets_omissions+=("$line"); done < <(for opt in "${webassets_nohtml[@]}"; do path="${opt/$url_bas/}"; for exclusion in "${exclude_arr[@]}"; do [ "$path" = "$exclusion" ] || [[ $path =~ ^$exclusion/.* ]] && continue 2; done; env echo "$opt"; done)
    fi
  else
    webassets_omissions=("${webassets_nohtml[@]}")
  fi

  # Return if empty (nothing further found)
  [ ${#webassets_omissions[@]} -eq 0 ] && { echo "None found. " "1"; echo "Done."; return 0; }

  # Filter out URLs with query strings
  echo "Filter out URLs with query strings" "1"
  webassets=()
  while IFS='' read -r line; do webassets+=("$line"); done < <(for opt in "${webassets_omissions[@]}"; do if [[ "$opt" != *"?"* ]]; then env echo "$opt"; else continue; fi; done)

  # Return if empty (all those found were filtered out)
  [ ${#webassets[@]} -eq 0 ] && { echo "None suitable found. " "1"; echo "Done."; return 0; }

  # Input file for Wget (generated)
  input_file_extra="$script_dir/$tmp_dir/$wget_inputs_extra"
  touch "$input_file_extra"
  printf "%s\n" "${webassets[@]}" > "$input_file_extra"
  echo "Done."

  wget_asset_options=("$wget_ssl" --directory-prefix "$mirror_archive_dir"  --input-file="$input_file_extra")

  if [ "$wvol" = "-q" ] && [ "$log_level" != "silent" ]; then
    wget_asset_options+=(-a "$log_file")
  else
    wget_extra_core_options+=("$wvol")
  fi

  echo "Running Wget on these additional URLs with options: " "${wget_extra_core_options[@]}" "${wget_extra_options[@]}" "${wget_asset_options[@]}"

  error_set +e
  $wget_cmd "${wget_extra_core_options[@]}" "${wget_extra_options[@]}" "${wget_asset_options[@]}"
  wget_error_codes "$?"
  error_set -e
}

# Carry out further processing of output
wget_postprocessing() {
  cd "$working_mirror_dir" || { echo "Unable to enter $working_mirror_dir."; echo "Aborting."; exit; }
  echo -n "Carrying out post-Wget processing in $working_mirror_dir ... "

  # Convert remaining absolute paths to relative paths
  webpages=()
  while IFS='' read -r line; do webpages+=("$line"); done < <(grep -Erl "$url_base/[^\"' ]+" . --include "*\.html")

  if [ ${#webpages[@]} -eq 0 ]; then
    echo "No pages to process.  Done." "1"
    return 0
  fi

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
    sed_subs1=('s~http://'"$hostport/"'~'"$pathpref"'~g' "$opt")
    sed_subs2=('s~https://'"$hostport/"'~'"$pathpref"'~g' "$opt")
    sed "${sed_options[@]}" "${sed_subs1[@]}"
    sed "${sed_options[@]}" "${sed_subs2[@]}"
  done
  echo "Done."

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
        sed_subs=('s~'"$domain"'~'"$deploy_domain"'~g')
        echo -n "Replacing remaining occurrences of $domain with $deploy_domain ... "
        if [ "$ostype" = "BSD" ]; then
          find . -type f \( -name '*.html' -o -name '*.xml' -o -name '*.txt' \) -print0 | xargs -0 sed -i '' 's~'"$domain"'~'"$deploy_domain"'~g'
        else
          find . -type f \( -name '*.html' -o -name '*.xml' -o -name '*.txt' \) -print0 | xargs -0 sed -i 's~'"$domain"'~'"$deploy_domain"'~g'
        fi
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
  echo -n "Converting feed files and references from index.html to index.xml ... "
  find ./ -depth -type f -path "*feed/index.html" -exec sh -c 'mv "$1" "${1%.html}.xml"' _ '{}' \;

  webpages=()
  while IFS='' read -r line; do webpages+=("$line"); done < <(grep -Erl "$feed_html" . --include "*\.html")

  if (( ${#webpages[@]} )); then
    for opt in "${webpages[@]}"; do
      sed_subs=('s~'"$feed_html"'~'"$feed_xml"'~g' "$opt")
      sed "${sed_options[@]}" "${sed_subs[@]}"
    done
  fi
  echo "Done."

  sed_subs1=('s/href="http:\/\/'"${deploy_domain}"'/href="https:\/\/'"${deploy_domain}"'/g')
  sed_subs2=("s/href='http:\/\/${deploy_domain}/href='https:\/\/${deploy_domain}/g")
  if [ "$protocol" = "https" ] && [ "$force_ssl" = "yes" ]; then
    echo -n "Updating anchors for $deploy_domain from http: to https: ... "
    find . -type f -name '*.html' -print0 | xargs -0 sed "${sed_options[@]}" "${sed_subs1[@]}"
    find . -type f -name '*.html' -print0 | xargs -0 sed "${sed_options[@]}" "${sed_subs2[@]}"
    echo "Done."
  fi

  cd "$mirror_dir" || { echo "Unable to enter $mirror_dir."; echo "Aborting."; exit; }
}

add_extras() {
  # For archival, copy subs files into the respective Wget mirror directory
  extras_src="$script_dir/$extras_dir/$hostport/"
  echo -n "Copying additional files from $extras_src to the static mirror (for distribution) ... "

  # Create necessary directories
  if [ ! -d "$extras_src" ]; then
    echo; read -r -e -p "The folder for extra files, $extras_src, doesn't exist.  Do you wish it to be created(y/n)? " confirm
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

  extras_dest="$working_mirror_dir/"
  [ "$rvol" != "" ] && rsync_options+=("$rvol")
  error_set +e

  # First, try with rsync, otherwise use cp, to make the copy
  if ! rsync "${rsync_options[@]}" "$extras_src" "$extras_dest"; then
    echo -n "$msg_error: there was a problem running rsync.  Using 'cp' command ... "
    cp -r "$extras_src" "$extras_dest" || { printf "%s: copy failed.\n" "$msg_error"; return; }
  fi
  error_set -e
  echo "Done."
}

clean_mirror() {
  cd "$working_mirror_dir" || { echo "Unable to enter $working_mirror_dir."; echo "Aborting."; exit; }

  # reconstruct the canonical URL and replace index.html, the default output from Wget
  url_base_deploy="$protocol://$deploy_domain"
  echo -n "Updating canonical URLs in document headers ... "
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
  html_errors_file="$script_dir/$tmp_dir/${htmltidy_errors_file}"
  if [ "$htmltidy" = "yes" ]; then
    if ! cmd_check "$htmltidy_cmd" "1"; then
      printf "Unable to run HTML Tidy (htmltidy_cmd is set to %s) - please check that it is installed according to instructions at https://www.html-tidy.org/. Skipping.\n" "$htmltidy_cmd";
    else
      echo -n "Running HTML Tidy on html files with options ${htmltidy_options[*]} ... "
      htmltidy_options+=(-f "$html_errors_file")
      while IFS= read -r -d '' fname
      do
        $htmltidy_cmd "${htmltidy_options[@]}" "$fname"
      done <   <(find . -type f -name "*.html" -print0)
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

    # access logout (or any) page with expired cookie -
    # should receive HTTP Error: 403 (Forbidden)
    wget_options_logout=(--spider "$wget_ssl" --directory-prefix "$mirror_archive_dir" "$url_base$logout_path")
    $wget_cmd "${wget_extra_options[@]}" "${wget_options_logout[@]}"
    # Delete cookies
    rm "$cookies_path"
  fi

  # create robots file, where necessary
  if [ "$robots_create" = "yes" ]; then
    robots_path="$mirror_dir/$mirror_archive_dir/$hostport/robots.txt"
    touch "$robots_path"
    echo "$robots_default" > "$robots_path"
    echo $'\n'"Sitemap: https://$deploy_domain/$sitemap_file"$'\n'>> "$robots_path"
  fi

  # create sitemap, where necessary
  if [ "$sitemap_create" = "yes" ]; then
    sitemap_path="$mirror_dir/$mirror_archive_dir/$hostport/sitemap.xml"
    touch "$sitemap_path"
    sitemap_content="$(sitemap_header)";
    sitemap_loc_files=()
    while IFS='' read -r line; do sitemap_loc_files+=("$line"); done < <(find . -type f -name "*.html")

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
  echo -n "Wrap lines that end in '=' ... "
  sed_subs=(-e ':a' -e 'N' -e '$!ba' -e 's/=[\r\n][\r\n]*[[:space:]]*/=/g')
  find . -type f -name "*.html" -exec sed "${sed_options[@]}" "${sed_subs[@]}" {} +
  # and ensure that the title is on one line
  sed_subs=(-e ':a' -e 'N' -e '$!ba' -e 's/[\r\n][\r\n]*[[:space:]]*\([^<]*<\/title>\)/ \1/g')
  find . -type f -name "*.html" -exec sed "${sed_options[@]}" "${sed_subs[@]}" {} +
  echo "Done."
  
  cd "$mirror_dir" || { echo "Unable to enter $mirror_dir."; echo "Aborting."; exit; }
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
  hostport_dir=$mirror_archive_dir'/'$hostport
  [ -d "$hostport_dir" ] || mkdir -p "$hostport_dir"

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
        tag=$(env echo "$line" | awk -F '[<>]' '{print $2}')
        [ "$tag" = "$local_sitename" ] && read_data=true
        continue
      # Look for closing tag and exit loop
      elif [ "${line:1:1}" = "/" ]; then
        tag=$(env echo "$line" | awk -F '[/<>]' '{print $3}')
        read_data=false
        [ "$tag" = "$local_sitename" ] && break
      # Read data
      elif [[ "$read_data" = true ]]; then
        read -r -a strarr <<< "$line"
        src_file=${strarr[0]}
        sub_input_file=$sub_files_dir'/'$src_file
        echo -e "input file $sub_input_file" "1"

        # Create the necessary subdirectories containing modified files
        src="$hostport_dir/$src_file"
        sub_input_dir="$(dirname "${sub_input_file}")"
        src_dir="$(dirname "${src}")"
        mkdir -p "$src_dir"

        # Freshen the files to be updated by copying across from the latest mirror
        echo "local source: $working_mirror_dir/$src_file copied to $sub_input_dir/" "1"
        mkdir -p "$sub_input_dir" && cp "$working_mirror_dir/$src_file" "$sub_input_dir/"

        # loop through the snippet IDs for this file, read and apply changes for each
        # (uses the /r command to read input from a file)
        id_list=${strarr[1]}
        for i in ${id_list//,/$IFS}
        do
          id_num=$(printf "%0*d" 3 "$i")
          snippet_id="SNIPPET"$id_num
          echo "$snippet_id" "1"
          snippet_file_id=$(env echo "$snippet_id" | tr '[:upper:]' '[:lower:]')
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
    snippets_src="$script_dir/$sub_dir/$mirror_archive_dir/$hostport/"
    dest="$working_mirror_dir"
    echo "Copying from: $snippets_src" "1"
    echo "To: $dest" "1"
    cp -r "$snippets_src" "$dest" || { echo "."; echo "$msg_error: Unable to copy the snippets to the mirror."; }
  fi

  cd "$script_dir" || echo "$msg_warning: cannot change directory to $script_dir."
}

create_zip() {
  cd "$mirror_dir" || { echo "$msg_error: Unable to enter directory $mirror_dir."; echo "Skipping the creation of the zip file."; return; }
  echo "Creating a ZIP archive ... "
  if [ -f "$zip_archive" ]; then
    zip_backup="$zip_archive.backup"
    mv "$zip_archive" "$zip_backup" || echo "$msg_warning: unable to create a backup for $zip_archive"
    echo "Backed up $zip_archive to $zip_backup" "1"
  fi
  zip -q -r "$zip_archive" "$mirror_archive_dir"
  echo "ZIP archive created."
  cd "$script_dir"
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
    # Link to Netlify site name (else log in)
    netlify link --name "$deploy_netlify_name" || { netlify login; }
    # Deploy site to Netlify
    netlify_options=(deploy --dir="$working_mirror_dir" --prod)
    netlify "${netlify_options[@]}"
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
    exit
  else
    dest=$deploy_user'@'$deploy_host':'$deploy_path'/'
    echo "Sync to remote server"
  fi
}

deploy() {
  cd "$working_mirror_dir" || { echo "Unable to enter $working_mirror_dir."; echo "Aborting."; exit; }

  # Final tweaks for canonical URL links ahead of deployment
  echo -n "Updating internal anchors to conform with canonical URLs ... "
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

  src="$working_mirror_dir/"
  comment_status=0   # Host entry commented out? (0 for no, 1 for yes)
  toggle_flag=0      # Has status been toggled?  (0 for no, 1 for yes)

  # if source and deployment domains are the same, then call Hosts function
  if [ "$deploy_host" = "$domain" ]; then
    echo "NOTICE: Your source and deployment domains are the same."
    # check /etc/hosts - if it exists, search for the domain and then offer choice ...
    if [ -f "$etc_hosts" ]; then
      hosts_toggle
    else
      echo "However, you do not appear to have an entry in $etc_hosts."
      # check whether paths are the same
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
    fi
  else
    # Deploy on local server (a single instance that gets overwritten at each run)
    echo "Deploying locally:"
    dest=$deploy_path
  fi
  echo "From: $src"
  echo "To: $dest"
  rsync_src=("$src")
  rsync_dest=("$dest")

  # First, try with rsync
  [ "$rvol" != "" ] && rsync_options+=("$rvol")
  if ! rsync "${rsync_options[@]}" "${rsync_src[@]}" "${rsync_dest[@]}"; then
    echo -n "$msg_error: there was a problem running rsync"

    # Use cp as a fallback for local
    if [ "$deploy_remote" != "yes" ]; then
      echo ", using 'cp' command"
      cp -r "$src" "$dest"
    else
      echo ". Deployment failed."
    fi
  else
    msg_done+="The site has been deployed on $deploy_host, for web access at http[s]://$deploy_domain."
    msg_done+=$'\n'
  fi

  if [ "$toggle_flag" = "1" ]; then
    # invite user to restore Hosts file as it was
    read -r -e -p "The transfer is complete.  Would you like to restore $etc_hosts as it was (y/n)? " confirm
    confirm=${confirm:0:1}
    if [ "$confirm" = "y" ] || [ "$confirm" = "Y" ]; then
      [ "$comment_status" = "1" ] && entry="#$entry"
      comment_uncomment "$etc_hosts" "$entry"
    fi
  fi
}

conclude() {
  echo -n "Completed in "; stopclock SECONDS
  echo "$msg_done"
  echo "Thank you for using MakeStaticSite, free software released under the $mss_license.  The latest version is available from $mss_download."
  echo
}

################# END OF FUNCTIONS ################

# run the script
main "$@"
