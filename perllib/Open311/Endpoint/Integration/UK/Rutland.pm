package Open311::Endpoint::Integration::UK::Rutland;

use Moo;
extends 'Open311::Endpoint::Integration::Multi';

use Module::Pluggable
    search_path => ['Open311::Endpoint::Integration::UK::Rutland'],
    instantiate => 'new';

has jurisdiction_id => (
    is => 'ro',
    default => 'rutland',
);

sub service_request_content {
    '/open311/service_request_extended'
}

=pod

Rutland was previously only a Salesforce backend in open311-adapter, so we
maintain its categories/IDs without any backend prefix as any updates on pre-multi
reports will be looking for the id without the prefix

=cut

has integration_without_prefix => (
    is => 'ro',
    default => 'SalesForce',
);

__PACKAGE__->run_if_script;
