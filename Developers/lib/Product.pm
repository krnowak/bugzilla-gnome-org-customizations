package Bugzilla::Extension::Developers::Product;

use strict;
use warnings;
use Bugzilla::Group;
use Bugzilla::Product;

sub developers {
    my ($self) = @_;

    if (!defined $self->{'developers'}) {
        $self->{'developers'} = [];

        my $group = Bugzilla::Group->new({ name => $self->name . '_developers' });
        $self->{developers} = $group ? $group->members_non_inherited : [];
    }

    return $self->{'developers'};
}

BEGIN {
        *Bugzilla::Product::developers = \&developers;
}

1;
