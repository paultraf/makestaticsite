# MakeStaticSite &mdash; a Bash shell script to generate and deploy static websites

MakeStaticSite (project site [https://makestaticsite.sh/](https://makestaticsite.sh/)) is a set of Bash shell scripts that configure and use [Wget](https://www.gnu.org/software/wget/) to generate a static website from a (typically dynamic) website, with various options to tailor and deploy the output.  It aims to improve the performance and security of public-facing websites, whilst allowing continuity in the way they are developed and maintained, without requiring technical know-how on behalf of users. 


## Table of Contents

* [About](#about)
  * [Requirements](#requirements)
  * [Features](#features)
  * [Limitations](#limitations)
  * [Acknowledgements](#acknowledgements)
  
* [Installing](#installing)
  * [Layout](#layout)
  
* [How to use](#how-to-use)
  * [First run](#first-run)
  * [Customisation](#customisation)
  * [Workflow](#workflow)
  * [Options](#options)
  * [Snippets](#snippets)
  * [Newsfeeds](#newsfeeds)

* [Further work](#further-work)


## About

MakeStaticSite provides a convenient means to set up and manage the automated creation and deployment of static (or flat) versions of websites.  These include content management systems (such as [WordPress](https://wordpress.org/) and [Drupal](https://drupal.org/)) that can, for example, be administered locally and then deployed remotely to a hosting provider or Content Distribution Network (CDN).

It delivers a version of the site that preserves content and look and feel, in a static format that is inherently fast and secure.  In this mode, MakeStaticSite is not intended as a strict archival tool as the output is not an exact mirror &mdash; for example, it has its own canonical layout and modifies internal links accordingly; further files may be added; RSS feeds are saved and then renamed with `.xml` extensions, and so on.

Even so, some archival functions have been added, with native support for the Wayback Machine, focused mainly on the [Internet Archive service](https://web.archive.org/).  It can also generate [WARC (Web ARChive)](https://iipc.github.io/warc-specifications/) files (leveraging [Wget's support](https://www.gnu.org/software/wget/manual/wget.html#index-WARC)) with an option to concatenate multiple archives (one for each run of Wget) as a single compressed `.warc.gz` file.  The result can be played back with tools such as [ReplayWeb.page](https://replayweb.page/).

The goal is for anyone who has a little familiarity with the command line to be able to use the tool to assist in maintaining their sites.  Similarly, a scripting-based approach has been chosen to make the code widely accessible for developers to further fine-tune;
a number of refinements are already included that augment the standard use of [Wget](https://www.gnu.org/software/wget/), such as support for arbitrary attributes and, in the case of WordPress, the use of [WP-CLI](https://wp-cli.org/) to prepare sites beforehand.

MakeStaticSite is available under AGPL version 3 license.  See the COPYING file for more information.

### Requirements

This software should work on version 3.2 of GNU [Bash](https://www.gnu.org/software/bash/), though version 4+ is recommended. 

MakeStaticSite depends on GNU [Wget](https://www.gnu.org/software/wget/).  Other requirements are: [rsync](https://rsync.samba.org/) for remote deployment; [WP-CLI](https://wp-cli.org/) for optimising WordPress sites ahead of running Wget; and [HTML Tidy](https://www.html-tidy.org/) for refining HTML output for better conformance with W3C standards.  The latest versions are generally recommended.  Otherwise, apart from Internet connectivity, there are few dependencies beyond what the shell already provides.

Please note that the system is not designed for [Wget2](https://gitlab.com/gnuwget/wget2), though it would be useful to support that in future.


### Features

* A straightforward command line interface
* Able to create static versions of a wide range of dynamic websites, with support for retrieving content from the site root or any subdirectory 
* Support for managing multiple sites, each with custom settings
* Setup script, which guides users with an interactive dialogue and automatically generates a configuration file.
* During setup, choose from three run levels to determine the amount of customisation - from minimal to advanced.
* In addition to the main host domain, additional assets such as JavaScript, CSS and images can be retrieved and collated from other domains and subdomains
* A phased-based workflow separating different aspects in the build process
* Deep search for orphaned Web assets, later retrieved in further runs of Wget
* Suitable for batch processes, allowing operations to be scaled up so that any or all of the sites are updated in one process.
* Support for HTTP basic authentication and/or CMS login (experimental, only tested with WordPress)
* Partial support for sites archived by the [Wayback Machine](https://web.archive.org/), incrementally spanning as many snapshots as a crawl requires.
* Basic support for generating WARC files (and also content indexes).
* Runtime settings include verbosity (amount of information) for terminal output and logging to file
* Option of a downloadable copy of the entire site (ZIP file) for offline use 
* Local and remote (server) deployment options, including rsync over ssh and [Netlify](https://netlify.com).
* For [WordPress](https://wordpress.org) installations, optional WP-CLI-based site streamlining with a drop-in search replacement (WP Offline Search plugin) that works offline.
* Snippets &mdash; for tweaking page with offline variants using chunks of HTML.
* Assistance for W3C standards compliance with [HTML Tidy](https://www.html-tidy.org/). The system also generates a sitemap XML and `robots.txt` file under the primary domain to match the outputted files.
* Support for the Wayback Machine, including date-time ranges.

### Limitations

* MakeStaticSite is prototype software, provided as-is and tested on only a few sites, but in the hope that it will prove useful and become community-supported.
* The system is designed for the original GNU Wget, whereas most development effort is now on GNU Wget2.
* Not a general crawler, but designed to retrieve from a single site, with supporting assets (CSS, multimedia, etc.) incorporated from other domains and subdomains.
* This is a _static_ HTML crawler that retrieves web content without running any JavaScript for client-side rendering, not a _dynamic_ crawler that can process the JavaScript on that page and then render it. Even so, the workflow architecture might support processing of web page outputs in this way.
* It is not a good fit for sites that uses query strings extensively, as is the case for collections databases with a large inventory.  Whilst query strings are supported in the initial run of Wget, requests for URLs in the post-processing do not currently include query strings.
* The script can only provide a snapshot of comments, discussions, surveys, etc. that are provided by the Website itself; the interactivity of such components is generally lost.  In this case, this kind of interactivity will need to be provided by third-parties, typically through the use of embedded JavaScript.
* Performance: MakeStaticSite output is not instant.  It typically takes up to a few minutes to build a site, which, depending on usage scenario, may or may not be a significant duration. For Wayback Machine sites it is slower. Some acceleration is possible by running Wget threads in parallel (see the `wget_threads` option).
* For WordPress sites, using WP-CLI remotely over ssh may not be fully supported by hosting providers running jailed shells for shared hosting. In that case, WordPress updates need to be done manually.

### Acknowledgements

Many thanks to various developers for sharing their knowledge on shell scripting, particularly on blogs and Q&A websites such as [Stack Exchange](https://stackexchange.com/) and to those who have tested, commented on and otherwise supported MakeStaticSite.

## Installing

The source distribution is made available as a gzipped tar file. Download the latest version from:

[https://makestaticsite.sh/download/makestaticsite_latest.tar.gz](https://makestaticsite.sh/download/makestaticsite_latest.tar.gz) 

Once downloaded, from the command line run the following to extract it:

    tar -xzvf makestaticsite_latest.tar.gz
    
This will create a `makestaticsite` directory.  Enter it and then make the scripts executable:

    chmod u+x *.sh

### Layout

    .
    ├── config/                 # site configuration files
    ├── extras/                 # additional site files (copied over)
    ├── lib/                    # library files
    ├── log/                    # log files (generated)
    ├── tmp/                    # temporary files (generated)
    ├── makestaticsite.sh       # main script
    ├── setup.sh                # setup script
    ├── version_history.txt     # summary of changes for each version
    ├── COPYING                 # software license
    └── README.md


## How to use

### First run

Once extracted, to try it out for the first time, at the command line enter the `makestaticsite` directory and run `./setup.sh` on a URL of your choosing.

<pre>
./setup.sh -u <em>url</em>
</pre>

(where <em>url</em> can be a URL of a live site or a [Memento](https://mementoweb.org/guide/quick-intro/) of a Wayback Machine such as
[https://web.archive.org/web/20250125054844/https://makestaticsite.sh/about/](https://web.archive.org/web/20250125054844/https://makestaticsite.sh/about/), a snapshot on the Internet Archive.)

This will set up a configuration file with default options, which is then supplied to the main script `makestaticsite.sh` to generate the site. The terminal output will provide various information, including the location of the output. 

### Customisation

For standard usage, at the command line run `./setup.sh`

You will be asked a series of questions (with suggested defaults) about the site you are mirroring with (for WordPress) options to tweak it beforehand; then, the precise `wget` options to create the mirror, how it should be deployed (locally or on a remote server), whether to create a zip file, and various other options.

Once you have set up a configuration, `mysite.cfg` for a domain `example.com`, say, you can proceed to build the static version with: 
<pre>
./makestaticsite.sh -i <em>mysite</em>
</pre>
It will proceed to generate a static mirror in the following directory: 
<pre>
mirror/<em>mirror_id</em>/example.com
</pre>
where `mirror_id` is a site identifier based on `mysite`; when the `archive` option is set, it is `mysite` concatenated with a timestamp. 

For other command-line options, run:

    ./makestaticsite.sh -h

Manual intervention should be minimal &mdash; mainly required when Wget encounters errors or when you are using WordPress and opt to add an offline search facility, in which case you will be prompted to go to the WordPress dashboard and create the search index.

### Workflow

MakeStaticSite divides its work into *phases*, of which there are ten altogether, which may be regarded as a pipeline.

1. Prepare the CMS
2. Generate static site
3. Augment static site
4. Refine static site
5. Add extras
6. Optimise
7. Use snippets
8. Create offline zip
9. Deploy
10. Conclude (summary report)

Accordingly, you can run the script with arguments `p` and `q`, specifying start and end phases respectively such that:
`1 <= p <= q <= 10`

There are broadly two use cases.  

(Case 1) When creating a site for the first time, you can opt to finish at any intermediate phase as far as the conclusion.  

<pre>
./makestaticsite -i mysite -q <em>END_NUM</em>
</pre>

(where `END_NUM` is the phase where it stops.)

Thus, to just carry out an initial run of Wget and not carry out further processing, set `END_NUM` to 2.

(Case 2) An existing mirror may be modified, perhaps subsequent to a run abbreviated as above.  Here, both the start and end phases may be specified:
<pre>
./makestaticsite -m <em>mirror_id</em> -p <em>START_NUM</em> -q <em>END_NUM</em>
</pre>
(where the argument `-m` expects a mirror ID, `START_NUM` is the phase where the script starts processing, and `END_NUM` is the phase where it stops.)


### Options

The customisation of MakeStaticSite is carried out through two sets of options.  We provide just a brief description here apart from those [relating to Wget](#wget) as this is core to the whole operation.

 * **Configuration options** define the target, i.e. the site you are capturing, any authentication requirements, options for Wget, what kinds of refinement to carry out and how to deploy the end result.
   
   The options are stored in `.cfg` files in the `config` directory.  They can be created manually, but it's recommended to use the setup script and then tweak as needed.
   
   Details: [https://makestaticsite.sh/help/configuration/](https://makestaticsite.sh/help/configuration/)

 * **Runtime options** set the general parameters for running MakeStaticSite on a particular system.  These settings, stored in `lib/constants.sh`, apply to any configuration file supplied, so are to be treated as universal constants.  They can be tweaked on any given run, but it is strongly recommended that a backup be made first.
 
   Details: [https://makestaticsite.sh/help/options/](https://makestaticsite.sh/help/options/)
  

#### Wget

Wget is at the heart of MakeStaticSite and needs to be precisely configured with multiple command-line arguments to make a faithful snapshot of a site.  This is why a warning is given if the version used is not very recent.   Also, a single run might not be sufficient to capture everything, particularly orphaned links, so MakeStaticSite provides a separate process (when `wget_extra_urls` is set) to gather additional URLs and then Wget is called again for each URL that is discovered.

There are several variables that contribute arguments, some are basic and should be included in every run, whilst others are site-specific.

(1) Configuration options

* `wget_extra_options` (default: `-X/wp-json,/wp-admin --reject xmlrpc*`) should specify what directories should be ignored (`-X`) and what file extensions not to follow (`-R` or `--reject`).  A default setup of a CMS such as WordPress typically exposes various APIs for data retrieval, which depend on server-side scripting.  These are redundant and should be removed, ideally within the CMS, with these arguments for Wget acting as a fallback.

A couple of other parameters that could be supplied here:

* `--spider` for just testing the `wget` operation without downloading files.  This will still report errors (and also create the directory structure).

* `--limit-rate=100k` limits the `wget` download rate to about 100KB per second.

Please refer to the [Wget manual](https://www.gnu.org/software/wget/manual/wget.html) for details of these and other options.


(2) Runtime options

* `wget_core_options` (default: `--mirror --convert-links --adjust-extension --page-requisites`) is a fairly standard set of arguments for generating a static mirror (phase 2); `--adjust-extension` generates files with `.html` extension, making the output suitable for offline browsing, which is one of the main goals of the project.  

* `wget_extra_core_options` (default: `-r -l inf -nc --adjust-extension`) is a trimmed-down version of `wget_core_options` to be used in phase 3 when Wget is rerun with the assumption that hidden URLs are assets, not Web pages, which should be left alone to preserve navigation integrity.

* `wget_reject_clause` (default: `*login*,*logout*`) is added automatically to `wget_extra_options` (login/logout links are redundant in a static site and should not be followed).

Another option to facilitate crawling a remote site:

* `wget_user_agent` (default is empty) can be specified in the case that a host server is configured to forbid access to content without the receipt of a user agent string in a certain format (not usually including Wget).  To circumvent this issue a suitable string can be specified here.


### Snippets

Snippets provide a means to make changes to the web pages generated by Wget.  For example, when mirroring a CMS, there may be (links to) login pages that should be hidden. 

A _snippet_ is a chunk on HTML to be substituted for another chunk in the original web page on the host (`$url`).  Each one is assigned a numerical ID, using fixed point notation with three decimal places, i.e., between 000 and 999.  They are stored as files in the `snippets/` directory inside MakeStaticSite's top-level directory, with filename matching their ID.  Thus, a snippet with ID 001 the corresponding file is `snippet001.html`.  A snippet may be used in more than one site, hence they are stored together.  To differentiate sets of snippets, a numbering convention may be used, e.g., 1xx for site 1, 2xx for site 2.

To incorporate snippets, the following pair of tags need to be included in the source HTML of any page where a replacement needs to be made (in WordPress, when using the Gutenberg editor, you can insert them by using the `<code>` block).  For ID 001, say, insert the following HTML before the content to be changed:

    <!--SNIPPET001BEGIN-->

And insert the other immediately after the content:

    <!--SNIPPET001END-->

An index to all the snippets is stored in `snippets.data`, which lists the path to each file to be modified followed by a list of snippet identifiers.  A simple tag is used to demarcate sets of snippets for a particular site, where the element name corresponds to the local site name.

The following code specifies three snippets for one site and one for another:

    <sigalaresearch>
    index.html:1
    about/website/index.html:2,3
    </sigalaresearch>
    <ptworld_local>
    contact/index.html:4
    </ptworld_local>

After a Wget mirror is created, the script will match on the `<$local_sitename>` and work through lines inside the tag pair, extracting the file path and snippet IDs.  It will  proceed to create a temporary copy of the file and path and apply the relevant snippet substitution.  Depending on the settings, the revised file may be deployed and/or included in the zip file. 

Once a snippet has been applied, the SNIPPET tag is removed, whereas if a SNIPPET tag is visible, the snippet has not yet been applied.  The latter is true for content within the `mirror/` directory, which contains the 'raw' snapshot before applying snippets; files which have been changed are stored in the `subs/` directory.


### Newsfeeds

MakeStaticSite attempts to adjust Wget output to maintain support for RSS feeds.  Currently targeted at WordPress, it renames files inside `feed/` directories from `index.html` to `index.xml`.  To properly support this in deployment, on the web server, add `index.xml` as the last entry to the `DirectoryIndex` directive in `.htaccess` at the site's root.


## Further work

Many improvements could surely be made to improve the quality of the code as well as extend it, with i18n being a high priority.  Another key requirement is to add support for Wget2, and HTTrack should also be considered.  Also, a properly implemented modular architecture would enable enhanced support for a variety of content management systems (CMS).  Whilst MakeStaticSite is authored in Bash, versions for other shells should be possible and might not require a great deal of modification. 

Details: [https://makestaticsite.sh/developers/further-work/](https://makestaticsite.sh/developers/further-work/)

