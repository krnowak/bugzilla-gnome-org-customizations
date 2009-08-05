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
    bug_id
    short_hash
    short_stack
    stack_hash
    trace_hash
    trace_text
    type
    quality
);

use constant DB_TABLE => 'trace';

use constant LIST_ORDER => 'bug_id';

use constant VALIDATORS => {
    stack_hash  => \&_check_hash,
    short_hash  => \&_check_hash,
    trace_hash  => \&_check_hash,
    short_stack => \&_check_short_stack,
    trace_text  => \&_check_thetext,
    type        => \&_check_type,
    quality     => \&_check_quality,
};

use constant REQUIRED_CREATE_FIELDS => qw(
    type
    trace_hash
    stack_hash
    short_hash
    trace_text
);

# This is how long a Base64 MD5 Hash is.
use constant HASH_SIZE => 22;

use constant TRACE_TYPES => ['GDB', 'Python'];

use constant IGNORE_FUNCTIONS => qw(
   __kernel_vsyscall
   raise
   abort
   ??
);

################
# Constructors #
################

# Returns a hash suitable for passing to create(), or undef if there is no
# trace in the comment.
sub parse_from_text {
    my ($class, $text, $bug_id) = @_;
    my $trace = Parse::StackTrace->parse(types => TRACE_TYPES, 
                                         text => $text);
    return undef if !$trace;

    my @all_functions;
    my $quality = 0;
    my $crash_thread = $trace->thread_with_crash || $trace->threads->[0];
    foreach my $frame (@{ $crash_thread->frames }) {
        foreach my $item (qw(args number file line code)) {
            $quality++ if defined $frame->$item && $frame->$item ne '';
        }
        my $function = $frame->function;
        if (!grep($_ eq $function, IGNORE_FUNCTIONS)) {
            push(@all_functions, $frame->function);
            $quality++;
        }
    }

    my $max_short_stack = $#all_functions > 4 ? 4 : $#all_functions;
    my @short_stack = @all_functions[0..$max_short_stack];
    my $stack_hash = md5_base64(join(',', @all_functions));
    my $short_hash = md5_base64(join(',', @short_stack));
    my $trace_text = $trace->text;
    my $trace_hash = md5_base64($trace_text);

    return {
        bug_id      => $bug_id,
        stack_hash  => $stack_hash,
        short_hash  => $short_hash,
        short_stack => join(', ', @short_stack),
        trace_hash  => $trace_hash,
        trace_text  => $trace_text,
        type        => ref($trace),
        quality     => $quality,
    };
}

sub new_from_text {
    my ($class, $text, $bug_id) = @_;
    my $parsed = Parse::StackTrace->parse(types => TRACE_TYPES,
                                          text => $text);
    return undef if !$parsed;
    my $hash = md5_base64($parsed->text);
    my $traces = $class->match({ trace_hash => $hash, bug_id => $bug_id });
    if (@$traces) {
        $traces->[0]->{stacktrace_object} = $parsed;
        return $traces->[0];
    }
    warn "No trace found on bug $bug_id with hash $hash";
    return undef;
}

###############################
####      Accessors      ######
###############################

sub full_hash   { return $_[0]->{full_hash};   }
sub short_hash  { return $_[0]->{short_hash};  }
sub short_stack { return $_[0]->{short_stack}; }
sub trace_hash  { return $_[0]->{trace_hash};  }
sub text        { return $_[0]->{trace_text};  }
sub type        { return $_[0]->{type};        }
sub quality     { return $_[0]->{quality};     }

sub stacktrace_object {
    my $self = shift;
    my $type = $self->type;
    eval("use $type; 1;") or die $@;
    $self->{stacktrace_object} ||= $type->parse({ text => $self->trace_text });
    return $self->{stacktrace_object};
}

###############################
###       Validators        ###
###############################

sub _check_hash {
    my ($self, $hash) = @_;
    $hash = trim($hash);
    ThrowCodeError('traceparser_no_hash') if !$hash;
    length($hash) == HASH_SIZE
        or ThrowCodeError('traceparser_bad_hash', { hash => $hash });
    return $hash;
}

sub _check_short_stack { return trim($_[1]) || '' }

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

sub _check_quality { return int($_[1]); }

1;
