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
# The Original Code is the Bugzilla TraceParser Plugin.
#
# The Initial Developer of the Original Code is Canonical Ltd.
# Portions created by Canonical Ltd. are Copyright (C) 2009
# Canonical Ltd. All Rights Reserved.
#
# Contributor(s):
#   Max Kanat-Alexander <mkanat@bugzilla.org>

package Bugzilla::Extension::TraceParser;
use strict;
use base qw(Bugzilla::Extension);

use Bugzilla::Bug;
use Bugzilla::Constants;
use Bugzilla::Error;
use Bugzilla::Group;
use Bugzilla::Install::Util qw(indicate_progress);
use Bugzilla::User::Setting qw(add_setting);
use Bugzilla::Util qw(detaint_natural);

use Bugzilla::Extension::TraceParser::Trace;

use List::Util;
use POSIX qw(ceil);
use Scalar::Util qw(blessed);

our $VERSION = '0.1';

use constant DEFAULT_POPULAR_LIMIT => 20;

sub bug_end_of_create {
    my ($self, $args) = @_;
    
    my $bug = $args->{bug};
    my $comments = $bug->comments({ order => 'oldest_to_newest' });
    my $comment = $comments->[0];
    my $data = Bugzilla::Extension::TraceParser::Trace->parse_from_text($comment->body);
    return if !$data;
    my $trace = Bugzilla::Extension::TraceParser::Trace->create(
        { %$data, comment_id => $comment->id });
    _check_duplicate_trace($trace, $bug, $comment);    
}

sub _check_duplicate_trace {
    my ($trace, $bug, $comment) = @_;
    my $dbh = Bugzilla->dbh;
    my $template = Bugzilla->template;
    my $user = Bugzilla->user;

    if (my $dup_to = $trace->must_dup_to) {
        $dbh->bz_rollback_transaction if $dbh->bz_in_transaction;
        _handle_dup_to($trace, $dup_to, $comment);
    }

    return if Bugzilla->usage_mode != USAGE_MODE_BROWSER;
    my $cgi = Bugzilla->cgi;
    return if $cgi->param('traceparser_skip_duplicate');

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
        $template->process('traceparser/possible-duplicate.html.tmpl', \%vars)
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
    my $bug_traces = Bugzilla::Extension::TraceParser::Trace->traces_on_bug($dup_to);
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
            my $body = blessed($comment) ? $comment->body : $comment->{body};
            $dup_to->add_comment($body, \%comment_options);
            $comment_added = 1;
        }
    }

    $dup_to->update();
    if (Bugzilla->usage_mode == USAGE_MODE_BROWSER) {
        my $template = Bugzilla->template;
        my $cgi = Bugzilla->cgi;
        my $vars = {};
        $vars->{bugs} = [$dup_to];
        $vars->{bugids} = [$dup_to->id];
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

sub bug_end_of_update {
    my ($self, $args) = @_;
    
    my ($bug, $timestamp) = @$args{qw(bug timestamp)};
    return if !$bug->{added_comments};
    # Delete the cache, because we want to refresh this from the DB.
    delete $bug->{comments};
    my $comments = $bug->comments({ order => 'oldest_to_newest',
                                    after => $bug->delta_ts, to => $timestamp });

    foreach my $comment (@$comments) {
        my $data = Bugzilla::Extension::TraceParser::Trace->parse_from_text(
            $comment->body);
        next if !$data;
        Bugzilla::Extension::TraceParser::Trace->create(
            { %$data, comment_id => $comment->id });
    }    
}

sub bug_format_comment {
    my ($self, $args) = @_;

    my ($text, $bug, $regexes, $comment) = @$args{qw(text bug regexes comment)};
    return if !$comment;
    my ($trace) = @{ Bugzilla::Extension::TraceParser::Trace->match(
                         { comment_id => $comment->id }) };
    return if !$trace;

    # $$text contains the wrapped text, and $comment contains the unwrapped
    # text. To find the trace that we want from the DB, we need to use the
    # unwrapped text. But to find the text that we need to replace, we
    # need to use the wrapped text.
    my $match_text;
    if ($comment->already_wrapped) {
        $match_text = $trace->text;
    }
    else {
        my $stacktrace = Bugzilla::Extension::TraceParser::Trace->stacktrace_from_text($$text);
        $match_text = $stacktrace->text;
    }

    $match_text = quotemeta($match_text);
    my $replacement;
    my $template = Bugzilla->template_inner;
    $template->process('traceparser/format.html.tmpl', { trace => $trace },
                       \$replacement)
      || ThrowTemplateError($template->error);
    # Make sure that replacements don't contain $1, $2, etc.
    $replacement =~ s{\$}{\\\$};
    push(@$regexes, { match => qr/$match_text/s, replace => $replacement });
}

sub db_schema_abstract_schema {
    my ($self, $args) = @_;
    
    
    
    my $schema = $args->{schema};
    $schema->{trace} = {
        FIELDS => [
            id          => {TYPE => 'MEDIUMSERIAL',  NOTNULL => 1, 
                            PRIMARYKEY => 1},
            comment_id  => {TYPE => 'INT3', NOTNULL => 1, 
                            REFERENCES => {TABLE  => 'longdescs',
                                           COLUMN => 'comment_id',
                                           DELETE => 'CASCADE'}},
            type        => {TYPE => 'varchar(255)', NOTNULL => 1},
            short_hash  => {TYPE => 'char(22)'},
            stack_hash  => {TYPE => 'char(22)'},
            trace_text  => {TYPE => 'LONGTEXT', NOTNULL => 1},
            quality     => {TYPE => 'real', NOTNULL => 1},
        ],
        INDEXES => [
            trace_short_hash_idx => ['short_hash'],
            trace_stack_hash_idx => ['stack_hash'],
            trace_comment_id_idx => {TYPE => 'UNIQUE', FIELDS => ['comment_id']},
        ],
    };
    
    $schema->{trace_dup} = {
        FIELDS => [
            hash      => {TYPE => 'char(22)', NOTNULL => 1},
            identical => {TYPE => 'BOOLEAN', NOTNULL => 1, DEFAULT => 0},
            bug_id    => {TYPE => 'INT3', NOTNULL => 1, 
                          REFERENCES => {TABLE  => 'bugs',
                                         COLUMN => 'bug_id'}},
        ],
        INDEXES => [
            trace_dup_hash_idx => {TYPE => 'UNIQUE', 
                                   FIELDS => [qw(hash identical)]},
            trace_bug_id_idx   => ['bug_id'],
        ],
    };
}

sub install_before_final_checks {
    my ($self, $args) = @_;
    
    if (!new Bugzilla::Group({ name => 'traceparser_edit' })) {
        Bugzilla::Group->create({
            name        => 'traceparser_edit',
            description => 'Can edit properties of traces',
            isbuggroup  => 0 });
    }
    
    add_setting('traceparser_show_traces',
                ['on', 'off'], 'off');
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
        my $trace = Bugzilla::Extension::TraceParser::Trace->parse_from_text($text);
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
        Bugzilla::Extension::TraceParser::Trace->create($trace);
        indicate_progress({ current => $count++, total => $total_traces,
                            every => 100 });
    }
    $dbh->bz_commit_transaction();
}

sub page_before_template {
    my ($self, $args) = @_;
    
    my ($vars, $page) = @$args{qw(vars page_id)};
    if ($page =~ m{^traceparser/trace\.}) {
        _page_trace($vars);
    }
    elsif ($page =~ m{^traceparser/popular-traces\.}) {
        _page_popular_traces($vars);
    }
    elsif ($page =~ m{^traceparser/post-duplicate-trace\.}) {
        _page_post_duplicate_trace($vars);
    }
}

sub _page_trace {
    my $vars = shift;
    my $cgi = Bugzilla->cgi;
    my $dbh = Bugzilla->dbh;
    my $user = Bugzilla->user;

    my $trace_id = $cgi->param('trace_id');
    my $trace = Bugzilla::Extension::TraceParser::Trace->check({ id => $trace_id });
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
 
    my $traces = Bugzilla::Extension::TraceParser::Trace->new_from_list([keys %trace_count]);
    @$traces = reverse sort { $trace_count{$a->id} <=> $trace_count{$b->id} } 
                            @$traces;
    $vars->{limit} = $limit;
    $vars->{traces} = $traces;
    $vars->{trace_count} = \%trace_count;
}

sub _page_post_duplicate_trace {
    my $cgi = Bugzilla->cgi;
    my $comment = { body      => scalar $cgi->param('comment'),
                    isprivate => scalar $cgi->param('isprivate'),
                  };
    my $trace = Bugzilla::Extension::TraceParser::Trace->parse_from_text($comment->{body});
    my $bug = Bugzilla::Bug->check(scalar $cgi->param('bug_id'));
    _handle_dup_to($trace, $bug, $comment, 'allow closed');
}

1;

__PACKAGE__->NAME;
