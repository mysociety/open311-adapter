package Open311::Endpoint::Service::Request::SalesForce;
use Moo;
use MooX::HandlesVia;
extends 'Open311::Endpoint::Service::Request';
with 'Open311::Endpoint::Service::Role::ExtendedStatus';

use DateTime;
use Types::Standard ':all';

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
