package Open311::Endpoint::Service::Request::Confirm;
use Moo;
extends 'Open311::Endpoint::Service::Request::ExtendedStatus';
with 'Open311::Endpoint::Service::Role::CanBeNonPublic';

use Types::Standard ':all';

has '+optional_fields' => (
    default => sub { [ 'non_public', 'contact_name', 'contact_email' ] },
);

has contact_name => (
    is => 'ro',
    isa => Str,
);

has contact_email => (
    is => 'ro',
    isa => Str,
);

1;
