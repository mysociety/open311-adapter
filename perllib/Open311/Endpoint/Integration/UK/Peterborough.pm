package Open311::Endpoint::Integration::UK::Peterborough;

use Moo;
extends 'Open311::Endpoint::Integration::Multi';

use Module::Pluggable
    search_path => ['Open311::Endpoint::Integration::UK::Peterborough'],
    instantiate => 'new';

has jurisdiction_id => (
    is => 'ro',
    default => 'peterborough',
);

has integration_without_prefix => (
    is => 'ro',
    default => 'Confirm',
);

__PACKAGE__->run_if_script;
