##########################################################################
#
# MakeStaticSite --- a shell script to create and deploy static websites
# Copyright 2022-2025 Paul Trafford <pt@ptworld.net>
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
version=0.31.9
version_date='7 July 2025'
version_header="MakeStaticSite version $version, released on $version_date."
mss_license="GNU Affero General Public License version 3"
mss_site="https://makestaticsite.sh"
mss_download="$mss_site/download/makestaticsite_latest.tar.gz"


################################################
# Setup-specific settings
################################################
max_setup_level=2               # Maximum runtime level for setup (starts at 0)
max_redirects=5                 # Maximum number of redirects allowed for determining effective URL being mirrored


################################################
# Network settings
################################################
# Extended regular expressions approximating roughly to IPv4 and IPv6 addresses, Internet domain names and URLs:
# a "name" (Net, Host, Gateway, or Domain name) is a text string...
# drawn from the alphabet (A-Z), digits (0-9), minus sign (-), and period (.).  
# https://datatracker.ietf.org/doc/html/rfc952
# and may start with a digit:
# https://datatracker.ietf.org/doc/html/rfc1123#page-13
# URL syntax, with a list of acceptable (unreserved and reserved) characters based on Internet Society, URI, RFC 3986
# https://www.rfc-editor.org/rfc/rfc3986#section-2 
# For bracketed expressions, see
# https://pubs.opengroup.org/onlinepubs/009696899/basedefs/xbd_chap09.html#tag_09_03_05
ip4re="^[[:space:]]*#*[[:space:]]*\([0-9]\{0,1\}[0-9]\{0,1\}[0-9]\.\)\{3\}[0-9]\{0,1\}[0-9]\{0,1\}[0-9][[:space:]]*"
ip6re="^[[:space:]]*#*[[:space:]]*\([0-9a-fA-F]\{1,4\}::\{0,1\}\)\{1,7\}[0-9a-fA-F]\{1,4\}[[:space:]]*"
# Unlike hostnames, Internet domains contain at least one dot.
domain_re0="[[:alnum:]][-[:alnum:]+\.]*\.[-[:alnum:]+]*[[:alnum:]]"
domain_re="^$domain_re0"'$'     # Anchored domain match (add first and last characters)
url_re='(https?|ftp|file)://[][:alnum:]\+&@#/%?=~_|!:,.;\(\)\[\$'\''*-]+' # Unanchored URL syntax
datetime_regex='[1-2][0-9]\{3\}[0-1][0-9][0-3][0-9][0-2][0-9][0-5][0-9][0-5][0-9]'
wayback_datetime_regex='[1-2][0-9]\{3\}[0-1][0-9][0-3][0-9][0-2][0-9][0-5][0-9][0-5][0-9][a-z]\{0,2\}_\?' # regex for Wayback datetime folder (with support for suffix indicating asset types)
etc_hosts=/etc/hosts            # Location of hosts file


################################################
# File and Layout settings
################################################
offline_file_system=default     # The target file system for offline output (viewing, etc.) as distinct from output hosted on a server
                                #  - 'default' (or empty) for use on file systems on common desktop operating system, particularly Unix and similar (including Linux and macOS) and Microsoft Windows
                                #  - 'unix' for file systems on Unix and similar
                                #  - 'windows' for file systems on Microsoft Windows
mss_file_permissions=600        # Default Unix file permissions for file creation
mss_dir_permissions=700         # Default Unix file permissions for directory creation
tmp_dir=tmp                     # Directory where temporary files are to be stored
tab="  "                        # tab spacing for file outputs
host_dir_mode=auto              # Host directory mode; for Wget, empty or 'no' corresponds to -nh, else host directory included 
long_filename_threshold=200     # Number of characters in filename to trigger (Wget) length checks - should be signficantly less than 255


################################################
# Credentials processing and storage
################################################
credentials_rc_file=.netrc      # 'Run commands' file for (temporary) storage of credentials - either .wgetrc or .netrc
credentials_cleanup=yes         # Delete references to credentials in temp files and .rc file
                                # on completion of run (y/n)?
credentials_manage_cmd=pass     # [Path to] binary for managing (and encrypting) credentials
credentials_manage_cmd_url=https://www.passwordstore.org/#download # URL where credentials manager may be downloaded
credentials_storage_namespace=MSS # define a MakeStaticSite-specific directory for storing credentials (usernames, passwords, tokens, etc.)
credentials_storage_mode=plain  # How to store credentials:
                                #  - 'config' to store in the configuration file, as-is;
                                #  - 'plain' to store separately, as-is, in plain text;
                                #  - 'encrypt' to store separately and encrypt;
credentials_extension=gpg       # Encryption file type extension
credentials_home="$HOME/.password-store" # Password-designated directory under which credentials are stored
credentials_namespace_suffix=
if [ "$credentials_storage_namespace" != "" ]; then
  credentials_namespace_suffix="/"
fi
credentials_path_prefix="$credentials_storage_namespace$credentials_namespace_suffix"


################################################
# Wget crawl settings (main run and extra URLs) 
################################################
wget_cmd=wget                   # [Path to] wget binary
wget_version_atleast=1.21       # The version needed to support full functionality
wget_version_secure_atleast=1.25 # The version needed to support better security
wget_version_security_ref=CVE-2024-10524 # Security advisory reference for user to review
wget_error_level=4              # The lowest Wget error code tolerated or else aborts (>8 for no tolerance)
wget_protocol_relative_urls=yes # Allow protocol-relative URLs to be fetched by Wget by prefixing a protocol (y/n)
wget_protocol_prefix=https      # Protocol to prefix protocol-relative URLs
wget_user_agent=mss             # Set browser user agent
                                # - 'wget' for Wget's default ‘Wget <version>’
                                # - 'mss' for 'MakeStaticSite/<version> (Wget/<version>; <MSS site URL>)'
                                # - empty string to not send any
                                # - otherwise a non-empty string, wrapped in quotes, e.g. "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15)"
wget_http_login_field=user      # Wget's user login field for HTTP authentication
wget_http_password_field=password # Wget's password field for HTTP authentication
wget_cookies=cookies            # cookies file name stem, no extension - added later
wget_cookies_min_filelength=5   # minimum number of lines for a valid cookies file
wget_cookies_nullify_user_agent=no # When wget_user_agent is defined above as a non-empty string, should it be reset to null for handling cookies (yes/no)
wget_post=wget_post             # Wget POST data file name stem

# Input file names for Wget
wget_inputs_main_stem=wget_inputs_main # input file name stem for web content to be retrieved in main run of Wget in phase 2
wget_inputs_extra_stem=wget_inputs_extra # input file name stem for additional assets to be retrieved by Wget in phase 3
wget_long_filenames=wget_long_filenames # input file name stem for URLs with very long filenames for assets already retrieved by Wget
rename_wget_tmps=yes            # Remove .tmp.html suffixes from (Wget temp) file names

# Core options for Wget (array)
#  In Wget, --mirror is equivalent to '--recursive --timestamping --level=inf --no-remove-listing'
#  or, in short form, ‘-r -N -l inf --no-remove-listing’, where -r: recursive; -N: timestamping; -l inf: infinite depth
wget_mirror_options=(--recursive -N --level=inf --no-remove-listing)
wget_core_options=("${wget_mirror_options[@]}" --convert-links --adjust-extension --page-requisites --tries=3)
wget_wayback_core_options=(--tries=3) # Specify additional recursion options in () brackets, e.g. (--recursive --level=2)
wget_wayback_max_redirects=3    # The maximum number of redirects allowed for the Wayback Machine.
wget_span_subdomains=yes        # Should Wget span additional subdomains (yes/no)?
                                # - 'yes': match on domain prefixes specified by wget_span_domains_expr
wget_span_subdomains_expr='(www\.|web\.|)' # An extended regular expression of subdomain prefixes to the primary domain that can be spanned in addition to the primary domain itself.
wget_default_page=index.html    # The Wget --default-page option (index.html by default)
wget_adjust_extensions="html,css" # The Wget list of file extensions that have the extension appended to match the HTTP response header when the extension doesn't exist.
prune_filename_extensions_querystrings=yes # Remove file name extensions thus added by Wget via --adjust-extension option (y/n)? 
wget_no_parent=auto             # Should capturing URLs with directories include the --no-parent option?
                                # auto or yes - check and add automatically
                                # otherwise no intervention
# Wget progress bar, currently used when output_level=quiet (leave empty to omit)  
wget_progress_indicator=(--show-progress --progress=bar:force:noscroll)
wget_refresh_mirror=no          # Ensure Wget outputs to an empty directory (y/n)?
wget_ignore_errors=             # Ignore errors generated by Wget (placeholder)

################################################
# Wget settings for extra URLs 
# and additional processing
################################################
# Core options (array) for Wget phase 3 assets
# -p (page requisites) to download entire asset, possibly page, in directory structure
# -nc (no clobber), in case assets have already been downloaded.
# But no recursion
wget_extra_core_options=(-p -nc --adjust-extension)
wget_threads=1                  # number of parallel threads for running Wget on assets (integer)
wget_extra_urls_depth=3         # number of times to call wget_extra_urls() to scan for and fetch extra URLs (integer)
feed_html=feed/index.html       # tail of invalid feed URLs generated by Wget
feed_xml=feed/index.xml         # tail of valid feed URLs as replacement
wget_url_candidates_optimisation=yes # Optimize the determination of extra URL candidates, avoiding duplication (y/n)?

# WARC support
warc_output=no                  # Generate WARC archives (y/n)?
warc_header_format=mss          # Header format for WARC files:
                                # - 'default' will use Wget defaults
                                # - 'MSS' will generate additional fields: 'software: MakeStaticSite/<version> (Wget/<version>)' ,
                                # operator: $USER environment variable, hostname $HOSTNAME
                                # - otherwise a non-empty string conforming to 'warcinfo' standard, wrapped in quotes, e.g. "Operator: Fred Blogs Archival Services|software:MakeStaticSite <version> ", fields separated by '|'
                                # Reference: https://iipc.github.io/warc-specifications/specifications/warc-format/warc-1.1/#warcinfo
warc_cdx=yes                    # Write CDX index files (y/n)?
warc_compress=yes               # Compress WARC files using gzip (y/n)?
warc_combine_output=yes         # Combine enumerated WARC files into one file (y/n)?

################################################
# Capture and processing of asset URLS and paths
################################################
windows_filename_illegal_chars='\:*?"<>|' # Quoted list of characters that cannot be used in Microsoft Windows file names because the file system does not allow it.
# Scope of assets to be captured from parent directories and extra domains
url_asset_capture_level=3       # (0 fewest, 5 most) for URL matching in determining assets to download and localise
url_wildcard_capture=no         # Use a wildcard for matching URLs in asset processing (y/n)?  If set to 'yes', when capturing asset URLs on pages, a simple regex capture group will be used instead of the input file of itemised URLs generated in phases 2 and 3
url_separator_chars="[,:(]"     # additional (regular expression capture) class of URL separator characters as used in, for example, data-src (comma) and JSON (colon).  Leave empty to omit.
url_grep_search_pattern="[^\\\"'<) ]" # URL terminating characters in grep searches (ERE notation); if link text contain ')', then this character can be removed
url_max_chars=2048              # Maximum number of characters permitted in a URL (for use in processing)
static_webpage_file_extensions="html,htm,xhtm,xhtml" # A list of common static web page file extensions. (Note that any file extension in this document assume a preceding dot '.')
webpage_file_extensions="$static_webpage_file_extensions,dhtml,cgi,php,php2,php4,phtml,asp,aspx,jsp,cfm,cfml" # A list of common web page file extensions, including those for server-side scripts. Not exhaustive.

# Specification of assets eligible for downloading by Wget in phase 3.
web_source_extensions="htm,html,xml,txt,css" # list of web document file extensions intended for assets search
web_source_exclude_dirs=        # list of directories to exclude from search and replace (relative to working mirror directory - prefix will be determined automatically). Dev note: this ought to be refined to be extension dependent
web_element_extensions="js,css,svg,map,ico" # list of file extensions for standard Web page components 
font_extensions="cff,ttf,eot,woff,woff2" # list of file extensions for Web fonts 
image_extensions="jpeg,jpg,gif,png" # list of file extensions for Web images
audiovideo_extensions="heic,webp,mp3,m4a,ogg,wav,avi,mpg,mp4,mov,ogv,wmv,3gp,3gp2" # list of file extensions for audio and video assets
#doc_extensions="pdf,doc,docx,odt,ppt,xls,xlsx" # list of file extensions for office documents
doc_extensions="doc,docx,odt,ppt,xls,xlsx" # list of file extensions for office documents
asset_extensions="$web_element_extensions,$image_extensions,$audiovideo_extensions,$doc_extensions,$font_extensions"  # list of file extensions for assets that may be retrieved by Wget in phase 3. If no extensions are defined, then cURL will be used to remove non-HTML assets, but all other assets will be accepted
asset_extensions_external="$web_element_extensions,$image_extensions,$font_extensions" # a more limited set for assets gleaned from external domains

# Other processing
base_tags_remove=yes            # Remove any <base> tags (y/n)? 
relativise_host_assets=yes      # Convert absolute links to relative links for assets on host (y/n)?
shorten_longlines=auto          # Break apart long lines to reduce processing time
                                # - 'off' to not touch any files
                                # - 'auto' to decide whether or not shorten on a per file basis according to criteria based on file size and number of lines in document
                                # - 'on' to apply line shortening to all files                                 
average_linelength_max=1000     # For 'auto', shorten lines when the average line length exceeds this number of characters. 
longest_linelength_max=10000    # For 'auto', shorten lines when the longest line length exceeds this number of characters. 
newline_inserts=('<\/script></<\/script>$'"'\n'"'<' '<\/style></<\/style>$'"'\n'"'<' '<\div></<\div>$'"'\n'"'<' '\\\"\,\\\"/\\\"\,$'"'\n'"'\\\"' '\}@media/\}$'"'\n'"'@media' '\}@font-face/\}$'"'\n'"'@font-face') # Replacements to be made for shortening line length (array)

# Query strings
prune_query_strings=yes         # Remove query strings appended to paths and URLs in anchors limited to files of type given in query_prune_list (y/n)?
query_prune_list="$web_element_extensions,$image_extensions,$audiovideo_extensions,$doc_extensions,$font_extensions" # List of file extensions in requests that may have query string appended for versioning or other non-essential purposes. For static sites these can be pruned without loss of functionality.
query_prune_always_list=css     # Comma-separated list of file extensions that always get pruned, especially for offline support.
extra_assets_allow_query_strings=yes # Allow Wget to fetch additional URLs with query strings in phase 3 (y/n)? 
extra_assets_query_strings_limit=100000 # Only fetch URLs with query strings when the total number of assets is less than this number 


################################################
# Directory management of downloaded assets
################################################
extra_assets_mode=contain       # how assets from extra domains should be incorporated
                                # - empty or 'off' to keep in separate directories under mirror ID
                                # - 'contain' will move the directories inside the assets directory (see below)
assets_directory=webassets      # directory immediately under main host directory for storing extra assets - from parent directories and extra domains
                                # (set empty to place assets in root, only if there is not an assets folder already)
imports_directory=imports       # directory immediately inside assets_directory for storing assets imported for extra domains

# URLs with directories
parent_dirs_mode=contain        # What to do with assets that lie above the mirrored directory
                                # - empty or 'off' to keep assets where they are after the Wget mirror
                                # - 'contain' will move the directories inside the assets directory
external_dir_links=             # What to do with links to resources on same domain, but outside the mirrored tree
                                # - empty or 'off' to not make relative, only point to the deployment domain 
                                # - 'local' or anything other than empty or 'off' will make relative, to assets directory
mss_cut_dirs=yes                # Option to cut directories.  When this is enabled, there is no need to specify Wget option --cut-dirs 
                                # - 'yes' or 'on' for a MakeStaticSite-specific cut that moves content of URL path to root
                                # - empty, 'no' or 'off' to support Wget --cut-dirs and not carry out further MakeStaticSite-specific processing
                                # - 'auto' to support Wget --cut-dirs and carry out further processing (not yet implemented)
path_doubleslash_workaround=yes # Make adjustments for the way Wget handles URL paths containing '//', as with Wayback Machine (y/n)?

# Other assets and resources
cors_enable=yes                 # Enable cross-origin resources once downloaded (y/n)?


################################################
# Robot and site map settings
################################################
link_rel_canonical=yes          # include <link rel="canonical"...> tag in header (y/n)?
link_href_tail=                 # The tail of canonical URLs, e.g. index.html or / (leave blank for /)
a_href_tail=                    # The tail for internal links, e.g. index.html or / (leave blank for /). The value should normally match link_href_tail
robots_create=yes               # Generate and overwrite robots.txt (y/n)?
robots_default_file=robots.txt  # file name for default robots.txt (inside lib/files/), with sitemap to be appended
sitemap_create=yes              # Generate and overwrite site map file (y/n)?
sitemap_file=sitemap.xml        # Name of sitemap (XML) file
sitemap_schema=http://www.sitemaps.org/schemas/sitemap/0.9 # Sitemap XML schema URL
sitemap_file_extensions=htm,html # List of file extensions allowed for inclusion in sitemap file


################################################
# Wayback Machine settings
################################################
mod_wayback=mod_wayback.sh      # Wayback Machine module filename
wayback_cli=no                  # Use a third-party client to download sites from the Wayback Machine (y/n)?  If not set to 'yes', then any Wayback sites will be retrieved natively using default (Wget).
use_wayback_id=no               # When retrieving natively, capture the original page rather than the Wayback Machine's processed version (y/n)?
wayback_hosts=web.archive.org,wayback.archive-it.org,www.webarchive.org.uk  # Partial list of Wayback Machine hosts
wayback_memento_check=yes       # Perform dynamic check for Memento site using HTTP request header (y/n)?
wayback_header="Memento-Datetime:" # Memento header search string
wayback_mementos_only=yes       # Only download assets with Memento URLs (y/n)? (This resets page_element_domains to be empty.)
wayback_assets_mode=original    # How to incorporate assets downloaded during phase 3
                                #  - 'off' to take no action, not use any
                                #  - 'original' to recreate original layout as far as possible (timestamps removed)
                                #  - 'timestamp' to leave and reference assets in Wayback Machine timestamped folders
wayback_timestamp_policy=any  # Timestamp policy
                                #  - 'exact' to only download and refer to assets with exact timestamp
                                #  - 'any' to download assets with any date
                                #  - 'range' to download subject to specified date range (see below)
wayback_date_from_earliest=     # Earliest date timestamp for Wayback Machine snapshot files
wayback_date_to_latest=         # Latest date timestamp for Wayback Machine snapshot files
wayback_snapshot_path_depth=3   # The number of directories to traverse to get to the original host directory (a magic number, default set for Internet Archive, until a suitable algorithm is determined).
wayback_search_regex="(href|src)[[:space:]]*=[[:space:]]*[\'\\\"][^#:>\'\\\"/[:space:]][^[:space:]:>]+[\'\\\"]" # Extended regular expression for matching the href or src attribute in a link

# Wayback Machine output's directory layout
wayback_sitename_hosts=         # Host domain[s] to base the top-level directory and zipfile names on (overrides setup settings)
                                #  - 'wayback' (or empty string) sets the stem based on the Wayback host name 
                                # E.g. web.archive.org
                                #  - 'primary' sets the stem based on the target primary domain 
                                # E.g. www.example.org
                                #  - 'both' sets the stem based on the concatenation of the Wayback host name and the target primary domain
                                # E.g. web.archive.org-www.example.org
wayback_sitename_timestamps=    # Which timestamps to include, specific to Wayback Machine mirrors
                                #  - 'wayback' (or empty string) appends the 'from'[-'to'] Wayback timestamp[s]
                                # E.g. web.archive.org19970412232929     
                                #      web.archive.org-www.mhs.ox.ac.uk19970412232929
                                #  - 'mss' appends the MakeStaticSite timestamp (note its distinguishing use of underscore)
                                # E.g. web.archive.org202409_30160154
                                #  - 'both' appends the 'from'[-'to'] Wayback timestamp[s] to the Wayback host portion and the MakeStaticSite timestamp to the target domain portion.
                                # E.g. web.archive.org202409_30160154-www.mhs.ox.ac.uk19970412232929
wayback_merge_httphttps=yes     # Merge http and https directories in main branch of Wayback mirror output (y/n)?
wayback_host_original_dir=yes   # Restore original host directory when generating a mirror of site archived by the Wayback Machine (y/n)?

# Processing of Wayback Machine output
wayback_links_relative_rewrite=yes # Should residual relative links (e.g., involving host subdomains) also be written (y/n)?
                                # - 'yes': ensure that any such links are rewritten
                                # - any other setting: leave, as is, rewriting only with respect to original host.
wayback_relative_links_clean=wayback # How to treat residual Wayback stems in hyperlinks (typically starting '/web')
                                # - ‘original’: restore links to original host  
                                # - 'wayback': make absolute residual Wayback-specific relative links (prefix with Wayback host) 
wayback_host_original_sitemap=yes # Restore original URLs when generating the sitemap for a site archived by the Wayback Machine (y/n)?
wayback_newsfeed_clean=yes      # Delete references to Wayback Machine host for newsfeeds (y/n)?
                                #  - 'no' to keep as is
                                #  - 'yes' to restore the original link
                                #  - otherwise convert to a relative link
wayback_code_clean=yes          # Delete (JavaScript) Playback code inserted by Wayback Machine (y/n)?
wayback_code_toolbar_re='<!-- BEGIN WAYBACK TOOLBAR INSERT -->.*<!-- END WAYBACK TOOLBAR INSERT -->' # HTML Toolbar Code inserted by the Wayback Machine (regular expression)
wayback_code_tags=head,html     # Comma-separated list of possible tags (in reverse depth order) immediately preceding Wayback rewrite JavaScript code
wayback_code_re='.*<script.*<!-- End Wayback Rewrite JS Include -->' # JavaScript code inserted by the Wayback Machine (regular expression)
wayback_folders_clean=yes       # Delete supporting directories created by the Wayback Machine that appear in the mirror (y/n)?
wayback_folders=_static         # Comma-separated list of Wayback Machine directory names that may appear in the mirror
wayback_comments_clean=yes      # Delete HTML comments inserted by Wayback Machine (y/n)?
wayback_comments_re='[^</]*JAVASCRIPT APPENDED BY WAYBACK MACHINE.*load_resource.*' # Comments appended by the Wayback Machine (regular expression)
wayback_links_clean=no          # Restore original URL links in web pages, removing Wayback prefixes (y/n)?
                                #  - 'yes' to remove all such links
                                #  - 'no' (or any other value) to keep as is

# Settings specifically for Wayback Machine downloader coded in Ruby
# https://github.com/hartator/wayback-machine-downloader
wayback_machine_downloader_url=https://github.com/hartator/wayback-machine-downloader # URL of Wayback Machine Downloader repository
wayback_machine_downloader_cmd=wayback_machine_downloader # [Path to] binary for the Wayback Machine Downloader
wayback_machine_only=           # Restrict downloading to URLs that match this filter (enclose in slashes // to treat as a regex and place in quotes)
wayback_machine_excludes=       # Skip downloading of URLs that match this filter (enclose in slashes // to treat as a regex and place in quotes)
wayback_machine_statuscodes=    # Accepted status codes. The default is '200' - OK.  Enter 'all for 30x (redirections), 40x (not found, forbidden) and 50x (server error). 
wayback_matchtype=prefix        # Wayback Machine CDX server match type:
                                #  - 'domain' will return all results from host domain and all its subdomains 
                                #  - 'host' will return results from host domain, but no other domains 
                                #  - 'exact' will return results matching URL exactly
                                #  - 'prefix' will return results for all results under a URL path


################################################
# CMS-specific constants
################################################
wget_reject_clause="*login*,*logout*" # wget --reject parameter (uses wildcard *) to avoid following logout links


################################################
# [module] WordPress-specific settings
################################################
mod_wp="mod_wp.sh"              # WordPress module filename
php_version_atleast=5.6         # Minimum PHP version for running WP-CLI
php_tutorial_install=https://kinsta.com/blog/install-php/
wp_cli_install=https://wp-cli.org/#installing
wp_content=wp-content           # WordPress content folder name
wp_plugins=plugins              # WordPress plugins folder name

wp_permalinks_postname=yes      # Enforce %postname% in permalinks (yes/no)?
wp_search_plugin=https://makestaticsite.sh/download/contrib/wp-static-search-1-1-1.zip
wp_search_dir=wp-static-search  # Name of search plugin directory under wp-plugins/
wp_search_page=search           # Name of WordPress search page

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
htmltidy_url=https://www.html-tidy.org/ # URL of HTML Tidy project
htmltidy_errors_file=errors_htmltidy # HTML Tidy errors file stem
htmltidy_options=(-m -q -indent --indent-spaces 2 --gnu-emacs yes --tidy-mark no) # Command line options for HTML Tidy (array).
# -modify, -m:              modify the original input files
# -quiet, -q:               suppress nonessential output
# -indent, -i:              indent element content
# --indent-spaces 2:        number of spaces Tidy uses to indent content
# --gnu-emacs yes:          change format for reporting errors to include filename in reports
# --tidy-mark no:           don't add meta element to indicate Tidy is a document generator
# --wrap 0:                 don't wrap text (no right margin)
htmltidy_source_extensions="htm,html" # list of web document file extensions intended for HTML Tidy


################################################
# Link checker settings
################################################
linkchecker=n                   # Use link checker (y/n)?
linkchecker_cmd=linkchecker     # [Path to] Link checker binary
linkchecker_url=https://linkchecker.github.io/linkchecker/ # URL of link checker (LinkChecker) project
linkchecker_log_file=log_linkchecker # Link checker log file stem
linkchecker_check_external=n    # Check external URLs (y/n)?
linkchecker_errors_match_file="Real URL   file" # match pattern for error output on local files
linkchecker_errors_match_http="Real URL   http" # match pattern for error output on remote URLs
linkchecker_options=() # Other command line options for link checker (array).


################################################
# Pagefind (static search) settings
################################################
pagefind=n                      # Use Pagefind to generate a site search (y/n)?
pagefind_cmd=pagefind           # [Path to] Pagefind binary or Node wrapper (npx -y pagefind)
pagefind_url=https://pagefind.app/ # URL of Pagefind project
pagefind_log_file=log_pagefind  # Pagefind log file stem
pagefind_options_glob="**/*.(?i){HTM,HTML}" # Glob options for what to index (see https://pagefind.app/docs/config-options/#glob)
pagefind_path_prefix="/"        # Path prefix (to support installation of Pagefind in a subdirectory) 
pagefind_home_page=             # A specific home page for embedding the search box - usually leave this empty to 
                                # use the page given in the URL, but for a frameset may be useful to specify a frame page. 
pagefind_pages=home             # Which pages to add Pagefind search box to
                                #  - 'home' will just add to the page corresponding to the original URL
                                #  - 'all' will add to every web page (not recommended for frames)
                                #  - a comma-separated list to specify a certain set of web pages.
pagefind_insert_after_re="<body[^>]*>" # Where to insert Pagefind's code to generate the search box.
pagefind_code="<link href=\"${pagefind_path_prefix}pagefind/pagefind-ui.css\" rel=\"stylesheet\"><script src=\"${pagefind_path_prefix}pagefind/pagefind-ui.js\"></script><div id=\"search\"></div><script>    window.addEventListener('DOMContentLoaded', (event) => { new PagefindUI({ element: \"#search\", showSubResults: true }); });</script>"


################################################
# Display settings
################################################
# Ink colours supported on all displays, using standard labels:
# black, red, green, yellow, blue, magenta, cyan, white
# A few additional colours that need 256-colour support, with custom labels:
# amber, lime, paleblue
ink_error=red
ink_warning=amber
ink_ok=green
ink_info=lime


################################################
# Cleanup settings
################################################
clean_query_extensions=no       # Remove query strings from filenames (yes/no)
system_files_cleanup=Thumbs.db,.DS_Store # List of unwanted system files, to be removed from mirror output
web_print_runtime_data=no       # Append MakeStaticSite runtime session data summary to web pages (yes/no)?

################################################
# Other runtime settings
################################################
timezone=local                  # Time zone: local|utc|utclocal
output_level=quiet              # stdout verbosity - silent|quiet|normal|verbose
log_level=normal                # Log level: silent|quiet|normal|verbose
log_filename=makestaticsite.log # Name of MakeStaticSite log file
trap_errors=no                  # Trap errors with immediate script termination (yes/no)?
run_unattended=no               # Is MSS running unattended (yes/no)?
extras_dir=extras               # Name of folder containing all the additions
force_ssl=yes                   # Convert anchors to deployment domain to https (yes/no)?
force_domains=yes               # Auto replace domain with deploy_domain (yes/no)?
domain_match_prefix=//          # Domain prefix for matches (in sed)
domain_subs_prefix=//           # Domain prefix for substitutions (in sed)
zip_omit_download=yes           # Omit download folder from website zip (yes/no)?
rsync_options=(-a -z -h)        # Core rsync options (excludes the output level)
#  -a archive mode preserves permissions, ownership, and modification times, etc
#  -z compression during transfer
#  -h outputs numbers in human-readable format
webserver_preview=no            # Launch a temporary webserver with a site preview (yes/no)? 
webserver_preview_cmd="python -m http.server 8000" # Command to run to launch the server. Other options listed at: https://askubuntu.com/questions/1102594/how-do-i-set-up-the-simplest-http-local-server


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


################################################
# Site options
################################################

# Options are listed in a specific order to support workflow.
# Each option has three parts, which need to be defined in a specific order - 
# default value, description, info
# The user can change only the first.

allOptions_yesno=( y n yes no Y N YES NO )

allOptions=(

url=https://example.com/
url__desc='URL of website being snapped'
url__info='Enter a website root URL or a path.  To capture a specific directory and no parents, check whether the URL requires a trailing slash and add the -np option in wget_extra_options below.'

require_login=n
require_login__desc='Does the site require a login (y/n)?'
require_login__info="If your website requires you to log in with a username and password (typically, via a web form) to see any content, then enter 'y' otherwise 'n'.  Normally this is only the case for an intranet or firewalled site."

login_path='/wp-login.php'
login_path__desc='Path to login page as a root relative URL'
login_path__info='Path to login page with respect to the web root, i.e. omitting host and starting with a slash.'

logout_path="/wp-login.php?action=logout"
logout_path__desc='Path to logout page as a root relative URL'
logout_path__info='Path to logout page with respect to the web root, i.e. omitting host and starting with a slash.'

login_user_field=log
login_user_field__desc='Web form username field'
login_user_field__info='This is the username field, not the username itself, in the web form used for submitting login credentials.  It can usually be gleaned by viewing the HTML source of the login page.'

login_pwd_field=pwd
login_pwd_field__desc='Web form password field'
login_pwd_field__info='This is the password field, not the password itself, in the web form used for submitting login credentials.  It can usually be gleaned by viewing the HTML source of the login page.'

cookie_session_string=wordpress_logged_in,wordpress_test_cookie 
cookie_session_string__desc='List of cookie names denoting a valid login session'
cookie_session_string__info='Comma-separated list, typically comprising name-attribute substrings, denoting a valid login session'

site_user=username
site_user__desc='Website username'
site_user__info='Please enter a site username (as would be entered to log in).  This should usually be an account with minimal privileges, sufficient to access to content intended for the public.'

site_password=password
site_password__desc='Website password'
site_password__info="Please enter the password for the username just supplied.  If you don't wish to enter it here, then you can continue with the setup and before running makestaticsite.sh manually edit the configuration file."

ssl_checks=n
ssl_checks__desc='Validate certificate in encrypted (SSL/TLS) connections (y/n)?'
ssl_checks__info="If you trust the SSL certificate of the site for which you are making a static version, then enter 'n'.  Otherwise, enter 'y' and store the certificate on your file system in PEM format.  Then either enter --ca_certificate={the_cert_file_path} in .wgetrc or --ca-certificate={the_cert_file_path} in wget_extra_options below."

asset_domains=
asset_domains__desc='Additional domains for asset retrieval and offline access'
asset_domains__info="Provide a comma-separated list of domains, typically hosted on CDNs, for static assets stored external to the main domain. MakeStaticSite can retrieve these and incorporate in the mirror output.  Leave empty if there are no extra domains."

page_element_domains=auto
page_element_domains__desc='Additional domains for web page elements'
page_element_domains__info="Provide a comma-separated list of domains that contain embedded content and/or contribute to the styling of a page.  These typically include fonts, CSS, images and other multimedia, provided by 3rd-party services.  MakeStaticSite can retrieve these and incorporate in the mirror output. Enter 'auto' (without quotes) to generate this list automatically.  Leave empty if all these elements are located under your primary domain."

wget_extra_options="-X/wp-json,/wp-admin --reject xmlrpc*,'index.html?'* --limit-rate=500k"
wget_extra_options__desc='Additional command line options for Wget'
wget_extra_options__info="Wget will be run with the following options as standard: --mirror --convert-links --adjust-extension --no-check-certificate.  You may add further options here, e.g., to supply http credentials: --user username (password will then be asked separately); to specify path to a certificate file: --ca-certificate={cert_file_path}; to exclude WordPress JSON directory: -X /wp-json; to exclude index files with query strings, --reject 'index.html?*'; to limit the download rate (N kilobytes/sec): --limit-rate=Nk. Otherwise leave empty."

input_urls_file=
input_urls_file__desc='Name of Wget input file for custom crawl URLs'
input_urls_file__info='If your site makes use of custom CSS or JavaScript, list their URLs in this file so that Wget can capture them.  Otherwise leave empty.'

wget_extra_urls=y
wget_extra_urls__desc='Use Wget to retrieve additional assets from the domain (y/n)?'
wget_extra_urls__info="This option will attempt to retrieve further assets by searching each downloaded file for further URLs and then re-running Wget, using the same options except that existing files will not be overwritten (no clobber)."

site_post_processing=y
site_post_processing__desc='Further refine the output after the first site capture (y/n)?'
site_post_processing__info="This option will attempt to convert further absolute paths for url_base to relative paths; replace remaining occurrences of the source domain with deploy domain; and convert feed files and references from index.html to index.xml. Note that the method of search and replace is blunt - all occurrences will be replaced!"

archive=y
archive__desc='Add the mirror site to an archive (y/n)?'
archive__info='If selected, this option means that each site snapshot generated by Wget is saved in its own date/time-stamped directory.'

local_sitename=examplewebsite
local_sitename__desc='Directory name for the mirror site and stem of zip file.'
local_sitename__info='If not already existing, a new directory with this name will be created inside the mirror/ directory.  It will also provide the stem of the name of the zip file.'

wp_cli=n
wp_cli__desc='Use WP-CLI to carry out tweaks on WordPress database (y/n)?'
wp_cli__info="Use WP-CLI to update the WordPress database configuration so that it generates pages amenable to Wget.  WARNING: these changes happen immediately and currently cannot be reversed by MakeStaticSite.  Choose 'no' for updating WordPress some other way (e.g. manually through the dashboard) or if the site is not using WordPress."

wp_cli_remote=n
wp_cli_remote__desc='Is the use of WP-CLI on a remote server (through ssh) (y/n)?'
wp_cli_remote__info="WP-CLI supports remote connections over ssh, though this depends on the remote version and the remote shell."

source_host=examplehost.net
source_host__desc="The server hosting your WordPress site - ip address or domain"
source_host__info="For WP-CLI, the server hosting your WordPress site - ip address or domain."

source_protocol=
source_protocol__desc='Internet protocol (if any) to interact with the source (server) hosting the WordPress site'
source_protocol__info='If the site is local to your machine, then leave this empty.  If on a remote hosting provider, in the Cloud, then this is typically ssh.'

source_port=22
source_port__desc='ssh port for the source'
source_port__info='ssh port. If left as empty string, then the default (usually 22) will be used.  It will likely need to be set if port forwarding is used.'

source_user=
source_user__desc="User account on source (remote host)"
source_user__info="The user account on remote host (assumes the use of ssh private-public key pair).  Leave blank if accessing locally."

site_path=/var/www/mywpdirectory
site_path__desc='Full path to WordPress directory'
site_path__info='Full path to WordPress directory, which is commonly inside the Web root, e.g. /var/www/somedirectory'

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

zip_filename=website.zip
zip_filename__desc='Zip filename for static snapshot'
zip_filename__info='The zip filename can be named for specific distribution purposes.'

zip_download_folder=download
zip_download_folder__desc='Storage location for zip download'
zip_download_folder__info='For WordPress, this might be wp-content/uploads'

deploy=n,y,y
deploy__desc='Deploy the output on a server (y/n)?'
deploy__info='Deployment can be on a server hosted locally, e.g. on your development machine, or remotely. Further questions will be asked to tailor your options.'

deploy_domain=mydomain.com
deploy_domain__desc="Domain name for your web site."
deploy_domain__info="Domain name for the static web site that you are deploying, which will be used to help ensure that non-static and non-HTML elements are properly delivered.  This is usually distinct from the domain of the host server."

deploy_remote=y
deploy_remote__desc='Deploy to a server on a remote host (y/n)?'
deploy_remote__info="Either indicate 'yes' for deployment on a remote server on the Internet or 'no' for a local server, e.g. on your file system or one shared with your development machine."

deploy_remote_rsync=y
deploy_remote_rsync__desc='Deploy using rsync over ssh (y/n)?'
deploy_remote_rsync__info="Indicate 'yes' for deployment on a remote server that supports rsync over ssh."

deploy_host=examplehosting.net
deploy_host__desc="Host (IP or domain) for deploying the static site"
deploy_host__info="Host (IP address or domain) for deploying the static site remotely.  Leave empty for deployment on local filesystem.  This is not generally the domain name for your site (which you can enter later)."

deploy_port=22
deploy_port__desc='ssh port on deployment server'
deploy_port__info='ssh port is usually 22, but will likely need changing if port forwarding is used.'

deploy_user=username
deploy_user__desc="Username (for remote host)"
deploy_user__info="Account username on remote host, where the static site is being deployed.  Leave empty for deployment on local filesystem."

deploy_path=~/webs/staticwebsite
deploy_path__desc="Path for deploying the static site"
deploy_path__info="Path for deploying the static site on the hosting provider."

deploy_netlify=n
deploy_netlify__desc="Deploy the output on Netlify (y/n)?"
deploy_netlify__info="Indicate 'yes' for deployment on Netlify using its command-line interface.  This assumes you have a Netlify account and have set up a site."

deploy_netlify_name=netlify-name-12abc3
deploy_netlify_name__desc="Netlify site name (alphanumeric sequence)."
deploy_netlify_name__info="Netlify site name - when first issued, the default format comprises an alphanumeric sequence that includes a couple of human-readable words.  The name can be changed in Netlify's site administration panel."

htmltidy=n
htmltidy__desc="Clean up mirror output using HTML Tidy (y/n)?"
htmltidy__info="HTML Tidy can clean up HTML output for better conformance to W3C standards along with 'pretty print' cosmetic refinement."

add_extras=n
add_extras__desc="Add additional files to the static output (y/n)?"
add_extras__info="Option to supplement the static snapshot with further files sourced from elsewhere. They may include non-static files such as scripts to reinstate essential functionality.  Please place them in the $extras_dir/ directory."

)

allOptions_deps=(
require_login="(login_path logout_path login_user_field login_pwd_field cookie_session_string site_user site_password)"
wget_extra_urls="(site_post_processing)"
wp_cli="(wp_cli_remote source_host source_protocol source_port source_user site_path wp_helper_plugins add_search wp_search_plugin wp_restore_settings)"
wp_cli_remote="(source_host source_protocol source_port source_user)"
wp_helper_plugins="()"
add_search="(wp_search_plugin)"
wp_restore_settings="()"
upload_zip="(zip_filename zip_download_folder)"
deploy="(deploy_remote deploy_remote_rsync deploy_host deploy_port deploy_user deploy_path deploy_domain deploy_netlify deploy_netlify_name)"
deploy_remote="(deploy_remote_rsync deploy_host deploy_port deploy_user deploy_netlify deploy_netlify_name)"
deploy_remote_rsync="(deploy_host deploy_port deploy_user deploy_path)"
deploy_netlify="(deploy_netlify_name)"
htmltidy="(htmltidy_cmd htmltidy_options)"
)

# Options and dependencies
options_min=(url)               # Level 0 options
options_std=(url local_sitename wp_cli site_path wp_helper_plugins add_search use_snippets upload_zip zip_filename zip_download_folder deploy deploy_domain deploy_remote deploy_remote_rsync deploy_host deploy_user deploy_path htmltidy add_extras) # Level 1 options
options_allow_empty=(asset_domains page_element_domains wget_extra_options input_urls_file) # Options that can have empty/null values
options_check_cmd=(wget_cmd htmltidy_cmd linkchecker_cmd pagefind_cmd) # Command line applications that need to be checked for existence
options_check_dir=(site_path)   # Directories that need to be checked for existence
options_check_url=(url)         # URLs that need to be validated
options_check_yesno=(ssl_checks require_login wget_extra_urls site_post_processing archive wp_cli wp_cli_remote wp_helper_plugins add_search wp_restore_settings prune_query_strings use_snippets upload_zip deploy deploy_remote deploy_remote_rsync htmltidy linkchecker linkchecker_check_external pagefind host_dir_mode mss_cut_dirs add_extras wget_span_subdomains url_wildcard_capture cors_enable prune_filename_extensions_querystrings warc_output wget_url_candidates_optimisation wayback_cli use_wayback_id wayback_memento_check wayback_mementos_only wayback_anchors_original_host wayback_links_relative_rewrite wayback_merge_httphttps wayback_host_original_dir wayback_host_original_sitemap wayback_code_clean wayback_folders_clean wayback_comments_clean wget_protocol_relative_urls extra_assets_allow_query_strings zip_omit_download webserver_preview clean_query_extensions credentials_cleanup wget_cookies_nullify_user_agent rename_wget_tmps relativise_host_assets web_print_runtime_data wayback_code_clean) # Options that take yes/no values
options_check_remote=(site_path) # options that need to be checked on a remote server
options_credentials=(site_user) # credentials that may/should be encrypted

options_nodeps_load=(offline_file_system add_search deploy deploy_remote use_snippets upload_zip ssl_checks url asset_domains page_element_domains require_login local_sitename wget_extra_urls_depth wget_wayback_max_redirects wget_span_subdomains url_wildcard_capture input_urls_file site_post_processing prune_query_strings archive web_source_exclude_dirs htmltidy linkchecker linkchecker_check_external pagefind pagefind_options_glob pagefind_home_page pagefind_pages host_dir_mode mss_cut_dirs add_extras wp_cli site_path zip_filename zip_download_folder deploy_path deploy_domain cors_enable prune_filename_extensions_querystrings warc_output wget_url_candidates_optimisation warc_header_format wayback_cli use_wayback_id wayback_memento_check wayback_mementos_only wayback_anchors_original_host wayback_links_relative_rewrite wayback_relative_links_clean wayback_merge_httphttps wayback_host_original_dir wayback_host_original_sitemap wayback_code_clean wayback_folders_clean wayback_comments_clean extra_assets_allow_query_strings zip_omit_download webserver_preview clean_query_extensions credentials_cleanup wget_protocol_relative_urls wget_cookies_nullify_user_agent rename_wget_tmps relativise_host_assets web_print_runtime_data wayback_code_clean) # Options that are not dependent on others
