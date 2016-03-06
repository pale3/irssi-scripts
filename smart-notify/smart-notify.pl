# Copyright © 2015 Marko Rakamaric <marko.rakamaric@gmail.com>
# DEPENDECY: xdotool, xprop, perl-html-entities
# 
# This script is my solution to use notification system like libnotify.
# It is enchancement on every other script I encounter which uses notify-osd style. In some 
# way it is special as it involves determination wheater to show notification or not.
#
# Here are some features:
#    - check if irssi window is focused or not
#    - check if highlight channel is active or not
#    - check if irssi is spawned from tmux or just plain terminal client
# 
# Based on above, we determine if we should spawn notification or not. If tmux pane window is focused
# and irssi channel is in current view(active), then there is no need to spawn notification(user already 
# have eyes on channel).
#
# Options: 
#	 notify_tmux_window_name: 
#			DESCRIPTION: name of tmux pane window 
#			TYPE: string (default: IRSSI)
#			
#  notify_active_window_names 
#			DESRIPTION: title of irssi parent window againt we determine if we should spawn notification or not
#			TYPE: array (default: Scratchpad irssi)
#			
#  notify_multiplexter 
#			DESCRIPTION: are we using multiplexter at all (if this is set, one need to also set notify_tmux_window_name)
#			TYPE: string (default: true ) NOTE: LEAVE AS IS, probably wont work without this
#			
#  (TODO)notify_osd_cmd - notification command, system one
#                 - notify-send --help (default: notify-send -a irssi)
#  (TODO)notify_osd_sound - specify path to wav file to use upon notifaction 
#                   - (default: )
# 
# How to use: 
#    - use title for irssi parent window. This can be done forcing terminal to execute irssi
#      with irssi title. That way your irssi instance would have constant name of irssi as well as 
#      tmux window pane.
#			 ex: urxvt -title irssi -e irssi 
#		
#		extra: 
#    - you can define in ~/.bashrc alias so that you can use constant title for irssi
#		   E.g: echo "alias irssi='urxvt -title irssi -e irssi'" >> ~/home/$USER/.bashrc
#		   
#		 - you need to have tmux pane which has same name as one in setting notfy_tmux_window_name
#		 - for tmux if you are using sessions then define name of that session and specify name like this
#		   E.g: urxvt -title Scratchpad -e tmux attach
#
# Known BUG:
#    - if someone HILIGHT you on channel, you will get notification wheater that channel is active or not
#    
# Final words:
# This way we can always know if irssi has a focus or not. Irssi is terminal app so it' dificult to 
# determine if app has a focused or not. Using methods above we can hack that
	
use strict;
use Irssi;
use vars qw($VERSION %IRSSI);
use HTML::Entities;

# debug some outputs
#warn Dumper $string;
#$Data::Dumper::Useqq=1

$VERSION = "1.0";
%IRSSI = (
    authors     => 'Marko Rakamaric',
    contact     => 'jabber: pale3@tigase.im',
    name        => 'smart-notify.pl',
    description => 'Smart libnotify message notification',
    license     => 'GNU General Public License',
    url         => 'https://github.org/pale3/irssi-scripts/smart-notify/smart-notify.pl'
);

sub sanitize {
		my ($text) = @_;
  	
		my $apos = "&#39;";
  	my $aposenc = "\&apos;";
		encode_entities($text,'\'<>&');
  	
		$text =~ s/$apos/$aposenc/g;
  	$text =~ s/"/\\"/g;
		#$text =~ s/\x03\d\d(.*?)\x0F//g;
		
		# fix for bitlbee OTR trusted/untrusted color codes 
		$text =~ s/\x03\d\d(.*?)//g; # remove pre escape color codes
		$text =~ s/\x0F//g; # remove escape codes end
  	
		return $text;
}

sub notify {
    my ($server, $summary, $message) = @_;

    # Make the message entity-safe
		$summary = sanitize($summary);
		$message = sanitize($message);

    my $cmd = "EXEC - notify-send" .
							" -u " . Irssi::settings_get_str('notify_urgency') .
							" -i " . Irssi::settings_get_str('notify_icon') .
							" -a " . Irssi::settings_get_str('notify_appname') .
							" -- '" . $summary . "'" .
							" '" . $message . "'";
		
    $server->command($cmd);

}

sub print_text_notify {
		my ($dest, $text, $scattered) = @_;
		
		return unless Irssi::settings_get_bool('notify_enabled');
		
		my $server = $dest->{server};
		my $channel = $dest->{channel};

		return if (!$server || !($dest->{level} & MSGLEVEL_HILIGHT));
		
		my $stripped = $scattered;

		# whole text with sender and our nick
		$scattered =~ s/^.+? +(.*)/\1/ ; 

		my $sender = $scattered;
		$sender =~ s{[:^]+.*}{};
		
		return if (should_we_notify($dest->{target},$sender) ne 1);
		
		$text =~ s{^[^:]+:[^:]+:\s*}{};
	
		notify($server, $sender . "says: ",  $text);

}
 
sub is_channel_active {
		my ($server, $nick ) = @_;

		my $win = Irssi::active_win();
    my $active = $win->{active}->{name};
		
		# active channel same as sender or active same as dest channel
		my $ret = (($active eq $nick) or ($active eq $server) ) ? 1 : 0;
		return $ret;

}

sub is_window_active {
		my $curr_win_focus = `xdotool getwindowfocus`;
		chop($curr_win_focus);
		
		my $curr_win_title = `xprop -id $curr_win_focus _NET_WM_NAME`;
		chop($curr_win_title);
		
		# extract last word of xprop output with quotes
		$curr_win_title = @{[$curr_win_title =~ m/\w+/g]}[2];
		
		my @_gs_win_titles = split / /, Irssi::settings_get_str('notify_active_window_names');
		return unless (@_gs_win_titles);

		foreach my $title (@_gs_win_titles) {
				if ($curr_win_title eq $title){
					return 1;
				}
		}
}

sub is_in_multiplexer {
		# screen doesn't have fancy ipc, so I am not able to check in screen for active window
		# by default multiplexer if true then we assume tmux is in role
		my $_gs_multiplexer = Irssi::settings_get_str('notify_tmux_multiplexer');
		return unless ($_gs_multiplexer eq "true" );
		
		# get TMUX env var
		my $in_tmux = $ENV{'TMUX'};
		
		return $in_tmux;
}

sub is_tmux_pane_active{

		my $_gs_tmux_win_name = Irssi::settings_get_str('notify_tmux_window_name');
		return unless ($_gs_tmux_win_name );
		
		my $tmux_win_active = `tmux list-panes -F '#{window_name}' | head -n 1`;
		chomp($tmux_win_active);

		my $ret = ($tmux_win_active eq $_gs_tmux_win_name) ? 1 : 0;
		return $ret;
}

sub should_we_notify	{
    my ($server, $nick) = @_;
		my $notify;
		
		if (is_window_active() eq 1){ # ex: irssi, Scratchpad
			
			if (is_in_multiplexer() ne "" ){
				$notify = (( is_tmux_pane_active eq 1 ) and (is_channel_active($server,$nick) eq 1)) ? 0 : 1;
			}else{
				$notify = (is_channel_active($server,$nick) eq 1) ? 0 : 1;
			}

		}else{
			# allways notify as window is not focused
			$notify = 1;
		}

		return $notify;

}

sub message_private_notify {
    my ($server, $msg, $nick) = @_;
   
		return unless Irssi::settings_get_bool('notify_enabled');

		my $notify = (should_we_notify($server,$nick) ne 1) ? 0 : 1;

		return if ($notify ne 1);
		notify($server, $nick . " says: ", $msg );
		
}

sub dcc_request_notify {
    my ($dcc, $sendaddr) = @_;
    my $server = $dcc->{server};

		return unless Irssi::settings_get_bool('notify_enabled');
    
		return if (!$dcc);
    notify($server, "DCC ".$dcc->{type}." request", $dcc->{nick});
}

Irssi::settings_add_bool('notify', 'notify_enabled', 1);
Irssi::settings_add_str( 'notify', 'notify_tmux_multiplexer', 'true' ); # FIXME: use bool
Irssi::settings_add_str( 'notify', 'notify_tmux_window_name', 'IRSSI' );
Irssi::settings_add_str( 'notify', 'notify_active_window_names', 'Scratchpad irssi' );
Irssi::settings_add_str( 'notify', 'notify_icon', 'gtk-dialog-info' );
Irssi::settings_add_str( 'notify', 'notify_appname', 'irssi');
Irssi::settings_add_str( 'notify', 'notify_urgency', 'normal');

# Irssi::signals
Irssi::signal_add( 'print text', 'print_text_notify' );
Irssi::signal_add( 'message private', 'message_private_notify' );
Irssi::signal_add( 'dcc request', 'dcc_request_notify' );
