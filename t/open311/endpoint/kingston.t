package SOAP::Result;
use Object::Tiny qw(method result);

package Integrations::Echo::Dummy;
use Path::Tiny;
use Moo;
extends 'Integrations::Echo';
sub _build_config_file { path(__FILE__)->sibling("kingston.yml")->stringify }

package Open311::Endpoint::Integration::Echo::Dummy;
use Path::Tiny;
use Moo;
extends 'Open311::Endpoint::Integration::UK::Kingston';
around BUILDARGS => sub {
    my ($orig, $class, %args) = @_;
    $args{jurisdiction_id} = 'kingston_echo';
    $args{config_file} = path(__FILE__)->sibling("kingston.yml")->stringify;
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

use_ok 'Open311::Endpoint::Integration::UK::Kingston';

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
        if (@params == 5) {
            my $client_ref = $params[1]->value;
            like $client_ref, qr/RBK-2000123|REF-123|bulky-cc|bulky-phone/;
            my $event_type_id = $params[3]->value;
            if ($event_type_id == 1636) {
                my @data = ${$params[0]->value}->value->value;
                my @payment = ${$data[0]->value}->value;
                is $payment[0]->value, 1011;
                is $payment[1]->value, 1;
                my $val = $client_ref eq 'bulky-cc' ? 2 : 1;
                @payment = ${$data[1]->value}->value;
                is $payment[0]->value, 1012;
                is $payment[1]->value, 1; # Always 1
                @payment = ${$data[2]->value}->value;
                is $payment[0]->value, 1013;
                is $payment[1]->value, $val;
                if ($client_ref eq 'bulky-cc') { # Also check items
                    is @data, 9, 'Has all six items present in the data';
                }
            } elsif ($event_type_id == 1638 && $client_ref eq 'REF-123') {
                my @data = ${$params[0]->value}->value->value;
                my @type = ${$data[0]->value}->value;
                is $type[0]->value, 1011;
                is $type[1]->value, 3;
                my @method = ${$data[1]->value}->value;
                is $method[0]->value, 1013;
                is $method[1]->value, 1;
            }
        } elsif (@params == 2) {
            is $params[0]->value, '123pay';
            my @data = ${$params[1]->value}->value->value;
            my @ref = ${$data[0]->value}->value;
            is $ref[0]->value, 57236;
            is $ref[1]->value, 'ABC';
            my @amount = ${$data[1]->value}->value;
            is $amount[0]->value, 57237;
            is $amount[1]->value, "34.56";
        } else {
            is @params, 'UNKNOWN';
        }
        return SOAP::Result->new(result => {
            EventGuid => '1234',
        });
    } elsif ($args[0]->name eq 'GetEvent') {
        return SOAP::Result->new(result => {
            Id => '123pay',
            EventTypeId => EVENT_TYPE_BULKY,
            EventStateId => 4002,
        });
    } elsif ($method eq 'GetEventType') {
        return SOAP::Result->new(result => {
            Datatypes => { ExtensibleDatatype => [
                { Id => 1008, Name => "Notes" },
                { Id => 1020, Name => "TEM - Bulky Collection",
                    ChildDatatypes => { ExtensibleDatatype => [
                        { Id => 1021, Name => "Item" },
                        { Id => 1022, Name => "Description" },
                    ] },
                },
            ] },
        });
    } elsif ($method eq 'PerformEventAction') {
        my @params = ${$args[3]->value}->value;
        is @params, 2, 'No notes';
        my $ref = ${(${$params[1]->value}->value)[2]->value}->value->value->value;
        my $actiontype_id = $params[0]->value;
        is $actiontype_id, 518;
        return SOAP::Result->new(result => { EventActionGuid => 'ABC' });
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
    'attribute[fixmystreet_id]' => 2000123,
    'attribute[Paid_Container_Type]' => 1, # Garden Bin
    'attribute[Paid_Container_Quantity]' => 1,
);

subtest "POST subscription request OK" => sub {
    my $res = $endpoint->run_test_request(@params,
        service_code => EVENT_TYPE_SUBSCRIBE,
    );
    ok $res->is_success, 'valid request'
        or diag $res->content;

    is_deeply decode_json($res->content),
        [ {
            "service_request_id" => '1234',
        } ], 'correct json returned';
};

subtest "POST subscription request with client ref provided OK" => sub {
    my $res = $endpoint->run_test_request(@params,
        service_code => EVENT_TYPE_SUBSCRIBE,
        'attribute[payment_method]' => 'csc',
        'attribute[client_reference]' => 'REF-123',
    );
    ok $res->is_success, 'valid request'
        or diag $res->content;

    is_deeply decode_json($res->content),
        [ {
            "service_request_id" => '1234',
        } ], 'correct json returned';
};

subtest "POST bulky request card payment OK" => sub {
    my $res = $endpoint->run_test_request(@params,
        service_code => EVENT_TYPE_BULKY,
        'attribute[payment_method]' => 'credit_card',
        'attribute[client_reference]' => 'bulky-cc',
        'attribute[TEM_-_Bulky_Collection_Item]' => "11::77::34::34::34::23",
        'attribute[TEM_-_Bulky_Collection_Description]' => "Vanity dressing table::Looks heavy but not too bad for 2 to move::::::::",
    );
    ok $res->is_success, 'valid request'
        or diag $res->content;

    is_deeply decode_json($res->content),
        [ {
            "service_request_id" => '1234',
        } ], 'correct json returned';
};

subtest "POST bulky request phone payment OK" => sub {
    my $res = $endpoint->run_test_request(@params,
        service_code => EVENT_TYPE_BULKY,
        'attribute[payment_method]' => 'csc',
        'attribute[client_reference]' => 'bulky-phone',
    );
    ok $res->is_success, 'valid request'
        or diag $res->content;

    is_deeply decode_json($res->content),
        [ {
            "service_request_id" => '1234',
        } ], 'correct json returned';
};

subtest "POST a successful payment" => sub {
    my $res = $endpoint->run_test_request(
        POST => '/servicerequestupdates.json',
        api_key => 'test',
        updated_datetime => '2023-09-01T19:00:00+01:00',
        service_request_id => '123pay',
        update_id => 456,
        status => 'OPEN',
        description => 'Payment confirmed, reference ABC, amount £34.56',
        first_name => 'Bob',
        last_name => 'Mould',
    );
    ok $res->is_success, 'valid request'
        or diag $res->content;

    is_deeply decode_json($res->content),
        [ {
            "update_id" => 'BLANK',
        } ], 'correct json returned';
};

subtest "POST a cancellation" => sub {
    my $res = $endpoint->run_test_request(
        POST => '/servicerequestupdates.json',
        api_key => 'test',
        updated_datetime => '2023-09-01T19:00:00+01:00',
        service_request_id => '123cancel',
        update_id => 456,
        status => 'OPEN',
        description => 'Booking cancelled by customer',
        first_name => 'Bob',
        last_name => 'Mould',
    );
    ok $res->is_success, 'valid request'
        or diag $res->content;

    is_deeply decode_json($res->content),
        [ {
            "update_id" => 'ABC',
        } ], 'correct json returned';
};

done_testing;
