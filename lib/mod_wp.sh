##########################################################################
# 
# MakeStaticSite --- a shell script to create and deploy static websites 
# Copyright 2022-2023 Paul Trafford <pt@ptworld.net>
# 
# mod_wp.sh - WordPress module for MakeStaticSite
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
# 1. This module uses WP-CLI (https://wp-cli.org/)
#    Make sure that WP-CLI has read-write file permissions to update
#    plugins
# 2. Errors and warnings may be reported when running php scripts 
#    depending on the setting of error_reporting in php.ini
#    e.g., to suppress deprecated notices, use:
#    error_reporting = (E_ALL ^ E_DEPRECATED)
#


# Check whether WP-CLI is installed and whether to run locally
wp_cli_check() {
  command -v wp cli &> /dev/null || { printf "ERROR.  WP-CLI is not installed.\nPlease follow the installation instructions at %s and then try again.\n" "$wp_cli_install"; exit; }
  wp_cli_msg="WP-CLI is installed"
  [ "${wp_cli_remote}" != "yes" ] && wp_cli_msg+=" and will be run locally"
  env echo "$wp_cli_msg"
}

# Set a WordPress option (currently hardcoded to Perform plugin) 
wp_option_set() {
  if ! wp option pluck perform_common "$1" "$wp_location" &> /dev/null; then
    wp option patch insert perform_common "$1" '1' "$wp_location" "$wpvol"
  elif ! wp option patch update perform_common "$1" '1' "$wp_location" "$wpvol"; then
    echo "Unable to update the Perform setting: $1"
  fi
}

# Streamline the WP install ahead of being crawled by wget
wp_clean() {
  # Check that there is a WP site at the relevant WP directory (not http)
  wp core is-installed "$wp_location" || { printf "ERROR: No WordPress site found at %s\nAborting." "$wp_location"; exit; }
  [ "$source_protocol" = '' ] && echo "Found WordPress site at $site_path" || echo "Found WordPress site at $wp_location"

  # Ensure that no-follow option is disabled
  if ! blog_public_val=$(wp option get blog_public "$wp_location" "$wpvol"); then
    echo "Error: Unable to check the status of wp_option setting: blog_public"
  elif [ "$blog_public_val" != "1" ]; then
    echo "Notice: Changing search engine access to allow wget to crawl the site."
    wp option update blog_public 1 "$wp_location" "$wpvol"
  fi

  # Ensure Permalinks are using post names
  if ! permalink_structure_value=$(wp option get permalink_structure "$wp_location" --quiet); then
    echo "Unable to check the status of wp_option setting: permalink_structure"
  elif [ "$wp_permalinks_postname" = "yes" ] && [[ "$permalink_structure_value" != *"/%postname%/"* ]] ; then
    echo "Notice: Changing permalink structure for the site to use %postname%."
    wp option update permalink_structure "/%postname%/" "$wp_location" "$wpvol"
  fi

  if [ "$wp_helper_plugins" = "yes" ]; then
    if ! wp plugin is-installed perform "$wp_location"; then
      echo "Installing the perform plugin ..."

      # Test script write access to wp-content/ folder for plugin folder creation
      if [ ! -w "$wp_plugins_folder" ]; then
        echo "ERROR: This script can't install any plugins because this user account doesn't have write permission to the $wp_plugins_folder folder."

      # Download and install the latest version of perform plugin as necessary
      elif ! wp plugin install perform --activate "$wp_location" &> /dev/null; then
        echo "ERROR: unable to install the perform plugin -"
        echo "Check the settings for WP CLI and the path, $site_path,"
        echo "including file permissions for $USER."
        echo "Alternatively, install and activate the plugin through the dashboard."
        echo "Aborting."
        exit
      fi
    else
      echo "Perform plugin is already installed." "1"
    fi
 
    # Configure perform plugin options to simplify WP output
    if ! wp option get perform_common "$wp_location" &> /dev/null; then
      echo "Unable to check the status of wp_option setting: perform_common"
    else
      echo "Checking WordPress settings to remove query strings and shortlinks ... "

      # Check whether the wp_options have been set (need to create nested array)
      perform_common_value=$(wp option get perform_common --format=json "$wp_location")
      if [ "$perform_common_value" = '""' ]; then
        echo "Initialising Perform options"
        # N.B. The following will replace whatever value $perform_common had before
        wp option update perform_common '{"remove_query_strings": "1", "remove_shortlink": "1"}' --format=json "$wp_location" "$wpvol"
      else
        # it's not empty, so we now check the serialized option for remove_query_strings
        # and insert/update a value as necessary:
        echo -n "Updating Perform options ... "
        [ "$wp_remove_query_strings" = "yes" ] && wp_option_set "remove_query_strings"
        [ "$wp_remove_shortlink" = "yes" ] && wp_option_set "remove_shortlink"
        [ "$wp_disable_embeds" = "yes" ] && wp_option_set "disable_embeds"
        [ "$wp_disable_xmlrpc" = "yes" ] && wp_option_set "disable_xmlrpc"
        [ "$wp_remove_wlwmanifest_link" = "yes" ] && wp_option_set "remove_wlwmanifest_link"
        [ "$wp_remove_rest_api_links" = "yes" ] && wp_option_set "remove_rest_api_links"
        [ "$wp_remove_rsd_link" = "yes" ] && wp_option_set "remove_rsd_link"
        echo "Done." 
      fi
    fi
  fi
}

# Download and install WP Offline Search plugin as necessary
wp_install_search() {
  if ! wp plugin is-installed wp-static-search "$wp_location"; then
    echo "WP Static Search plugin not found.  Trying to install..."
    if ! wp plugin install "$wp_search_plugin" --activate "$wp_location" &> /dev/null; then
      echo "ERROR: unable to install the WP Static Search plugin."
      echo "Check the settings for WP CLI and the path."
      echo "Alternatively, install and activate the plugin through the dashboard."
    else
      echo "WP Static Search installed.";
      echo "NOTICE: a search index needs to be created manually via the WordPress Dashbboard 'static search' menu.  Once this is done (now, perhaps?) then the search facility will work in the static site."
      echo "Hit any key to continue."
      read -rsn1
    fi
  else
    echo "WP Static Search plugin is already installed." "1"
  fi

  # Create a search page as necessary
  # Ideally we should retrieve the post content and search for [static_search]
  if ! search_page=$(wp post list --post_type=page --post_status=publish --title=Search --format=count "$wp_location"); then
    echo "Error: unable to determine if a search page has been created."
  elif [ "$search_page" -eq "0" ]; then
    echo "Creating a search page..."
    if ! wp post create --post_type=page --post_title='Search' --post_content='<p>[static_search]</p>' --post_author=1 --post_status=publish "$wp_location"; then
      echo "Unable to create a search page.  Alternatively, do this manually."
    else
      echo "OK"
    fi
  else
    echo "It looks like there is already a search page.  Assume that it contains the shortcode [static_search], so we won't update it."
  fi

  # If addding search, generate a list comprising URL BASE 
  # plus additional CSS and JS files
  echo "Adding JS and CSS files to wget input to support search." "1"
  # Define the list of components that need to be included in wget
  wp_search_input_files=("$url_base/$wp_search_page"/ "$url_base/$wp_content"/lunr-index/lunr-index.js "$url_base/$wp_content"/lunr-index/lunr-index.ver "$url_base/$wp_search_plugin_path"/3rdparty-css-js/lunr-2.3.8.min.js "$url_base/$wp_search_plugin_path"/3rdparty-css-js/lunr-2.3.9.min.js "$url_base/$wp_search_plugin_path"/js/admin.js "$url_base/$wp_search_plugin_path"/js/worker.js "$url_base/$wp_search_plugin_path"/css/admin.css) 

  # Augment wget_input_files with WP static search files
  wget_input_files+=( "${wp_search_input_files[@]}" )

}

# main WordPress preparation loop
wp_prep() {
  # Check that we have the necessary command line interfaces and versions
  cmd_check "php" "1" || { printf "ERROR.  A PHP command line interpreter (CLI) is needed to support the use of WP-CLI, but could not be found.\nPlease check that you have PHP installed (at least version %s) and that it is available in your PATH.  An installation guide for various platforms is available from %s.\nAborting.\n" "$php_version_atleast" "$php_tutorial_install"; exit; }
  php_cli_version="$(which_version "php" "PHP ")" 
  version_check "$php_cli_version" "$php_version_atleast" || { echo "$msg_checking";  printf "WARNING. The version of %s is %s, which is old, so some functionality may be lost.  Version %s or later is recommended.\n" "PHP" "$php_cli_version" "$php_version_atleast";}
  wp_cli_check  

  # Read WordPress-specific variables
  wp_helper_plugins=$(yesno "$(config_get wp_helper_plugins "$myconfig")")
  wp_restore_settings=$(yesno "$(config_get wp_restore_settings "$myconfig")")

  # WordPress-related details for wget
  wp_plugins_folder="$site_path/$wp_content/$wp_plugins"
  wp_search_plugin_path="$wp_content/$wp_plugins/$wp_search_dir"

  # Options to indicate where WP is installed on our (local or remote) source
  if [ "$source_port" != "" ]; then
    source_port=":$source_port"
  fi
  [ "$wp_cli_remote" = "yes" ] && wp_location="--ssh=$source_user@$source_host$source_port$site_path" || wp_location="--path=$site_path"

  wp_clean
  [ "$add_search" = "yes" ] && wp_install_search || echo "Search not included, as per preferences."
#  [ "$wp_restore_settings" = "yes" ] && echo "Restoration of WordPress settings is not yet implemented.  Please make a backup and/or use the WordPress dashboard if you need to restore the previous settings."

  return 0
}  
