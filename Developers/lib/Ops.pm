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
# The Initial Developer of the Original Code is YOUR NAME
# Portions created by the Initial Developer are Copyright (C) 2011 the
# Initial Developer. All Rights Reserved.
#
# Contributor(s):
#   YOUR NAME <YOUR EMAIL ADDRESS>

package Bugzilla::Extension::Developers::Ops;
use strict;
use warnings;
use base qw(Exporter);
use Bugzilla;
use Bugzilla::Constants;
use Bugzilla::Group;
use Bugzilla::Product;
use Bugzilla::Extension::Developers::Util;

our @EXPORT = qw(
    migrate_gnome_developers
    maybe_create_developer
    maybe_remove_developers
    maybe_rename_developers_group
);

# This file can be loaded by your extension via
# "use Bugzilla::Extension::Developers::Util". You can put functions
# used by your extension in here. (Make sure you also list them in
# @EXPORT.)

sub _create_developer {
    my $product = shift;
    # For every product in Bugzilla, create a group named like
    # "<product_name>_developers".
    # Every developer in the product should be made a member of this group.
    my $new_group = Bugzilla::Group->create({
        name        => dev_group_name($product),
        description => dev_group_desc($product),
        isactive    => 1,
        isbuggroup  => 1,
    });
    # The "<product name>_developers" group should be set to
    # "MemberControl: Shown, OtherControl: Shown" in the product's group controls.
    #
    # The "<product name>_developers" group should also be given editcomponents
    # for the product.
    my $dbh = Bugzilla->dbh;

    $dbh->do('INSERT INTO group_control_map
              (group_id, product_id, entry, membercontrol,
               othercontrol, canedit, editcomponents)
              VALUES (?, ?, 0, ?, ?, 0, 1)',
              undef, ($new_group->id, $product->id, CONTROLMAPSHOWN,
                      CONTROLMAPSHOWN));

    # The group should be able to bless itself.
    $dbh->do('INSERT INTO group_group_map (grantor_id, member_id, grant_type)
                   VALUES (?,?,?)',
              undef, $new_group->id, $new_group->id, GROUP_BLESS);

    # The new <product_name>_developers groups should be automatically
    # made a member of the global developers group
    my $dev_group = Bugzilla::Group->new({ name => dev() });

    unless ($dev_group) {
        $dev_group = Bugzilla::Group->create({
            name        => dev(),
            description => Dev(),
            isbuggroup  => 1,
            isactive    => 1,
        });
    }
    $dbh->do('INSERT INTO group_group_map
              (member_id, grantor_id, grant_type)
              VALUES (?, ?, ?)',
             undef, ($new_group->id, $dev_group->id, GROUP_MEMBERSHIP));
    # The main "developers" group should be set to
    # "MemberControl: Shown, OtherControl: Shown" in the product's group controls.
    $dbh->do('INSERT INTO group_control_map
              (group_id, product_id, entry, membercontrol,
               othercontrol, canedit, editcomponents)
              VALUES (?, ?, 0, ?, ?, 0, 0)',
              undef, ($dev_group->id, $product->id, CONTROLMAPSHOWN,
                      CONTROLMAPSHOWN));
}

sub migrate_gnome_developers {
    my $dbh = Bugzilla->dbh;
    # Create the global developer group if it doesn't yet exist
    my $dev_group = Bugzilla::Group->new({ name => dev() });

    return 1 if $dev_group;

    # Create product specific groups:
    foreach my $product (Bugzilla::Product->get_all) {
        my $group = Bugzilla::Group->new(
            { name => dev_group_name($product) });

        unless ($group) {
            _create_developer($product);
        }
    }
}

sub maybe_create_developer {
    my ($class, $object) = @_;

    if ($class->isa(b_p())) {
        _create_developer($object);
    }
}

sub _delete_developer {
    my $product = shift;
    my $dbh = Bugzilla->dbh;
    # Delete this product's developer group and its members
    my $group = Bugzilla::Group->new({ name => dev_group_name($product) });

    if ($group) {
        $dbh->do('DELETE FROM user_group_map WHERE group_id = ?',
                  undef, $group->id);
        $dbh->do('DELETE FROM group_group_map
                  WHERE grantor_id = ? OR member_id = ?',
                  undef, ($group->id, $group->id));
        $dbh->do('DELETE FROM bug_group_map WHERE group_id = ?',
                  undef, $group->id);
        $dbh->do('DELETE FROM group_control_map WHERE group_id = ?',
                  undef, $group->id);
        $dbh->do('DELETE FROM groups WHERE id = ?',
                  undef, $group->id);
    }
}

sub maybe_remove_developers {
    my ($object) = @_;

    if ($object->isa(b_p())) {
        _delete_developer($object);
    }
}

sub _rename_developer {
    my ($product, $old_product, $changes) = @_;
    my $developer_group = new Bugzilla::Group(
        { name => dev_group_name($old_product) });
    my $new_group = new Bugzilla::Group(
        { name => dev_group_name($product) });

    if ($developer_group && !$new_group) {
        $developer_group->set_name(dev_group_name($product));
        $developer_group->set_description(dev_group_desc($product));
        $developer_group->update();
    }
}

sub maybe_rename_developers_group {
    my ($object, $old_object, $changes) = @_;

    if ($object->isa(b_p())) {
        if (defined ($changes->{'name'})) {
            _rename_developer($object, $old_object, $changes);
        }
    }
}

1;
