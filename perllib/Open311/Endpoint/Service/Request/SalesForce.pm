package Open311::Endpoint::Service::Request::SalesForce;
use Moo;
use MooX::HandlesVia;
extends 'Open311::Endpoint::Service::Request';

use DateTime;
use Types::Standard ':all';

has status => (
    is => 'rw',
    isa => Enum[ 'open', 'investigating', 'in_progress', 'planned', 'action_scheduled',
        'no_further_action', 'not_councils_responsibility', 'duplicate', 'internal_referral',
        'fixed', 'closed', ],
    default => sub { 'open' },
);

has title => (
    is => 'ro',
    isa => Maybe[Str],
);

has optional_fields => (
    is => 'ro',
    isa => ArrayRef[ Str ],
    default => sub { ['title'] },
);


1;
