# -*- Mode: perl; indent-tabs-mode: nil -*-
#
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Extension::GnomeAttachmentStatus;
use strict;
use warnings;
use base qw(Bugzilla::Extension);

# The code for this is in ./extensions/GnomeAttachmentStatus/lib/*.pm
use Bugzilla::Extension::GnomeAttachmentStatus::Ops;

use List::MoreUtils qw(any);

our $VERSION = '0.01';

sub new {
    my ($class) = @_;

    update_choice_class_map();
    return $class->SUPER::new();
}

# See the documentation of Bugzilla::Hook ("perldoc Bugzilla::Hook"
# in the bugzilla directory) for a list of all available hooks.

# Add 'gnome_attachment_status' table with almost the same schema as
# 'resolution' - 'resolution' has typical selectable field-like
# schema. One addition is a description column.
#
# It would be better to have a hook for adding more enum initial
# values instead (see Bugzilla::DB::bz_populate_enum_tables).
#
# Also check if overriden templates didn't change since last
# time. This check is for us to maybe backport the changes to our
# overrides.
sub db_schema_abstract_schema {
    my ($self, $args) = @_;
    my $schema = $args->{'schema'};

    add_gnome_attachment_status_table_to_schema($schema);
    check_overriden_templates;
}

sub object_columns {
    my ($self, $args) = @_;
    my $class = $args->{'class'};
    my $columns = $args->{'columns'};

    maybe_add_status_column($class, $columns);
}

sub object_update_columns {
    my ($self, $args) = @_;
    my $object = $args->{'object'};
    my $columns = $args->{'columns'};

    maybe_add_status_update_columns($object, $columns);
}

sub object_validators {
    my ($self, $args) = @_;
    my $class = $args->{'class'};
    my $validators = $args->{'validators'};

    maybe_setup_status_validator($class, $validators);
}

sub object_end_of_create_validators {
    my ($self, $args) = @_;
    my $class = $args->{'class'};
    my $params = $args->{'params'};

    maybe_fixup_final_status_param($class, $params);
}

sub template_before_process {
    my ($self, $args) = @_;
    my $file = $args->{'file'};
    my $vars = $args->{'vars'};
    my $context = $args->{'context'};

    maybe_run_template_handler ($file, $vars, $context);
}

# Either rename already existing 'status' column to
# 'gnome_attachment_status' or create it. This should be a part of
# install_update_db, but this hook is a PITA when dealing with columns
# that have foreign key constraints. In our case, we wanted to remove
# a foreign key constraint from status column, but it is not really
# removed from schema, so on next run of checksetup it would be
# recreated. To remove it for good, we need to remove the status
# column. To do that, we need to remove the foreign key constraint
# anyway first, but it is not removed, because when install_update_db
# hook is run, foreign keys are not yet set up, so bz_drop_fk does
# nothing, but foreign key already exists in database. Without foreign
# key removed, we are getting errors when dropping a column.
#
# In short: argh!
sub install_before_final_checks
{
    perform_migration
}

sub enabled {
    1;
}

__PACKAGE__->NAME;
