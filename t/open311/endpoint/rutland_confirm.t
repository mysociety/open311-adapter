package Integrations::Confirm::Rutland::Dummy;
use Path::Tiny;
use Moo;
extends 'Integrations::Confirm';
sub _build_config_file { path(__FILE__)->sibling("rutland_confirm.yml")->stringify }

package Open311::Endpoint::Integration::UK::Rutland::Confirm::Dummy;
use Path::Tiny;
use Moo;
extends 'Open311::Endpoint::Integration::UK::Rutland::Confirm';
around BUILDARGS => sub {
    my ($orig, $class, %args) = @_;
    $args{jurisdiction_id} = 'rutland_confirm';
    $args{config_file} = path(__FILE__)->sibling("rutland_confirm.yml")->stringify;
    return $class->$orig(%args);
};
has integration_class => (is => 'ro', default => 'Integrations::Confirm::Rutland::Dummy');

package main;

use strict;
use warnings;

use Test::More;

BEGIN { $ENV{TEST_MODE} = 1; }

my $endpoint = Open311::Endpoint::Integration::UK::Rutland::Confirm::Dummy->new;

subtest "Only uses the photo with the correct classification tag" => sub {
    my @photos = (
        {
            URL => '1',
            Name => '1.jpg',
            Date => DateTime->now->subtract(days => 1),
            ClassificationCode => 'DT10',
        },
        {
            URL => '2',
            Name => '2.jpg',
            Date => DateTime->now->subtract(days => 2),
            ClassificationCode => 'DT20',
        },
        {
            URL => '3',
            Name => '3.jpg',
            Date => DateTime->now->subtract(days => 3),
        },
    );
    my @filtered = $endpoint->filter_photos_graphql(@photos);

    is @filtered, 1;
    is $filtered[0]->{URL}, 2;
};

done_testing;

