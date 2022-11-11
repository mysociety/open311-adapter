package Open311::Endpoint::Integration::UK::Brent::Symology;

use Moo;
extends 'Open311::Endpoint::Integration::Symology';

has jurisdiction_id => (
    is => 'ro',
    default => 'brent_symology',
);

sub event_action_event_type {
    my ($self, $args) = @_;
    return '';
}

# Fetching updates will not currently work due to missing functions/setup

1;
