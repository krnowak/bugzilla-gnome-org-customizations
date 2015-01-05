package Bugzilla::Extension::PatchStatus::Status;

use strict;
use warnings;
use Bugzilla::Status;

sub _filtered_open_states {
    my @filtered = grep { $_ ne "NEEDINFO" } BUG_STATE_OPEN;

    return \@filtered;
}

sub gnome_open_statuses {
    my $dbh = Bugzilla->dbh();
    my $cache = Bugzilla->request_cache();

    $cache->{'gnome_open_bug_statuses'} ||= _filtered_open_states();

    return @{$cache->{'gnome_open_bug_statuses'}};
}

BEGIN {
    *Bugzilla::Status::gnome_open_statuses = \&gnome_open_statuses;
}

1;
