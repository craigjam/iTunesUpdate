# 				iTunesUpdate.pm 
#
#    Copyright (c) 2004-2007 James Craig (james.craig@london.com)
#
#
#    Portions of code derived from the SlimScrobbler plugin
#    Copyright (c) 2004 Stewart Loving-Gibbard (sloving-gibbard@uswest.net)
#
#    This program is free software; you can redistribute it and/or modify
#    it under the terms of the GNU General Public License as published by
#    the Free Software Foundation; either version 2 of the License, or
#    (at your option) any later version.
#
#    This program is distributed in the hope that it will be useful,
#    but WITHOUT ANY WARRANTY; without even the implied warranty of
#    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#    GNU General Public License for more details.
#
#    You should have received a copy of the GNU General Public License
#    along with this program; if not, write to the Free Software
#    Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA

use strict;
use warnings;
                   
package Plugins::iTunesUpdate::Plugin;

use Data::Dumper;

use Slim::Player::Playlist;
use Slim::Player::Source;
use Slim::Player::Client;

use Slim::Utils::Misc;
use Slim::Utils::OSDetect;
use Slim::Utils::Strings qw(string);
use Slim::Utils::Unicode;

use Time::HiRes;
use Class::Struct;
use POSIX qw(strftime);
use File::Spec::Functions qw(:ALL);
use File::Path;
use File::Find;

use Plugins::iTunesUpdate::Time::Stopwatch;

use vars qw($VERSION);
$VERSION = substr(q$Revision: 2.1.2 $,10);

#################################################
### Global constants - do not change casually ###
#################################################

# There are multiple different conditions which
# influence whether a track is considered played:
#
#  - A minimum number of seconds a track must be 
#    played to be considered a play. Note that
#    if set too high it can prevent a track from
#    ever being noted as played - it is effectively
#    a minimum track length. Overrides other conditions!
#
#  - A percentage play threshold. For example, if 50% 
#    of a track is played, it will be considered played.
#
#  - A time played threshold. After this number of
#    seconds playing, the track will be considered played.
my $ITUNES_UPDATE_MINIMUM_PLAY_TIME = 5;
my $ITUNES_UPDATE_PERCENT_PLAY_THRESHOLD = .60;
my $ITUNES_UPDATE_TIME_PLAY_THRESHOLD = 1800;

# Indicator if hooked or not
# 0= No
# 1= Yes
my $ITUNES_UPDATE_HOOK = 0;

# filename to save iTunes update data to
my $ITUNES_UPDATE_HIST_FILE = "iTunes_Hist.txt";

# persistent handle for iTunes
my $iTunesHandle=();
my $iTunesVersion;
# persistent os variable
my $os;
# Each client's playStatus structure. 
my %playerStatusHash = ();

my $cacheFolder;
my $cache;

##################################################
### SLIMP3 Plugin API                          ###
##################################################

my $ITUNES_UPDATE_MULTIPLIER_FULLSTAR = 20;
my $ITUNES_UPDATE_MULTIPLIER_HALFSTAR = 10;
my $ITUNES_UPDATE_MULTIPLIER = 20;

my %halfstar_mapping = ('play.hold' => 'savePlaylistToiTunes',
	'0.hold' => 'saveRating_0',
	'1.hold' => 'saveRating_1',
	'2.hold' => 'saveRating_2',
	'3.hold' => 'saveRating_3',
	'4.hold' => 'saveRating_4',
	'5.hold' => 'saveRating_5',
	'6.hold' => 'saveRating_6',
	'7.hold' => 'saveRating_7',
	'8.hold' => 'saveRating_8',
	'9.hold' => 'saveRating_9',
	'add.hold' => 'saveRating_10',
	'0.single' => 'numberScroll_0',
	'1.single' => 'numberScroll_1',
	'2.single' => 'numberScroll_2',
	'3.single' => 'numberScroll_3',
	'4.single' => 'numberScroll_4',
	'5.single' => 'numberScroll_5',
	'6.single' => 'numberScroll_6',
	'7.single' => 'numberScroll_7',
	'8.single' => 'numberScroll_8',
	'9.single' => 'numberScroll_9',
	'0' => 'dead',
	'1' => 'dead',
	'2' => 'dead',
	'3' => 'dead',
	'4' => 'dead',
	'5' => 'dead',		
	'6' => 'dead',
	'7' => 'dead',		
	'8' => 'dead',
	'9' => 'dead',		
);

my %fullstar_mapping = ('play.hold' => 'savePlaylistToiTunes',
	'0.hold' => 'saveRating_0',
	'1.hold' => 'saveRating_1',
	'2.hold' => 'saveRating_2',
	'3.hold' => 'saveRating_3',
	'4.hold' => 'saveRating_4',
	'5.hold' => 'saveRating_5',
	'0.single' => 'numberScroll_0',
	'1.single' => 'numberScroll_1',
	'2.single' => 'numberScroll_2',
	'3.single' => 'numberScroll_3',
	'4.single' => 'numberScroll_4',
	'5.single' => 'numberScroll_5',
	'0' => 'dead',
	'1' => 'dead',
	'2' => 'dead',
	'3' => 'dead',
	'4' => 'dead',
	'5' => 'dead',		
);

my %mapping = ();

sub defaultMap { 
	# Alter mapping for functions & buttons in Now Playing mode.
	if (Slim::Utils::Prefs::get("plugin_itunesupdate_halfstar")) {
		iTunesUpdateMsg("Enabling half star ratings\n");
		%mapping = %halfstar_mapping ; 
		$ITUNES_UPDATE_MULTIPLIER = $ITUNES_UPDATE_MULTIPLIER_HALFSTAR;
	} else {
		iTunesUpdateMsg("Enabling full star ratings\n");
		$ITUNES_UPDATE_MULTIPLIER = $ITUNES_UPDATE_MULTIPLIER_FULLSTAR;
		%mapping = %fullstar_mapping;
	}
	Slim::Hardware::IR::addModeDefaultMapping('playlist',\%mapping);
	return \%mapping; 
}

sub getDisplayName()
{
	return 'PLUGIN_ITUNES_UPDATER';
}

sub strings() 
{ 
	return '
PLUGIN_ITUNES_UPDATER
	EN	iTunes Update

PLUGIN_ITUNES_UPDATER_ACTIVATED
	EN	iTunes Update Activated...

PLUGIN_ITUNES_UPDATER_NOTACTIVATED
	EN	iTunes Update Not Activated...

PLUGIN_ITUNES_UPDATER_HIT_PLAY_TO_START
	EN	Hit play to start iTunes Updates from this client...

PLUGIN_ITUNES_UPDATER_HIT_PLAY_TO_STOP
	EN	Hit play to stop iTunes Updates from this client...

PLUGIN_ITUNES_UPDATER_RATING
	EN	iTunes Rating

PLUGIN_ITUNES_UPDATER_LAST_PLAYED
	EN	iTunes Last Played

PLUGIN_ITUNES_UPDATER_PLAY_COUNT
	EN	iTunes Play Count

PLUGIN_ITUNES_UPDATER_LAST_SKIPPED
	EN	iTunes Last Skipped

PLUGIN_ITUNES_UPDATER_SKIP_COUNT
	EN	iTunes Skip Count

PLUGIN_ITUNES_UPDATER_SAVE_PLAYLIST
	EN	Save playlist to iTunes

PLUGIN_ITUNES_UPDATER_SAVED_PLAYLIST
	EN	Saving playlist to iTunes...

PLUGIN_ITUNES_UPDATE_SETUP_GROUP
	EN	iTunes Update

PLUGIN_ITUNES_UPDATE_SETUP_GROUP_DESC
	EN	Choose whether the iTunes Update plugin will update the iTunes database directly or save information to a history file for later processing. Set this to "off" if you have SlimServer running as a service (e.g. selected "start automatically" at installation) or are not running this SlimServer on Windows. Use buttons 0 - 5 to represent stars unless half star setting is enabled.

PLUGIN_ITUNES_UPDATER_DIRECT_UPDATE
	EN	Direct Update

PLUGIN_ITUNES_UPDATER_SHOW_MESSAGES
	EN	Write messages to log

PLUGIN_ITUNES_UPDATER_IGNORE_FILETYPE
	EN	Ignore filetype

PLUGIN_ITUNES_UPDATER_IGNORE_FILETYPE_DESC
	EN	Update matching tracks in iTunes even if they have a different filetype from those in SlimServer

PLUGIN_ITUNES_UPDATER_NO_TRACK
	EN	Nothing being played!

PLUGIN_ITUNES_UPDATER_NOT_FOUND
	EN	Current track not found in iTunes!

PLUGIN_ITUNES_UPDATER_HALF_STAR
	EN	Allow half stars via remote (use buttons 0-9 & ADD=10)

PLUGIN_ITUNES_UPDATER_SET_ARTWORK
	EN	Use iTunes downloaded album artwork in SlimServer

'};

sub setMode() 
{
	my $client = shift;
	$client->lines(\&lines);
}

sub enabled() 
{
	return ($::VERSION ge '6.5');
}

my %functions = (
	'down' => sub {
		my $client = shift;
		$playerStatusHash{$client}->listitem($playerStatusHash{$client}->listitem+1);
		$client->update();
	},
	'up' => sub {
		my $client = shift;
		$playerStatusHash{$client}->listitem($playerStatusHash{$client}->listitem-1);
		$client->update();
	},
	'left' => sub  {
		my $client = shift;
		Slim::Buttons::Common::popModeRight($client);
	},
	'right' => sub  {
		my $client = shift;
		if ($playerStatusHash{$client}->listitem == @{$playerStatusHash{$client}->list}) {
			writePlaylistToiTunes($client);
		} else {
			$client->bumpRight();
		}
	},
	'play' => sub {
		my $client = shift;
		if ( $ITUNES_UPDATE_HOOK == 0 ) {
			hookiTunesUpdate();
			my ($line1, $line2)=($client->string('PLUGIN_ITUNES_UPDATER'),$client->string('PLUGIN_ITUNES_UPDATER_ACTIVATED'));
			$client->showBriefly($line1, $line2);
		} else {
			unHookiTunesUpdate();
			my ($line1, $line2)=($client->string('PLUGIN_ITUNES_UPDATER'),$client->string('PLUGIN_ITUNES_UPDATER_NOTACTIVATED'));
			$client->showBriefly($line1, $line2);
		}
	},

	'saveRating' => sub {
		my $client = shift;
		my $button = shift;
		my $digit = shift;
		my $rating = $digit * $ITUNES_UPDATE_MULTIPLIER;
				
		#iTunesUpdateMsg("saveRating: $client, $button, $digit, $ITUNES_UPDATE_MULTIPLIER\n");
		my $full_star = int($rating/20);
		my $half_star = (($rating-($full_star*20)) >= 0.5);
				
		$client->showBriefly(
			$client->string( 'PLUGIN_ITUNES_UPDATER'),
			$client->string( 'PLUGIN_ITUNES_UPDATER_RATING').(' O' x $full_star).(' o' x $half_star), 
			3);
		rateSong($client, $rating);
	},
	'savePlaylistToiTunes' => sub {
		my $client = shift;
		writePlaylistToiTunes($client);
	},
);
	
sub lines() 
{
	my $client = shift;
	my ($line1, $line2);
	$line1 = $client->string('PLUGIN_ITUNES_UPDATER');

	if ( $ITUNES_UPDATE_HOOK == 0 ) {
		$line2 = $client->string('PLUGIN_ITUNES_UPDATER_HIT_PLAY_TO_START');
	} else {
		$line1 .= ' : '.$client->string('PLUGIN_ITUNES_UPDATER_HIT_PLAY_TO_STOP');
		if (my $playStatus = getTrackInfo($client)) {
			if ($playStatus->checkediTunes() eq 'true') {
				my $ratingstr;
				my $rating = $playStatus->currentSongRating();
				for (my $loop = 20; $loop <= 100;$loop+=20) {
					$ratingstr .= " ";
					if ($rating >= $loop) {
						$ratingstr .= "*"; 
					} elsif ($rating >= ($loop - 10)) {
						$ratingstr .= "½"; 
					}
				}
				my @items = (
					$client->string('PLUGIN_ITUNES_UPDATER_RATING') .$ratingstr,
					$client->string('PLUGIN_ITUNES_UPDATER_LAST_PLAYED') .' '.$playStatus->lastPlayed(),
					$client->string('PLUGIN_ITUNES_UPDATER_PLAY_COUNT') .' '.$playStatus->playCount(),
					$client->string('PLUGIN_ITUNES_UPDATER_SAVE_PLAYLIST'),
					$client->string('PLUGIN_ITUNES_UPDATER_LAST_SKIPPED') .' '.$playStatus->lastSkip(),
					$client->string('PLUGIN_ITUNES_UPDATER_SKIP_COUNT') .' '.$playStatus->skipCount(),
				);
				$playStatus->list(\@items);

				$playStatus->listitem($playStatus->listitem % scalar(@items));
				$line2 = $items[$playStatus->listitem];
			} else {
				$line2 = $client->string('PLUGIN_ITUNES_UPDATER_NOT_FOUND');
			}
		} else {
			$line2 = $client->string('PLUGIN_ITUNES_UPDATER_NO_TRACK');
		}
	}
	return ($line1, $line2);
}

sub getFunctions() 
{
	return \%functions;
}

sub setupGroup
{
	my %setupGroup =
	(
	 PrefOrder => [
	 	'plugin_itunesupdate_directupdate',
		'plugin_itunesupdate_set_artwork',
	 	'plugin_itunesupdate_ignore_filetype',
		'plugin_itunesupdate_halfstar',
		'plugin_itunesupdate_showmessages'],
	 GroupHead => string('PLUGIN_ITUNES_UPDATE_SETUP_GROUP'),
	 GroupDesc => string('PLUGIN_ITUNES_UPDATE_SETUP_GROUP_DESC'),
	 GroupLine => 1,
	 GroupSub  => 1,
	 Suppress_PrefSub  => 1,
	 Suppress_PrefLine => 1,
	 Suppress_PrefHead => 1,
         PrefsInTable => 1,
	);

	my %setupPrefs =
	(
	plugin_itunesupdate_directupdate => {
			'validate'     => \&Slim::Utils::Validate::trueFalse
			,'PrefChoose'  => string('PLUGIN_ITUNES_UPDATER_DIRECT_UPDATE')
			,'changeIntro' => string('PLUGIN_ITUNES_UPDATER_DIRECT_UPDATE')
			,'options' => {
					 '1' => string('ON')
					,'0' => string('OFF')
				}
			,'currentValue' => sub { return Slim::Utils::Prefs::get("plugin_itunesupdate_directupdate");}
			},
	plugin_itunesupdate_set_artwork=> {
			'validate'     => \&Slim::Utils::Validate::trueFalse
			,'PrefChoose'  => string('PLUGIN_ITUNES_UPDATER_SET_ARTWORK')
			,'changeIntro' => string('PLUGIN_ITUNES_UPDATER_SET_ARTWORK')
			,'options' => {
					 '1' => string('ON')
					,'0' => string('OFF')
				}
			,'currentValue' => sub { return Slim::Utils::Prefs::get("plugin_itunesupdate_set_artwork");}
			},		
	plugin_itunesupdate_ignore_filetype=> {
			'validate'     => \&Slim::Utils::Validate::trueFalse
			,'PrefChoose'  => string('PLUGIN_ITUNES_UPDATER_IGNORE_FILETYPE')
			,'changeIntro' => string('PLUGIN_ITUNES_UPDATER_IGNORE_FILETYPE')
			,'options' => {
					 '1' => string('ON')
					,'0' => string('OFF')
				}
			,'currentValue' => sub { return Slim::Utils::Prefs::get("plugin_itunesupdate_ignore_filetype");}
			},		
	plugin_itunesupdate_halfstar => {
			'validate'     => \&Slim::Utils::Validate::trueFalse
			,'PrefChoose'  => string('PLUGIN_ITUNES_UPDATER_HALF_STAR')
			,'changeIntro' => string('PLUGIN_ITUNES_UPDATER_HALF_STAR')
			,'options' => {
					 '1' => string('ON')
					,'0' => string('OFF')
				}
			,'currentValue' => sub { return Slim::Utils::Prefs::get("plugin_itunesupdate_halfstar");}
			},
	plugin_itunesupdate_showmessages => {
			'validate'     => \&Slim::Utils::Validate::trueFalse
			,'PrefChoose'  => string('PLUGIN_ITUNES_UPDATER_SHOW_MESSAGES')
			,'changeIntro' => string('PLUGIN_ITUNES_UPDATER_SHOW_MESSAGES')
			,'options' => {
					 '1' => string('ON')
					,'0' => string('OFF')
				}
			,'currentValue' => sub { return Slim::Utils::Prefs::get("plugin_itunesupdate_showmessages");}
			},		
	);
	return (\%setupGroup,\%setupPrefs);
}

sub webPages {
	my %pages = ( "index\.htm" => \&handleWebIndex,
			);

	return (\%pages,"index.html");
}

sub handleWebIndex {
	my ($client, $params) = @_;

	# without a player, don't do anything
	if ($client = Slim::Player::Client::getClient($params->{player})) {
		# get the master player, if any
		$client = $client->masterOrSelf();

		$params->{refresh} = 60;
		if ($os eq 'win'
			and Slim::Utils::Prefs::get("plugin_itunesupdate_directupdate")
			and @{Slim::Player::Playlist::playList($client)} ) 
		{
			$params->{save} = 1;
		}
		if (my $playStatus = getTrackInfo($client)) {
			if ($params->{itu}) {
				if ($params->{itu} eq 'rating' and $params->{itu1}) {
					if ($params->{itu1} eq 'up' and $playStatus->currentSongRating() < 100) {
						rateSong($client,$playStatus->currentSongRating() + 10);
					} elsif ($params->{itu1} eq 'down' and $playStatus->currentSongRating() > 0) {
						rateSong($client,$playStatus->currentSongRating() - 10);
					} elsif ($params->{itu1} >= 0 or $params->{itu1} <= 100) {
						rateSong($client,$params->{itu1});
					}
				} elsif ($params->{itu} eq 'saveplaylist') {
					writePlaylistToiTunes($client,$params->{playlistname});
				}
			}
			$params->{playing} = $playStatus->checkediTunes();
			$params->{refresh} = $playStatus->currentTrackLength();
			$params->{track} = $playStatus->currentSongTrack();
			$params->{rating} = $playStatus->currentSongRating();
			$params->{lastPlayed} = $playStatus->lastPlayed();
			$params->{playCount} = $playStatus->playCount();
			$params->{skipCount} = $playStatus->skipCount();
			$params->{lastSkip} = $playStatus->lastSkip();
			$params->{trackId} = $playStatus->trackId();
		}
	}
	$params->{refresh} = 60 if (!$params->{refresh} or $params->{refresh} > 60);
	return Slim::Web::HTTP::filltemplatefile('plugins/iTunesUpdate/index.html', $params);
}

sub getTrackInfo {
		my $client = shift;
		my $playStatus = shift || getPlayerStatusForClient($client);
		if ($playStatus->isTiming() eq 'true') {
			if ($playStatus->checkediTunes() eq 'false') {
				if (Slim::Utils::Prefs::get("plugin_itunesupdate_directupdate")) {
				       if ( my ($playedCount, $playedDate, $rating,$skipCount,$skipDate) = _getTrackDetailsFromiTunes($playStatus)) {
						$playStatus->checkediTunes('true');
						$playStatus->lastPlayed($playedDate);
						$playStatus->playCount($playedCount);
						$playStatus->skipCount($skipCount);
						$playStatus->lastSkip($skipDate);
						#don't overwrite the user's rating
						if (!$playStatus->currentSongRated()) {
							$playStatus->currentSongRating($rating);
						}
					} else {
						$playStatus->checkediTunes('notfound');
					}
				} else {
					#don't overwrite the user's rating
					if (!$playStatus->currentSongRated()) {
						#get the rating from SS db
						my $trackHandle = Slim::Schema->resultset('Track')->find($playStatus->trackId());
						$playStatus->currentSongRating($trackHandle->rating);
					}
					$playStatus->lastPlayed("Unknown");
					$playStatus->playCount("Unknown");
					$playStatus->skipCount("Unknown");
					$playStatus->lastSkip("Unknown");
					$playStatus->checkediTunes('true');
				}
			}
		} else { 
			return undef;
		}
		return $playStatus;
}

sub initPlugin
{
        iTunesUpdateMsg("initialising\n");
	$os = Slim::Utils::OSDetect::OS();
	#if we haven't already started, do so
	if ( !$ITUNES_UPDATE_HOOK ) {
		if ($os eq 'win') {
			require Win32::OLE;
			import Win32::OLE;
			Win32::OLE->Option(Warn => \&OLEError);
			Win32::OLE->Option(CP => Win32::OLE::CP_UTF8());
		} elsif ($os eq 'mac') {
                        require Mac::AppleScript::Glue;
                        import Mac::AppleScript::Glue;
		}

		# this will disable half stars by default
		if (!defined(Slim::Utils::Prefs::get("plugin_itunesupdate_halfstar"))) { 
			iTunesUpdateMsg("First run - setting halfstar OFF\n");
			Slim::Utils::Prefs::set("plugin_itunesupdate_halfstar", 0 ); 
		}
		# this will disable artwork
		if (!defined(Slim::Utils::Prefs::get("plugin_itunesupdate_set_artwork"))) { 
			iTunesUpdateMsg("First run - setting artwork OFF\n");
			Slim::Utils::Prefs::set("plugin_itunesupdate_set_artwork", 0 ); 
		}


		my $functref = Slim::Buttons::Playlist::getFunctions();
		$functref->{'savePlaylistToiTunes'} = $functions{'savePlaylistToiTunes'};
		$functref->{'saveRating'} = $functions{'saveRating'};

		# this will enable direct access if unset and platform != unix
		if (!defined(Slim::Utils::Prefs::get("plugin_itunesupdate_directupdate")) and $os ne 'unix') { 
			iTunesUpdateMsg("First run - setting directupdate ON\n");
			Slim::Utils::Prefs::set("plugin_itunesupdate_directupdate", 1 ); 
		}
		# this will set messages on by default
		if (!defined(Slim::Utils::Prefs::get("plugin_itunesupdate_showmessages"))) { 
			iTunesUpdateMsg("First run - setting showmessages ON\n");
			Slim::Utils::Prefs::set("plugin_itunesupdate_showmessages", 1 ); 
		}
		if (!defined(Slim::Utils::Prefs::get("plugin_itunesupdate_ignore_filetype"))) { 
			iTunesUpdateMsg("Upgrade - setting ignore filetype OFF\n");
			Slim::Utils::Prefs::set("plugin_itunesupdate_ignore_filetype", 0 ); 
		}
		hookiTunesUpdate();

		$cacheFolder = initCacheFolder();
	}
}

sub shutdownPlugin {
        iTunesUpdateMsg("disabling\n");
        if ($ITUNES_UPDATE_HOOK) {
                unHookiTunesUpdate();
        }
}


##################################################
### per-client Data                            ###
##################################################

struct iTunesTrackStatus => {

	# Artist's name for current song
	currentSongArtist => '$',

	# Track title for current song
	currentSongTrack => '$',

	# Album title for current song.
	# (If not known, blank.)
	currentSongAlbum => '$',

	# Stopwatch to time the playing of the current track
	currentSongStopwatch => 'Time::Stopwatch',

	# Filename of the current track being played
	currentTrackOriginalFilename => '$',

	# Total length of the track being played
	currentTrackLength => '$',

	# Are we currently paused during a song's playback?
	isPaused => '$',

	# Are we currently timing a song's playback?
	isTiming => '$',

	# have we looked up the track in iTunes yet
	checkediTunes => '$',

	# Rating for current song
	currentSongRating => '$',
	#has the user actually changed the rating
	currentSongRated => '$',

	# iTunes last played time
	lastPlayed => '$',

	# iTunes play count
	playCount => '$',

	#iTunes skip count
	skipCount => '$',
	#iTunes last skip
	lastSkip => '$',

	# menu list index
	listitem => '$',

	# menu list 
	list => '@',

	trackId => '$',

};

# Set the appropriate default values for this playerStatus struct
sub setPlayerStatusDefaults($$)
{
	# Parameter - client
	my $client = shift;

	# Parameter - Player status structure.
	# Uses pass-by-reference
	my $playerStatusToSetRef = shift;

	# Artist's name for current song
	$playerStatusToSetRef->currentSongArtist("");

	# Track title for current song
	$playerStatusToSetRef->currentSongTrack("");

	# Album title for current song.
	# (If not known, blank.)
	$playerStatusToSetRef->currentSongAlbum("");

	# Rating for current song
	$playerStatusToSetRef->currentSongRating("");
	$playerStatusToSetRef->currentSongRated(0);

	# Filename of the current track being played
	$playerStatusToSetRef->currentTrackOriginalFilename("");

	# Total length of the track being played
	$playerStatusToSetRef->currentTrackLength(0);

	# Are we currently paused during a song's playback?
	$playerStatusToSetRef->isPaused('false');

	# Are we currently timing a song's playback?
	$playerStatusToSetRef->isTiming('false');

	# Stopwatch to time the playing of the current track
	$playerStatusToSetRef->currentSongStopwatch(Time::Stopwatch->new());

	$playerStatusToSetRef->checkediTunes('false');
	$playerStatusToSetRef->listitem(0);

}

# Get the player state for the given client.
# Will create one for new clients.
sub getPlayerStatusForClient($)
{
	# Parameter - Client structure
	my $client = shift;
	# Get the friendly name for this client
	my $clientName = Slim::Player::Client::name($client);
	# Get the ID (IP) for this client
	my $clientID = Slim::Player::Client::id($client);

	#iTunesUpdateMsg("Asking about client $clientName ($clientID)\n");

	# If we haven't seen this client before, create a new per-client 
	# playState structure.
	if (!defined($playerStatusHash{$client}))
	{
		iTunesUpdateMsg("Creating new PlayerStatus for $clientName ($clientID)\n");

		# Create new playState structure
		$playerStatusHash{$client} = iTunesTrackStatus->new();

		# Set appropriate defaults
		setPlayerStatusDefaults($client, $playerStatusHash{$client});
	}

	# If it didn't exist, it does now - 
	# return the playerStatus structure for the client.
	return $playerStatusHash{$client};
}

################################################
### main routines                            ###
################################################
sub OLEError {
	msg(Win32::OLE->LastError() . "\n");
}

# A wrapper to allow us to uniformly turn on & off debug messages
sub iTunesUpdateMsg
{
	my $message = join '','iTunesUpdate: ',@_;
	msg ($message) if (Slim::Utils::Prefs::get("plugin_itunesupdate_showmessages"));
}

sub iTunesUpdateErr
{
	my $message = join '','iTunesUpdate: ',@_;
	msg ($message);
}

# Hook the plugin to the play events.
# Do this as soon as possible during startup.
sub hookiTunesUpdate()
{  
	iTunesUpdateMsg("hookiTunesUpdate() engaged, iTunes Updater activated.\n");
	#Slim::Control::Command::setExecuteCallback(\&commandCallback);
	Slim::Control::Request::subscribe(\&Plugins::iTunesUpdate::Plugin::commandCallback,[['mode', 'play', 'stop', 'pause', 'playlist', 'power']]);
	$ITUNES_UPDATE_HOOK=1;
}

# Unhook the plugin's play event callback function. 
# Do this as the plugin shuts down, if possible.
sub unHookiTunesUpdate()
{
	iTunesUpdateMsg("unHookiTunesUpdate() engaged, iTunes Updater deactivated.\n");
	#Slim::Control::Command::clearExecuteCallback(\&commandCallback);
	Slim::Control::Request::unsubscribe(\&Plugins::iTunesUpdate::Plugin::commandCallback);
	$ITUNES_UPDATE_HOOK=0;
}

# These xxxCommand() routines handle commands coming to us
# through the command callback we have hooked into.
sub openCommand($$)
{
	######################################
	### Open command
	######################################

	# This is the chief way we detect a new song being played, NOT the play command.
	# Parameter - iTunesTrackStatus for current client
	my $playStatus = shift;

	# Stop old song, if needed
	# do this before updating the filename as we need to use it in the stop function
	if ($playStatus->isTiming() eq "true")
	{
		stopTimingSong($playStatus);
	}
	# Parameter - filename of track being played
	$playStatus->currentTrackOriginalFilename(shift);

	# Start timing new song
	startTimingNewSong($playStatus);#, $artistName,$trackTitle,$albumName);
}

sub playCommand($)
{
	######################################
	### Play command
	######################################

	# Parameter - iTunesTrackStatus for current client
	my $playStatus = shift;

	if ( ($playStatus->isTiming() eq "true") &&($playStatus->isPaused() eq "true") )
	{
		iTunesUpdateMsg("Resuming with play from pause\n");
		resumeTimingSong($playStatus);
	} elsif ( ($playStatus->isTiming() eq "true") &&($playStatus->isPaused() eq "false") )
	{
		iTunesUpdateMsg("Ignoring play command, assumed redundant...\n");		      
	} else {
		# this seems to happen when you switch on and press play    
		# Start timing new song
		startTimingNewSong($playStatus);
	}
}

sub pauseCommand($$)
{
	######################################
	### Pause command
	######################################

	# Parameter - iTunesTrackStatus for current client
	my $playStatus = shift;

	# Parameter - Optional second parameter in command
	# (This is for the case <pause 0 | 1> ). 
	# If user said "pause 0" or "pause 1", this will be 0 or 1. Otherwise, undef.
	my $secondParm = shift;

	# Just a plain "pause"
	if (!defined($secondParm))
	{
		# What we do depends on if we are already paused or not
		if ($playStatus->isPaused() eq "false") {
			iTunesUpdateMsg("Pausing (vanilla pause)\n");
			pauseTimingSong($playStatus);   
		} elsif ($playStatus->isPaused() eq "true") {
			iTunesUpdateMsg("Unpausing (vanilla unpause)\n");
			resumeTimingSong($playStatus);      
		}
	}

	# "pause 1" means "pause true", so pause and stop timing, if not already paused.
	elsif ( ($secondParm eq 1) && ($playStatus->isPaused() eq "false") ) {
		iTunesUpdateMsg("Pausing (1 case)\n");
		pauseTimingSong($playStatus);      
	}

	# "pause 0" means "pause false", so unpause and resume timing, if not already timing.
	elsif ( ($secondParm eq 0) && ($playStatus->isPaused() eq "true") ) {
		iTunesUpdateMsg("Pausing (0 case)\n");
		resumeTimingSong($playStatus);      
	} else {      
		iTunesUpdateMsg("Pause command ignored, assumed redundant.\n");
	}
}

sub stopCommand($)
{
	######################################
	### Stop command
	######################################

	# Parameter - iTunesTrackStatus for current client
	my $playStatus = shift;

	if ($playStatus->isTiming() eq "true")
	{
		stopTimingSong($playStatus);      
	}
}


# This gets called during playback events.
# We look for events we are interested in, and start and stop our various
# timers accordingly.
sub commandCallback($) 
{
	my $request=shift;
	my $client = $request->client();
	return if (!$client);

	# Get the PlayerStatus
	my $playStatus = getPlayerStatusForClient($client);

	######################################
	### Open command
	######################################
	# This is the chief way we detect a new song being played, NOT play.
	# should be using playlist,newsong now...
	if ($request->isCommand([['playlist'],['open']]) )
	{
		openCommand($playStatus,$request->getParam('_path'));
	}

	######################################
	### Play command
	######################################

	if( ($request->isCommand([['playlist'],['play']])) or ($request->isCommand([['mode','play']])) )
	{
		playCommand($playStatus);
	}

	######################################
	### Pause command
	######################################

	if ($request->isCommand([['pause']]))
	{
		pauseCommand($playStatus,$request->getParam('_newvalue'));
	}

	if ($request->isCommand([['mode'],['pause']]))
	{  
		# "mode pause" will always put us into pause mode, so fake a "pause 1".
		pauseCommand($playStatus, 1);
	}

	######################################
	### Stop command
	######################################

	if ( ($request->isCommand([["stop"]])) or ($request->isCommand([['mode'],['stop']])) )
	{
		stopCommand($playStatus);
	}

	######################################
	### Stop command
	######################################

	if ( $request->isCommand([['playlist'],['sync']]) )
	{
		# If this player syncs with another, we treat it as a stop,
		# since whatever it is presently playing (if anything) will end.
		stopCommand($playStatus);
	}

	######################################
	## Power command
	######################################
	if ( $request->isCommand([['power']]))
	{
		my $param = $request->getParam('_newvalue');
		if (defined $param and $param == 0) {
			#power off - register as a pause to prevent a skip on restart
			pauseCommand($playStatus,1);
		}
	}
}

# A new song has begun playing. Reset the current song
# timer and set new Artist and Track.
sub startTimingNewSong($$$$)
{
	iTunesUpdateMsg("Starting a new song\n");
	# Parameter - iTunesTrackStatus for current client
	my $playStatus = shift;

	if (Slim::Music::Info::isFile($playStatus->currentTrackOriginalFilename)) {
		my $track     = Slim::Schema->resultset('Track')->objectForUrl($playStatus->currentTrackOriginalFilename);

		#save trackId
		$playStatus->trackId($track->id);

		# Get new song data
		$playStatus->currentTrackLength($track->durationSeconds);

		my $artistName = $track->artist();
		#put this in because I'm getting crashes on missing artists
		$artistName = $artistName->name() if (defined $artistName);
		$artistName = "" if (!defined $artistName or $artistName eq string('NO_ARTIST'));

		my $albumName  = $track->album->title();
		$albumName = "" if (!defined $albumName or $albumName eq string('NO_ALBUM'));

		my $trackTitle = $track->title;
		$trackTitle = "" if $trackTitle eq string('NO_TITLE');

		# Set the Name & artist & album
		$playStatus->currentSongArtist($artistName);
		$playStatus->currentSongTrack($trackTitle);
		$playStatus->currentSongAlbum($albumName);

		if ($playStatus->isTiming() eq "true")
		{
			iTunesUpdateMsg("Programmer error in startTimingNewSong() - already timing!\n");	 
		}

		# Clear the stopwatch and start it again
		($playStatus->currentSongStopwatch())->clear();
		($playStatus->currentSongStopwatch())->start();

		# Not paused - we are playing a song
		$playStatus->isPaused("false");

		# We are now timing a song
		$playStatus->isTiming("true");

		$playStatus->checkediTunes("false");

		if ($os eq 'win' and Slim::Utils::Prefs::get("plugin_itunesupdate_set_artwork")) {
			getTrackInfo(undef,$playStatus);
		}

		iTunesUpdateMsg("Starting to time ",$playStatus->currentTrackOriginalFilename,"\n");
	} else {
		iTunesUpdateMsg("Not timing ",$playStatus->currentTrackOriginalFilename," - not a file\n");
	}
	#showCurrentVariables($playStatus);
}

# Pause the current song timer
sub pauseTimingSong($)
{
	# Parameter - iTunesTrackStatus for current client
	my $playStatus = shift;

	if ($playStatus->isPaused() eq "true")
	{
		iTunesUpdateMsg("Programmer error or other problem in pauseTimingSong! Confused about pause status.\n");      
	}

	# Stop the stopwatch 
	$playStatus->currentSongStopwatch()->stop();

	# Go into pause mode
	$playStatus->isPaused("true");

	iTunesUpdateMsg("Pausing ",$playStatus->currentTrackOriginalFilename,"\n");
	iTunesUpdateMsg("Elapsed seconds: ",$playStatus->currentSongStopwatch()->getElapsedTime(),"\n");
	#showCurrentVariables($playStatus);
}

# Resume the current song timer - playing again
sub resumeTimingSong($)
{
	# Parameter - iTunesTrackStatus for current client
	my $playStatus = shift;

	if ($playStatus->isPaused() eq "false")
	{
		iTunesUpdateMsg("Programmer error or other problem in resumeTimingSong! Confused about pause status.\n");      
	}

	# Re-start the stopwatch 
	$playStatus->currentSongStopwatch()->start();

	# Exit pause mode
	$playStatus->isPaused("false");

	iTunesUpdateMsg("Resuming ",$playStatus->currentTrackOriginalFilename,"\n");
	#showCurrentVariables($playStatus);
}

# Stop timing the current song
# (Either stop was hit or we are about to play another one)
sub stopTimingSong($)
{
	# Parameter - iTunesTrackStatus for current client
	my $playStatus = shift;

	if ($playStatus->isTiming() eq "false")
	{
		msg("Programmer error in iTunes::stopTimingSong() - not already timing!\n");   
	}

	if (Slim::Music::Info::isFile($playStatus->currentTrackOriginalFilename)) {
		iTunesUpdateMsg("Stopping timing ",$playStatus->currentTrackOriginalFilename,"\n");
		# If the track was played long enough to count as a listen..
		my $action = getActionForTrackPlay($playStatus);
		logTrack($playStatus,$action);
	} else {
		msg("That wasn't a file - not logging to iTunes\n");
	}
	$playStatus->currentSongArtist("");
	$playStatus->currentSongTrack("");
	$playStatus->currentSongRating("");
	$playStatus->currentSongRated(0);

	# Clear the stopwatch
	$playStatus->currentSongStopwatch()->clear();

	$playStatus->isPaused("false");
	$playStatus->isTiming("false");
}

# Debugging routine - shows current variable values for the given playStatus
sub showCurrentVariables($)
{
	# Parameter - iTunesTrackStatus for current client
	my $playStatus = shift;

	iTunesUpdateMsg("======= showCurrentVariables() ========\n");
	iTunesUpdateMsg("Artist:",playStatus->currentSongArtist(),"\n");
	iTunesUpdateMsg("Track: ",$playStatus->currentSongTrack(),"\n");
	iTunesUpdateMsg("Album: ",$playStatus->currentSongAlbum(),"\n");
	iTunesUpdateMsg("Original Filename: ",$playStatus->currentTrackOriginalFilename(),"\n");
	iTunesUpdateMsg("Duration in seconds: ",$playStatus->currentTrackLength(),"\n"); 
	iTunesUpdateMsg("Time showing on stopwatch: ",$playStatus->currentSongStopwatch()->getElapsedTime(),"\n");
	iTunesUpdateMsg("Is song playback paused? : ",$playStatus->isPaused(),"\n");
	iTunesUpdateMsg("Are we currently timing? : ",$playStatus->isTiming(),"\n");
	iTunesUpdateMsg("=======================================\n");
}

sub getActionForTrackPlay($$)
{
	# Parameter - iTunesTrackStatus for current client
	my $playStatus = shift;

	# Total time elapsed during play
	my $totalTimeElapsedDuringPlay = $playStatus->currentSongStopwatch()->getElapsedTime();
	iTunesUpdateMsg("Time actually played in track: $totalTimeElapsedDuringPlay\n");

	my $wasLongEnough = 0;
	my $currentTrackLength = $playStatus->currentTrackLength();
	my $tmpCurrentSongTrack = $playStatus->currentSongTrack();

	# The minimum play time the % minimum requires
	my $minimumPlayLengthFromPercentPlayThreshold = $ITUNES_UPDATE_PERCENT_PLAY_THRESHOLD * $currentTrackLength;

	my $printableDisplayThreshold = $ITUNES_UPDATE_PERCENT_PLAY_THRESHOLD * 100;
	#iTunesUpdateMsg("Current play threshold is $printableDisplayThreshold%.\n");
	#iTunesUpdateMsg("Minimum play time is $ITUNES_UPDATE_MINIMUM_PLAY_TIME seconds.\n");
	#iTunesUpdateMsg("Time play threshold is $ITUNES_UPDATE_TIME_PLAY_THRESHOLD seconds.\n");
	#iTunesUpdateMsg("Percentage play threshold calculation:\n");
	#iTunesUpdateMsg("$ITUNES_UPDATE_PERCENT_PLAY_THRESHOLD * $currentTrackLength =$minimumPlayLengthFromPercentPlayThreshold\n");	

	# Did it play at least the absolute minimum amount?
	if ($totalTimeElapsedDuringPlay < $ITUNES_UPDATE_MINIMUM_PLAY_TIME ) 
	{
		# No. This condition overrides the others.
		iTunesUpdateMsg("\"$tmpCurrentSongTrack\" NOT played long enough: Played $totalTimeElapsedDuringPlay; needed to play $ITUNES_UPDATE_MINIMUM_PLAY_TIME seconds.\n");
		return undef;
	}
	# Did it play past the percent-of-track played threshold?
	elsif ($totalTimeElapsedDuringPlay >= $minimumPlayLengthFromPercentPlayThreshold)
	{
		# Yes. We have a play.
		iTunesUpdateMsg("\"$tmpCurrentSongTrack\" was played long enough to count as played.\n");
		iTunesUpdateMsg("Played past percentage threshold of $minimumPlayLengthFromPercentPlayThreshold seconds.\n");
		$wasLongEnough = 1;
	}
	# Did it play past the number-of-seconds played threshold?
	elsif ($totalTimeElapsedDuringPlay >= $ITUNES_UPDATE_TIME_PLAY_THRESHOLD)
	{
		# Yes. We have a play.
		iTunesUpdateMsg("\"$tmpCurrentSongTrack\" was played long enough to count as played.\n");
		iTunesUpdateMsg("Played past time threshold of $ITUNES_UPDATE_TIME_PLAY_THRESHOLD seconds.\n");
		$wasLongEnough = 1;
	} else {
		# We *could* do this calculation above, but I wanted to make it clearer
		# exactly why a play was too short, if it was too short, with explicit
		# debug messages.
		my $minimumPlayTimeNeeded;
		if ($minimumPlayLengthFromPercentPlayThreshold < $ITUNES_UPDATE_TIME_PLAY_THRESHOLD) {
			$minimumPlayTimeNeeded = $minimumPlayLengthFromPercentPlayThreshold;
		} else {
			$minimumPlayTimeNeeded = $ITUNES_UPDATE_TIME_PLAY_THRESHOLD;
		}
		# Otherwise, it played above the minimum 
		#, but below the thresholds, so, no play.
		iTunesUpdateMsg("\"$tmpCurrentSongTrack\" NOT played long enough: Played $totalTimeElapsedDuringPlay; needed to play $minimumPlayTimeNeeded seconds.\n");
		$wasLongEnough = 0;   
	}

	if ($wasLongEnough) {
		return 'played';
	} elsif ($playStatus->isPaused()) {
		return 'skipped';
	}
	return undef;
}

#trackStat plugin api
sub setTrackStatRating {
	my ($client, $url, $rating) = @_;
	my $playStatus = getPlayerStatusForClient($client);
	if ($playStatus->currentTrackOriginalFilename eq $url)
	{
		rateSong($client,$rating);
	}
}

#this is where the actual work happens
sub logTrack($$) 
{
	my $playStatus = shift;
	my $action = shift;

	return unless ($action ne "" or $playStatus->currentSongRated());

	logTrackToiTunes($playStatus,$action);
	logTrackToSlimServer($playStatus,$action);

}

sub logTrackToSlimServer($$)
{
	my $playStatus = shift;
	my $action = shift;

	my $trackHandle = Slim::Schema->resultset('Track')->find($playStatus->trackId());

	if ($trackHandle) {
		if ($playStatus->currentSongRated()){
			my $rating = $playStatus->currentSongRating();
			iTunesUpdateMsg("Updating rating in SlimServer\n");
			# Run this within eval for now so it hides all errors until this is standard
			eval {
				$trackHandle->set('rating' => $rating);
				$trackHandle->update();
			};
		}
	} else {
		iTunesUpdateErr("Track: ", $playStatus->currentTrackOriginalFilename()," not found in SlimServer\n");
	}
}

sub logTrackToiTunes($$)
{
	my $playStatus = shift;
	my $action = shift;
		
	if (Slim::Utils::Prefs::get("plugin_itunesupdate_directupdate")) {
		_logTrackToiTunes($playStatus,$action);
	} else {
		_logTrackToFile($playStatus,$action);
	}
}

sub writePlaylistToiTunes{
	my $client = shift;
	my $playlistname = shift;
	my $playlist = Slim::Player::Playlist::playList($client);
	
	if (Slim::Utils::Prefs::get("plugin_itunesupdate_directupdate")) {
		$client->showBriefly( 
			$client->string( 'PLUGIN_ITUNES_UPDATER'),
			$client->string( 'PLUGIN_ITUNES_UPDATER_SAVED_PLAYLIST'),
			3);
		if (!$playlistname) {
			#default playlist name is player name + timestamp
			my $playlistname = Slim::Player::Client::name($client)." ".strftime("%Y-%b-%d %H:%M:%S", localtime);
		}
		my $iTunesPlaylist = _openiTunesPlaylist($playlistname);
		if ($iTunesPlaylist) {
			foreach my $item (@{$playlist}) {
				my $iTunesTrack = _searchiTunes($item);      
				if ($iTunesTrack) {
					_addTrackToiTunesPlaylist($iTunesPlaylist,$iTunesTrack);
				}
			}
		}  
	} else {
		iTunesUpdateMsg("sorry - iTunesUpdate playlist save not enabled for this platform\n");
	}
}
sub _getTrackDetailsFromiTunes
{
	my ($playStatus) = shift;
	my ($playedCount, $playedDate,$rating);
	my ($skipCount,$skipDate) = ('Unknown','Unknown');

	iTunesUpdateMsg("==getTrackDetailsFromiTunes()\n");

	my $trackHandle = _searchiTunes( $playStatus->currentTrackOriginalFilename());

	if ($trackHandle) {
			if ($os eq 'win') {
				$playedCount = $trackHandle->playedCount;
				$playedDate = $trackHandle->playedDate->Date("dd-MMM-yyyy")
					." "
					.$trackHandle->playedDate->Time("HH:mm:ss");
				$rating = $trackHandle->rating;
				if ($iTunesVersion >= 7) {
					$skipCount = $trackHandle->skippedCount;
					$skipDate = $trackHandle->skippedDate->Date("dd-MMM-yyyy")
						." "
						.$trackHandle->skippedDate->Time("HH:mm:ss");
					saveArtworkToCache($playStatus,$trackHandle);
				}
			} elsif ($os eq 'mac') {
				$playedDate = $trackHandle->played_date->{_ref};
				$playedCount = $trackHandle->played_count();
				$rating = $trackHandle->rating();
				if ($iTunesVersion >= 7) {
					$skipCount = $trackHandle->skipped_count();
					$skipDate = $trackHandle->skipped_date->{_ref};
				}
			}
			$playedDate = 'Never Played' if ($playedDate =~ m/30-Dec-1899 00:00:00/);
			if ($iTunesVersion >= 7) {
				$skipDate = 'Never Skipped' if ($skipDate =~ m/30-Dec-1899 00:00:00/);
			}
	} else {
		iTunesUpdateErr("Track: ", $playStatus->currentTrackOriginalFilename()," not found in iTunes\n");
		return undef;
	}
	return $playedCount, $playedDate,$rating, $skipCount, $skipDate;
}

sub _logTrackToiTunes($$)
{
	my ($playStatus,$action) = @_;

	#iTunesUpdateMsg("==logTrackToiTunes()\n");

	my $trackHandle = _searchiTunes( $playStatus->currentTrackOriginalFilename());

	if ($trackHandle) {
		if ($action eq 'played') {
			iTunesUpdateMsg("Marking as played in iTunes\n");
			if ($os eq 'win') {
				$trackHandle->{playedCount}++;
				$trackHandle->{playedDate} = strftime ("%Y-%m-%d %H:%M:%S", localtime);
			} elsif ($os eq 'mac') {
				my $playedCount = $trackHandle->played_count();
				if (!$playedCount) {
					$playedCount = 1;
				} else {
					$playedCount += 1;
				}
				$trackHandle->set(played_count => $playedCount);
				$trackHandle->set(played_date => $iTunesHandle->current_date()); 
			}
		} elsif ($iTunesVersion >= 7 and $action eq 'skipped'){
			iTunesUpdateMsg("Marking as skipped in iTunes\n");
			if ($os eq 'win') {
				$trackHandle->{skippedCount}++;
				$trackHandle->{skippedDate} = strftime ("%Y-%m-%d %H:%M:%S", localtime);
			} elsif ($os eq 'mac') {
				my $skippedCount = $trackHandle->skipped_count();
				if (!$skippedCount) {
					$skippedCount = 1;
				} else {
					$skippedCount += 1;
				}
				$trackHandle->set(skipped_count => $skippedCount);
				$trackHandle->set(skipped_date => $iTunesHandle->current_date()); 
			}
		}
		if ($playStatus->currentSongRated()){
			my $rating = $playStatus->currentSongRating();
	                #iTunes ratings are 0-5 stars, 100 = 5 stars
			iTunesUpdateMsg("Updating rating in iTunes\n");
			if ($os eq 'win') {
				$trackHandle->{rating} = $rating;
			} elsif ($os eq 'mac') {
				$trackHandle->set(rating => $rating);
			}
		}
	} else {
		iTunesUpdateErr("Track: ", $playStatus->currentTrackOriginalFilename()," not found in iTunes\n");
	}
}

sub _logTrackToFile {
	my ($playStatus,$action) = @_;
	my $status;

	iTunesUpdateMsg("==logTrackToFile()\n");

	my $filename = catfile(Slim::Utils::Prefs::get('playlistdir'),$ITUNES_UPDATE_HIST_FILE);
	my $output = FileHandle->new($filename, ">>") or do {
		iTunesUpdateErr("Could not open $filename for appending.\n");
		return;
	};

	printf $output "%s|%s|%s|%s|%s|%s|%s\n",
	$playStatus->currentSongTrack(),
	$playStatus->currentSongArtist(),
	$playStatus->currentSongAlbum(),
	Slim::Utils::Misc::pathFromFileURL($playStatus->currentTrackOriginalFilename()),
	$action,
	strftime ("%Y%m%d%H%M%S", localtime),
	#don't save the rating if it wasn't set by the user
	($playStatus->currentSongRated() ? $playStatus->currentSongRating() : "");

	close $output;
}

sub rateSong($$) {
	my ($client,$digit)=@_;
	# get the master player, if any
	$client = $client->masterOrSelf();

	my $playStatus = getPlayerStatusForClient($client);

	iTunesUpdateMsg("Changing song rating to: $digit\n");

	$playStatus->currentSongRating($digit);
	$playStatus->currentSongRated(1);
}

sub _searchiTunes {
	my $track_url = shift;
	my $track     = Slim::Schema->resultset('Track')->objectForUrl($track_url);
	iTunesUpdateMsg("URL: ".$track->url."\n");
        my $fileLocation = Slim::Utils::Misc::pathFromFileURL($track->url,0);
	iTunesUpdateMsg("fileLoc: $fileLocation\n");

	# create searchString and remove duplicate/trailing whitespace as well.
        my $searchString = "";

	#put this in because I'm getting crashes on missing artists
        my $artist = $track->artist;
	$artist = $artist->name() if (defined $artist);
	$searchString .= $artist unless (!$artist or $artist eq string('NO_ARTIST'));

        my $album = $track->album->title();
	$searchString .= " $album" unless (!$album or $album eq string('NO_ALBUM'));
        my $title = $track->title();
	$searchString .= " $title" unless ($title eq string('NO_TITLE')); 

	iTunesUpdateMsg( "Searching iTunes for \"$searchString\"\n");

	return 0 unless $fileLocation and length($searchString) >= 1;

	_openiTunes() or return 0;

	if ($os eq 'win') {
		return _searchiTunesWin($searchString, $fileLocation);
	} elsif ($os eq 'mac') {
		return _searchiTunesMac($searchString, $fileLocation);
	}
	return 0;
}

sub _searchiTunesWin {
        my $searchString = shift;
        my $fileLocation = shift;
	my $IITrackKindFile = 1;
	my $ITPlaylistSearchFieldVisible = 1;
	
	#replace \ with / - seems to have changed in SS
	$fileLocation =~ s/\//\\/g;
	#replace \\ with \ - not consistent within iTunes (not in my library at least)
	$fileLocation =~ s/\\\\/\\/;

	if (Slim::Utils::Prefs::get('plugin_itunesupdate_ignore_filetype')){
		#remove file extension
		$fileLocation =~ s/\.\w+?$//;
	}

	my $mainLibrary = $iTunesHandle->LibraryPlaylist;	
	my $trackCollection = $mainLibrary->Search($searchString, $ITPlaylistSearchFieldVisible);
	if ($trackCollection)
	{
		iTunesUpdateMsg("Found ",$trackCollection->Count," track(s) in iTunes\n");
		for (my $j = 1; $j <= $trackCollection->Count ; $j++) {
			my $iTunesLoc = $trackCollection->Item($j)->Location;
			#change double \\ to \ 
			$iTunesLoc =~ s/\\\\/\\/;

			#check the location and type
			if ($trackCollection->Item($j)->Kind == $IITrackKindFile
				and index(lc($iTunesLoc),lc($fileLocation)) == 0

				)
			{
				#we have the file (hopefully)
				iTunesUpdateMsg("Found track in iTunes\n");
				return $trackCollection->Item($j);
			} else {
				iTunesUpdateErr("False match: $iTunesLoc\n");
				iTunesUpdateErr("Checked for: $fileLocation\n");
			}
		}
	}
	return 0;
}

sub _searchiTunesMac {
        my $searchString = shift;
        my $fileLocation = shift;

	#OSX iTunes seems to store some accented characters as 2 characters
	#this function should recombine them
	$fileLocation = Slim::Utils::Unicode::recomposeUnicode($fileLocation);

	my $fileLocationNoExt = $fileLocation;
	my $extLength = 0;

	my $trax = $iTunesHandle->search_library_playlist_1_for($searchString);
	for my $track (@{$trax}) {
		my $iTunesLoc = $track->location->{_ref};
		# modify iTunesLoc to match the location string
		$iTunesLoc =~ s/^alias "[^:]*:(.*)"$/$1/;
		$iTunesLoc =~ tr/:/\//;
		if (Slim::Utils::Prefs::get('plugin_itunesupdate_ignore_filetype')){
			#remove file extension
			$iTunesLoc =~ s/\.\w+?$//;
		}

		# have to do a substring match as the begining of the two
		# strings is different
		my $xpect = length($fileLocation) - length($iTunesLoc);
		my $found = index(lc($fileLocationNoExt), lc($iTunesLoc));
		if ($xpect >= 0 and $found == $xpect) {
			iTunesUpdateMsg("Found track in iTunes: $iTunesLoc\n");
			return $track;
		} else {
			iTunesUpdateErr("Checking for: $fileLocation\n");
			iTunesUpdateErr("False Match:  $iTunesLoc\n");
		}
	}
	return 0;
}

sub _addTrackToiTunesPlaylist($$) {
	my ($playlistHandle,$trackHandle) = @_;

	return unless $playlistHandle and $trackHandle;

	iTunesUpdateMsg("Attempting to add track to playlist\n");
	if ($os eq 'win') {
		return $playlistHandle->AddTrack($trackHandle);
	} elsif ($os eq 'mac') {
		iTunesUpdateErr("Not (yet) supported on Mac OS X\n");
	}
	return 0;
}

sub _openiTunesPlaylist($) {
	my $playlistname = shift;
	return 0 unless $playlistname;

	_openiTunes() or return 0;
	iTunesUpdateMsg("Attempting to create playlist: $playlistname\n");
	if ($os eq 'win') {
		return $iTunesHandle->CreatePlaylist($playlistname);
	} elsif ($os eq 'mac') {
		iTunesUpdateErr("Not (yet) supported on Mac OS X\n");
                return 0;
		my $playlist = $iTunesHandle->make_new_user_playlist();
		$playlist->set(name => $playlistname);
		return $playlist;
	} 
	return 0;
}

sub _openiTunes {
	my $failure;

	unless ($iTunesHandle) {
		iTunesUpdateMsg ("Attempting to make connection to iTunes...\n");
		if ($os eq 'win') {
			$iTunesHandle = Win32::OLE->GetActiveObject('iTunes.Application');
			unless ($iTunesHandle) {
				$iTunesHandle = new Win32::OLE( "iTunes.Application") 
			}
		} elsif ($os eq 'mac') {
			$iTunesHandle = new Mac::AppleScript::Glue::Application('iTunes');
		} else {
			iTunesUpdateErr("iTunes not supported on plattform\n");
			return 0;
		}
		unless ($iTunesHandle) {
			iTunesUpdateErr( "Failed to launch iTunes!!!\n");
			return 0;
		}
		my $iTunesFullVersion = $iTunesHandle->Version;
		iTunesUpdateMsg ("Connection established to iTunes: $iTunesFullVersion\n");
		($iTunesVersion) = split /\./,$iTunesFullVersion;
	} else {
		#iTunesUpdateMsg ("iTunes already open: testing connection\n");
		$iTunesHandle->Version or $failure = 1;	
		if ($failure) {
			iTunesUpdateErr ("iTunes dead: reopening...\n");
			undef $iTunesHandle;
			return _openiTunes();
		}
	}
	return 1;
}
### artwork
sub initCacheFolder {
	my $purge = shift;
	my $cacheFolder = Slim::Utils::Prefs::get('cachedir');
	my $cacheAge = 7;
	
	mkdir($cacheFolder) unless (-d $cacheFolder);
	$cacheFolder = catfile($cacheFolder,".itunes-artwork-cache");
	mkdir($cacheFolder) unless (-d $cacheFolder);
	
	# purge the cache
	finddepth(\&foundFile, $cacheFolder);
	
	# set timer to purge cache once a day
	Slim::Utils::Timers::setTimer(0, Time::HiRes::time() + 60*60*24, \&initCacheFolder);
	return $cacheFolder;
}

sub foundFile() {
	my $cacheAge = 7;
	my $file = $File::Find::name;
	#delete old files
	if (-M $file > $cacheAge) {
		unlink $file;
	} else {
		#remove empty directories
		rmdir $_;
	}
}

sub saveArtworkToCache {
	my $playStatus = shift;
	my $trackHandle = shift;

	return unless Slim::Utils::Prefs::get("plugin_itunesupdate_set_artwork");

	if (my $artCollection = $trackHandle->Artwork) {
		for (my $j = 1; $j <= $artCollection->Count ; $j++) {
			if ($artCollection->Item($j)->isDownloadedArtwork) {
				my $cachedFileLoc = $trackHandle->Location;
				#remove prefix & filename
				($cachedFileLoc) = $cachedFileLoc =~ m/^.+?[\/\\](.+)[\/\\]/;
				my $format = $artCollection->Item($j)->Format;
				my $suffix = ('xxx','jpg','png','bmp')[$format];
				my $filename = catfile($cacheFolder,$cachedFileLoc);
				if (!getCachedArtwork($cachedFileLoc)) {
					eval { mkpath($filename) };
  					if ($@) {
						iTunesUpdateMsg("Unable to create $filename :$@\n");
						return;
  					} else {  
						$filename = catfile($filename,"art.$suffix");
						iTunesUpdateMsg("Saving iTunes art to $filename\n");
						$artCollection->Item($j)->SaveArtworkToFile("$filename");
					}
				} else {
					iTunesUpdateMsg("Cached iTunes artwork found!\n");
					$filename = catfile($filename,"art.$suffix");
				}
				my $ssHandle = Slim::Schema->resultset('Track')->find($playStatus->trackId());
				$ssHandle->set('cover' => $filename);
				$ssHandle->set('thumb' => $filename);
				$ssHandle->update();
			}
		}
	}
}

sub getCachedArtwork {
	my $cachedFile = shift;
	if (-d $cachedFile) {
		return 1;
	} else {
		return 0;
	}
}

1;
