package Integrations::Aurora::Dummy;
use Path::Tiny;
use Moo;
extends 'Integrations::Aurora';
sub _build_config_file { path(__FILE__)->sibling("aurora.yml")->stringify }

package Open311::Endpoint::Integration::UK::Dummy;
use Path::Tiny;
use Moo;
extends 'Open311::Endpoint::Integration::Aurora';

around BUILDARGS => sub {
    my ($orig, $class, %args) = @_;
    $args{jurisdiction_id} = 'dummy';
    $args{config_file} = path(__FILE__)->sibling("aurora.yml")->stringify;
    return $class->$orig(%args);
};

has integration_class => (is => 'ro', default => 'Integrations::Aurora::Dummy');

package main;

use strict;
use warnings;

use Test::More;
use Test::LongString;

my $endpoint = Open311::Endpoint::Integration::UK::Dummy->new;

BEGIN { $ENV{TEST_MODE} = 1; }

subtest "services" => sub {
    my $res = $endpoint->run_test_request(
        GET => '/services.json',
    );
    contains_string $res->content, "unimplemented";
};

subtest "post_service_request" => sub {
    my $res = $endpoint->run_test_request(
        POST => '/requests.json',
        api_key => 'api_key',
        service_code => 'potholes',
        lat => 0,
        long => 0,
        address_id => 'id',
        'attribute[easting]' => 0,
        'attribute[northing]' => 0,
        'attribute[fixmystreet_id]' => 0,
    );
    contains_string $res->content, "unimplemented";
};

subtest "post_service_request_update" => sub {
    my $res = $endpoint->run_test_request(
        POST => '/servicerequestupdates.json',
        api_key => 'api_key',
        description => 'description',
        service_request_id => 'service_request_id',
        status => 'CLOSED',
        update_id => 'update_id',
        updated_datetime => '2025-11-05T23:00:00+00:00',
    );
    contains_string $res->content, "unimplemented";
};

subtest "get_service_request_updates" => sub {
    my $res = $endpoint->run_test_request(
        GET => '/servicerequestupdates.json',
    );
    contains_string $res->content, "unimplemented";
};

done_testing;
