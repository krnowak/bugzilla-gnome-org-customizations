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
# The Original Code is the Bugzilla Example Plugin.
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
use Bugzilla::Install::Util qw(indicate_progress);

use TraceParser::Trace;

use constant IGNORE_FUNCTIONS => qw(
   __kernel_vsyscall
   raise
   abort
);

my $dbh = Bugzilla->dbh;
my $has_traces = $dbh->selectrow_array('SELECT 1 FROM trace ' 
                                        . $dbh->sql_limit('1'));
if (!$has_traces) {
    print "Parsing traces from comments...\n";
    my $total = $dbh->selectrow_array('SELECT COUNT(*) FROM longdescs');

    if ($dbh->isa('Bugzilla::DB::Mysql')) {
        $dbh->{'mysql_use_result'} = 1;
    }

    $dbh->bz_start_transaction();
    my $sth = $dbh->prepare('SELECT bug_id,thetext FROM longdescs');
    $sth->execute();
    my $count = 0;
    while (my ($bug_id, $text) = $sth->fetchrow_array) {
        $count++;
        my $trace = TraceParser::Trace->parse_from_text($text);
        indicate_progress({ current => $count, total => $total, 
                            every => 100 });
        next if !$trace;
        TraceParser::Trace->create({ %$trace, bug_id => $bug_id });
    }
    $dbh->bz_commit_transaction();

    if ($dbh->isa('Bugzilla::DB::Mysql')) {
        $dbh->{'mysql_use_result'} = 0;
    }
}
