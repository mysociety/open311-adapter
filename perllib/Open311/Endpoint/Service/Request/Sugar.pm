package Open311::Endpoint::Service::Request::Sugar;
use Moo;
extends 'Open311::Endpoint::Service::Request::ExtendedStatus';

use Types::Standard ':all';

has '+optional_fields' => (
    default => sub { [ 'title' ] },
);

has title => (
    is => 'ro',
    isa => Maybe[Str],
);

1;
