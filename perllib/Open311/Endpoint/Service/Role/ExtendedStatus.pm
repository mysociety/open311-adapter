package Open311::Endpoint::Service::Role::ExtendedStatus;
use Moo::Role;

use Types::Standard ':all';

has '+status' => (
    is => 'rw',
    isa => Enum[ 'open', 'investigating', 'in_progress', 'planned', 'action_scheduled',
        'no_further_action', 'not_councils_responsibility', 'duplicate', 'internal_referral',
        'fixed', 'closed', ],
    default => sub { 'open' },
);

1;
