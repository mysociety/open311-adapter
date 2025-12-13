=head1 NAME

Integrations::Aurora

=head1 DESCRIPTION

This module provides an interface to the Aurora Cases API

https://cases.aurora.symology.net/swagger/index.html

=cut

package Integrations::Aurora;

use strict;
use warnings;

use Moo;

with 'Role::Config';
with 'Role::Logger';

1;
