package Role::Logger;

use Moo::Role;
use Open311::Endpoint::Logger;

has logger => (
    is => 'lazy',
    default => sub { Open311::Endpoint::Logger->new },
);

1;
