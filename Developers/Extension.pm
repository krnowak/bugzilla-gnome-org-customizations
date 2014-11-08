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
# The Original Code is the Developers Bugzilla Extension.
#
# The Initial Developer of the Original Code is Olav Vitters
# Portions created by the Initial Developer are Copyright (C) 2011 the
# Initial Developer. All Rights Reserved.
#
# Contributor(s):
#   Olav Vitters <olav@vitters.nl>

package Bugzilla::Extension::Developers;
use strict;
use base qw(Bugzilla::Extension);

# This code for this is in ./extensions/Developers/lib/Util.pm
use Bugzilla::Extension::Developers::Ops;
use Bugzilla::Extension::Developers::Product;
use Bugzilla::Extension::Developers::User;

our $VERSION = '0.01';

# See the documentation of Bugzilla::Hook ("perldoc Bugzilla::Hook"
# in the bugzilla directory) for a list of all available hooks.
sub install_update_db {
    my ($self, $args) = @_;

    migrate_gnome_developers();
}

sub object_end_of_create {
    my ($self, $args) = @_;
    my $class = $args->{'class'};
    my $object = $args->{'object'};

    maybe_create_developer($class, $object);
}

sub object_before_delete {
    my ($self, $args) = @_;
    my $object = $args->{'object'};

    maybe_remove_developers($object);
}

sub object_end_of_update {
    my ($self, $args) = @_;
    my $object = $args->{'object'};
    my $old_object = $args->{'old_object'};
    my $changes = $args->{'changes'};

    maybe_rename_developers_group($object, $old_object, $changes);
}

__PACKAGE__->NAME;
