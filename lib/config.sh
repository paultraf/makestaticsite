##########################################################################
# 
# MakeStaticSite --- a shell script to create and deploy static websites 
# Copyright 2022-2025 Paul Trafford <pt@ptworld.net>
# 
# config.sh - configuration functions for MakeStaticSite
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


config_read_file() {
  (grep -E "^$2=" -m 1 "$1" 2>/dev/null || env echo "var=__UNDEFINED__") | head -n 1 | cut -d '=' -f 2-;
}


# Determine a parameter value from the supplied config file
# or set a default.
# Expects two parameters:
#  - option variable
#  - config file (less extension)
# plus one optional:
#  - full path to configuration files
config_get() {
  config_home=
  if [ -n "${3+x}" ]; then
    config_home="$3/"
  fi
  # Determine the referenced variable name
  var_ref="$1"
  var_label=${!var_ref}

  val="$(config_read_file "${config_home}config/$2".cfg "$1")";
  if [ "$val" = "__UNDEFINED__" ]; then
    val="$(config_read_file config/default.cfg "$1")";
    inputvar="$1"
    if [ "$val" = "__UNDEFINED__" ] && [ "$var_label" = "" ]; then
      val=""                              # Assume empty string if not defined    
      for opt in "${allOptions[@]}"; do
        defaultvar=$(expr "$opt" : '\([^=]*\)')       # Everything up to '='
        defaultval=$(expr "$opt" : '[^=]*.\(.*\)')    # Everything after '='
        pat='(.+)__(.+)'
        [[ $defaultvar =~ $pat ]]
        if [ -z ${BASH_REMATCH[1]+x} ] && [ "$defaultvar" = "$inputvar" ]; then             
          val="$defaultval"
          break
        fi
      done
    else
      # Just echo back an option if it's defined in constants.sh, but not the .cfg file
      printf "%s" "$var_label"; return;
    fi
  fi
  val=$(expr "$val" : '\([^#]*[^ #]\)')    # ignore appended spaces and hash
  val=$(env echo "$val" | tr -d "\"" | xargs) # remove any surrounding quotes + excess whitespace
  printf -- "%s" "${val}";
}


# Check the configuration file is in place
check_config_file() {

  if [ ! -f "config/$1.cfg" ]; then
    if [ "$1" = "default" ]; then
      echo "ERROR: the default configuration file is missing. The script needs this to run. Please create this by running the setup script."
      echo "Hit 'y' to run it now, any other key to abort."
      read -rsn1 input
      if [ "$input" = "y" ] || [ "$input" = "Y" ]; then
        "./setup.sh"
        exit
      else
        echo "Aborting."
        exit
      fi
    else
      if [ "$mirror_id_flag" = "on" ]; then
        echo "$msg_error: The configuration file cannot be determined from the Mirror ID (a string ending YYYYMMDD_NNNNNN is expected)."
        if [ "$config_flag" = "on" ]; then
          echo "Also, the configuration file that you supplied with the -i option can't be found.  Please review your command-line options."
        else
          echo "You can supply the config file with the -i option and re-run."
        fi
      else
        echo "$msg_error: the configuration file was not found at config/$1.cfg"
        echo "Please check your spelling.  To create config files, it is recommended using the setup script."
      fi
      echo "Aborting."
      exit
    fi
  fi
}


# Assign option variables.
# Expects one parameter: variable label containing list of options
assign_option_variables() {
  local option_names="$1[@]"          # pass array by name reference
  options_list=("${!option_names}")   # assign options_list via parameter expansion
  for opt in "${options_list[@]}"; do
    # standardise values for options of type yes/no 
    if [[ ' '${options_check_yesno[*]}' ' =~ ' '$opt' ' ]]; then
      printf -v "${opt}" '%s' "$(yesno "$(config_get "$opt" "$myconfig")")"
    else
      printf -v "${opt}" '%s' "$(config_get "$opt" "$myconfig")"
    fi
  done
}


# Extract a list of option variables from allOptions_deps array
# Expects one parameter: option key
get_options_list() {
  [ -z "${1+x}" ] && return ""
  local option="$1"
  local list=
  for opt_dep in "${allOptions_deps[@]}"; do
    var_dep=$(expr "$opt_dep" : '\([^=]*\)'; return 0) # Array key is everything up to '='
    if [ "$var_dep" = "$option" ]; then
      list=$(expr "$opt_dep" : '[^=]*.(\(.*\))'; return 0) # Array value is everything inside the brackets, after '=' 
      break
    fi
  done
  echo "$list"
}
