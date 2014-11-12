# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Extension::TemplateOverrides::Digests;

use strict;
use warnings;
use base qw(Exporter);

our @EXPORT = qw(
    overrides_digests
);

sub overrides_digests {
    my %digests = (
        'attachment/edit.html.tmpl' => '426ceeb820cefad35cbbf10ab053c1fc9f53fa71a63dd455418bff3221a46a0e',
        'attachment/list.html.tmpl' => 'b0c5edd84b8cc31666d0d0b4bf36cdb981ee322995dad891cf05f0f40b2d0392',
        'bug/comments.html.tmpl' => 'd68e98b67eac9cd74ec7b0b663734f7a14953788864135be076a8cb03d648f09',
        'global/user.html.tmpl' => 'ca16e2a988436109612b7b249e536f49669d4c5a9161911e3c14906a5f6d041d',
        'global/choose-classification.html.tmpl' => 'da8b876b1a79fb40b5ec2e46e6706b63aa0d6ec15a6a41c80ebc1ad889e6e0d4',
        'global/choose-product.html.tmpl' => 'ab607993022411e13f6cfa51d3c6c32e9309b4c54640347e67742baee8a5e941',
        'global/common-links.html.tmpl' => 'bd97d3329db516532e773b6446da863e7d5eb141e057f1a121d1d1a4417e4f06',
    );

    %digests;
}

1;
