package SOAP::Result;
use Object::Tiny qw(method result);

package Integrations::Echo::Dummy;
use Path::Tiny;
use Moo;
extends 'Integrations::Echo';
sub _build_config_file { path(__FILE__)->sibling("sutton.yml")->stringify }

package Open311::Endpoint::Integration::Echo::Dummy;
use Path::Tiny;
use Moo;
extends 'Open311::Endpoint::Integration::UK::Sutton';
around BUILDARGS => sub {
    my ($orig, $class, %args) = @_;
    $args{jurisdiction_id} = 'echo_dummy';
    $args{config_file} = path(__FILE__)->sibling("sutton.yml")->stringify;
    return $class->$orig(%args);
};
has integration_class => (is => 'ro', default => 'Integrations::Echo::Dummy');

package main;

use strict;
use warnings;
use utf8;

BEGIN { $ENV{TEST_MODE} = 1; }

use Test::More;
use Test::MockModule;
use SOAP::Lite;
use JSON::MaybeXS;

use_ok 'Open311::Endpoint::Integration::UK::Sutton';

use constant EVENT_TYPE_MISSED => '3145';
use constant EVENT_TYPE_SUBSCRIBE => 3159;
use constant EVENT_TYPE_BULKY => 3130;

my $soap_lite = Test::MockModule->new('SOAP::Lite');
$soap_lite->mock(call => sub {
    # This is called when a test below makes a SOAP call, along with the data
    # to be passed via SOAP to the server. We check the values here, then pass
    # back a mocked result.
    my ($cls, @args) = @_;
    my $method = $args[0]->name;
    if ($method eq 'PostEvent') {
        my @params = ${$args[3]->value}->value;
        my $offset = 0;
        my $guid;
        if ($params[0]->name eq 'Guid') {
            $offset = 1;
            $guid = $params[0]->value;
        }
        my $client_ref = $params[1+$offset]->value;
        my $event_type = $params[3+$offset]->value;
        my $service_id = $params[4+$offset]->value;
        like $client_ref, qr/LBS-200012[3-6]/;
        if ($client_ref eq 'LBS-2000124') {
            is $event_type, 3145;
            is $service_id, 940;
            my @data = ${$params[$offset]->value}->value->value;
            is scalar @data, 0;
        } elsif ($client_ref eq 'LBS-2000125') {
            is $event_type, 3145;
            is $service_id, 944;
            is $guid, 'd5f79551-3dc4-11ee-ab68-f0c87781f93b';
            my @reservations = ${$params[5+$offset]->value}->value->value;
            is $reservations[0]->name, 'string';
            is $reservations[0]->value, 'reservation1==';
            is $reservations[1]->name, 'string';
            is $reservations[1]->value, 'reservation2==';
            my @data = ${$params[$offset]->value}->value->value;
            is scalar @data, 0;
        } elsif ($client_ref eq 'LBS-2000123') {
            is $event_type, EVENT_TYPE_SUBSCRIBE;
            is $service_id, 979;
            my @data = ${$params[$offset]->value}->value->value;
            is scalar @data, 1;
            my @renewal = ${$data[0]->value}->value;
            is $renewal[0]->value, 57764;
            is $renewal[1]->value, 1;
        } elsif ($client_ref eq 'LBS-2000126') {
            is $event_type, EVENT_TYPE_BULKY;
            is $service_id, 986;
            my @data = ${$params[$offset]->value}->value->value;
            is scalar @data, 0;
        }
        return SOAP::Result->new(result => {
            EventGuid => '1234',
        });
    } elsif ($method eq 'GetEventType') {
        return SOAP::Result->new(result => {
            Datatypes => { ExtensibleDatatype => [
                { Id => 1008, Name => "Notes" },
                { Id => 57764, Name => "Renewal" },
            ] },
        });
    } else {
        is $method, 'UNKNOWN';
    }
});

use Open311::Endpoint::Integration::Echo::Dummy;
my $endpoint = Open311::Endpoint::Integration::Echo::Dummy->new;

my @params = (
    POST => '/requests.json',
    api_key => 'test',
    first_name => 'Bob',
    last_name => 'Mould',
    lat => 51,
    long => -1,
    'attribute[uprn]' => 1000001,
);

subtest "POST subscription request OK" => sub {
    my $res = $endpoint->run_test_request(@params,
        service_code => EVENT_TYPE_SUBSCRIBE,
        'attribute[fixmystreet_id]' => 2000123,
        'attribute[Paid_Container_Type]' => 1, # Garden Bin
        'attribute[Paid_Container_Quantity]' => 1,
        description => "title: Garden Subscription - Renew\n\ndetail: ...",
    );
    ok $res->is_success, 'valid request'
        or diag $res->content;

    is_deeply decode_json($res->content),
        [ {
            "service_request_id" => '1234',
        } ], 'correct json returned';
};

subtest "POST missed bin OK" => sub {
    my $res = $endpoint->run_test_request(@params,
        service_code => EVENT_TYPE_MISSED,
        'attribute[fixmystreet_id]' => 2000124,
        'attribute[service_id]' => 940,
    );
    ok $res->is_success, 'valid request'
        or diag $res->content;

    is_deeply decode_json($res->content),
        [ {
            "service_request_id" => '1234',
        } ], 'correct json returned';
};

subtest "POST missed mixed+paper OK" => sub {
    my $res = $endpoint->run_test_request(@params,
        service_code => EVENT_TYPE_MISSED,
        'attribute[fixmystreet_id]' => 2000125,
        'attribute[service_id]' => 944,
        'attribute[GUID]' => 'd5f79551-3dc4-11ee-ab68-f0c87781f93b',
        'attribute[reservation]' => 'reservation1==::reservation2==',
    );
    ok $res->is_success, 'valid request'
        or diag $res->content;

    is_deeply decode_json($res->content),
        [ {
            "service_request_id" => '1234',
        } ], 'correct json returned';
};

subtest "POST bulky collection OK" => sub {
    my $res = $endpoint->run_test_request(@params,
        service_code => EVENT_TYPE_BULKY,
        'attribute[fixmystreet_id]' => 2000126,
    );
    ok $res->is_success, 'valid request'
        or diag $res->content;

    is_deeply decode_json($res->content),
        [ {
            "service_request_id" => '1234',
        } ], 'correct json returned';
};

done_testing;
