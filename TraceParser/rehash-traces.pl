#!/usr/bin/perl -w

use strict;
use warnings;
use lib qw(. lib);
use Bugzilla;
BEGIN { Bugzilla->extensions(); }
use Bugzilla::Install::Util qw(indicate_progress);
use Bugzilla::Extension::TraceParser::Trace;

my $dbh = Bugzilla->dbh;

print "Re-parsing traces...\n";
my $total = $dbh->selectrow_array('SELECT COUNT(*) FROM trace');

if ($dbh->isa('Bugzilla::DB::Mysql')) {
    $dbh->{'mysql_use_result'} = 1;
}

my $sth = $dbh->prepare('SELECT id,trace_text FROM trace ORDER BY id');
$sth->execute();
my $count = 0;
my @traces;
while (my ($id, $text) = $sth->fetchrow_array) {
    $count++;
    my $trace = Bugzilla::Extension::TraceParser::Trace->parse_from_text($text);
    indicate_progress({ current => $count, total => $total, every => 10 });
    $trace->{id} = $id;
    push(@traces, $trace);
}

if ($dbh->isa('Bugzilla::DB::Mysql')) {
    $dbh->{'mysql_use_result'} = 0;
}

$dbh->bz_start_transaction();
print "Updating trace hashes...\n";
$count = 1;
foreach my $trace (@traces) {
    $dbh->do("UPDATE trace SET stack_hash = ?, short_hash = ?, quality = ?
               WHERE id = ?",
             undef, $trace->{stack_hash}, $trace->{short_hash},
             $trace->{quality}, $trace->{id});
    indicate_progress({ current => $count, total => $total, every => 10 });
}
$dbh->bz_commit_transaction();
