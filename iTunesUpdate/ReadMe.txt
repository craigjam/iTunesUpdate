"iTunes Update" SlimServer Plugin

	v2.7.1: 5 October 2009

James Craig (james.craig@london.com)


iTunes Update is a SlimServer plug-in to update your iTunes database with Slimserver client listening data, user ratings and playlists. 


Features:
=========

* Updating of iTunes play count, skip count, last played & last skipped fields
 - When a track is determined to have been 'played', the iTunes playcount and last played fields are updated.

This is decided by 3 variables - minimum listen time (default 5s), percentage listen time (default 50%) and maximum listen time (default 15 minutes). If necessary, these settings can be modified in the iTunesUpdate.pm code. For some reason (buffering perhaps) it's very unlikely that a full 100% of time is ever registered, so don't set the % too high (This is particularly noticable on very short tracks).

 - If a track is not counted as played, the iTunes skipped count and last skipped fields are updated.
  Situations that are not considered to be skipping:
 	- stopping playback in the middle of a song
 	- switching player off
 	- changing tracks while paused

* Set iTunes rating from SlimServer

When the current track finishes playing the rating will be written to iTunes (even if the play count isn't changed). Tracks can be re-rated as many times as you like before they're written to iTunes.
There are two rating schemes:
a) full stars: use keys 0-5 on the remote (default setting)
b) half stars: use keys 0-9 and 'add' for 10. (enable this mode from the Plugin settings page.)

Rating from the SlimServer web page and Controller menus is done directly from the iTunesUpdate page or menu.
On SlimDevices players with displays, when in the iTunesUpdate menu the remote can be used to set a rating for the track currently playing (0 being no stars in iTunes) - Hold down the desired number until a message appears on the player's screen.

Rating should also work from the 'now playing' menu but this can be affected by other plugins registering the same keys.
To force rating from any player menus you will need to add a custom remote map. You'll find two example files in the iTunesUpdate plugin directory - CustomStars.map for normal ratings and CustomHalfStars.map for half-star rating. If you don't have a custom IR map, move the file you want to the IR directory (at the same level as Plugins in the SlimServer installation) and select the map file from Player Settings->Remote in the web interface. If you already have a custom map, copy the commands you want from my files to yours. 

* Save SlimServer current playlist to iTunes

The current playlist can be saved to iTunes directly from the web interface or Controller menus.
When in the iTunes Update menu (or 'now playing' screen, with notes as above) on a SqueezeBox holding down the play key will write the current client playlist to iTunes.
It will have the the same as current player with the current date and time added. 
This can take a while so be careful not to activate this multiple times!
  
* iTunes info displayed in SqueezeCenter interface
While playing music navigate to the iTunes Update menu on your Squeezebox or Controller or the web interface and the iTunes info for the current song will be displayed.

* import iTunes Downloaded Artwork into SqueezeCentre (Windows only)
As tracks are added to any SqueezeCentre player's current playlist, iTunes Update will copy any Downloaded Album artwork into SqueezeCentre. Artwork is saved for seven days.

* apply iTunes bookmarks in SlimServer (experimental feature).
With the bookmark option enabled in the iTunes Update settings, the plugin will apply bookmarks read from iTunes. For example if you have listened to 20 minutes of a 'bookmarkable' track in iTunes, then start listening to the same track in SlimServer, playback will start from the same point. When the track finishes, the bookmark in iTunes will be cleared.

Notes
=====
- There are two modes of operation, which can be changed from the SlimServer web interface in Server Settings - Plugins
	1. Direct update to iTunes (enabled by default on Windows/Mac Slimserver):
		Slimserver must be running on the same host as iTunes is run
		(iTunes does not need to be running before Slimserver - it will be started when necessary)
		Updates are performed direct to iTunes in real-time as songs finish playing

	2. Indirect update to iTunes (any Slimserver platform, default configuration on UNIX)
		iTunesUpdate logs play history and ratings to a file in the playlist directory (default: iTunesUpdate_hist.txt).
		The standalone program iTunesUpdate.pl can process this file and apply the updates.
		(iTunesUpdateWin.pl must be run on the iTunes host)
		Note: Saving of playlists & info display are not available in this mode of operation.

- The plugin will NOT work in 'direct update' mode if SlimServer is running as a service on Windows
	(SlimServer is installed as a service if you leave the 'Start Automatically' box checked on installation or have 'run automatically on system start' checked in the SlimTray app)
	In SlimServer 6.5.1 onwards, if you have SlimTray running, stop SlimServer and change to 'Run automatically on log' then start SlimServer. Otherwise disable the SlimServer service (the Services program can be found in the Administrative Tools folder) and run SlimServer as the iTunes user.  This can be automated by adding the SlimServer program to the Startup folder.

- If using the 'Direct Update' mode you may want to increase the 'iTunes rescan interval' setting (SlimServer- Server Settings - iTunes) from the default. Every time a track is played the change in iTunes library can trigger a library rescan once the interval has elapsed, which may interrupt playback. You can disable the automatic rescan by setting this value to 0, and set a daily rescan with the Scheduled Rescan plugin.

- SlimServer can take a while to start iTunes if not already open. Saving long playlists to iTunes can take a while. These actions may cause a pause in playback.

- Because SlimServer caches the MP3 tags, iTunes will not be updated if key tags (artist,album, track name) have been changed in iTunes and the SlimServer cache hasn't been updated.

- If you sync players, the slave players will stop recording their play data, on the assumption that a synchronized play counts as one listen. All tracks listened to while sync'd will be recorded by the *MASTER* unit only

- Make sure that you have the "Treat multi-disc sets as a single album" option selected in Server Settings/Behaviour/Grouping
(otherwise your albums will have different names in SlimServer and iTunes)

- If you want to use the save playlists features from the main menu disable the savePlaylist plugin as this uses the same button.

Installation
==============

Windows Only: 
If you wish to use 'direct access' mode, make sure that SlimServer is configured to 'start on login' from the SlimServer tray icon.

Mac Only:
1. Install 'Developer Tools' from your OSX DVD
2. Install Perl modules Mac::Applescript::Glue;
	To install from CPAN in the default directory.
	At the comand line enter:
	sudo perl -MCPAN -e shell
	(it asks for your password)
	You are then dropped into the CPAN shell.
	install Mac::AppleScript::Glue
	(This is case sensitive.)
	Eventually this completes successfully, or fails some of the tests..
	If tests fail, you need to force the installation:
	force install Mac::AppleScript::Glue

General:

1: Put iTunesUpdate directory (including subdirs) into the Plugins directory.
On the Mac the plugin needs to be installed in 
~user/Library/Application Support/Squeeze Center/Plugins (if SC7 is installed for just one user)
or
/Library/Application Support/Squeeze Center/Plugins (if installed for all users)

2: restart SlimServer.

3: to disable direct updates to iTunes (eg. if running a Windows SlimServer that is not on the iTunes machines)
change the direct update setting in SlimServer under Server Settings - Plugins.

4: if direct update is disabled:
	run/schedule iTunesUpdate.pl as desired on the iTunes host. 

	Usage is:
	iTunesUpdate.pl <iTunes Update history file> [loop time]
	e.g.
	iTunesUpdate.pl "C:\My Music\Playlists\iTunesUpdate_hist.txt"

	The default is to perform all updates in a single pass then exit. 
	Supply an optional loop time value to leave the process running and checking for new updates.

5: set the 'ignore filetype' option on if you wish to synchronise iTunes with SlimServer tracks regardless of filetype, e.g. playing flac in SlimServer and storing mp3 files in iTunes. Your files will have to share exactly the same path and filename up to the filetype extension.

Thanks
======
To Stewart Loving-Gibbard who wrote the SlimScrobbler plugin.
http://www.skyscratch.com/SlimScrobbler

Daniel Boss for getting the plugin working on OSX

Barcar for the half-star rating patch

Greg Alton for testing iTunesUpdate.pl on OSX

All SlimServer plugin writers for inspiration

Anyone who's answered a question of mine on the SlimDevices mailing lists

Versions
========
v2.7.1  - replace durationSecs with secs
...
v2.5.0  - Fix rating from Jive menu
v2.4.5  - Fix rating skipped tracks from iTunesUpdate script`
v2.4.4  - Jive menu added
	- custom icon added
	- fix on-screen messages
v2.4.3  - Fix crash on Jive menu
v2.4.2  - Fix version check in update script
v2.4.1  - Fix bug saving unset rating to update file
v2.4.0  - Jive menus added
        - fix ignore_filetype option for Mac
v2.3.1  - bug fixes for 2.3.1
v2.3.0  - Load artwork for all tracks added to playlists
v2.2.0	- Upgrade for SqueezeCenter 7.0
v2.1.2  - fix the ignore filetype option
v2.1.1	- note whether the user actually rated the track
v2.1.0  - display iTunes downloaded album artwork on Windows/Direct Update
	- fix some bugs in iTunesUpdate.pl courtesy of Ric Woodgate

v2.0.0	- iTunesUpdate.pl replaces iTunesUpdateWin.pl after testing OSX functionality courtesy of Greg Alton
v1.9.2  - missing use POSIX in .pl script
v1.9.1  - don't skip unless minimum threshold (5s) is passed. Increase min percent for play to 60.
v1.9.0  - support for iTunes 7 skip features

v1.8.0	- half star ratings from remote courtesy of Barcar
v1.7.5  - fixes for SS 6.5
	. fix bugs in setup options
v1.7.4  - web improvements when direct update off
v1.7.3  - added ignore filetype option
v1.7.2  - implemented TrackStat rating hook so that TrackStat ratings are saved to iTunes
v1.7.1  - slashes changed direction in SlimServer!
v1.7.0  - save rating in SlimServer db
        . save playlist from web page/menu
v1.6.3	- allow for half ratings in web page
v1.6.2  - fixed crash on firmware upgrade
v1.6.1  - fixed web pages
v1.6	- changes for SS 6.5
v1.5.2	- tweaks to web page & Fishbone template
v1.5.1	- dereference OSX date object?
v1.5    - created web page
v1.4.2	- fixed rating issue in iTunesUpdateWin.pl
v1.4.1  - changed getting of artist/album names from SlimServer
        . removed some logging
v1.4    - display iTunes info in plugins section
v1.3.4  - stop if disabled while running
v1.3.3  - use recomposeUnicode to fix iTunes Unicode read from Library XML on OSX
v1.3.2	- fixed UTF8 support
	. fixed typo in iTunesUpdateWin.pl
v1.3.1	- fixed 1.3 changes for Windows
v1.3	- some changes for OSX from Daniel Boss
        . disable creating playlists as this doesn't work
        . check the actual file path rather track attributes
v1.2	- create initPlugin() function so not started etc. if disabled
v1.1	- Changed directory structure
	- Fixed incorrect number key reassignment
	. Fixed dateformat typo in iTunesUpdateWin.pl
	. Changes for SlimServer v6.0
	. Search match only on location
	. Fixed incorrect function name in openiTunes()
v1.0	- Mac platform support (code provided by Daniel Boss)
v0.7	- Changed date format used to YYYY-MM-DD HH:MM:SS
	. Close OLE object cleanly
v0.6	- Change to getDisplayName for v6.0
	. Correct plugin name in strings
	. Location match case insensitive 
v0.4	- Fixes to iTunesUpdateWin.pl (suggested by Jesse David Hollington)
	. Change UNIX slash direction to match iTunes
	. Match path from end of string to ignore preceding share name
v0.3	- Ignore 'empty client' commands
	. fix blank space regexp and code
	. Remove many log messages
	. Standardise remaining log messages
	. Only attempt to log play of files 
	. Fixed creation of settings on first run
	. Add 'show messages' to plugin settings
v0.2 	- Added option of separate history upload
	. Created standalone script for Windows history upload
	. Created Mac functions and appleScript prototypes
v0.1 	- First release
