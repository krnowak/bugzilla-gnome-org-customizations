# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Extension::ExtensionDependencies::Util;
use strict;
use warnings;
use base qw(Exporter);
use Bugzilla;
our @EXPORT = qw(
    check_dependencies
);

# This file can be loaded by your extension via
# "use Bugzilla::Extension::ExtensionDependencies::Util". You can put functions
# used by your extension in here. (Make sure you also list them in
# @EXPORT.)

sub check_dependencies {
    my ($silent) = @_;
    my $extensions = Bugzilla->extensions();
    my %extensions_hash = map { ref($_) => $_ } @{$extensions};

    for my $extension_name (sort keys(%extensions_hash)) {
        my $extension = $extensions_hash{$extension_name};

        next unless $extension->can('gnome_deps');

        my @deps = map {'Bugzilla::Extension::' . $_} $extension->gnome_deps();

        print "Checking dependencies of $extension_name...\n" unless $silent;
        for my $dep (@deps) {
            print "Checking if $dep is available...\n" unless $silent;
            unless ($extensions_hash{$dep}) {
                die "$extension_name has unsatisfied dependency on $dep extension - $dep is not available";
            }
            print "Checking if $dep is enabled...\n" unless $silent;
            unless ($extensions_hash{$dep}->enabled()) {
                die "$extension_name has unsatisfied dependency on $dep extension - $dep is disabled";
            }
        }
    }
}

1;
