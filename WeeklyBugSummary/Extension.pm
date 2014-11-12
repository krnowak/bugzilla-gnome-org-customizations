package Bugzilla::Extension::WeeklyBugSummary;
use strict;
use warnings;
use base qw(Bugzilla::Extension);

use Bugzilla::Extension::WeeklyBugSummary::Util;

our $VERSION = '0.01';

sub page_before_template {
    my ($self, $args) = @_;

    page($args);
}

__PACKAGE__->NAME;
