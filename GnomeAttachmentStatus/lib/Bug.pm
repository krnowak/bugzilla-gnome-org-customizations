# -*- Mode: perl; indent-tabs-mode: nil -*-
#
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Extension::GnomeAttachmentStatus::Bug;
use strict;
use warnings;
use Bugzilla::Extension::GnomeAttachmentStatus::Util;
use Bugzilla::Bug;
use constant SHOW_G_A_S => 'show_' . g_a_s();

sub bugzilla_bug_show_gnome_attachment_status {
    my ($self) = @_;

    return 0 if $self->{'error'};
    unless (exists ($self->{SHOW_G_A_S()})) {
        $self->{SHOW_G_A_S()} = grep { $_->ispatch } @{$self->attachments};
    }

    return $self->{SHOW_G_A_S()};
}

BEGIN {
    *Bugzilla::Bug::show_gnome_attachment_status = \&bugzilla_bug_show_gnome_attachment_status;
}

1;
