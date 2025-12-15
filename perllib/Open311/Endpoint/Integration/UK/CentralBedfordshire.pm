package Open311::Endpoint::Integration::UK::CentralBedfordshire;

use Moo;
extends 'Open311::Endpoint::Integration::Multi';

use Module::Pluggable
    search_path => ['Open311::Endpoint::Integration::UK::CentralBedfordshire'],
    instantiate => 'new';

has jurisdiction_id => (
    is => 'ro',
    # Using 'centralbedfordshire_symology' to be consistent with jurisdiction
    # before becoming a multi integration.
    # Will want to migrate to just 'centralbedfordshire' at some point.
    default => 'centralbedfordshire_symology',
);

has integration_without_prefix => (
    is => 'ro',
    default => 'Aurora',
);

__PACKAGE__->run_if_script;
