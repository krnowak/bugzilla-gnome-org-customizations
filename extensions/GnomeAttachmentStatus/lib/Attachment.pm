# -*- Mode: perl; indent-tabs-mode: nil -*-
#
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Extension::GnomeAttachmentStatus::Attachment;
use strict;
use warnings;
# The below line is only to avoid protection faults in
# Bugzilla::Object::set().
use base qw(Bugzilla::Object);
use Bugzilla::Extension::GnomeAttachmentStatus::Util;
use Bugzilla::Attachment;

sub bugzilla_attachment_set_gnome_attachment_status {
    my ($attachment, $status) = @_;

    $attachment->set(g_a_s(), $status);
}

sub bugzilla_attachment_gnome_attachment_status {
    my ($attachment) = @_;

    $attachment->{g_a_s()};
}

BEGIN {
    *Bugzilla::Attachment::set_gnome_attachment_status = \&bugzilla_attachment_set_gnome_attachment_status;
    *Bugzilla::Attachment::gnome_attachment_status = \&bugzilla_attachment_gnome_attachment_status;
}

1;
