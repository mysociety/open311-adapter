package Open311::Endpoint::Integration::UK::Dummy;
use Moo;
extends 'Open311::Endpoint::Integration::Multi';
use Module::Pluggable
    search_path => ['Open311::Endpoint::Integration::UK::Dummy'],
    instantiate => 'new';

package Open311::Endpoint::Integration::UK::Dummy::SubA;
use Moo;
extends 'Open311::Endpoint';
sub services {
    die "Fail!";
}

package Open311::Endpoint::Integration::UK::Dummy::SubB;
use Moo;
extends 'Open311::Endpoint';
sub services {
    my $service = Open311::Endpoint::Service->new(
        service_name => 'test',
        service_code => 'test',
        description => 'test',
    );
    return ($service);
}

package main;

use strict;
use warnings;
use Test::More;
use Test::Exception;

use_ok('Open311::Endpoint::Integration::UK::Dummy');

my $e = Open311::Endpoint::Integration::UK::Dummy->new;

dies_ok { $e->services } 'Calling multi services when one fails, dies';

done_testing;
