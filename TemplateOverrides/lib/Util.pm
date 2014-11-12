# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Extension::TemplateOverrides::Util;

use strict;
use warnings;
use base qw(Exporter);
use Array::Utils qw(array_minus intersect);
use IO::Dir;
use File::Spec;
use Bugzilla::Extension::TemplateOverrides::Digests;

our @EXPORT = qw(
    check_overridden_templates
);

# This file can be loaded by your extension via
# "use Bugzilla::Extension::TemplateOverrides::Util". You can put functions
# used by your extension in here. (Make sure you also list them in
# @EXPORT.)

sub _get_templates {
    my (@initial_paths) = @_;
    my @paths = map {[$_, undef]} @initial_paths;
    my @tmpls = ();

    while (@paths) {
        my $path_pair = shift(@paths);
        my $initial = $path_pair->[0];
        my $rest = $path_pair->[1];
        my $path = $initial;

        if (defined($rest)) {
            $path = File::Spec->catdir($initial, $rest);
        }

        my $dir = IO::Dir->new($path);

        next unless defined($dir);
        while (defined(my $entry = $dir->read())) {
            next if $entry =~ /^\.{1,2}$/;

            my $rest_entry = $entry;

            if (defined($rest)) {
                $rest_entry = File::Spec->catdir($rest, $entry);
            }

            my $complete_path = File::Spec->catdir($initial, $rest_entry);

            if (-d $complete_path) {
                push(@paths, [$initial, $rest_entry]);
                next;
            }
            if ($entry =~ /\.tmpl$/) {
                push(@tmpls, $rest_entry);
                next;
            }
        }
    }

    @tmpls;
}

sub _check_overrides {
    my ($extension_paths, $default_paths, $digests) = @_;
    my @overridden = _get_templates(@{$extension_paths});
    my @default = _get_templates(@{$default_paths});
    my @common = intersect(@default, @overridden);
    my @not_overrides = array_minus(@overridden, @common);

    if (@not_overrides) {
        die 'Following templates are not overriding ' .
            'anything: ' . join(', ', @not_overrides);
    }

    my @digested_files = keys(%{$digests});
    my @not_digested = array_minus(@overridden, @digested_files);

    if (@not_digested) {
        die 'Following overrides are missing their digests: ' .
            join(', ', @not_digested);
    }

    my @digested_not_overrides = array_minus(@digested_files, @overridden);

    if (@digested_not_overrides) {
        die 'Following files have digests, but no overrides for them exist: ' .
            join(', ', @digested_not_overrides);
    }
}

sub check_overridden_templates {
    my ($silent) = @_;
    my %digests = overrides_digests();

    print "Checking overridden templates...\n" unless $silent;
    return unless keys(%digests);
    # template_include_path is from Bugzilla::Install::Util package.
    my @template_paths = map {File::Spec->canonpath($_)} @{Bugzilla::Install::Util::template_include_path()};
    my @extension_paths = grep {/^extensions\/TemplateOverrides\//} @template_paths;
    my @default_paths = grep {!/^extensions\//} @template_paths;

    _check_overrides(\@extension_paths, \@default_paths, \%digests);
    for my $file (sort keys (%digests))
    {
        my $complete_path = undef;

        for my $path (@default_paths)
        {
            my $potential_path = File::Spec->catfile($path, $file);

            next unless (-r $potential_path);
            $complete_path = $potential_path;
            last;
        }
        unless ($complete_path)
        {
            die "Original template for $file not found - should not happen";
        }

        my $sha = Digest::SHA->new(256);
        $sha->addfile($complete_path);
        my $digest = $sha->hexdigest();
        if ($digest ne $digests{$file})
        {
            die "Original $file (at $complete_path) has changed " .
            'since last checksetup. Please check if the changes ' .
            'should be backported to overridden templates and ' .
            'update the digest in %digests variable with ' .
            $digest;
        }
    }
}

1;
