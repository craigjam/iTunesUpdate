package Plugins::iTunesUpdate::Settings;

use strict;
use base qw(Slim::Web::Settings);
use Slim::Utils::Log;
use Slim::Utils::Misc;
use Slim::Utils::Prefs;
use Slim::Utils::OSDetect;

use Data::Dumper;

my $log = logger('plugin.itunesupdate');
my $prefs = preferences('plugin.itunesupdate');

#
sub name {
    return 'PLUGIN_ITUNES_UPDATER';
}

sub needsClient {
	return 0;
}

#
#
#
sub page {
    return 'plugins/iTunesUpdate/settings/basic.html';
}

# migrate to version 1 of namespace - in this case copying old style prefs across
$prefs->migrate(1, sub {
	my $prefs = shift;
	# copy valid from old preferences file
	$prefs->set('directupdate', Slim::Utils::Prefs::OldPrefs->get('plugin_itunesupdate_directupdate') );
	$prefs->set('halfstar', Slim::Utils::Prefs::OldPrefs->get('plugin_itunesupdate_halfstar') );
	$prefs->set('set_artwork', Slim::Utils::Prefs::OldPrefs->get('plugin_itunesupdate_set_artwork') );
	$prefs->set('ignore_filetype', Slim::Utils::Prefs::OldPrefs->get('plugin_itunesupdate_ignore_filetype') );
	1;
});

# init prefs which have not previously been set
$prefs->init({
	"directupdate"=> (Slim::Utils::OSDetect::OS() ne 'unix'),
	"halfstar"=> 0,
	"set_artwork"=> 0,
	"ignore_filetype"=> 0,
	"bookmarks" => 0,
});

#
#
#
sub handler {
 my ($class, $client, $params) = @_;

	my @prefs = qw(
		directupdate
		set_artwork
		ignore_filetype
		halfstar
		bookmarks
	);

	#the rest of the prefs
	for my $pref (@prefs) {
		if ($params->{'saveSettings'}) {
			$prefs->set($pref, $params->{$pref});
		}
		$params->{'prefs'}->{$pref} = $prefs->get($pref);
		$log->debug("$pref:".Dumper($params->{'prefs'}->{$pref}));
       	}

        return $class->SUPER::handler($client, $params);
}

1;

__END__
