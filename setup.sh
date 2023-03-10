#!/usr/bin/env bash

##########################################################################
#
# MakeStaticSite --- a shell script to create and deploy static websites
# Copyright 2022-2023 Paul Trafford <pt@ptworld.net>
#
# setup.sh - set up the config for MakeStaticSite
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

source "lib/constants.sh"  # load constants, particularly runtime options
source "lib/validate.sh"   # load the validation library functions

main() {
  # Step 0: Initialisation
  print_welcome
  init_mssconfig

  # Step 1: Read and process input
  get_configfile
  process_options

  # Step 2: Write config file
  write_config

  # Step 3: Summarise and end
  conclude
}
################ end of steps ##################


################################################
#              Support functions
################################################

which_version() {
  "$1" --version | grep "$2" | grep -o -m 1 -- "[0-9]\{1,2\}\.[0-9]\{1,2\}\(\.[0-9]\{1,2\}\)*[ \-]" | head -1 | tr -d '[:space:]-'
}

print_welcome() {
  echo "Welcome to MakeStaticSite for the generation and deployment of static websites.  This is free software released under the $mss_license, the latest version being available from ${mss_download}."
  echo
}

init_mssconfig(){
  # Check system requirements - Bash, cURL, Wget and rsync
  msg_checking="Checking your system for Wget and other essential components ... "
  bash_check
  cmd_check "curl" || { echo -n "$msg_checking"; printf "%s: Unable to find binary: curl ("'$'"PATH contains %s).\nThis command is essential for checking connectivity.  It may be downloaded from https://curl.se/.\nAborting.\n" "$msg_error" "$PATH"; exit; }
  cmd_check "$wget_cmd" || { echo -n "$msg_checking"; printf "%s: Unable to find binary: wget ("'$'"PATH contains %s)\nThis command is essential for creating the static snapshots.  Please make sure it is installed and review the value of the wget_cmd option in constants.sh.\nAborting.\n" "$msg_error" "$PATH"; exit; }
  wget_cmd_version="$(which_version "$wget_cmd" "GNU Wget")"
  version_check "$wget_cmd_version" "$wget_version_atleast" || { echo "$msg_checking";  printf "%s: The version of %s is %s, which is old, so some functionality may be lost.  Version %s or later is recommended.\n" "$msg_warning" "$wget_cmd" "$wget_cmd_version" "$wget_version_atleast";}
  cmd_check "rsync" || { echo; printf "%s: Unable to find binary: rsync ("'$'"PATH contains %s).\nThis command is essential for transferring files remotely.  It may be downloaded from https://rsync.samba.org/.\nAborting.\n" "$msg_error" "$PATH"; exit; }

  # Define a timestamp function
  # (get atomic time, but caution needed when using parameters of 'date' 
  # command as they vary between platforms)
  if [ "$timezone" != "utc" ]; then
    timestamp=$(date "+%Y-%m-%d %H:%M:%S")
    if [ "$timezone" = "utclocal" ]; then
      timestamp+=$(date +" %z")
    fi
  else
    timestamp=$(TZ=UTC date "+%Y-%m-%d %H:%M:%S")" UTC"
  fi

  # Local context
  script_dir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )" # this directory

  read -r -d '' content <<EOF || echo > /dev/null
################################################
# Configuration file for makestaticsite.sh
# generated by setup.sh
# Created: $timestamp
# Last modified: 
################################################

EOF

  content+=$'\n'$'\n'
}

get_configfile() {
  echo 'This setup script will ask a few questions to help you set up a configuration file for a single site (the script can be run any number of times to generate configs for other sites).  For each option, its label will be displayed together with some guidance. Please enter the values accordingly.'
  echo
  read -r -e -p "Please press Enter to start configuring ... " confirm
  echo
  myconfig=mydefault.cfg
  while getopts ":i:" option; do
    case ${option} in
      i)
        myconfig=$OPTARG.cfg
        echo "This configuration will be written to the file $myconfig" 1
      ;;
      : )
        # Print argument error
        echo "Invalid option: $OPTARG requires an argument" 1 1>&2
      ;;
      \? )
        # Print option error
        echo "Invalid option: $OPTARG" 1 1>&2
      ;;
    esac
  done
}

# Read options through stdin
read_option() {
  opt=$1
  case $opt in
    desc)
      opt_desc="$val"
      ;;
    info)
      opt_info="$val"
      if [ "$opt_info" != "" ]; then
        env echo "$optvar: $opt_info"
      fi
      if [ "$BASH_VERSION" -ge "4" ]; then
        if [ -n "${opt_default+x}" ] && [ "$opt_default" != "" ]; then
          input_text="-i$opt_default"
        else
          input_text=""
        fi
        input_hint=""
      else
        input_text=""
        if [ "${opt_desc: -1}" != "?" ] && [ "$opt_default" != '' ]; then
          input_hint=" (e.g., $opt_default)"
        else
          input_hint=""
        fi
      fi
      if [ "${opt_desc: -1}" = "?" ]; then
        env echo ""
        input_line="$opt_desc $input_hint"
        validate_input "$input_text" "$input_line" "$optvar"

        opt_value=${input_value::1}
        if [ "$opt_value" = "n" ]; then
          case $optvar in
            require_login)
              opt_excludes+=(site_user site_password)
              ;;
            wget_extra_urls)
              opt_excludes+=(wget_post_processing)
              ;;
            wp_cli)
              opt_excludes+=(wp_cli_remote source_host source_protocol source_port source_user site_path wp_helper_plugins add_search wp_search_plugin wp_restore_settings)
              ;;
            wp_cli_remote)
              opt_excludes+=(source_host source_protocol source_port source_user)
              ;;
            wp_helper_plugins)
              opt_excludes+=()
              ;;
            add_search)
              opt_excludes+=(wp_search_plugin)
              ;;
            wp_restore_settings)
              opt_excludes+=()
              ;;
            upload_zip)
              opt_excludes+=(zip_filename zip_download_folder)
              ;;
            deploy)
              opt_excludes+=(deploy_remote deploy_remote_rsync deploy_host deploy_port deploy_user deploy_path deploy_domain deploy_netlify deploy_netlify_name)
              ;;
            deploy_remote)
              opt_excludes+=(deploy_remote_rsync deploy_host deploy_port deploy_user deploy_netlify deploy_netlify_name)
              ;;
            deploy_rsync)
              opt_excludes+=(deploy_host deploy_port deploy_user)
              ;;
            deploy_netlify)
              opt_excludes+=(deploy_netlify_name)
              ;;
            htmltidy)
              opt_excludes+=(htmltidy_cmd htmltidy_options)
              ;;
          esac
        fi
      else
        echo
        input_line="Please enter the value for $optvar$input_hint: "
        validate_input "$input_text" "$input_line" "$optvar"
      fi
      echo

      # Print tidy output - should be able to put most # in a column
      printf -v CONFIGLINE "%-38s %s %s\n" "$optvar=$input_value" '#' "$opt_desc"
      content+="$CONFIGLINE"
      ;;
    *)
      optvar="$var"
      opt_default="$val"
      ;;
  esac

}


process_options() {
  opt_excludes=()

  for opt in "${allOptions[@]}"; do
    var=$(expr "$opt" : '\([^=]*\)'; return 0)       # Everything up to '='
    val=$(expr "$opt" : '[^=]*.\(.*\)'; return 0)    # Everything after '='
    pat='(.+)__(.+)'
    [[ $var =~ $pat ]] || option_stem=
    if [ -n "${BASH_REMATCH[1]+x}" ]; then
      option_stem=${BASH_REMATCH[1]}
    fi
    if [ "$option_stem" = "" ]; then
      option_stem="$var"
    fi
    if [ -n "${BASH_REMATCH[2]+x}" ]; then
      option_type=${BASH_REMATCH[2]}
    else
      option_type=
    fi
    if [[ ! "${opt_excludes[*]}" =~ ${option_stem} ]]; then
      read_option "$option_type"
    fi
  done
}

write_config() {
  echo "Thank you for providing the configuration options."
  echo "Here is a summary of your input:"
  echo
  echo -e "$content"
  echo
  read -r -e -p "Do you wish to write this configuration to a file (y/n)? " confirm
  confirm=${confirm:0:1}
  if [ "$confirm" = "y" ] || [ "$confirm" = "Y" ]; then
    status='0'
  else
    status='2'
  fi
  while [ "$status" = '0' ]
  do
    read -r -e -p "Please enter a filename (a .cfg extension will be added automatically): " filename

    # strip any by alphanumeric characters; should support accented letters
    cfgfilestem=$(env echo "$filename" | tr -cd '[:alnum:]._-')
    if [ "$cfgfilestem" != "$filename" ]; then
      echo "$msg_warning: only alphanumeric characters, hyphen and underscore allowed in filenames.  Have stripped out any others.  The resulting file name is $cfgfilestem.cfg"
    fi
    if [ "$cfgfilestem" = "" ];then
        echo "$msg_error: The file name cannot be empty"
        continue
    fi
    cfgfile=$cfgfilestem'.cfg'
    write_file="$script_dir/config/$cfgfile"
    if [ -f "$write_file" ]; then
      read -r -e -p "$msg_warning: The file $cfgfile already exists. Overwrite (y/n)? " confirm
      confirm=${confirm:0:1}
      if [ "$confirm" = "y" ] || [ "$confirm" = "Y" ]; then
        status='1'
      fi
    else
      status='1'
    fi
  done
  if [ "$status" = "1" ]; then
    echo "Writing file to: $write_file"
    env echo "$content" > "$write_file"

    # copy to default.cfg if it doesn't already exist
    default_cfg="$script_dir/config/default.cfg"
    if [ ! -f "$default_cfg" ]; then
      cp "$write_file" "$default_cfg"
      echo "Made a copy to default.cfg.  This means that you can run makestaticsite.sh without a parameter and it will load $cfgfile automatically"
    fi
  fi
}

conclude() {
  echo
  if [ "$status" = "1" ]; then
    read -r -e -p "Would you like to make the static site now (y/n)? " confirm
  confirm=${confirm:0:1}
    if [ "$confirm" = "y" ] || [ "$confirm" = "Y" ]; then
      ./makestaticsite.sh -i "$cfgfilestem"
      echo
    fi
    echo "To make this static site in future, run the following:"
    echo "./makestaticsite.sh -i $cfgfilestem"
    echo
    echo "Thank you. Setup is complete."
  fi
}
############### end of functions ###############

# run the script
main "$@"
