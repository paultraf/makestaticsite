#!/usr/bin/env bash

##########################################################################
#
# MakeStaticSite --- a shell script to create and deploy static websites
# Copyright 2022-2025 Paul Trafford <pt@ptworld.net>
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
source "lib/general.sh"    # load general functions library
source "lib/validate.sh"   # load the validation library functions
# shellcheck source=lib/mod_wayback.sh
source "lib/$mod_wayback";


main() {
  # Step 0: Initialisation
  get_inks
  read_config "$@"
  print_welcome
  init_mssconfig

  # Step 1: Read and process input
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

read_config() {
  cfgfile=
  cfg_string=
  log_filename=
  local OPTIND
  while getopts ":o:l:L:q:u" option; do
    case "$option" in
      l)
        level="$OPTARG"
        validate_range 0 "$max_setup_level" "$level" ||{ printf "$msg_error: Sorry, the setup level of $level is out of range (it should be an integer between 0 and %s).  Please try again.\n" "$max_setup_level"; exit; }
        ;;
      L)
        log_filename="$OPTARG"
        ;;
      q)
        end_phase="$OPTARG"
        ;;
      u)
        level=0
        run_unattended=yes
        ;;
      o)
        cfgfile="$OPTARG.cfg";
        cfg_string=", $cfgfile,"
        ;;
      : )
        # Print argument error
        printf "Invalid option: %s requires an argument. Please try again.\n" "$OPTARG" 1>&2
        exit
        ;;
      \? )
        # Print option error
        printf "Invalid option: %s. Please try again.\n" "$OPTARG" 1>&2
        exit
        ;;
    esac
  done

  echo 
  shift "$((OPTIND-1))"

  if [ "$*" != "" ]; then
    url="$*";
    validate_url "$url" || { printf "Sorry, the URL appears to contain one or more invalid characters. Aborting - please check and try again. \n"; exit; }
    echo
  fi

  # If an end phase (number) has been specified, but is too small, then not much will be done
  if [ "$end_phase" != "" ] && ((end_phase < 2)); then
    printf "$msg_warning: No site will be output because the supplied end phase (q) is too low.\n"
  fi

  if [ "$run_unattended" = "yes" ] && [ -z ${url+x} ]; then
    printf "$msg_error: You have run setup in unattended mode (-u flag), but not supplied a URL. Aborting - please try again. \n"; exit;
  fi

  if [ "$run_unattended" = "yes" ] && (( level > 0 )); then
    printf "$msg_error: You can only run setup in unattended mode (-u flag) at level 0. Aborting - please try again.\n"; exit;
  fi
  
}

print_welcome() {
  printf "Welcome to MakeStaticSite for the generation and deployment of static websites.  This is free software released under the %s, the latest version being available from %s.\n\n" "$mss_license" "${mss_download}"
  printf 'This setup script will ask a few questions to help you set up a configuration file%s for a single site (the script can be run any number of times to generate configs for other sites).  For each option, its label will be displayed together with some guidance. Please enter the values accordingly.\n\n' "$cfg_string"
  if [ -n "${level+x}" ]; then
    printf "The amount of questioning depends on the runtime level - 0 (minimal), 1 (standard) and 2 (advanced).  You have chosen to run this script at level %s.\n\n" "$level"
  else
    printf "The amount of questioning depends on the runtime level\n"
    printf " 0 - minimal setup, suitable for sampling or archival.\n"
    printf " 1 - standard customisation options, including basic deployment.\n"
    printf " 2 - full customisation for fine-tuning options, including Wget parameters.\n\n"
    while true; do
      read -r -e -p "Please enter a level between 0 and $max_setup_level to start configuring: " level
      validate_range 0 "$max_setup_level" "$level" || { printf "Sorry, the setup level number is out of range (it should be an integer between 0 and %s).  Please try again.\n" "$max_setup_level"; continue; }
      break
    done
  fi  
  printf "\n"
}

init_mssconfig(){
  # Check system requirements - Bash, cURL, Wget and rsync
  msg_checking="Checking your system for Wget and other essential components ... "
  bash_check
  cmd_check "curl" || { printf "%s\n%s: Unable to find binary: curl ("'$'"PATH contains %s).\nThis command is essential for checking connectivity.  It may be downloaded from https://curl.se/.\nAborting.\n" "$msg_checking" "$msg_error" "$PATH"; exit; }
  cmd_check "$wget_cmd" || { printf "%s\n%s: Unable to find binary: wget ("'$'"PATH contains %s)\nThis command is essential for creating the static snapshots.  Please make sure it is installed and review the value of the wget_cmd option in constants.sh.\nAborting.\n" "$msg_checking" "$msg_error" "$PATH"; exit; }
  wget_cmd_version="$(which_version "$wget_cmd" "GNU Wget")"
  version_check "$wget_cmd_version" "$wget_version_atleast" || { printf "%s\n%s: The version of %s is %s, which is old, so some functionality may be lost.  Version %s or later is recommended.\n" "$msg_checking" "$msg_warning" "$wget_cmd" "$wget_cmd_version" "$wget_version_atleast";}
  cmd_check "rsync" || { printf "\n%s: Unable to find binary: rsync ("'$'"PATH contains %s).\nThis command is essential for transferring files remotely.  It may be downloaded from https://rsync.samba.org/.\nAborting.\n" "$msg_error" "$PATH"; exit; }

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

# A support function for read_option()
# It requires the following parameters
#  - input_line clause
#  $input_value (stored separately from the configuration file)   |    Wget $wget_http_login_field $optvar_username
#  - credentials_insert_path tail
#  $optvar/$input_value   |   $wget_http_login_field/$optvar_username
#  - option value to print out as part of guidance for user input
#  $optvar password    |   --$wget_http_password_field

read_credentials() {
  input_value_backup="$input_value"
  input_line="Please enter the password for $1"
  domain=$(printf "%s\n" "$url" | awk -F/ '{print $3}' | awk -F: '{print $1}')
  credentials_insert_path="${credentials_path_prefix}$domain/$2"
  credentials_path="$credentials_home/$credentials_insert_path"
  if [ "$credentials_storage_mode" = "encrypt" ]; then
    if [ -z ${pass_check+x} ]; then
      cmd_check "$credentials_manage_cmd" || { printf "\n%s: Unable to find binary: $credentials_manage_cmd ("'$'"PATH contains %s).\nThis command is essential for encrypting credentials.  It may be downloaded from %s.  Alternatively,  modify the value of credentials_storage_mode in constants.sh to 'plain', and re-run, but with less security. \nAborting.\n" "$msg_error" "$PATH" "$credentials_manage_cmd_url"; exit; }
      pass_check=1
    fi
    input_line+=". It will be stored in encrypted form."
    printf "%s: %s\n\n" "$(msg_ink "info" "$3")" "$input_line"
    confirm=Y
    if [ -f "$credentials_path.$credentials_extension" ]; then
      read -r -e -p "An entry already exists for $credentials_path. Overwrite it? [y/N] " confirm
      confirm=${confirm:0:1}
      if [ "$confirm" = "y" ] || [ "$confirm" = "Y" ]; then
        rm "$credentials_path.$credentials_extension" || echo "$msg_error: unable to remove the existing file at $credentials_path.$credentials_extension."
      fi
    fi
    if [ "$confirm" = "y" ] || [ "$confirm" = "Y" ]; then
      input_encrypted_password "-"
    fi
  elif [ "$credentials_storage_mode" = "plain" ]; then
    mkdir -p "$mss_dir_permissions" "$(dirname "$credentials_path")" 
    touchmod "$credentials_path"

    # read password and write to "$credentials_path"
    input_text="-s"
    validate_input "$input_text" "$input_line: " "$optvar"
    if [ "$input_value" = "" ]; then
      echo "$msg_warning! No password was set!"
    fi
    printf "%s" "$input_value" > "$credentials_path"
    printf "\n"
  fi
  input_value="$input_value_backup"  # reinstate ahead of writing the username to .cfg
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
      if { [ "$level" = 0 ] && [[ ! "${options_min[*]}" =~ ${optvar} ]]; } || { [ "$level" = 1 ] && [[ ! "${options_std[*]}" =~ ${optvar} ]]; }; then
        opt_limits=y
      else
        opt_limits=n
        if [ "$var" = "local_sitename__info" ]; then
          opt_default="${host//\./_}"
        elif [ "$var" = "zip_filename__info" ]; then
          opt_default="${host//\./_}"'.zip'
        fi
      fi
      if [ "$opt_info" != "" ] && [ "$opt_limits" = "n" ] && { [ -z "${url+x}" ] || [ "$optvar" != "url" ]; }; then
        printf "%s: %s\n" "$(msg_ink "info" "$optvar")" "$opt_info"
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
        if [ "$opt_limits" = "n" ]; then
          printf "\n"
        fi
        input_line="$opt_desc $input_hint"
        if [ "$opt_limits" = "y" ]; then
          opt_value="$opt_default"
          input_value="$opt_default"
        else
          validate_input "$input_text" "$input_line" "$optvar"
          opt_value=${input_value::1}
        fi
        if [ "$opt_value" = "n" ]; then
          # loop over allOptions_deps to see what further options to exclude
          for opt_dep in "${allOptions_deps[@]}"; do
            var_dep=$(expr "$opt_dep" : '\([^=]*\)'; return 0)       # Array key is everything up to '='
            val_dep=$(expr "$opt_dep" : '[^=]*.\(.*\)'; return 0)    # Array value is everything after '='
            if [ "$optvar" = "$var_dep" ]; then
              opt_excludes+=$val_dep
            fi
          done
        fi
      else
        if [ "$opt_limits" = "y" ]; then
          input_value="$opt_default"
          # generate local_sitename and zip_filename from the URL's host portion
          if [ "$var" = "local_sitename__info" ]; then
            input_value="${host//\./_}"
          elif [ "$var" = "zip_filename__info" ]; then
            input_value="${host//\./_}"'.zip'
          fi
        elif [ -n "${url+x}" ] && [ "$optvar" = "url" ]; then
          echo "You have entered as URL: $url"
          input_value="$url"
          invalid_http_reason= # description of invalid http status
          if ! validate_url "$input_value"; then
            invalid_http_reason="The URL is invalid."
          else
            validate_url_range "$input_value" "input_value"
          fi
          if [ "$invalid_http_reason" != "" ]; then
            if [ "$run_unattended" = "yes" ]; then
              echo "$invalid_http_reason Aborting."; exit
            else
              input_line="Please enter the value for $optvar$input_hint: "
              validate_input "$input_text" "$input_line" "$optvar"
            fi
          fi
        else
          echo
          input_line="Please enter the value for $optvar$input_hint: "
          validate_input "$input_text" "$input_line" "$optvar"
        fi

        ## Website (not HTTP basic authentication) login: enter credentials, as needed, according to credentials storage mode
        if [[ ' '${options_credentials[*]}' ' =~ ' '$optvar' ' ]] && [ "$credentials_storage_mode" != "config" ]; then
          printf "\n"
          read_credentials "$input_value (stored separately from the configuration file)" "$optvar/$input_value" "$optvar password"
        fi

        ## HTTP basic authentication: enter credentials, as needed, according to credentials storage mode
        re_user='\-\-'"$wget_http_login_field"' ([^ \-]*)'
        re_password='\-\-'"$wget_http_password_field"' ([^ \-]*)'
        if [ "$optvar" = "wget_extra_options" ] && [[ ! $input_value =~ $re_password ]] && [[ $input_value =~ $re_user ]]; then 
          # interactive mode dependent on --user option, but no --password option
          optvar_username="${BASH_REMATCH[1]}" # determined by last expression in conditional
          if [ "$optvar_username" = "" ]; then
            echo "$msg_error: no username specified as Wget --$wget_http_login_field option.  Aborting."; exit
          fi
          read_credentials "Wget $wget_http_login_field $optvar_username" "$wget_http_login_field/$optvar_username" "--$wget_http_password_field"
        fi
      fi
      if [ "$opt_limits" = "n" ]; then
        echo
      fi
      if [ "$optvar" = "url" ]; then
        host=$(printf "%s" "$input_value" | awk -F/ '{print $3}' | awk -F: '{print $1}')
        # Check for Wayback Machine
        if check_wayback_url "$input_value" "$wayback_hosts" "input_value"; then
          archived_domain_path=$(printf "%s" "${input_value//:\/\//|}" | cut -d\| -f3)
          if [ "$archived_domain_path" = "" ]; then
            echo "$msg_error: Sorry, no archive URL found at the Wayback Machine!  For guidance on acceptable URLs, please consult https://help.archive.org/help/using-the-wayback-machine/ and then try again."; exit
          else
            echo "Wayback Machine URL detected with archive having domain and path: $archived_domain_path."
            primary_host=$(printf "%s" "$archived_domain_path" | cut -d/ -f1)
            if [ "$wayback_sitename_hosts" = "primary" ]; then
              host="$primary_host"
            elif [ "$wayback_sitename_hosts" = "both" ]; then
              host+="-$primary_host"
            fi
            process_wayback_url "$input_value"
          fi
        fi
      fi
      # Print tidy output - should be able to put most # in a column
      printf -v CONFIGLINE "%-38s %s %s\n" "$optvar=$input_value" '#' "$opt_desc"

      # Assign value to variable for use elsewhere in the script
      printf -v "${optvar}" '%s' "${input_value}"
      
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
  if [ "$credentials_storage_mode" != "config" ]; then
    opt_excludes+=("site_password")
  fi
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
      string_count=$(grep -o ',' <<< "$val" | wc -l) || string_count=0
      # enumerate the strings and check if they are all yes/no
      if (( string_count > 0 )); then
        is_yesno="y"
        IFS="," read -r -a val_array <<< "$val"
        for opt_val in "${val_array[@]}"; do 
          # if $opt_val is not a yes or no then break
          if [[ ! "${allOptions_yesno[*]}" =~ ${opt_val} ]]; then
            is_yesno="n"
            break
          fi
        done
        if [ "$is_yesno" = "y" ]; then
          # assign the default value from the array's runtime level as index
          val=${val_array[$level]}
        fi
      fi
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
  printf "Thank you for providing the configuration options.\nHere is a summary of your input:\n\n%s\n" "$content"
  status='0'
  if [ "$cfgfile" = "" ]; then
    if [ "$run_unattended" = "yes" ]; then
      # autogenerate cfg filename based on url host
      cfgfile="${host//\./_}.cfg"
      write_file="$script_dir/config/$cfgfile"
      i=1
      while [ -f "$write_file" ]
      do
        cfgfile="${host//\./_}_$i.cfg"
        write_file="$script_dir/config/$cfgfile"
        (( i++ ))
      done
      status='1'
    else
      read -r -e -p "Do you wish to write this configuration to a file (y/n)? " confirm
      confirm=${confirm:0:1}
      if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then
        status='2'
      fi
    fi  
  else
    printf "Will now attempt to write this to the configuration file you specified: %s\n" "$cfgfile"   
  fi  
  while [ "$status" = '0' ]
  do
    if [ "$cfgfile" = "" ]; then
      read -r -e -p "Please enter a filename (a .cfg extension will be added automatically): " cfgfile
    fi
    cfgfile=${cfgfile/.cfg/}
    cfgfile="$cfgfile.cfg"
    cfgfile_original="$cfgfile"
    # should allow alphanumeric characters that include accented letters
    cfgfile=$(printf "%s" "$cfgfile" | tr -cd '[:alnum:]._-')
    if [ "$cfgfile" != "$cfgfile_original" ]; then
      printf "%s: only alphanumeric characters, dot, hyphen and underscore allowed in filenames.  Have stripped out any others.  The resulting file name is %s\n" "$msg_warning" "$cfgfile"
    fi
    if [ "$cfgfile" = ".cfg" ]; then
      printf "%s: The file name (less extension) cannot be empty\n" "$msg_error"
      cfgfile=""
      continue
    fi
    write_file="$script_dir/config/$cfgfile"
    if [ -f "$write_file" ]; then
      read -r -e -p "$msg_warning: The file $cfgfile already exists. Overwrite (y/n)? " confirm
      confirm=${confirm:0:1}
      if [ "$confirm" = "y" ] || [ "$confirm" = "Y" ]; then
        status='1'
      else
        cfgfile= 
      fi
    else
      status='1'
    fi
  done
  if [ "$status" = "1" ]; then
    printf "Writing configuration options to: %s ... " "$write_file"
    touchmod "$write_file"

    printf "%s\n" "$content" > "$write_file" || { printf "\n%s: Unable to write the configuration file.\nAborting.\n" "$msg_error"; exit; }
    printf "Done.\n\n";

    # copy to default.cfg if it doesn't already exist else confirm whether or not to overwrite it
    default_cfg="$script_dir/config/default.cfg"
    if [ ! -f "$default_cfg" ]; then
      cp_check "$write_file" "$default_cfg"
      printf "Made a copy to default.cfg.  This means that you can run makestaticsite.sh without a parameter and it will load %s automatically.\n" "$cfgfile"
    elif [ "$level" != 0 ]; then
      read -r -e -p "Would you like this configuration to be copied to default.cfg file, which is loaded automatically when you run makestaticsite.sh without a parameter (y/n)? " confirm
      confirm=${confirm:0:1}
      if [ "$confirm" = "y" ] || [ "$confirm" = "Y" ]; then
        cp_check "$write_file" "$default_cfg"
        echo "OK. Made a copy to default.cfg."
      else
        echo "OK. Left default.cfg alone."
      fi
    fi
  fi
}

conclude() {
  if [ "$status" = "1" ]; then
    if [ "$run_unattended" != "yes" ]; then
      read -r -e -p "Would you like to make the static site now (y/n)? " confirm
      confirm=${confirm:0:1}
      echo
    else
      confirm="y"
    fi  
    if [ "$confirm" = "y" ] || [ "$confirm" = "Y" ]; then
      echo "Proceeding to make the static site ... "
      args=(-i "$cfgfile")
      [ "$log_filename" != "" ] && args+=(-L "$log_filename")
      [ "$end_phase" != "" ] && args+=(-q "$end_phase")
      [ "$run_unattended" = "yes" ] && args+=(-u)
      ./makestaticsite.sh "${args[@]}"
      echo
    fi
    printf "To make this static site in future, run the following:\n./makestaticsite.sh -i %s\n\nThank you. Setup is complete.\n" "$cfgfile"
  elif [ "$status" = "2" ]; then
    printf "No output written.\n\nThank you for trying the setup script. Goodbye.\n"; exit
  fi
}
############### end of functions ###############

# run the script
main "$@"

