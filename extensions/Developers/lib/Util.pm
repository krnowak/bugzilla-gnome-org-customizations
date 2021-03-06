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

package Bugzilla::Extension::Developers::Util;
use strict;
use warnings;
use base qw(Exporter);

our @EXPORT = qw(
    b_p
    dev
    Dev
    dev_group_name
    dev_group_desc
);

# This file can be loaded by your extension via
# "use Bugzilla::Extension::Developers::Util". You can put functions
# used by your extension in here. (Make sure you also list them in
# @EXPORT.)

sub b_p {
    'Bugzilla::Product';
}

sub dev {
    'developers'
}

sub Dev {
    'Developers'
}

sub dev_group_name {
    my ($product) = @_;

    $product->{'name'} . '_' . dev();
}

sub dev_group_desc {
    my ($product) = @_;

    $product->{'name'} . ' ' . Dev();
}

1;
