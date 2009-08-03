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
# The Original Code is the Bugzilla Traceparser Plugin.
#
# The Initial Developer of the Original Code is Canonical Ltd.
# Portions created by Canonical Ltd. are Copyright (C) 2009
# Canonical Ltd. All Rights Reserved.
#
# Contributor(s):
#   Max Kanat-Alexander <mkanat@bugzilla.org>


use strict;
use warnings;
use Bugzilla;

my $schema = Bugzilla->hook_args->{schema};
$schema->{trace} = {
    FIELDS => [
        id          => {TYPE => 'MEDIUMSERIAL',  NOTNULL => 1, 
                        PRIMARYKEY => 1},
        bug_id      => {TYPE => 'INT3', NOTNULL => 1, 
                        REFERENCES => {TABLE  => 'bugs',
                                       COLUMN => 'bug_id',
                                       DELETE => 'CASCADE'}},
        type        => {TYPE => 'varchar(255)', NOTNULL => 1},
        short_stack => {TYPE => 'MEDIUMTEXT', NOTNULL => 1},
        short_hash  => {TYPE => 'char(22)', NOTNULL => 1},
        stack_hash  => {TYPE => 'char(22)', NOTNULL => 1},
        trace_hash  => {TYPE => 'char(22)', NOTNULL => 1},
        trace_text  => {TYPE => 'LONGTEXT', NOTNULL => 1},
        quality     => {TYPE => 'INT3', NOTNULL => 1},
    ],
    INDEXES => [
        trace_short_hash_idx => ['short_hash'],
        trace_stack_hash_idx => ['stack_hash'],
        trace_bug_id_idx => ['bug_id'],
    ],
};
