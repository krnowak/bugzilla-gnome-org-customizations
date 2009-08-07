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

package TraceParser::Trace;
use strict;
use base qw(Bugzilla::Object);

use Bugzilla::Bug;
use Bugzilla::Error;
use Bugzilla::Util;
use Scalar::Util qw(blessed);

use Parse::StackTrace;
use Digest::MD5 qw(md5_base64);

###############################
####    Initialization     ####
###############################

use constant DB_COLUMNS => qw(
    id
    comment_id
    short_hash
    stack_hash
    trace_hash
    type
    quality
);

use constant DB_TABLE => 'trace';

use constant LIST_ORDER => 'quality DESC, comment_id';

use constant VALIDATORS => {
    stack_hash  => \&_check_hash,
    short_hash  => \&_check_hash,
    trace_hash  => \&_check_hash,
    trace_text  => \&_check_thetext,
    type        => \&_check_type,
};

use constant REQUIRED_CREATE_FIELDS => qw(
    comment_id
    trace_hash
    trace_text
    type
);

# This is how long a Base64 MD5 Hash is.
use constant HASH_SIZE => 22;

# How many functions we should be hashing for the short_hash.
use constant STACK_SIZE => 5;

use constant TRACE_TYPES => ['GDB', 'Python'];

use constant IGNORE_FUNCTIONS => qw(
   __kernel_vsyscall
   __libc_start_main
   raise
   abort
   poll
   ??
);

################
# Constructors #
################

# Preload the list with important stuff we'll probably need, for performance
# reasons.
sub _do_list_select {
    my $class = shift;
    my $objects = $class->SUPER::_do_list_select(@_);
    if (@$objects > 1) {
        my $dbh = Bugzilla->dbh;
        my @trace_ids = map { $_->id } @$objects;
        my %bug_ids = @{ $dbh->selectcol_arrayref(
            'SELECT trace.id, longdescs.bug_id 
               FROM trace INNER JOIN longdescs 
                          ON trace.comment_id = longdescs.comment_id
              WHERE id IN(' . join(',', @trace_ids) . ')', {Columns=>[1,2]}) };
        my %unique_ids = map { $bug_ids{$_} => 1 } (keys %bug_ids);
        my $bugs = Bugzilla::Bug->new_from_list([values %bug_ids]);

        # Populate "product" for each bug.
        my %product_ids = map { $_->{product_id} => 1 } @$bugs;
        my %products = @{ $dbh->selectcol_arrayref(
            'SELECT id, name FROM products WHERE id IN(' 
            . join(',', keys %product_ids) . ')', {Columns=>[1,2]}) };
        foreach my $bug (@$bugs) {
            $bug->{product} = $products{$bug->{product_id}};
        }

        # Pre-initialize the can_see_bug cache for these bugs.
        Bugzilla->user->visible_bugs($bugs);
        my %bug_map = map { $_->id => $_ } @$bugs;

        # And add them to each trace object.
        foreach my $trace (@$objects) {
            my $bug_id = $bug_ids{$trace->id};
            $trace->{bug} = $bug_map{$bug_id};
        }
    }
    return $objects;
}

sub stacktrace_from_text {
    my ($class, $text) = @_;
    return Parse::StackTrace->parse(types => TRACE_TYPES, text => $text);
}

# Returns a hash suitable for passing to create(), or undef if there is no
# trace in the comment.
sub parse_from_text {
    my ($class, $text) = @_;
    my $trace = $class->stacktrace_from_text($text);
    return undef if !$trace;

    my @frames = @{ $class->_important_stack_frames($trace) };

    my $quality = 0;
    foreach my $frame (@frames) {
        foreach my $item (qw(args number file line code)) {
            $quality++ if defined $frame->$item && $frame->$item ne '';
        }
    }

    my @all_functions = @{ _relevant_functions(\@frames) };
    $quality += scalar(@all_functions);

    if ($quality) {
        $quality = "$quality.0" / scalar(@frames);
    }

    my $stack_hash;
    my $short_hash;
    # We don't do similarity on traces that have fewer than 2 functions
    # in their stack.
    if (@all_functions > 1) {
        my @short_stack = @{ $class->short_stack(\@all_functions) };
        $stack_hash = _hash(join(',', @all_functions));
        $short_hash = _hash(join(',', @short_stack));
    }
    my $trace_text = $trace->text;
    my $trace_hash = _hash($trace_text);

    return {
        stack_hash  => $stack_hash,
        short_hash  => $short_hash,
        trace_hash  => $trace_hash,
        trace_text  => $trace_text,
        type        => ref($trace),
        quality     => $quality,
    };
}

sub _hash {
    my ($str) = @_;
    utf8::encode($str) if utf8::is_utf8($str);
    return md5_base64($str);
}

#################
# Class Methods #
#################

sub traces_on_bug {
    my ($class, $bug) = @_;
    my $bug_id = blessed $bug ? $bug->id : $bug;
    my $comment_ids = Bugzilla->dbh->selectcol_arrayref(
        'SELECT comment_id FROM longdescs WHERE bug_id = ?',
        undef, $bug_id);
    return $class->match({ comment_id => $comment_ids });
}

###############################
####      Accessors      ######
###############################

sub comment_id  { return $_[0]->{comment_id};  }
sub stack_hash  { return $_[0]->{stack_hash};  }
sub short_hash  { return $_[0]->{short_hash};  }
sub trace_hash  { return $_[0]->{trace_hash};  }
sub type        { return $_[0]->{type};        }
sub quality     {
    my $self = shift;
    return sprintf('%.1f', $self->{quality});
}

sub text {
    my $self = shift;
    $self->{text} ||= Bugzilla->dbh->selectrow_array(
        'SELECT trace_text FROM trace WHERE id = ?',
        undef, $self->id);
    return $self->{text};
}

sub bug {
    my $self = shift;
    return $self->{bug} if exists $self->{bug};
    my $bug_id = Bugzilla->dbh->selectrow_array(
        'SELECT bug_id FROM longdescs WHERE comment_id = ?', undef, 
        $self->comment_id);
    $self->{bug} = new Bugzilla::Bug($bug_id);
    return $self->{bug};
}

sub crash_thread {
    my ($invocant, $st) = @_;
    $st ||= $invocant->stack;
    return $st->thread_with_crash || $st->threads->[0];
}

sub identical_traces {
    my $self = shift;
    return $self->{identical_traces} if exists $self->{identical_traces};
    my $class = ref $self;
    my $identical ||= $class->match({ stack_hash => $self->stack_hash });
    @$identical = grep { $_->id != $self->id } @$identical;
    $self->{identical_traces} = $identical;
    return $self->{identical_traces};
}

sub must_dup_to {
    my $self = shift;
    my $id = $self->identical_dup_id || $self->similar_dup_id;
    return new Bugzilla::Bug($id);
}

sub _important_stack_frames {
    my ($invocant, $st) = @_;
    $st ||= $invocant->stack;

    my $crash_thread = $invocant->crash_thread($st);
    my $frames = $crash_thread->frames;

    my $crash_position;
    my $position = 0;
    foreach my $frame (@$frames) {
        if ($frame->is_crash) {
            $crash_position = $position;
            last;
        }
        $position++;
    }

    if ($crash_position) {
        # Also remove the crash frame itself (thus the + 1)
        @$frames = splice(@$frames, $crash_position + 1);
    }

    return $frames;
}

sub _relevant_functions {
    my ($frames) = @_;
    my @relevant;
    foreach my $frame (@$frames) {
        my $function = $frame->function;
        if (!grep($_ eq $function, IGNORE_FUNCTIONS)) {
            $function =~ s/^IA__//;
            push(@relevant, $function);
        }
    }
    return \@relevant;
}

sub short_stack {
    my ($invocant, $functions) = @_;
    $functions ||= _relevant_functions($invocant->_important_stack_frames);

    my @short_stack;
    my $num_functions = scalar(@$functions);
    if ($num_functions) {
        my $max_short_stack = $num_functions >= STACK_SIZE ? STACK_SIZE
                                                           : $num_functions;
        @short_stack = @$functions[0..($max_short_stack-1)];
    }
    return \@short_stack;
}

# Gets similar traces without also listing identical traces in the list.
sub similar_traces {
    my $self = shift;
    return $self->{similar_traces} if exists $self->{similar_traces};
    my $class = ref $self;
    my $similar = $class->match({ short_hash => $self->short_hash });
    my %identical = map { $_->id => 1 } @{ $self->identical_traces };
    @$similar = grep { !$identical{$_->id} and $_->id != $self->id } @$similar;
    $self->{similar_traces} = $similar;
    return $similar;
}

sub stack {
    my $self = shift;
    my $type = $self->type;
    eval("use $type; 1;") or die $@;
    $self->{stack} ||= $type->parse(text => $self->text);
    return $self->{stack};
}

###########################
# Trace Duplicate Methods #
###########################

sub identical_dup_id {
    my $self = shift;
    return $self->{identical_dup_id} if exists $self->{identical_dup_id};
    $self->{identical_dup_id} = Bugzilla->dbh->selectrow_array(
        'SELECT bug_id FROM trace_dup WHERE hash = ? AND identical = 1',
        undef, $self->stack_hash);
    return $self->{identical_dup_id};
}

sub similar_dup_id {
    my $self = shift;
    return $self->{similar_dup_id} if exists $self->{similar_dup_id};
    $self->{similar_dup_id} = Bugzilla->dbh->selectrow_array(
        'SELECT bug_id FROM trace_dup WHERE hash = ? AND identical = 0',
        undef, $self->short_hash);
    return $self->{similar_dup_id};
}

sub update_identical_dup {
    my ($self, $bug_id) = @_;
    _update_dup($self->stack_hash, 1, $bug_id);
}

sub update_similar_dup {
    my ($self, $bug_id) = @_;
    _update_dup($self->short_hash, 0, $bug_id);
}

sub _update_dup {
    my ($hash, $identical, $bug_id) = @_;
    my $dbh = Bugzilla->dbh;
    if (!$bug_id) {
        $dbh->do("DELETE FROM trace_dup WHERE hash = ? AND identical = ?",
                 undef, $hash, $identical);
        return;
    }

    my $bug = Bugzilla::Bug->check($bug_id);
    $bug_id = $bug->id; # detaint $bug_id

    my $exists = $dbh->selectrow_array(
        'SELECT 1 FROM trace_dup WHERE hash = ? AND identical = ?',
        undef, $hash, $identical);
    if ($exists) {
        $dbh->do('UPDATE trace_dup SET bug_id = ? 
                   WHERE hash = ? AND identical = ?', 
                 undef, $bug_id, $hash, $identical);
    }
    else {
        $dbh->do('INSERT INTO trace_dup (bug_id, hash, identical)
                       VALUES (?,?,?)', undef, $bug_id, $hash, $identical);
    }
}


###############################
###       Validators        ###
###############################

sub _check_hash {
    my ($self, $hash) = @_;
    $hash = trim($hash);
    return undef if !$hash;
    length($hash) == HASH_SIZE
        or ThrowCodeError('traceparser_bad_hash', { hash => $hash });
    return $hash;
}

sub _check_thetext {
    my ($invocant, $text) = @_;
    if (!$text or $text =~ /^\s+$/s) {
        my $class = ref($invocant) || $invocant;
        ThrowCodeError('param_required', { function => "${class}::create",
                                           param    => 'thetext' });
    }
    return $text;
}

sub _check_type {
    my ($invocant, $type) = @_;
    $type = trim($type);
    if (!$type) {
        my $class = ref($invocant) || $invocant;
        ThrowCodeError('param_required', { function => "${class}::create",
                                           param    => 'type' });
    }
    $type =~ /^Parse::StackTrace::Type/
      or ThrowCodeError('traceparser_bad_type', { type => $type });
    return $type;
}

1;
