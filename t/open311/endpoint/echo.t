package SOAP::Result;
use Object::Tiny qw(method result);

package Integrations::Echo::Dummy;
use Path::Tiny;
use Moo;
extends 'Integrations::Echo';
sub _build_config_file { path(__FILE__)->sibling("echo.yml")->stringify }

package Open311::Endpoint::Integration::Echo::Dummy;
use Path::Tiny;
use Moo;
extends 'Open311::Endpoint::Integration::Echo';
around BUILDARGS => sub {
    my ($orig, $class, %args) = @_;
    $args{jurisdiction_id} = 'echo_dummy';
    $args{config_file} = path(__FILE__)->sibling("echo.yml")->stringify;
    return $class->$orig(%args);
};
has integration_class => (is => 'ro', default => 'Integrations::Echo::Dummy');

package main;

use strict;
use warnings;

BEGIN { $ENV{TEST_MODE} = 1; }

use Test::More;
use Test::MockModule;
use SOAP::Lite;

use JSON::MaybeXS;

use constant EVENT_TYPE_MISSED => 2096;
use constant EVENT_TYPE_REQUEST => 2104;
use constant EVENT_TYPE_ENQUIRY => 2148;

my $soap_lite = Test::MockModule->new('SOAP::Lite');
$soap_lite->mock(call => sub {
    # This is called when a test below makes a SOAP call, along with the data
    # to be passed via SOAP to the server. We check the values here, then pass
    # back a mocked result.
    my ($cls, @args) = @_;
    my $method = $args[0]->name;
    if ($method eq 'PostEvent') {
        my @params = ${$args[3]->value}->value;
        my $event_type = $params[2]->value;
        my $service_id = $params[3]->value;
        if ($event_type == EVENT_TYPE_REQUEST) {
            is $service_id, 547, 'Service ID overriden for a new container request';
        }
        my @data = ${$params[0]->value}->value->value;
        if ($event_type == EVENT_TYPE_MISSED) {
            is @data, 3, 'Name and source is only extra data';
        } else {
            is @data, 4, 'Name, source and (container stuff or notes)';
        }
        my @first_name = ${$data[0]->value}->value;
        is $first_name[0]->value, 1001;
        is $first_name[1]->value, 'Bob';
        my @last_name = ${$data[1]->value}->value;
        is $last_name[0]->value, 1002;
        is $last_name[1]->value, 'Mould';
        my @source = ${$data[2]->value}->value;
        is $source[0]->value, 1003;
        is $source[1]->value, 2;
        if ($event_type == EVENT_TYPE_REQUEST) {
            # Compare the Container Stuff entry and its children
            my @notes = ${$data[3]->value}->value;
            is $notes[1]->value, 1004;
            my @children = ${$notes[0]->value}->value->value;
            my @child = ${$children[0]->value}->value;
            is $child[0]->value, 1005;
            is $child[1]->value, 2;
            @child = ${$children[1]->value}->value;
            is $child[0]->value, 1006;
            is $child[1]->value, 7;
            @child = ${$children[2]->value}->value;
            is $child[0]->value, 1007;
            is $child[1]->value, 12;
        } elsif ($event_type == EVENT_TYPE_ENQUIRY) {
            my @notes = ${$data[3]->value}->value;
            is $notes[0]->value, 1008;
            is $notes[1]->value, 'These are some notes';
        }

        # Check the UPRN has been included
        my @event_object = ${${$params[1]->value}->value->value}->value;
        is $event_object[0]->value, 'Source';
        my @object_ref = ${$event_object[1]->value}->value;
        is $object_ref[0]->value, 'Uprn';
        is $object_ref[1]->value, 'PointAddress';
        my $uprn = ${$object_ref[2]->value}->value->value->value->value;
        is $uprn, 1000001;
        return SOAP::Result->new(result => {
            EventGuid => '1234',
        });
    } elsif ($method eq 'GetEventType') {
        return SOAP::Result->new(result => {
            Datatypes => { ExtensibleDatatype => [
                { Id => 1001, Name => "First Name" },
                { Id => 1002, Name => "Surname" },
                { Id => 1003, Name => "Source" },
                { Id => 1004, Name => "Container Stuff",
                    ChildDatatypes => { ExtensibleDatatype => [
                        { Id => 1005, Name => "Quantity" },
                        { Id => 1006, Name => "Reason" },
                        { Id => 1007, Name => "Container Type" },
                    ] },
                },
                { Id => 1008, Name => "Notes" },
            ] },
        });
    } else {
        is $method, 'UNKNOWN';
    }
});

use Open311::Endpoint::Integration::Echo::Dummy;

my $endpoint = Open311::Endpoint::Integration::Echo::Dummy->new;

subtest "GET services" => sub {
    my $res = $endpoint->run_test_request(
        GET => '/services.json',
    );
    ok $res->is_success, 'valid request'
        or diag $res->content;

    is_deeply decode_json($res->content), [
   {
      "keywords" => "",
      "service_name" => "Request new container",
      "service_code" => EVENT_TYPE_REQUEST,
      "metadata" => "true",
      "type" => "realtime",
      "description" => "Request new container",
      "group" => "Waste"
   },
   {
      "description" => "Gate not closed",
      "group" => "Waste",
      "metadata" => "true",
      "type" => "realtime",
      "service_code" => "2118",
      "service_name" => "Gate not closed",
      "keywords" => ""
   },
   {
      "service_name" => "Waste spillage",
      "service_code" => "2119",
      "keywords" => "",
      "group" => "Waste",
      "description" => "Waste spillage",
      "metadata" => "true",
      "type" => "realtime"
   },
   {
      "service_name" => "General Enquiry",
      "service_code" => EVENT_TYPE_ENQUIRY,
      "keywords" => "",
      "description" => "General Enquiry",
      "group" => "Waste",
      "type" => "realtime",
      "metadata" => "true"
   },
   {
      "service_name" => "Report missed collection",
      "service_code" => "missed",
      "keywords" => "",
      "description" => "Report missed collection",
      "group" => "Waste",
      "type" => "realtime",
      "metadata" => "true"
   },
    ], 'correct json returned';
};

subtest "GET service" => sub {
    my $res = $endpoint->run_test_request(
        GET => '/services/missed.json',
    );
    ok $res->is_success, 'valid request'
        or diag $res->content;

    is_deeply decode_json($res->content), {
      "service_code" => "missed",
      "attributes" => [
          { code => 'uprn', order => 1, required => 'false', variable => 'true', datatype => 'string', datatype_description => '', automated => 'hidden_field', description => 'UPRN reference' },
          { code => 'service_id', order => 2, required => 'false', variable => 'true', datatype => 'string', datatype_description => '', automated => 'server_set', description => 'Service ID' },
      ],
    }, 'correct json returned';
};

subtest "POST missed collection OK" => sub {
    my $res = $endpoint->run_test_request(
        POST => '/requests.json',
        api_key => 'test',
        service_code => 'missed',
        first_name => 'Bob',
        last_name => 'Mould',
        description => "This is the details",
        lat => 51,
        long => -1,
        'attribute[service_id]' => 536, # Communal container mix
        'attribute[uprn]' => 1000001,
    );
    ok $res->is_success, 'valid request'
        or diag $res->content;

    is_deeply decode_json($res->content),
        [ {
            "service_request_id" => '1234',
        } ], 'correct json returned';
};

subtest "POST new request OK" => sub {
    my $res = $endpoint->run_test_request(
        POST => '/requests.json',
        api_key => 'test',
        service_code => EVENT_TYPE_REQUEST,
        first_name => 'Bob',
        last_name => 'Mould',
        description => "This is the details",
        lat => 51,
        long => -1,
        'attribute[uprn]' => 1000001,
        'attribute[Container_Type]' => 12, # Black Box (Paper)
        'attribute[Quantity]' => 2,
    );
    ok $res->is_success, 'valid request'
        or diag $res->content;

    is_deeply decode_json($res->content),
        [ {
            "service_request_id" => '1234',
        } ], 'correct json returned';
};

subtest "POST general enquiry OK" => sub {
    my $res = $endpoint->run_test_request(
        POST => '/requests.json',
        api_key => 'test',
        service_code => EVENT_TYPE_ENQUIRY,
        first_name => 'Bob',
        last_name => 'Mould',
        description => "This is the details",
        lat => 51,
        long => -1,
        'attribute[service_id]' => 531, # Domestic refuse
        'attribute[uprn]' => 1000001,
        'attribute[Notes]' => "These are some notes",
    );
    ok $res->is_success, 'valid request'
        or diag $res->content;

    is_deeply decode_json($res->content),
        [ {
            "service_request_id" => '1234',
        } ], 'correct json returned';
};

done_testing;
