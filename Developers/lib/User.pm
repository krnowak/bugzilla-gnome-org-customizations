package Bugzilla::Extension::Developers::User;

use strict;
use warnings;
use Bugzilla::User;
use Bugzilla::Extension::Developers::Product;
sub is_developer {
    my ($self, $product) = @_;

    if ($product) {
        # Given the only use of this is being passed bug.product_obj,
        # at the moment the performance of this should be fine.
        my $devs = $product->developers;
        my $is_dev = grep { $_->id == $self->id } @$devs;
        return $is_dev ? 1 : 0;
    }
    else {
        return $self->in_group("developers") ? 1 : 0;
    }

    return 0;
}

BEGIN {
        *Bugzilla::User::is_developer = \&is_developer;
}

1;
