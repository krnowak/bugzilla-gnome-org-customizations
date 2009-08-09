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
use Bugzilla::Bug;
use Bugzilla::Constants;
use Bugzilla::Error;
use Bugzilla::Install::Util qw(indicate_progress);
use Bugzilla::Util qw(detaint_natural);

use TraceParser::Trace;

use List::Util;
use POSIX qw(ceil);

our @EXPORT = qw(
    bug_create
    bug_update
    install_update_db
    format_comment
    page
);

use constant DEFAULT_POPULAR_LIMIT => 20;

sub bug_create {
    my %params = @_;
    my $bug = $params{bug};
    my $comments = Bugzilla::Bug::GetComments($bug->id, 'oldest_to_newest',
        '1970-01-01', $bug->creation_ts, 'raw');
    my $comment = $comments->[0];
    my $data = TraceParser::Trace->parse_from_text($comment->{body});
    return if !$data;
    my $trace = TraceParser::Trace->create(
        { %$data, comment_id => $comment->{id} });
    _check_duplicate_trace($trace, $bug, $comment);
}

sub _check_duplicate_trace {
    my ($trace, $bug, $comment) = @_;
    my $cgi = Bugzilla->cgi;
    my $dbh = Bugzilla->dbh;
    my $template = Bugzilla->template;
    my $user = Bugzilla->user;

    if (my $dup_to = $trace->must_dup_to) {
        $dbh->bz_rollback_transaction if $dbh->bz_in_transaction;
        _handle_dup_to($trace, $dup_to, $comment);
    }

    my @identical = grep { $_->is_visible } @{ $trace->identical_traces };
    my @similar   = grep { $_->is_visible } @{ $trace->similar_traces };
    if (@identical or @similar) {
        $dbh->bz_rollback_transaction if $dbh->bz_in_transaction;
        my $product = $bug->product;
        my @prod_traces  = grep { $_->bug->product eq $product } 
                                (@identical, @similar);
        my @other_traces = grep { $_->bug->product ne $product } 
                                (@identical, @similar);

        my %vars = (
            comment    => $comment,
            prod_bugs  => _traces_to_bugs(\@prod_traces),
            other_bugs => _traces_to_bugs(\@other_traces),
            product    => $product,
        );
        my $total_other_bugs = scalar(@{ $vars{other_bugs} });

        my %by_product;
        foreach my $bug (@{ $vars{other_bugs} }) {
            $by_product{$bug->product} ||= [];
            push(@{ $by_product{$bug->product} }, $bug);
        }
        $vars{other_bugs} = \%by_product;

        if ($total_other_bugs > 10) {
            my $total_products = scalar keys %by_product;
            $vars{other_limit} = ceil(10.0 / $total_products);
        }

        print $cgi->header;
        $template->process('trace/possible-duplicate.html.tmpl', \%vars)
          or ThrowTemplateError($template->error);
        exit;
    }
}

sub _traces_to_bugs {
    my $traces = shift;
    my $user = Bugzilla->user;

    my @bugs_in = map { $_->bug } @$traces;
    my %result_bugs;
    foreach my $bug (@bugs_in) {
        $bug = _walk_dup_chain($bug);
        if ($user->can_see_bug($bug)) {
            $result_bugs{$bug->id} = $bug;
        }
    }

    my @sorted_bugs = sort _cmp_trace_bug (values %result_bugs);
    return \@sorted_bugs;
}

sub _walk_dup_chain {
    my $bug = shift;
    if (!$bug->dup_id) {
        return $bug;
    }
    return _walk_dup_chain(new Bugzilla::Bug($bug->dup_id));
}

sub _cmp_trace_bug($$) {
    my ($a, $b) = @_;

    # $a should sort before $b if it has a resolution of FIXED
    # and $b does not.
    if ($a->resolution eq 'FIXED' and $b->resolution ne 'FIXED') {
        return -1;
    }
    elsif ($a->resolution ne 'FIXED' and $b->resolution eq 'FIXED') {
        return 1;
    }

    # Otherwise, $a should sort before $b if it is open and $b is not.
    if ($a->isopened and !$b->isopened) {
        return -1;
    }
    elsif (!$a->isopened and $b->isopened) {
        return 1;
    }

    # But sort UNCONFIRMED later than other open statuses
    if ($a->bug_status eq 'UNCONFIRMED' and $b->bug_status ne 'UNCONFIRMED') {
        return 1;
    }
    elsif ($a->bug_status ne 'UNCONFIRMED' and $b->bug_status eq 'UNCONFIRMED') {
       return -1;
    }

    # Otherwise, show older bugs first.
    return $a->id <=> $b->id;
}

sub _handle_dup_to {
    my ($trace, $dup_to, $comment, $allow_closed) = @_;
    my $user = Bugzilla->user;

    if (!$user->can_edit_product($dup_to->product_id)
        or !$user->can_see_bug($dup_to))
    {
        ThrowUserError('traceparser_dup_to_hidden',
                       { dup_to => $dup_to });
    }

    if (!$dup_to->isopened and !$allow_closed) {
        ThrowUserError('traceparser_dup_to_closed',
                       { dup_to => $dup_to });
    }

    $dup_to->add_cc($user);

    # If this trace is higher quality than any other trace on the
    # bug, then we add the comment. Otherwise we just skip the
    # comment entirely.
    my $bug_traces = TraceParser::Trace->traces_on_bug($dup_to);
    my $higher_quality_traces;
    foreach my $t (@$bug_traces) {
        if ($t->{quality} >= $trace->{quality}) {
            $higher_quality_traces = 1;
            last;
        }
    }

    my $comment_added;
    if (!$higher_quality_traces) {
        if ($dup_to->check_can_change_field('longdesc', 0, 1)) {
            my %comment_options = %$comment;
            my @comment_cols = Bugzilla::Bug::UPDATE_COMMENT_COLUMNS;
            foreach my $key (keys %comment_options) {
                if (!grep { $_ eq $key } @comment_cols) {
                    delete $comment_options{$key};
                }
            }
            $dup_to->add_comment($comment->{body}, \%comment_options);
            $comment_added = 1;
        }
    }

    $dup_to->update();
    if (Bugzilla->usage_mode == USAGE_MODE_BROWSER) {
        my $template = Bugzilla->template;
        my $cgi = Bugzilla->cgi;
        my $vars = {};
        # Do the various silly things required to display show_bug.cgi
        # in Bugzilla 3.4.
        $vars->{use_keywords} = 1 if Bugzilla::Keyword::keyword_count();
        $vars->{bugs} = [$dup_to];
        $vars->{bugids} = [$dup_to->id];
        if ($cgi->cookie("BUGLIST")) {
            $vars->{bug_list} = [split(/:/, $cgi->cookie("BUGLIST"))];
        }
        eval {
            require PatchReader;
            $vars->{'patchviewerinstalled'} = 1;
        };
        $vars->{comment_added} = $comment_added;
        $vars->{message} = 'traceparser_dup_to';
        print $cgi->header;
        $template->process('bug/show.html.tmpl', $vars)
            or ThrowTemplateError($template->error);
        exit;
    }

    # This is what we do for all non-browser usage modes.
    ThrowUserError('traceparser_dup_to',
                   { dup_to => $dup_to, 
                     comment_added => $comment_added });
}

sub bug_update {
    my %params = @_;
    my ($bug, $timestamp) = @params{qw(bug timestamp)};
    return if !$bug->{added_comments};
    my $comments = Bugzilla::Bug::GetComments($bug->id, 'oldest_to_newest', 
                                              $bug->delta_ts, $timestamp, 1);
    foreach my $comment (@$comments) {
        my $data = TraceParser::Trace->parse_from_text($comment->{body});
        next if !$data;
        TraceParser::Trace->create({ %$data, comment_id => $comment->{id} });
    }
}

sub install_update_db {
    my $dbh = Bugzilla->dbh;
    my $has_traces = $dbh->selectrow_array('SELECT 1 FROM trace '
                                           . $dbh->sql_limit('1'));
    return if $has_traces;

    print "Parsing traces from comments...\n";
    my $total = $dbh->selectrow_array('SELECT COUNT(*) FROM longdescs');

    if ($dbh->isa('Bugzilla::DB::Mysql')) {
        $dbh->{'mysql_use_result'} = 1;
    }

    my $sth = $dbh->prepare('SELECT comment_id, thetext FROM longdescs 
                           ORDER BY comment_id');
    $sth->execute();
    my $count = 1;
    my @traces;
    while (my ($comment_id, $text) = $sth->fetchrow_array) {
        my $trace = TraceParser::Trace->parse_from_text($text);
        indicate_progress({ current => $count++, total => $total,
                            every => 100 });
        next if !$trace;
        $trace->{comment_id} = $comment_id;
        push(@traces, $trace);
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

sub format_comment {
    my %params = @_;
    my ($text, $bug, $regexes, $comment) = @params{qw(text bug regexes comment)};
    return if !$comment;
    my ($trace) = @{ TraceParser::Trace->match({ comment_id => $comment->{id} }) };
    return if !$trace;

    # $$text contains the wrapped text, and $comment contains the unwrapped
    # text. To find the trace that we want from the DB, we need to use the
    # unwrapped text. But to find the text that we need to replace, we
    # need to use the wrapped text.
    my $match_text;
    if ($comment->{already_wrapped}) {
        $match_text = $trace->text;
    }
    else {
        my $stacktrace = TraceParser::Trace->stacktrace_from_text($$text);
        $match_text = $stacktrace->text;
    }

    $match_text = quotemeta($match_text);
    my $replacement;
    my $template = Bugzilla->template_inner;
    $template->process('trace/format.html.tmpl', { trace => $trace },
                       \$replacement)
      || ThrowTemplateError($template->error);
    # Make sure that replacements don't contain $1, $2, etc.
    $replacement =~ s{\$}{\\\$};
    push(@$regexes, { match => qr/$match_text/s, replace => $replacement });
}

sub page {
    my %params = @_;
    my ($vars, $page) = @params{qw(vars page_id)};
    if ($page =~ /^trace\./) {
        _page_trace($vars);
    }
    elsif ($page =~ /^popular-traces\./) {
        _page_popular_traces($vars);
    }
    elsif ($page =~ /^post-duplicate-trace/) {
        _page_post_duplicate_trace($vars);
    }
}

sub _page_trace {
    my $vars = shift;
    my $cgi = Bugzilla->cgi;
    my $dbh = Bugzilla->dbh;
    my $user = Bugzilla->user;

    my $trace_id = $cgi->param('trace_id');
    my $trace = TraceParser::Trace->check({ id => $trace_id });
    $trace->check_is_visible;

    my $action = $cgi->param('action') || '';
    if ($action eq 'update') {
        $user->in_group('traceparser_edit')
          or ThrowUserError('auth_failure', 
                 { action => 'modify', group => 'traceparser_edit',
                   object => 'settings' });
        if (!$trace->stack_hash) {
            ThrowUserError('traceparser_trace_too_short');
        }
        my $ident_dup = $cgi->param('identical_dup');
        my $similar_dup = $cgi->param('similar_dup');
        $dbh->bz_start_transaction();
        $trace->update_identical_dup($ident_dup);
        $trace->update_similar_dup($similar_dup);
        $dbh->bz_commit_transaction();
    }

    if ($trace->stack_hash) {
        my $identical_traces = $trace->identical_traces;
        my $similar_traces   = $trace->similar_traces;
        $vars->{similar_traces}   = _group_by_product($similar_traces);
        $vars->{identical_traces} = _group_by_product($identical_traces);
    }

    $vars->{trace} = $trace;
}

sub _group_by_product {
    my $traces = shift;

    my %by_product;
    foreach my $trace (@$traces) {
        my $product = $trace->bug->product;
        next if (!Bugzilla->user->can_see_product($product)
                 or $trace->is_hidden_comment);
        $by_product{$product} ||= [];
        push(@{ $by_product{$product} }, $trace);
    }
    return \%by_product;
}

sub _page_popular_traces {
    my $vars = shift;
    my $limit = Bugzilla->cgi->param('limit') || DEFAULT_POPULAR_LIMIT;
    detaint_natural($limit);
    my $dbh = Bugzilla->dbh;

    # insidergroup protections. This unfortunately makes the page
    # slower for users who aren't in the insidergroup.
    my ($extra_from, $extra_where) = ('', '');
    if (Bugzilla->params->{insidergroup} and !Bugzilla->user->is_insider) {
        $extra_from = 'INNER JOIN longdescs ON trace.comment_id ='
                       . ' longdescs.comment_id';
        $extra_where = "AND longdescs.isprivate = 0"
    }

    my %trace_count = @{ $dbh->selectcol_arrayref(
        "SELECT MAX(id), COUNT(*) AS trace_count
           FROM trace $extra_from
          WHERE short_hash IS NOT NULL $extra_where
       GROUP BY short_hash ORDER BY trace_count DESC "
        . $dbh->sql_limit('?'), {Columns=>[1,2]}, $limit) };
 
    my $traces = TraceParser::Trace->new_from_list([keys %trace_count]);
    @$traces = reverse sort { $trace_count{$a->id} <=> $trace_count{$b->id} } 
                            @$traces;
    $vars->{traces} = $traces;
    $vars->{trace_count} = \%trace_count;
}

sub _page_post_duplicate_trace {
    my $cgi = Bugzilla->cgi;
    my $comment = { body      => scalar $cgi->param('comment'),
                    isprivate => scalar $cgi->param('isprivate'),
                  };
    my $trace = TraceParser::Trace->parse_from_text($comment->{body});
    my $bug = Bugzilla::Bug->check(scalar $cgi->param('bug_id'));
    _handle_dup_to($trace, $bug, $comment, 'allow closed');
}

1;
