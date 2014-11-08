package Bugzilla::Extension::Developers::Product;

use strict;
use warnings;
use Bugzilla::Group;
use Bugzilla::Product;
use Bugzilla::Extension::Developers::Util;

sub developers {
    my ($self) = @_;

    if (!defined $self->{dev()}) {
        my $group = Bugzilla::Group->new({ name => dev_group_name($self) });

        $self->{dev()} = $group ? $group->members_non_inherited : [];
    }

    return $self->{dev()};
}

BEGIN {
        *Bugzilla::Product::developers = \&developers;
}

1;
