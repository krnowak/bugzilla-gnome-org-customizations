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
# The Initial Developer of the Original Code is Canonical Ltd.
# Portions created by the Initial Developer are Copyright (C) 2009
# the Initial Developer. All Rights Reserved.
#
# Contributor(s): 
#   Max Kanat-Alexander <mkanat@bugzilla.org>

package TraceParser::Hooks;
use strict;
use base qw(Exporter);
use TraceParser::Trace;

our @EXPORT = qw(
    linkify_comment
    page
);

sub linkify_comment {
    my %params = @_;
    my ($text, $bug_id, $match, $replace) = @params{qw(text bug_id match replace)};
    my $trace = TraceParser::Trace->new_from_text($$text, $bug_id);
    return if !$trace;
    my $template = Bugzilla->template_inner;
    my $match_text = quotemeta($trace->text);
    push(@$match, qr/$match_text/s);
    my $replacement;
    $template->process('trace/format.html.tmpl', { trace => $trace },
                       \$replacement)
      || ThrowTemplateError($template->error);
    push(@$replace, $replacement);
}


sub page {
    my %params = @_;
    my ($vars, $page) = @params{qw(vars page_id)};
    return if $page !~ '^trace\.';
    my $trace_id = Bugzilla->cgi->param('trace_id');
    my $trace = TraceParser::Trace->check({ id => $trace_id });
    $vars->{trace} = $trace;
}

1;
