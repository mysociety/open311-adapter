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

use constant EVENT_TYPE_MISSED => 'missed';
use constant EVENT_TYPE_SUBSCRIBE => 1638;

my $soap_lite = Test::MockModule->new('SOAP::Lite');
$soap_lite->mock(call => sub {
    # This is called when a test below makes a SOAP call, along with the data
    # to be passed via SOAP to the server. We check the values here, then pass
    # back a mocked result.
    my ($cls, @args) = @_;
    my $method = $args[0]->name;
    if ($method eq 'PostEvent') {
        my @params = ${$args[3]->value}->value;
        my $client_ref = $params[1]->value;
        my $event_type = $params[3]->value;
        my $service_id = $params[4]->value;
        like $client_ref, qr/LBS-200012[345]/;
        if ($client_ref eq 'LBS-2000124') {
            is $event_type, 1566;
            is $service_id, 405;
            my @data = ${$params[0]->value}->value->value;
            my @bin = ${$data[0]->value}->value;
            is $bin[0]->value, 2000;
            is $bin[1]->value, 1;
            my @type = ${$data[1]->value}->value;
            is $type[0]->value, 1009;
            is $type[1]->value, 2;
        } elsif ($client_ref eq 'LBS-2000125') {
            is $event_type, 1568;
            is $service_id, 408;
            my @data = ${$params[0]->value}->value->value;
            my @paper = ${$data[0]->value}->value;
            is $paper[0]->value, 2002;
            is $paper[1]->value, 1;
            my @type = ${$data[1]->value}->value;
            is $type[0]->value, 1009;
            is $type[1]->value, 1;
        }
        return SOAP::Result->new(result => {
            EventGuid => '1234',
        });
    } elsif ($method eq 'GetEventType') {
        return SOAP::Result->new(result => {
            Datatypes => { ExtensibleDatatype => [
                { Id => 1004, Name => "Container Stuff",
                    ChildDatatypes => { ExtensibleDatatype => [
                        { Id => 1005, Name => "Quantity" },
                        { Id => 1007, Name => "Containers" },
                    ] },
                },
                { Id => 1008, Name => "Notes" },
                { Id => 2000, Name => "Refuse Bin" },
                { Id => 2001, Name => "Container Mix" },
                { Id => 2002, Name => "Paper" },
                { Id => 1009, Name => "Payment Type" },
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
    description => "This is the details",
    lat => 51,
    long => -1,
    'attribute[uprn]' => 1000001,
);

subtest "POST subscription request OK" => sub {
    my $res = $endpoint->run_test_request(@params,
        service_code => EVENT_TYPE_SUBSCRIBE,
        'attribute[fixmystreet_id]' => 2000123,
        'attribute[Subscription_Details_Containers]' => 26, # Garden Bin
        'attribute[Subscription_Details_Quantity]' => 1,
        'attribute[Request_Type]' => 1,
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
        'attribute[service_id]' => 2238,
        'attribute[LastPayMethod]' => 3,
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
        'attribute[service_id]' => 2240,
        'attribute[LastPayMethod]' => 2,
    );
    ok $res->is_success, 'valid request'
        or diag $res->content;

    is_deeply decode_json($res->content),
        [ {
            "service_request_id" => '1234',
        } ], 'correct json returned';
};

done_testing;
