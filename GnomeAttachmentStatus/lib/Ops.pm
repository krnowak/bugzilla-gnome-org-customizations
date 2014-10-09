# -*- Mode: perl; indent-tabs-mode: nil -*-
#
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Extension::GnomeAttachmentStatus::Ops;
use strict;
use warnings;
use base qw(Exporter);
use Data::Dumper;
use Bugzilla::Extension::GnomeAttachmentStatus::Util;
use Bugzilla::Extension::GnomeAttachmentStatus::Field;
use Bugzilla::Extension::GnomeAttachmentStatus::Bug;
use Bugzilla::Extension::GnomeAttachmentStatus::Attachment;
use Bugzilla::Install::Util;
use Digest::SHA;
use File::Spec;

our @EXPORT = qw(
    update_choice_class_map
    add_gnome_attachment_status_table_to_schema
    check_overriden_templates
    maybe_add_status_column
    maybe_add_status_update_columns
    maybe_setup_status_validator
    maybe_fixup_final_status_param
    maybe_run_template_handler
    perform_migration
);

# This file can be loaded by your extension via
# "use Bugzilla::Extension::GnomeAttachmentStatus::Util". You can put functions
# used by your extension in here. (Make sure you also list them in
# @EXPORT.)

sub update_choice_class_map {
    my $type = 'Bugzilla::Extension::GnomeAttachmentStatus::Field';

    unless (exists (Bugzilla::Field::Choice::CLASS_MAP->{$type->FIELD_NAME()})) {
        Bugzilla::Field::Choice::CLASS_MAP->{$type->FIELD_NAME} = $type;
    }
}

sub add_gnome_attachment_status_table_to_schema
{
    my ($schema) = @_;
    my $definition = {
        FIELDS => [
            id                  => {TYPE => 'SMALLSERIAL', NOTNULL => 1,
                                    PRIMARYKEY => 1},
            value               => {TYPE => 'varchar(64)', NOTNULL => 1},
            sortkey             => {TYPE => 'INT2', NOTNULL => 1, DEFAULT => 0},
            isactive            => {TYPE => 'BOOLEAN', NOTNULL => 1,
                                    DEFAULT => 'TRUE'},
            visibility_value_id => {TYPE => 'INT2'},
            description         => {TYPE => 'MEDIUMTEXT', NOTNULL => 1}
        ],
        INDEXES => [
            gnome_attachment_status_value_idx   => {FIELDS => ['value'],
                                                    TYPE => 'UNIQUE'},
            gnome_attachment_status_sortkey_idx => ['sortkey', 'value'],
            gnome_attachment_status_visibility_value_id_idx => ['visibility_value_id'],
        ]
    };

    # Create the table unconditionally. If we are updating from old
    # setup, we will just remove the attachment_status table.
    $schema->{g_a_s()} = $definition;
}

sub _attachment_edit_handler {
    my ($file, $vars, $context) = @_;
    my $var_name = 'all_' . g_a_s() . '_values';
    my @values = Bugzilla::Field::Choice->type(fd_a_g_a_s())->get_all();

    $vars->set($var_name, \@values);
}

sub _attachment_list_handler {
    my ($file, $vars, $context) = @_;
    my $bug_id = $vars->get('bugid');

    if ($bug_id) {
        my $bug = Bugzilla::Bug->new($bug_id);
        my $show_status = $bug->show_gnome_attachment_status();

        $vars->set('show_gnome_attachment_status', $show_status);
    }
}

# This block is to make template_infos a private static variable, so
# it is initialized only once.
{
    sub _init_template_infos {
        my $infos = {
            'attachment/edit.html.tmpl' => {
                'handler' => \&_attachment_edit_handler,
                'digest' => '426ceeb820cefad35cbbf10ab053c1fc9f53fa71a63dd455418bff3221a46a0e'
            },
            'attachment/list.html.tmpl' => {
                'handler' => \&_attachment_list_handler,
                'digest' => 'b0c5edd84b8cc31666d0d0b4bf36cdb981ee322995dad891cf05f0f40b2d0392'
            }
        };

        my @extension_paths = grep {/^\.\/extensions\/GnomeAttachmentStatus\//} @{Bugzilla::Install::Util::template_include_path()};

        for my $file (sort keys (%{$infos}))
        {
            my $complete_path = undef;

            for my $path (@extension_paths)
            {
                my $potential_path = File::Spec->catfile($path, $file);

                next unless (-r $potential_path);
                $complete_path = $potential_path;
                last;
            }

            my $overriden = defined ($complete_path);

            $infos->{$file}{'overriden'} = $overriden;
            if ($overriden and not exists ($infos->{$file}{'digest'}))
            {
                # If this happens then it is programmer's error.
                die "No digest of original template file ($complete_path) available";
            }
        }
        $infos;
    }

    my $template_infos = undef;

    sub _get_template_infos
    {
        unless (defined ($template_infos))
        {
            $template_infos = _init_template_infos();
        }
        $template_infos;
    }
}

sub check_overriden_templates
{
    print "Checking overriden templates...\n";
    # template_include_path is from Bugzilla::Install::Util package.
    my @default_paths = grep {!/^\.\/extensions\//} @{Bugzilla::Install::Util::template_include_path()};
    my $infos = _get_template_infos();

    for my $file (sort keys (%{$infos}))
    {
        next unless $infos->{$file}{'overriden'};

        my $complete_path = undef;

        for my $path (@default_paths)
        {
            my $potential_path = File::Spec->catfile($path, $file);

            next unless (-r $potential_path);
            $complete_path = $potential_path;
            last;
        }
        unless ($complete_path)
        {
            print "Original template for $file not found\n";
            next;
        }

        my $sha = Digest::SHA->new(256);
        $sha->addfile($complete_path);
        my $digest = $sha->hexdigest();
        if ($digest ne $infos->{$file}{'digest'})
        {
            die "Original $file (at $complete_path) has changed " .
            'since last checksetup. Please check if the changes ' .
            'should be backported to overriden templates and ' .
            'update the digest in template_infos variable with ' .
            $digest;
        }
    }
}

sub maybe_add_status_column
{
    my ($class, $columns) = @_;

    if ($class->isa(bz_a())) {
        push (@{$columns}, g_a_s());
    }
}

# XXX: Gross hack. It would be better if we had a hook (named for
# instance 'object_cgi_update) inside attachment.cgi which provides an
# object being updated and either cgi object or cgi params.
sub _cgi_hack_update {
    my ($attachment) = @_;
    my $cgi = Bugzilla->cgi;
    my $status = $cgi->param(g_a_s());
    my $action = $cgi->param('action');

    if (defined($status) && defined($action) && $action eq 'update') {
        $attachment->set_gnome_attachment_status($status);
    }
}

sub maybe_add_status_update_columns
{
    my ($object, $columns) = @_;

    if ($object->isa(bz_a())) {
        push (@{$columns}, g_a_s());
        _cgi_hack_update($object);
    }
}

# Does the attachment status validation
sub _validate_status {
    my ($class_or_object, $value, $field) = @_;

    if ($class_or_object->isa(bz_a()) && $field eq g_a_s()) {
        if (defined ($value)) {
            my $validated_field = Bugzilla::Field::Choice->type(fd_a_g_a_s())->check($value);

            return $validated_field->name;
        } else {
            return 'none';
        }
    }

    return $value;
}

sub maybe_setup_status_validator
{
    my ($class, $validators) = @_;

    if ($class->isa(bz_a())) {
        if (exists ($validators->{g_a_s()})) {
            my $old_validator = $validators->{g_a_s()};

            $validators->{g_a_s()} = sub {
                my ($class, $value, $field) = @_;

                _validate_status($class, &{$old_validator}(@_), $field);
            };
        } else {
            $validators->{g_a_s()} = \&_validate_status;
        }
    }
}

sub maybe_fixup_final_status_param
{
    my ($class, $params) = @_;

    if ($class->isa(bz_a())) {
        # assuming that status, if exists, is already validated
        unless (defined $params->{g_a_s()} and $params->{'ispatch'}
                and Bugzilla->user->in_group('editbugs'))
        {
            $params->{g_a_s()} = 'none';
        }
    }
}

sub maybe_run_template_handler
{
    my ($file, $vars, $context) = @_;
    my $infos = _get_template_infos;

    if (exists ($infos->{$file})) {
        $infos->{$file}{'handler'}($file, $vars, $context);
    }
}

# Checks whether we have a vanilla instance.
sub _fresh {
    my $dbh = Bugzilla->dbh;
    my $column = $dbh->bz_column_info(a(), st());

    return undef if (defined $column);
    print "fresh: no status column\n";

    $column = $dbh->bz_column_info(a(), g_a_s());
    return undef if (defined $column);
    print "fresh: no gnome attachment status column\n";

    $column = $dbh->bz_column_info(a_s(), 'id');
    return undef if defined ($column);
    print "fresh: no attachment status table\n";

    $column = $dbh->bz_column_info(g_a_s(), 'id');
    # gnome attachment status table has to exist now - it was created
    # in db_schema_abstract_schema hook.
    return undef if not defined $column;
    print "fresh: gnome attachment status exists\n";

    my $value = $dbh->selectrow_arrayref('SELECT COUNT(*) FROM ' . g_a_s());
    return undef unless defined $value and $value->[0] == 0;

    print "fresh: gnome attachment status table empty\n";
    print "fresh: it is a fresh install\n";
    1;
}

sub _fill_gnome_attachment_status_table {
    my $dbh = Bugzilla->dbh;
    # gnome attachment status table is created in db_schema_abstract_schema hook
    my $insert = $dbh->prepare('INSERT INTO ' . g_a_s() . ' (value, sortkey, description) VALUES (?,?,?)') or die $dbh->errstr;
    my $sortorder = 0;
    my @pairs = (['none', 'an unreviewed patch'],
                 ['accepted-commit_now', 'The maintainer has given commit permission'],
                 ['needs-work', 'The patch needs work'],
                 ['accepted-commit_after_freeze', 'This patch is acceptable, but can\'t be committed until after the relevant freeze (string, etc.) is lifted.'],
                 ['commited', 'This patch has already been committed but the bug remains open for other reasons'],
                 ['rejected', 'The patch provides a change that is just not wanted, or the patch can\'t be fixed to be correct without rewriting.  Maintainers should always explain their reasons whenever marking a patch as rejected.'],
                 ['reviewed', 'None of the other states made sense or are quite correct, but the other comments in the bug explain the status of the patch and the patch should be considered to have been reviewed.  If the submitter doesn\'t feel the comments on the patch are clear enough, they can unset this state']);
    foreach my $pair (@pairs) {
        $sortorder += 100;
        $insert->execute($pair->[0], $sortorder, $pair->[1]) or die $dbh->errstr;
    }
}

sub _get_g_a_s_definition {
    {TYPE => 'varchar(64)',
     NOTNULL => 1};
}

sub _add_gnome_attachment_status_column {
    my $dbh = Bugzilla->dbh;

    $dbh->bz_add_column(a(), g_a_s(), _get_g_a_s_definition(), 'none');
    $dbh->bz_add_index(a(), idx(a(), g_a_s()), [g_a_s()]);
}

sub _install_gnome_attachment_status {
    my $dbh = Bugzilla->dbh;

    $dbh->bz_start_transaction;

    _fill_gnome_attachment_status_table;
    _add_gnome_attachment_status_column;

    # populate fielddefs table for attachment status
    my $field_params = {
        name => fd_a_g_a_s(),
        description => 'Attachment status',
        type => Bugzilla::Constants::FIELD_TYPE_SINGLE_SELECT
    };
    Bugzilla::Field->create($field_params);
    $dbh->bz_commit_transaction;
}

# Checks whether we are updating from old attachment status. This is
# very specific to the setup of GNOME database.
sub _updating {
    my $dbh = Bugzilla->dbh;
    my $column = $dbh->bz_column_info(a(), st());

    return undef unless (defined $column);
    print "updating: status column exists\n";

    $column = $dbh->bz_column_info(a_s(), 'id');
    return undef unless defined $column;
    print "updating: attachment status table exists\n";
    print "updating: it is an update\n";
    1;
}

# This code is very specific to the setup of GNOME database.
sub _update_gnome_attachment_status {
    # What needs to be done here:
    # 'attachments' table:
    # - create new column - 'gnome_attachment_status', copy contents
    #   of 'status' to it, remove the 'status' column and create an
    #   index for new column. We are doing it because I had problems
    #   with dropping the foreign key constraint (it wasn't dropped at
    #   all and it is still kept in bz_schema) and later both dropping
    #   an attachment_status index and renaming the 'status' column
    #   fail. Hopefully with all this, both an index and a foreign key
    #   on status column are dropped. (1)
    # - rename 'attachment_index' to 'attachments_ispatch_idx' (2)
    #
    # 'attachment_status' table:
    # - drop it in favor of 'gnome_attachment_status'. We could just
    #   rename it, but I see no sensible way of checking for existence
    #   of some table/column in db_schema_abstract_schema - schema
    #   passed to this hook is rather vanilla. Calling bz_column_info
    #   there ends with endless recursion. (3)
    #
    # 'fielddefs' table:
    # - rename 'attachments.status' to
    #   'attachments.gnome_attachments_status' (4)
    #
    # 'namedqueries' table:
    # - replace all uses of 'attachments.status' with
    #   'attachments.gnome_attachment_status' (5)

    my $dbh = Bugzilla->dbh;
    my $stmt;

    $dbh->bz_start_transaction;
    # (1)
    _add_gnome_attachment_status_column;
    $stmt = $dbh->prepare('UPDATE ' . a() . ' SET ' . g_a_s() . ' = ' . st()) or die $dbh->errstr;
    $stmt->execute or die $stmt->errstr;
    $dbh->bz_drop_fk(a(), st());
    $dbh->bz_drop_index(a(), a() . '_' . st());
    $dbh->bz_drop_column(a(), st());
    # (2)
    $dbh->bz_drop_index(a(), sa() . '_index');
    $dbh->bz_add_index(a(), idx(a(), 'ispatch'), ['ispatch']);
    # (3)
    _fill_gnome_attachment_status_table;
    $dbh->bz_drop_table(a_s);
    # (4)
    $stmt = $dbh->prepare('UPDATE fielddefs SET name = \'' . fd_a_g_a_s() . '\' WHERE name = \'' . fd_a_s() . '\'') or die $dbh->errstr;

    $stmt->execute or die $stmt->errstr;
    # (5)
    my $query_rows = $dbh->selectall_arrayref('SELECT id, query ' .
                                              'FROM namedqueries ' .
                                              'WHERE query ' .
                                              'LIKE \'%' . fd_a_s() . '%\'') or die $dbh->errstr;
    my $old_fd = fd_a_s();
    my $new_fd = fd_a_g_a_s();

    $stmt = $dbh->prepare('UPDATE namedqueries ' .
                          'SET query = ? ' .
                          'WHERE id = ?') or die $dbh->errstr;
    for my $row (@{$query_rows})
    {
        my $id = $row->[0];
        my $query = $row->[1];

        $query =~ s/\Q$old_fd\E/$new_fd/g;
        $stmt->execute($query, $id) or die $stmt->errstr;
    }
    $dbh->bz_commit_transaction;
}

sub perform_migration
{
    if (_fresh) {
        _install_gnome_attachment_status;
    } elsif (_updating) {
        _update_gnome_attachment_status;
    } else {
        print "install_update_db: we are already updated\n";
        # Do nothing, we are already updated.
    }
}

1;
