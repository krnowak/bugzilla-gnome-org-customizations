# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Extension::TemplateOverrides;

use 5.10.1;
use strict;
use warnings;

use parent qw(Bugzilla::Extension);

# This code for this is in ./extensions/TemplateOverrides/lib/Util.pm
use Bugzilla::Extension::TemplateOverrides::Util;

our $VERSION = '0.01';

sub install_before_final_checks {
    my ($self, $params) = @_;
    my $silent = $params->{'silent'};

    check_overridden_templates($silent);
}

__PACKAGE__->NAME;
