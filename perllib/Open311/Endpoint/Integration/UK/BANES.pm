=head1 NAME

Open311::Endpoint::Integration::UK::BANES - Bath and North East Somerset integration set-up

=head1 SYNOPSIS

BANES manage their own Open311 server to receive all reports made on FMS, whether in
email categories or in those created by their Confirm integration. The Confirm
integration only receives the reports in categories in its services.

=cut

package Open311::Endpoint::Integration::UK::BANES;

use Moo;
extends 'Open311::Endpoint::Integration::Multi';

use Module::Pluggable
    search_path => ['Open311::Endpoint::Integration::UK::BANES'],
    instantiate => 'new';

has jurisdiction_id => (
    is => 'ro',
    default => 'banes',
);

=pod

BANES was previously only a Confirm backend in open311-adapter, so we
maintain its categories/IDs without any backend prefix as any updates on pre-multi
reports will be looking for the id without the prefix

=cut

has integration_without_prefix => (
    is => 'ro',
    default => 'Confirm',
);

__PACKAGE__->run_if_script;
