package Bugzilla::Extension::PatchReport;
use strict;
use warnings;
use base qw(Bugzilla::Extension);

use Bugzilla::Extension::PatchReport::Util;

our $VERSION = '0.01';

sub page_before_template {
    my ($self, $args) = @_;

    page(%{ $args });
}

sub install_before_final_checks {
    my ($self, $params) = @_;
    my $extensions = Bugzilla->extensions();
    my $extension_name = 'Bugzilla::Extension::GnomeAttachmentStatus';
    my $found_attachment_status_extension = undef;

    unless ($params->{'silent'}) {
        print "Checking if we have $extension_name installed...\n";
    }

    for my $extension (@{$extensions}) {
        if ($extension->isa($extension_name)) {
            $found_attachment_status_extension = 1;
            last;
        }
    }

    unless ($found_attachment_status_extension) {
        die __PACKAGE__->NAME . ' extension requires ' . $extension_name . ' extension';
    }
}

sub enabled {
    1;
}

__PACKAGE__->NAME;
