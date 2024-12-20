=head1 NAME

Open311::Endpoint::Integration::UK::Bristol - Bristol integration set-up

=head1 SYNOPSIS

Bristol manage their own Open311 server, but have a managed Alloy integration, so is
set up as a Multi integration with Alloy and a Passthrough

=cut

package Open311::Endpoint::Integration::UK::Bristol;

use Moo;
extends 'Open311::Endpoint::Integration::Multi';

use Module::Pluggable
    search_path => ['Open311::Endpoint::Integration::UK::Bristol'],
    instantiate => 'new';

has jurisdiction_id => (
    is => 'ro',
    default => 'bristol',
);

has integration_without_prefix => (
    is => 'ro',
    default => 'Passthrough',
);

__PACKAGE__->run_if_script;
