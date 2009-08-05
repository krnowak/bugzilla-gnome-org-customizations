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
    trace_text
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

    my $crash_thread = $trace->thread_with_crash || $trace->threads->[0];
    my @frames = @{ $crash_thread->frames };
    my ($has_crash) = grep { $_->is_crash } @frames;

    my @all_functions;
    my $quality = 0;
    my $counting_functions = 0;
    foreach my $frame (@frames) {
        if (!$has_crash or $frame->number > $has_crash->number) {
            $counting_functions++;
        }
        next if !$counting_functions;

        foreach my $item (qw(args number file line code)) {
            $quality++ if defined $frame->$item && $frame->$item ne '';
        }

        my $function = $frame->function;
        if (!grep($_ eq $function, IGNORE_FUNCTIONS)) {
            $function =~ s/^IA__//;
            push(@all_functions, $function);
            $quality++;
        }
    }

    if ($quality) {
        $quality = "$quality.0" / scalar(@frames);
    }

    my $stack_hash;
    my $short_hash;
    # We don't do similarity on traces that have fewer than 2 functions
    # in their stack.
    if (@all_functions > 1) {
        my $max_short_stack = $#all_functions >= STACK_SIZE ? STACK_SIZE 
                              : $#all_functions;
        my @short_stack = @all_functions[0..($max_short_stack-1)];
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
    my $str = shift;
    utf8::encode($str) if utf8::is_utf8($str);
    return md5_base64($str);
}

###############################
####      Accessors      ######
###############################

sub comment_id  { return $_[0]->{comment_id};  }
sub stack_hash  { return $_[0]->{stack_hash};  }
sub short_hash  { return $_[0]->{short_hash};  }
sub trace_hash  { return $_[0]->{trace_hash};  }
sub text        { return $_[0]->{trace_text};  }
sub type        { return $_[0]->{type};        }
sub quality     {
    my $self = shift;
    return sprintf('%.1f', $self->{quality});
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

sub stack {
    my $self = shift;
    my $type = $self->type;
    eval("use $type; 1;") or die $@;
    $self->{stack} ||= $type->parse(text => $self->text);
    return $self->{stack};
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
