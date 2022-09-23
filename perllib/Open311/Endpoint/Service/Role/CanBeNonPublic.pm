package Open311::Endpoint::Service::Role::CanBeNonPublic;
use Moo::Role;

use Types::Standard ':all';

has 'optional_fields' => (
    is => 'ro',
    isa => ArrayRef[ Str ],
    default => sub { [ 'non_public' ] },
);

has non_public => (
    is => 'ro',
    isa => Str,
    default => 0
);

1;
