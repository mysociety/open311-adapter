package Open311::Endpoint::Integration::UK::Bexley;

use Moo;
extends 'Open311::Endpoint::Integration::Multi';

use Module::Pluggable
    search_path => ['Open311::Endpoint::Integration::UK::Bexley'],
    instantiate => 'new';

has jurisdiction_id => (
    is => 'ro',
    default => 'bexley',
);

has integration_without_prefix => (
    is => 'ro',
    default => 'Symology',
);

__PACKAGE__->run_if_script;
