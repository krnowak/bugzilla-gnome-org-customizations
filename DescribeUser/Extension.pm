package Bugzilla::Extension::DescribeUser;
use strict;
use warnings;
use base qw(Bugzilla::Extension);

use Bugzilla::Extension::DescribeUser::Util qw(page);

our $VERSION = '0.01';

sub page_before_template {
    my ($self, $args) = @_;

    page($args);
}

sub config_modify_panels {
    my ($self, $args) = @_;
    my $panels = $args->{'panels'};
    # Point default of mybugstemplate towards this extension
    my $query_params = $panels->{'query'}->{'params'};
    my ($mybugstemplate) = grep {$_->{'name'} eq 'mybugstemplate'} @{$query_params};

    $mybugstemplate->{'default'} = 'page.cgi?id=describeuser.html&login=%userid%';
}

__PACKAGE__->NAME;
