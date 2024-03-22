package SOAP::Result;
use Object::Tiny qw(method result);

package Integrations::Echo::Dummy;
use Path::Tiny;
use Moo;
extends 'Integrations::Echo';
sub _build_config_file { path(__FILE__)->sibling("echo.yml")->stringify }

package Open311::Endpoint::Integration::UK::Bromley::Dummy;
use Path::Tiny;
use Moo;
extends 'Open311::Endpoint::Integration::UK::Bromley::Echo';
around BUILDARGS => sub {
    my ($orig, $class, %args) = @_;
    $args{jurisdiction_id} = 'bromley_dummy';
    $args{config_file} = path(__FILE__)->sibling("echo.yml")->stringify;
    return $class->$orig(%args);
};
has integration_class => (is => 'ro', default => 'Integrations::Echo::Dummy');

package main;

use strict;
use warnings;

BEGIN { $ENV{TEST_MODE} = 1; }

use DateTime;
use Test::More;
use Test::MockModule;
use JSON::MaybeXS;

use constant EVENT_TYPE_ASSISTED => 2149;

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
        is $client_ref, 'FMS-2000123';

        my $event_type = $params[3]->value;
        my $service_id = $params[4]->value;
        is $service_id, 531, 'Service ID correct';

        # Check the UPRN has been included
        my @event_object = ${${$params[2]->value}->value->value}->value;
        is $event_object[0]->value, 'Source';
        my @object_ref = ${$event_object[1]->value}->value;
        is $object_ref[0]->value, 'Uprn';
        is $object_ref[1]->value, 'PointAddress';
        my $uprn = ${$object_ref[2]->value}->value->value->value->value;

        my $date = DateTime->today(time_zone => "Europe/London");

        my @data = ${$params[0]->value}->value->value;
        is $uprn, 1000001;
        if (@data == 8) {
            is @data, 8, 'Various supplied data';
            my @action = ${$data[0]->value}->value;
            is $action[0]->value, 1001;
            is $action[1]->value, 1;
            my @start = ${$data[1]->value}->value;
            is $start[0]->value, 1002;
            is $start[1]->value, $date->strftime("%d/%m/%Y");
            my @end = ${$data[2]->value}->value;
            is $end[0]->value, 1003;
            is $end[1]->value, '01/01/2050';
            my @review = ${$data[3]->value}->value;
            is $review[0]->value, 1004;
            is $review[1]->value, $date->add(years=>2)->strftime("%d/%m/%Y");
            my @loc = ${$data[4]->value}->value;
            is $loc[0]->value, 1005;
            is $loc[1]->value, 'Behind the wall';
            my @notes = ${$data[5]->value}->value;
            is $notes[0]->value, 1006;
            is $notes[1]->value, 'This is the details';
            my @type = ${$data[6]->value}->value;
            is $type[0]->value, 1007;
            is $type[1]->value, 3;
            my @title = ${$data[7]->value}->value;
            is $title[0]->value, 1008;
            is $title[1]->value, 2;
        } else {
            is @data, 3, 'Various supplied data';
            my @action = ${$data[0]->value}->value;
            is $action[0]->value, 1001;
            is $action[1]->value, 2;
            my @start = ${$data[1]->value}->value;
            is $start[0]->value, 1003;
            is $start[1]->value, $date->strftime("%d/%m/%Y");
            my @notes = ${$data[2]->value}->value;
            is $notes[0]->value, 1006;
            is $notes[1]->value, 'This is the details';
        }

        return SOAP::Result->new(result => {
            EventGuid => '1234',
        });
    } elsif ($method eq 'GetEventType') {
        my @params = ${$args[3]->value}->value;
        my $event_type = ${$params[2]->value}->value->value->value;
        return SOAP::Result->new(result => {
            Datatypes => { ExtensibleDatatype => [
                { Id => 1001, Name => "Assisted Action" },
                { Id => 1002, Name => "Assisted Start Date" },
                { Id => 1003, Name => "Assisted End Date" },
                { Id => 1004, Name => "Review Date" },
                { Id => 1005, Name => "Exact Location" },
                { Id => 1006, Name => "Notes" },
                { Id => 1007, Name => "Container Type" },
                { Id => 1008, Name => "Title" },
            ] },
        });
    } elsif ($method eq 'PerformEventAction') {
        my @params = ${$args[3]->value}->value;
        my $actiontype_id = $params[0]->value;
        is $actiontype_id, 8;
        my $datatype_id = ${${$params[1]->value}->value->value}->value->value;
        is $datatype_id, 5;
        return SOAP::Result->new(result => {
            EventActionGuid => 'cancel_update_id',
        });
    } else {
        is $method, 'UNKNOWN';
    }
});

use Open311::Endpoint::Integration::UK::Bromley::Dummy;

my $endpoint = Open311::Endpoint::Integration::UK::Bromley::Dummy->new;

subtest "POST add assisted collection OK" => sub {
    my $res = $endpoint->run_test_request(
        POST => '/requests.json',
        api_key => 'test',
        service_code => EVENT_TYPE_ASSISTED . "-add",
        first_name => 'Bob',
        last_name => 'Mould',
        description => "This is the details",
        lat => 51,
        long => -1,
        'attribute[service_id]' => 531, # Domestic refuse
        'attribute[uprn]' => 1000001,
        'attribute[fixmystreet_id]' => 2000123,
        'attribute[Exact_Location]' => 'Behind the wall',
        'attribute[Container_Type]' => 3,
        'attribute[title]' => 'MRS',
    );
    ok $res->is_success, 'valid request'
        or diag $res->content;

    is_deeply decode_json($res->content),
        [ {
            "service_request_id" => '1234',
        } ], 'correct json returned';
};

subtest "POST remove assisted collection OK" => sub {
    my $res = $endpoint->run_test_request(
        POST => '/requests.json',
        api_key => 'test',
        service_code => EVENT_TYPE_ASSISTED . "-remove",
        first_name => 'Bob',
        last_name => 'Mould',
        description => "This is the details",
        lat => 51,
        long => -1,
        'attribute[service_id]' => 531, # Domestic refuse
        'attribute[uprn]' => 1000001,
        'attribute[fixmystreet_id]' => 2000123,
    );
    ok $res->is_success, 'valid request'
        or diag $res->content;

    is_deeply decode_json($res->content),
        [ {
            "service_request_id" => '1234',
        } ], 'correct json returned';
};

subtest "POST a cancellation" => sub {
    my $res = $endpoint->run_test_request(
        POST => '/servicerequestupdates.json',
        api_key => 'test',
        updated_datetime => '2023-09-01T19:00:00+01:00',
        service_request_id => 'canceltest',
        update_id => 123,
        status => 'OPEN',
        description => 'Booking cancelled by customer',
        first_name => 'Bob',
        last_name => 'Mould',
    );
    ok $res->is_success, 'valid request'
        or diag $res->content;

    is_deeply decode_json($res->content),
        [ {
            "update_id" => 'cancel_update_id',
        } ], 'correct json returned';
};

done_testing;
