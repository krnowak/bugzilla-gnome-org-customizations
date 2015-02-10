# -*- Mode: perl; indent-tabs-mode: nil -*-
#
# The contents of this file are subject to the Mozilla Public
# License Version 1.1 (the "License"); you may not use this file
# except in compliance with the License. You may obtain a copy of
# the License at http://www.mozilla.org/MPL/
#
# Software distributed under the License is distributed on an "AS
# IS" basis, WITHOUT WARRANTY OF ANY KIND, either express or
# implied. See the License for the specific language governing
# rights and limitations under the License.
#
# The Original Code is the Bugzilla Bug Tracking System.
#
# Contributor(s):  Frédéric Buclin <LpSolit@gmail.com>
#                  Max Kanat-Alexander <mkanat@bugzilla.org>
#                  Owen Taylor <otaylor@fishsoup.net>

package Bugzilla::Extension::Splinter::WebService;
use strict;
use warnings;

use Bugzilla;
use Bugzilla::Attachment;
use Bugzilla::BugMail;
use Bugzilla::Constants;
use Bugzilla::Field;
use Bugzilla::Util qw(trim);

use Bugzilla::Extension::Splinter::WebServiceUtil;

use base qw(Bugzilla::WebService);

use constant PUBLIC_METHODS => qw(
    publish_review
);

# The idea of this method is to be able to
#
#  - Add a comment with says "Review of attachment <id>:" rather than
#    "From update of attachment"
#
# and:
#
#  - Update the attachment status (in the future flags as well)
#
# While sending out only a single mail as the result. If we did one post
# to processs_bug.cgi and one to attachment.cgi, we'd get two mails.
#
# Based upon WebServer::Bug::add_comment() and attachment.cgi
sub publish_review {
    my ($self, $params) = @_;

    # The user must login in order to publish a review
    Bugzilla->login(LOGIN_REQUIRED);

    # Check parameters
    defined $params->{'attachment_id'}
        || ThrowCodeError('param_required', { 'param' => 'attachment_id' });
    my $review = $params->{'review'};
    (defined($review) && trim($review) ne '')
        || ThrowCodeError('param_required', { 'param' => 'review' });

    my $attachment_status = $params->{'attachment_status'};
    if (defined($attachment_status)) {
        my $field_object = Bugzilla::Field->new({ name => 'attachments.gnome_attachment_status' });
        my @legal_values = map { $_->name } @{ $field_object->legal_values() };
        check_field('attachments.gnome_attachment_status', $attachment_status, \@legal_values);
    }

    my $attachment = Bugzilla::Attachment->new($params->{'attachment_id'});
    defined($attachment)
        || ThrowUserError('invalid_attach_id',
                          { 'attach_id' => $params->{'attachment_id'} });

    # Publishing a review of an attachment you can't access doesn't leak
    # information about that attachment, but it seems like bad policy to
    # allow it.
    check_can_access($attachment);

    my $bug = Bugzilla::Bug->new($attachment->bug_id);
    my $user = Bugzilla->user();

    $user->can_edit_product($bug->product_id)
        || ThrowUserError('product_edit_denied', {'product' => $bug->product()});

    # This is a "magic string" used to identify review comments
    my $comment = 'Review of attachment ' . $attachment->id() . ":\n\n" . $review;
    my $dbh = Bugzilla->dbh();
    # Figure out when the changes were made.
    my ($timestamp) = $dbh->selectrow_array("SELECT NOW()");

    # Append review comment
    $bug->add_comment($comment);
    $dbh->bz_start_transaction();

    if (defined($attachment_status) && $attachment->gnome_attachment_status() ne $attachment_status) {
        $attachment->set_gnome_attachment_status($attachment_status);
        $attachment->update();
    }

    # This actually adds the comment
    $bug->update();
    $dbh->bz_commit_transaction();

    # Send mail.
    Bugzilla::BugMail::Send($bug->bug_id(), { changer => $user });

    # Nothing very interesting to return on success, so just return an empty structure
    return {};
}

1;
