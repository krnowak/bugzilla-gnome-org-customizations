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
    my ($self) = @_;
    my $extensions = Bugzilla->extensions();
    my $extension_name = 'Bugzilla::Extension::GnomeAttachmentStatus';
    my $found_attachment_status_extension = undef;

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

__PACKAGE__->NAME;
