package Bugzilla::Extension::Developers::User;

use strict;
use warnings;
use Bugzilla::User;
use Bugzilla::Extension::Developers::Util;
use Bugzilla::Extension::Developers::Product;
use List::MoreUtils qw{any};

sub is_developer {
    my ($self, $product) = @_;

    if ($product) {
        # Given the only use of this is being passed bug.product_obj,
        # at the moment the performance of this should be fine.
        return any { $_->id == $self->id } @{$product->developers()};
    }
    return $self->in_group(dev());
}

BEGIN {
        *Bugzilla::User::is_developer = \&is_developer;
}

1;
