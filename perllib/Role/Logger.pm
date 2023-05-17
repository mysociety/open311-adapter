package Role::Logger;

use Moo::Role;
use Open311::Endpoint::Logger;

has logger => (
    is => 'lazy',
    default => sub {
        # Not all things using this logger have config_filename set up
        my $config = $_[0]->can('config_filename') ? $_[0]->config_filename : '';
        Open311::Endpoint::Logger->new(
            config_filename => $config,
        );
    },
);

1;
