package Open311::Endpoint::Service::Request::Update::mySociety;

use Moo;
use Types::Standard ':all';

extends 'Open311::Endpoint::Service::Request::Update';

has status => (
    is => 'ro',
    isa => Enum[
        'open',
        'closed',
        'fixed',
        'in_progress',
        'action_scheduled',
        'investigating',
        'duplicate',
        'not_councils_responsibility',
        'no_further_action',
        'internal_referral',
    ],
);

has external_status_code => (
    is => 'ro',
    isa => Maybe[Str],
);

has customer_reference => (
    is => 'ro',
    isa => Maybe[Str],
);


1;
