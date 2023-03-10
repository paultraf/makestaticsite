##########################################################################
#
# MakeStaticSite --- a shell script to create and deploy static websites
# Copyright 2022-2023 Paul Trafford <pt@ptworld.net>
#
# constants.sh - constants for MakeStaticSite
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


################################################
# MakeStaticSite info
################################################
version="0.22.3"
version_date='10 March 2023'
version_header="MakeStaticSite version $version, released on $version_date."
mss_license="GNU Affero General Public License version 3"
mss_download="https://makestaticsite.sh/download/makestaticsite_latest.tar.gz"


################################################
# Network settings
################################################
# Regular expressions approximating roughly to IPv4 and IPv6 addresses
ip4re="^[[:space:]]*#*[[:space:]]*\([0-9]\{0,1\}[0-9]\{0,1\}[0-9]\.\)\{3\}[0-9]\{0,1\}[0-9]\{0,1\}[0-9][[:space:]]*"   ip6re="^[[:space:]]*#*[[:space:]]*\([0-9a-fA-F]\{1,4\}::\{0,1\}\)\{1,7\}[0-9a-fA-F]\{1,4\}[[:space:]]*"
etc_hosts=/etc/hosts            # Location of hosts file


################################################
# Layout settings
################################################
tmp_dir="tmp"                   # Directory where temporary files are to be stored
tab="  "                        # tab spacing for file outputs


################################################
# Wget settings - initial and phase 2
################################################
# input file names for Wget (phase 1 and 2 respectively)
wget_cmd=wget                   # [Path to] wget binary
wget_version_atleast="1.21"
wget_error_level=6              # The lowest Wget error code tolerated else aborts (>8 for no tolerance)
wget_user_agent= # set browser user agent (empty for default), wrapped in quotes, e.g. "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15)"
wget_cookies="cookies.txt"      # name of cookies file
wget_inputs_main="wget_inputs_main.txt"
wget_inputs_extra="wget_inputs_extra.txt"
rename_wget_tmps=yes            # Remove .tmp.html suffixes from (wget temp) file names

# Core options for Wget (array)
#  --mirror is equivalent to ???-r -N -l inf --no-remove-listing???
# where -r: recursive; -N: timestamping; -l inf: infinite depth
wget_core_options=(--mirror --convert-links --adjust-extension --page-requisites)

# Core options for Wget phase 2 (array)
# Setting nc (no clobber) should be reasonable in that
# most pages should have already been downloaded
wget_extra_core_options=(-r -l inf -nc --adjust-extension)

wget_refresh_mirror=no          # ensure wget outputs to an empty directory (y/n)?
wget_ignore_errors=""           # Ignore errors generated by Wget (placeholder)
feed_html="feed/index.html"     # tail of invalid feed URLs generated by Wget
feed_xml="feed/index.xml"       # tail of valid feed URLs as replacement

################################################
# Robot and site map settings
################################################
link_rel_canonical=yes          # include <link rel="canonical"...> tag in header (y/n)?
link_href_tail=                 # The tail of canonical URLs, e.g. index.html or / (leave blank for /)
a_href_tail=                    # The tail for internal links, e.g. index.html or / (leave blank for /). The value should normally match link_href_tail

robots_create=yes               # Generate and overwrite robots.txt (y/n)?
# Define main portion of the default robots.txt file contents
# (the sitemap needs to be appended later to $url)
read -r -d "" robots_default << EOT
User-agent: *
Allow: /

EOT

sitemap_create=yes              # Generate and overwrite site map file (y/n)?
sitemap_file="sitemap.xml"      # Name of sitemap (XML) file
sitemap_schema="http://www.sitemaps.org/schemas/sitemap/0.9" # Site map XML schema URL

################################################
# CMS-specific constants
################################################
login_path="/wp-login.php"      # Path to login page (with respect to web root)
logout_path="/wp-login.php?action=logout" # Path to logout page (with respect to web root)
login_user_field="log"          # Field name for username
login_pwd_field="pwd"           # Field name for password
cookie_session_string="wordpress_logged_in" # Substring of name attribute denoting a login session
wget_reject_clause="*login*,*logout*" # wget --reject parameter (uses wildcard *) to avoid following logout links


################################################
# WordPress-specific settings
################################################
php_version_atleast="5.6"
php_tutorial_install="https://kinsta.com/blog/install-php/"
wp_cli_install="https://wp-cli.org/#installing"
wp_content='wp-content'         # WordPress content folder name
wp_plugins='plugins'            # WordPress plugins folder name

wp_permalinks_postname=yes      # Enforce %postname% in permalinks (yes/no)?
wp_search_plugin="https://makestaticsite.sh/download/contrib/wp-static-search-1-1-1.zip"
wp_search_dir='wp-static-search' # Name of search plugin directory under wp-plugins/
wp_search_page="search"         # Name of WordPress search page

wp_remove_query_strings=yes     # Remove query strings from WordPress core URLs
wp_remove_shortlink=yes         # Remove WordPress shortlinks
wp_disable_embeds=yes           # Disable embeds in WordPress
wp_disable_xmlrpc=yes           # Disable support for XML-RPC in WordPress
wp_remove_wlwmanifest_link=yes  # Remove Windows Live Writer <link> tag from header
wp_remove_rest_api_links=yes    # Remove support for REST API in WordPress
wp_remove_rsd_link=yes          # Remove Really Simple Discovery (RSD) <link> tag in WordPress 


################################################
# HTML Tidy settings
################################################
htmltidy_cmd=tidy               # [Path to] HTML Tidy binary
htmltidy_errors_file="errors_htmltidy.txt" # HTML Tidy errors file
htmltidy_options=(-m -q -indent --indent-spaces 2 --gnu-emacs yes --tidy-mark no) # Command line options for HTML Tidy (array).
# -modify, -m:              modify the original input files
# -quiet, -q:               suppress nonessential output
# -indent, -i:              indent element content
# --indent-spaces 2:        number of spaces Tidy uses to indent content
# --gnu-emacs yes:          change format for reporting errors to include filename in reports
# --tidy-mark no:           don't add meta element to indicate Tidy is a document generator
# --wrap 0:                 don't wrap text (no right margin)

################################################
# Display settings
################################################
ink_normal=$(tput sgr0)
ink_red=$(tput setaf 1)
ink_amber=$(tput setaf 130)     # Change this to a number less than 8 if tput colors is 8
ink_green=$(tput setaf 2)
msg_error=${ink_red}ERROR${ink_normal}
msg_warning=${ink_amber}WARNING${ink_normal}
msg_ok=${ink_green}OK${ink_normal}


################################################
# Other runtime settings
################################################
timezone=local                  # Time zone: local|utc|utclocal
output_level=quiet              # stdout verbosity - silent|quiet|normal|verbose
log_level=verbose                # Log level: silent|quiet|normal|verbose
log_filename=makestaticsite.log # Name of MakeStaticSite log file
trap_errors=no                  # Trap errors with immediate script termination (yes/no)
if [ "$trap_errors" = "yes" ]; then
# Stop the script if any command [in a pipeline] fails, variable unset; 
# then report 'system error'.  Also disable globbing
  trap 'if [ "$?" != "0" ]; then env echo "An unexpected system error occurred in function ${FUNCNAME} called from line $BASH_LINENO.  Aborting."; fi' EXIT
  set -euf -o pipefail
fi
run_unattended=yes               # Is MSS running unattended (yes/no)?
extras_dir=extras               # Name of folder containing all the additions
force_ssl=yes                   # Convert anchors to deployment domain to https (yes/no)
force_domains=yes               # Auto replace domain with deploy_domain (yes/no)
rsync_options=(-a -z -h)        # Core rsync options (excludes the output level)
#  -a archive mode preserves permissions, ownership, and modification times, etc
#  -z compression during transfer
#  -h outputs numbers in human-readable format


################################################
# Phases
################################################

all_phases=(
"0=Initialisation"
"1=Prepare the CMS"
"2=Generate static site"
"3=Augment static site"
"4=Refine static site"
"5=Add extras"
"6=Optimise"
"7=Use snippets"
"8=Create offline zip"
"9=Deploy"
)

((max_phase_num=${#all_phases[@]}-1))              # Number of phases minus one


################################################
# Site options
################################################

# Options are listed in a specific order to support workflow.
# Each option has three parts, which need to be defined in a specific order - 
# default value, description, info
# The user can change only the first.

allOptions=(

url='https://example.com/'
url__desc='URL of website being snapped'
url__info='Enter a website root URL or a path.  To capture a specific directory and no parents, check whether the URL requires a trailing slash and add the -np option in wget_extra_options below.'

require_login=n
require_login__desc='Does the site require a login (y/n)?'
require_login__info="If your website requires you to log in with a username and password (typically, via a web form), then enter 'y' otherwise 'n'."

site_user=username
site_user__desc='Website username'
site_user__info='Please enter a site username.  This should usually be an account with minimal privileges, sufficient to access to content intended for the public.'

site_password=password
site_password__desc='Website password'
site_password__info="Please enter the password for the username just supplied.  If you don't wish to enter it here, then you can continue with the setup and before running makestaticsite.sh manually edit the configuration file."

ssl_checks=n
ssl_checks__desc='Validate certificate in encrypted (SSL/TLS) connections (y/n)?'
ssl_checks__info="If you trust the SSL certificate of the site for which you are making a static version, then enter 'n'.  Otherwise, enter 'y' and store the certificate on your file system in PEM format.  Then either enter --ca_certificate={the_cert_file_path} in .wgetrc or --ca-certificate={the_cert_file_path} in wget_extra_options below."

wget_extra_options="-X/wp-json,/wp-admin --reject xmlrpc*"
wget_extra_options__desc='Additional command line options for Wget'
wget_extra_options__info="Wget will be run with the following options as standard: --mirror --convert-links --adjust-extension --no-check-certificate."$'\n'"You may add further options here, e.g., to supply http credentials: --user username --password password; to specify path to a certificate file: --ca-certificate={cert_file_path}; to exclude WordPress JSON directory: -X /wp-json; to exclude index files with query strings, --reject 'index.html?*'; to limit the download rate (N kilobytes/sec): -Nk"$'\n'"Otherwise leave empty."

input_urls_file=''
input_urls_file__desc='Name of Wget input file for custom crawl URLs'
input_urls_file__info='If your WordPress site makes use of custom CSS or JavaScript, list their URLs in this file so that Wget can capture them.  Otherwise leave empty.'

wget_extra_urls=y
wget_extra_urls__desc='Use Wget to retrieve additional assets from domain (y/n)?'
wget_extra_urls__info="This option will attempt to retrieve further assets by searching each downloaded file for further URLs and then re-running Wget, using the same options except that existing files will not be overwritten (no clobber)."

wget_post_processing=y
wget_post_processing__desc='Further refine the output from the first run of Wget (y/n)?'
wget_post_processing__info="This option will attempt to convert further absolute paths for url_base to relative paths; replace remaining occurrences of the source domain with deploy domain; and convert feed files and references from index.html to index.xml. Note that the method of search and replace is blunt - all occurrences will be replaced!"

archive=y
archive__desc='Add the mirror site to an archive (y/n)?'
archive__info='If selected, this option means that each snapshot with Wget is saved in its own date/time-stamped directory.'

local_sitename='examplewebsite'
local_sitename__desc='Directory name for the mirror site and stem of zip file.'
local_sitename__info='If not already existing, a new directory with this name will be created inside the mirror/ directory.  It will also provide the stem of the name of the zip file.'

wp_cli=n
wp_cli__desc='Use WP-CLI to carry out tweaks on WordPress database (y/n)?'
wp_cli__info="Use WP-CLI to update the WordPress database configuration so that it generates pages amenable to Wget.  WARNING: these changes happen immediately and currently cannot be reversed by MakeStaticSite.  Choose 'no' for updating WordPress some other way (e.g. manually through the dashboard) or if the site is not using WordPress."

wp_cli_remote=n
wp_cli_remote__desc='Is the use of WP-CLI on a remote server (through ssh) (y/n)?'
wp_cli_remote__info="WP-CLI supports remote connections over ssh, though this depends on the remote version and the remote shell."

site_path='/var/www/mywpdirectory'
site_path__desc='Full path to WordPress directory'
site_path__info='Full path to WordPress directory, which is commonly inside the Web root, e.g. /var/www/somedirectory'

source_host="examplehost.net"
source_host__desc="The server hosting your WordPress site - ip address or domain"
source_host__info="For WP-CLI, the server hosting your WordPress site - ip address or domain."

source_protocol=""
source_protocol__desc='Internet protocol (if any) to interact with the source (server) hosting the WordPress site'
source_protocol__info='If the site is local to your machine, then leave this empty.  If on a remote hosting provider, in the Cloud, then this is typically ssh.'

source_port="22"
source_port__desc='ssh port for the source'
source_port__info='ssh port. If left as empty string, then the default (usually 22) will be used.  It will likely need to be set if port forwarding is used.'

source_user=""
source_user__desc="User account on source (remote host)"
source_user__info="The user account on remote host (assumes the use of ssh private-public key pair).  Leave blank if accessing locally."

wp_helper_plugins=y
wp_helper_plugins__desc='Try to install WordPress plugins to configure site snapshot (y/n)?'
wp_helper_plugins__info='For Wget to properly create a static snapshot of WordPress, a few options need to be configured.  These can be carried out by plugins.  Otherwise, they can be configured manually.'

add_search=y
add_search__desc='Add a static search function (y/n)?'
add_search__info='Adds the WP Search Offline plugin (beta), a drop-in replacement for WordPress search that works offline (no Internet needed).'

#wp_restore_settings=n
#wp_restore_settings__desc='Restore WordPress settings to those before makestaticsite was run (y/n)?'
#wp_restore_settings__info='Any changes carried out to the WordPress database during the run of makestaticsite.sh will be restored.  Please note that this is not yet implemented.'
#
use_snippets=n
use_snippets__desc='Use snippets to create page variants (y/n)?'
use_snippets__info='After Wget has created the mirror, use snippets to create variants of selected pages.  They will be included in the zip file and/or deployed site, depending on the respective options.  See separate documentation for instructions on their creation.'

upload_zip=y
upload_zip__desc='Create a zip file for distribution with the static website (y/n)?'
upload_zip__info='If selected, a zip file of the static snapshot will be created and added to a folder for distribution.  It is suitable for offline browsing.'

zip_filename='website.zip'
zip_filename__desc='Zip filename for static snapshot'
zip_filename__info='Zip filename for static snapshot.  This can be named for specific distribution purposes.'

zip_download_folder='download'
zip_download_folder__desc='Storage location for zip download'
zip_download_folder__info='For WordPress, this might be wp-content/uploads'

deploy=y
deploy__desc='Deploy the output on a server (y/n)?'
deploy__info='Deployment can be on a server hosted locally, e.g. on your development machine, or remotely. Further questions will be asked to tailor your options.'

deploy_domain="mydomain.com"
deploy_domain__desc="Domain name for your web site."
deploy_domain__info="Domain name for the static web site that you are deploying, which will be used to help ensure that non-static and non-HTML elements are properly delivered.  This is usually distinct from the domain of the host server."

deploy_remote=n
deploy_remote__desc='Deploy to a server on a remote host (y/n)?'
deploy_remote__info="Either indicate 'yes' for deployment on a remote server on the Internet or 'no' for a local server, e.g. on your file system or one shared with your development machine."

deploy_remote_rsync=y
deploy_remote_rsync__desc='Do you wish to deploy using rsync over ssh (y/n)?'
deploy_remote_rsync__info="Indicate 'yes' for deployment on a remote server that supports rsync over ssh."

deploy_host="examplehosting.net"
deploy_host__desc="Host (ip or domain) for deploying the static site"
deploy_host__info="Host (ip address or domain) for deploying the static site remotely.  Leave empty for deployment on local filesystem.  This is not generally the domain name for your site (which you can enter later)."

deploy_port=22
deploy_port__desc='ssh port on deployment server'
deploy_port__info='ssh port is usually 22, but will likely need changing if port forwarding is used.'

deploy_user="username"
deploy_user__desc="Username (for remote host)"
deploy_user__info="Account username on remote host, where the static site is being deployed.  Leave empty for deployment on local filesystem."

deploy_path="~/webs/staticwebsite"
deploy_path__desc="Path for deploying the static site"
deploy_path__info="Path for deploying the static site on the hosting provider."

deploy_netlify="n"
deploy_netlify__desc="Deploy the output on Netlify (y/n)?"
deploy_netlify__info="Indicate 'yes' for deployment on Netlify using its command-line interface.  This assumes you have a Netlify account and have set up a site."

deploy_netlify_name="netlify-name-12abc3"
deploy_netlify_name__desc="Netlify site name (alphanumeric sequence)."
deploy_netlify_name__info="Netlify site name - when first issued, the default format comprises an alphanumeric sequence that includes a couple of human-readable words.  The name can be changed in Netlify's site administration panel."

htmltidy=n
htmltidy__desc="Clean up mirror output using HTML Tidy (y/n)?"
htmltidy__info="Option to clean up HTML output for better conformance to W3C standards along with 'pretty print' cosmetic refinement."

add_extras=n
add_extras__desc="Add additional files to the static output (y/n)?"
add_extras__info="Option to supplement the static snapshot with further files sourced from elsewhere. They may include non-static files such as scripts to reinstate essential functionality.  Please place them in the $extras_dir/ directory."

)

options_allow_empty=(wget_extra_options input_urls_file)
options_check_cmd=(wget_cmd htmltidy_cmd)
options_check_dir=(site_path)
options_check_url=(url)
options_check_yesno=(ssl_checks wget_extra_urls wget_post_processing archive wp_cli wp_cli_remote wp_helper_plugins add_search wp_restore_settings use_snippets upload_zip deploy deploy_remote deploy_remote_rsync htmltidy add_extras)

