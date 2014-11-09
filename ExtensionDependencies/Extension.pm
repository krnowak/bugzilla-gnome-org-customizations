# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Extension::ExtensionDependencies;
use strict;
use warnings;
use base qw(Bugzilla::Extension);

# This code for this is in ./extensions/ExtensionDependencies/lib/Util.pm
use Bugzilla::Extension::ExtensionDependencies::Util;

our $VERSION = '0.01';

# See the documentation of Bugzilla::Hook ("perldoc Bugzilla::Hook"
# in the bugzilla directory) for a list of all available hooks.
sub install_before_final_checks {
    my ($self, $params) = @_;
    my $silent = $params->{'silent'};

    check_dependencies($silent);
}

__PACKAGE__->NAME;
