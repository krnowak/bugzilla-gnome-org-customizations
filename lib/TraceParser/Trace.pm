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
    bug_id
    has_symbols
    id
    full_hash
    short_hash
    type
    quality
);

use constant DB_TABLE => 'trace';

use constant VALIDATORS => {
    bug_id      => \&_check_bug_id,
    has_symbols => \&Bugzilla::Object::check_boolean,
    full_hash   => \&_check_hash,
    short_hash  => \&_check_hash,
    short_stack => \&_check_short_stack,
    type        => \&_check_type,
    quality     => \&_check_quality,
};

use constant REQUIRED_CREATE_FIELDS => qw(type full_hash short_hash);

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

# Returns a hash suitable for passing to create() (without the bug_id
# argument), or undef if there is no trace in the comment.
sub parse_from_text {
    my ($class, $text) = @_;
    my $trace = Parse::StackTrace->parse(types => TRACE_TYPES, 
                                         text => $text);
    return undef if !$trace;

    my @all_functions;
    my $quality = 0;
    my $crash_thread = $trace->thread_with_crash || $trace->threads->[0];
    foreach my $frame (@{ $crash_thread->frames }) {
        foreach my $item (qw(function args number file line code)) {
            $quality++ if defined $frame->$item;
        }
        my $function = $frame->function;
        if (defined $function && !grep($_ eq $function, IGNORE_FUNCTIONS)) {
            push(@all_functions, $frame->function);
        }
    }

    my $max_short_stack = $#all_functions > 4 ? 4 : $#all_functions;
    my @short_stack = @all_functions[0..$max_short_stack];
    my $full_hash = md5_base64(join(',', @all_functions));
    my $short_hash = md5_base64(join(',', @short_stack));

    return {
        has_symbols => 0, # FIXME
        full_hash   => $full_hash,
        short_hash  => $short_hash,
        short_stack => join(', ', @short_stack),
        type        => ref($trace),
        quality     => $quality,
    };
}

###############################
####      Accessors      ######
###############################

sub has_symbols { return $_[0]->{has_symbols}; }
sub full_hash   { return $_[0]->{full_hash};   }
sub short_hash  { return $_[0]->{short_hash};  }
sub short_stack { return $_[0]->{short_stack}; }
sub type        { return $_[0]->{type};        }
sub quality     { return $_[0]->{quality};     }

sub bug {
    my $self = shift;
    $self->{bug} ||= new Bugzilla::Bug($self->{bug_id});
    return $self->{bug};
}

###############################
###       Validators        ###
###############################

sub _check_bug_id {
    my ($self, $bug_id) = @_;
    return Bugzilla::Bug->check($bug_id)->id;
}

sub _check_hash {
    my ($self, $hash) = @_;
    $hash = trim($hash);
    ThrowCodeError('traceparser_no_hash') if !$hash;
    length($hash) == HASH_SIZE
        or ThrowCodeError('traceparser_bad_hash', { hash => $hash });
    return $hash;
}

sub _check_short_stack { return trim($_[1]) || '' }

sub _check_type {
    my ($invocant, $type) = @_;
    $type = trim($type);
    if (!$type)
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
