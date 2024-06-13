package Open311::Endpoint::Integration::UK::Camden;

use Moo;
extends 'Open311::Endpoint::Integration::Multi';

use Module::Pluggable
    search_path => ['Open311::Endpoint::Integration::UK::Camden'],
    instantiate => 'new';

has jurisdiction_id => (
    is => 'ro',
    default => 'camden',
);

=pod

Camden was previously only a Symology backend in open311-adapter, so we
maintain its categories/IDs without any backend prefix as any updates on pre-multi
reports will be looking for the id without the prefix

=cut

has integration_without_prefix => (
    is => 'ro',
    default => 'Symology',
);

__PACKAGE__->run_if_script;
