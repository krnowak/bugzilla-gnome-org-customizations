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
use Bugzilla::Install::Util qw(indicate_progress);
use TraceParser::Trace;

our @EXPORT = qw(
    install_update_db
    linkify_comment
    page
);

sub install_update_db {
    my $dbh = Bugzilla->dbh;
    my $has_traces = $dbh->selectrow_array('SELECT 1 FROM trace '
                                           . $dbh->sql_limit('1'));
    return if !$has_traces;

    print "Parsing traces from comments...\n";
    my $total = $dbh->selectrow_array('SELECT COUNT(*) FROM longdescs');

    if ($dbh->isa('Bugzilla::DB::Mysql')) {
        $dbh->{'mysql_use_result'} = 1;
    }

    my $sth = $dbh->prepare('SELECT bug_id, thetext FROM longdescs');
    $sth->execute();
    my $count = 0;
    my @traces;
    while (my ($bug_id, $text) = $sth->fetchrow_array) {
        $count++;
        my $trace = TraceParser::Trace->parse_from_text($text, $bug_id);
        push(@traces, $trace) if $trace;
        indicate_progress({ current => $count, total => $total,
                            every => 100 });
    }

    my $total_traces = scalar(@traces);
    print "Parsed $total_traces traces.\n";

    if ($dbh->isa('Bugzilla::DB::Mysql')) {
        $dbh->{'mysql_use_result'} = 0;
    }

    print "Inserting parsed traces into DB...\n";
    $count = 1;
    $dbh->bz_start_transaction();
    while (my $trace = shift @traces) {
        TraceParser::Trace->create($trace);
        indicate_progress({ current => $count++, total => $total_traces,
                            every => 100 });
    }
    $dbh->bz_commit_transaction();
}

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
