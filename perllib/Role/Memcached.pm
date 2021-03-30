package Role::Memcached;

use Moo::Role;
use Cache::Memcached;

has memcache_namespace  => (
    is => 'lazy',
    default => sub { $_[0]->config_filename }
);

has memcache => (
    is => 'lazy',
    default => sub {
        my $self = shift;
        my $namespace = 'open311adapter:' . $self->memcache_namespace . ':';
        $namespace = "test:$namespace" if $ENV{TEST_MODE};
        new Cache::Memcached {
            'servers' => [ '127.0.0.1:11211' ],
            'namespace' => $namespace,
            'debug' => 0,
            'compress_threshold' => 10_000,
        };
    },
);

1;
