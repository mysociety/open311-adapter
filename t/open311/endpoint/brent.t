package SOAP::Result;
use Object::Tiny qw(method result);

package main;
use strict;
use warnings;

BEGIN { $ENV{TEST_MODE} = 1; }

use JSON::MaybeXS;
use YAML::XS qw(LoadFile);
use Path::Tiny;
use Test::More;
use Test::MockModule;
use Test::LongString;

# Set up

sub new_service {
    Open311::Endpoint::Service->new(description => $_[0], service_code => $_[0], service_name => $_[0]);
}

my $echo_int = Test::MockModule->new('Integrations::Echo');
$echo_int->mock('config', sub {
    my $cfg = path(__FILE__)->sibling('brent_echo.yml');
    my $config = LoadFile($cfg) or die $!;
    return $config;
});

my $echo = Test::MockModule->new('Open311::Endpoint::Integration::UK::Brent::Echo');
$echo->mock('BUILDARGS', sub {
    my $cls = shift;
    my $cfg = path(__FILE__)->sibling('brent_echo.yml');
    my $config = LoadFile($cfg) or die $!;
    return $echo->original('BUILDARGS')->($cls, %$config, @_);
});

my $symology = Test::MockModule->new('Open311::Endpoint::Integration::UK::Brent::Symology');
$symology->mock('_build_config_file', sub {
    path(__FILE__)->sibling('brent_symology.yml');
});

my $brent_integ = Test::MockModule->new('Integrations::Symology');
$brent_integ->mock(config => sub {
    {
        endpoint_url => 'http://www.example.org/',
        endpoint_username => 'ep',
        endpoint_password => 'password',
    }
});

use constant {
    REPORT_NSGREF => 0,
    REPORT_DATE => 1,
    REPORT_TIME => 2,
    REPORT_USER => 3,
    REPORT_REQUEST_TYPE => 4,
    REPORT_PRIORITY => 5,
    REPORT_AC1 => 6,
    REPORT_ACT2 => 7,
    REPORT_LOCATION => 8,
    REPORT_REF => 9,
    REPORT_DESC => 10,
    REPORT_EASTING => 11,
    REPORT_NORTHING => 12,
    REPORT_INWEB => 13,
    REPORT_SERVICECODE => 14,
    REPORT_NEXTACTION => 15,
    UPDATE_REPORT_ID => 123,
};

use constant {
    NSGREF => '123/4567',
};

use constant {
    NORTHING => 100,
    EASTING => 100,
};

my $soap_lite = Test::MockModule->new('SOAP::Lite');
$soap_lite->mock(call => sub {
    # This is called when a test below makes a SOAP call, along with the data
    # to be passed via SOAP to the server. We check the values here, then pass
    # back a mocked result.
    my ($cls, @args) = @_;
    if ($args[0] eq 'SendRequestAdditionalGroupAuthenticated') {
        is $args[1]->value, 'ep';
        is $args[2]->value, 'password';
        my @request = ${$args[4]->value}->value;
        is $request[REPORT_NSGREF]->value, NSGREF;
        my $next_action = Open311::Endpoint::Integration::UK::Brent::Symology->new->endpoint_config->{nsgref_to_action}{+NSGREF};
        is $request[REPORT_NEXTACTION]->value, $next_action; # Worked out automatically from 0
        is $request[REPORT_NORTHING]->value, NORTHING;
        my $photo_desc = "\n\n[ This report contains a photo, see: http://example.org/photo/1.jpeg ]";
        my $burnt = 'No';
        is $request[REPORT_DESC]->value, "This is the details$photo_desc\n\nBurnt out?: $burnt\n\nCar details: Details";
        is $request[REPORT_PRIORITY]->value, "P";
        is $request[REPORT_LOCATION]->value, 'Report title';
        return {
            StatusCode => 0,
            StatusMessage => 'Success',
            SendRequestResults => {
                SendRequestResultRow => {
                    RecordType => 2,
                    ConvertCRNo => 1001,
                }
            }
        };
    } elsif ($args[0] eq 'SendEventActionAuthenticated') {
        my @request = map { $_->value } ${$args[4]->value}->value;
        my $photo_desc = "\n\n[ This update contains a photo, see: http://example.org/photo/1.jpeg ]";
        my $report_id = $request[2];
        my $code = 'CHRR';
        is_deeply \@request, [ 'ServiceCode', 1001, $report_id, $code, '', 'FMS', "This is the update$photo_desc", undef ];
        return {
            StatusCode => 0,
            StatusMessage => 'Event Loaded',
            SendEventActionResults => {
                SendEventActionResultRow => {
                    RecordType => 2,
                }
            }
        };
    } elsif ($args[0]->name eq 'PostEvent') {
        my @params = ${$args[3]->value}->value;

        my $client_ref = $params[1]->value;
        is $client_ref, 'FMS-234';

        my $event_type = $params[3]->value;
        my $service_id = $params[4]->value;

        if ($event_type =~ /^(935|943)/) {
            is $service_id, 277;
        } elsif ($event_type == 2891) {
            is $service_id, 262, 'Service id updated to missed refuse collection';
            my @data = ${$params[0]->value}->value->value;
            is @data, 2, 'Extra data is refuse BIN and refuse BAG';
            my @bin = ${$data[0]->value}->value;
            my @bag = ${$data[1]->value}->value;
            is $bin[0]->value, 1001;
            is $bin[1]->value, 1, 'Refuse BIN has been ticked';
            is $bag[0]->value, 1002;
            is $bag[1]->value, 1, 'Refuse BAG has been ticked';
        } elsif ($event_type == 1159) {
            is $service_id, 317;
            my @data = ${$params[0]->value}->value->value;
            is @data, 2, 'Extra data right size';
            my @name = ${$data[0]->value}->value;
            my @ref = ${$data[1]->value}->value;
            is $name[0]->value, 1001;
            is $name[1]->value, 'Bob', 'Name';
            is $ref[0]->value, 1009;
            is $ref[1]->value, 'PAY12345', 'Correct reference';
        } else {
            die "Bad event type provided";
        }

        # Check the USRN has been included
        if ($event_type =~ /^(935|943)/) {
            my @event_object = ${${$params[2]->value}->value->value}->value;
            is $event_object[0]->value, 'Source';
            my @object_ref = ${$event_object[1]->value}->value;
            is $object_ref[0]->value, 'Usrn';
            is $object_ref[1]->value, 'Street';
            my $usrn = ${$object_ref[2]->value}->value->value->value->value;

            my @data = ${$params[0]->value}->value->value;

            if ($event_type == 935) {
                is $usrn, '123/4567';
                is @data, 5, 'Name and source is only extra data';
            } elsif ($event_type == 943) {
                is $usrn, '123/4567';
                is @data, 4, 'Name (no surname) and source is only extra data';
            }
            my $c = 0;
            my @first_name = ${$data[$c++]->value}->value;
            is $first_name[0]->value, 1001;
            is $first_name[1]->value, 'Bob';
            if ($event_type == 935 ) {
                my @last = ${$data[$c++]->value}->value;
                is $last[0]->value, 1002;
                is $last[1]->value, 'Mould';
            }
            my @source = ${$data[$c++]->value}->value;
            is $source[0]->value, 1003;
            is $source[1]->value, 2;
            my @loc = ${$data[$c++]->value}->value;
            is $loc[0]->value, 1010;
            is $loc[1]->value, "Report title";
            my @notes = ${$data[$c++]->value}->value;
            is $notes[0]->value, 1008;
            is $notes[1]->value, 'Report details';
        }

        return SOAP::Result->new(result => {
            EventGuid => '1234',
        });
    } elsif ($args[0]->name eq 'GetEventType') {
        my @params = ${$args[3]->value}->value;
        my $event_type = ${$params[2]->value}->value->value->value;
        if ( $event_type == 935 || $event_type == 943) {
            return SOAP::Result->new(result => {
                Datatypes => { ExtensibleDatatype => [
                    { Id => 1001, Name => "First Name" },
                    { Id => 1002, Name => "Surname" },
                    { Id => 1003, Name => "Source" },
                    { Id => 1010, Name => "Exact Location" },
                    { Id => 1008, Name => "Notes" },
                ] },
            });
        } elsif ($event_type == 1159) {
            return SOAP::Result->new(result => {
                Datatypes => { ExtensibleDatatype => [
                    { Id => 1001, Name => "First Name" },
                    { Id => 1002, Name => "Surname" },
                    { Id => 1009, Name => "Payment Code" },
                ] },
            });
        } elsif ( $event_type == 2891) {
            return SOAP::Result->new(result => {
                Datatypes => { ExtensibleDatatype => [
                    { Id => 1001, Name => "Refuse BIN" },
                    { Id => 1002, Name => "Refuse BAG" },
                ] },
            });
        }
    } else {
        is $args[0], '';
    }
});

# Tests

use_ok('Open311::Endpoint::Integration::UK::Brent');
my $endpoint = Open311::Endpoint::Integration::UK::Brent->new;

subtest "GET Service List" => sub {
    my $res = $endpoint->run_test_request( GET => '/services.json' );
    ok $res->is_success, 'valid request'
        or diag $res->content;
    is_deeply decode_json($res->content),
        [ {
          "service_code" => "Echo-1159",
          "service_name" => "Garden subscription",
          "description" => "Garden subscription",
          "metadata" => "true",
          "group" => "Waste",
          "keywords" => "waste_only",
          "type" => "realtime"
        }, {
            'type' => 'realtime',
            'service_code' => 'Echo-2891',
            'service_name' => 'Report missed collection',
            'group' => 'Waste',
            'description' => 'Report missed collection',
            'keywords' => 'waste_only',
            'metadata' => 'true'
        }, {
          "service_code" => "Echo-935",
          "service_name" => "Non-offensive graffiti",
          "description" => "Non-offensive graffiti",
          "metadata" => "true",
          "group" => "",
          "keywords" => "",
          "type" => "realtime"
        }, {
          "service_code" => "Echo-943",
          "service_name" => "Fly-posting",
          "description" => "Fly-posting",
          "metadata" => "true",
          "group" => "",
          "keywords" => "",
          "type" => "realtime"
        }, {
          "service_code" => "Symology-AbanVeh",
          "service_name" => "Abandoned vehicles",
          "description" => "Abandoned vehicles",
          "metadata" => "true",
          "group" => "",
          "keywords" => "",
          "type" => "realtime"
       } ], 'correct json returned';
};

subtest "POST service request OK" => sub {
    my $res = $endpoint->run_test_request(
        POST => '/requests.json',
        api_key => 'test',
        service_code => 'Symology-AbanVeh',
        first_name => 'Bob',
        last_name => 'Mould',
        description => "This is the details",
        lat => 51,
        long => -1,
        media_url => 'http://example.org/photo/1.jpeg',
        'attribute[NSGRef]' => NSGREF,
        'attribute[burnt]' => 'No',
        'attribute[car_details]' => 'Details',
        'attribute[easting]' => EASTING,
        'attribute[northing]' => NORTHING,
        'attribute[fixmystreet_id]' => 123,
        'attribute[title]' => 'Report title'
    );
    ok $res->is_success, 'valid request'
        or diag $res->content;

    is_deeply decode_json($res->content),
        [ {
            "service_request_id" => "Symology-1001"
        } ], 'correct json returned';
};

subtest "POST Echo service request OK" => sub {
    my $res = $endpoint->run_test_request(
        POST => '/requests.json',
        api_key => 'test',
        service_code => 'Echo-935',
        first_name => 'Bob',
        last_name => 'Mould',
        description => "This is the details",
        lat => 51,
        long => -1,
        media_url => 'http://example.org/photo/1.jpeg',
        'attribute[usrn]' => NSGREF,
        #'attribute[easting]' => EASTING,
        #'attribute[northing]' => NORTHING,
        'attribute[fixmystreet_id]' => 234,
        'attribute[title]' => 'Report title',
        'attribute[description]' => 'Report details',
    );
    ok $res->is_success, 'valid request'
        or diag $res->content;

    is_deeply decode_json($res->content),
        [ {
            "service_request_id" => "Echo-1234"
        } ], 'correct json returned';
};

subtest "POST other Echo service request OK" => sub {
    my $res = $endpoint->run_test_request(
        POST => '/requests.json',
        api_key => 'test',
        service_code => 'Echo-943',
        first_name => 'Bob',
        last_name => 'Mould',
        description => "This is the details",
        lat => 51,
        long => -1,
        media_url => 'http://example.org/photo/1.jpeg',
        'attribute[usrn]' => NSGREF,
        'attribute[fixmystreet_id]' => 234,
        'attribute[title]' => 'Report title',
        'attribute[description]' => 'Report details',
    );
    ok $res->is_success, 'valid request'
        or diag $res->content;

    is_deeply decode_json($res->content),
        [ {
            "service_request_id" => "Echo-1234"
        } ], 'correct json returned';
};

subtest "POST missed collection Echo service request OK" => sub {
    my $res = $endpoint->run_test_request(
        POST => '/requests.json',
        api_key => 'test',
        service_code => 'Echo-2891',
        first_name => 'Bob',
        last_name => 'Mould',
        description => "Report missed collection",
        lat => 51,
        long => -1,
        'attribute[fixmystreet_id]' => 234,
        'attribute[service_id]' => 262,
    );
    ok $res->is_success, 'valid request'
        or diag $res->content;

    is_deeply decode_json($res->content),
        [ {
            "service_request_id" => "Echo-1234"
        } ], 'correct json returned';
};

subtest "POST waste Echo service request OK" => sub {
    my $res = $endpoint->run_test_request(
        POST => '/requests.json',
        api_key => 'test',
        service_code => 'Echo-1159',
        first_name => 'Bob',
        last_name => 'Mould',
        description => "Garden subscription details",
        lat => 51,
        long => -1,
        'attribute[usrn]' => NSGREF,
        'attribute[fixmystreet_id]' => 234,
        'attribute[title]' => 'Garden subscription - New',
        'attribute[description]' => 'Garden subscription details',
        'attribute[service_id]' => 317,
        'attribute[PaymentCode]' => 'PAY12345',
    );
    ok $res->is_success, 'valid request'
        or diag $res->content;

    is_deeply decode_json($res->content),
        [ {
            "service_request_id" => "Echo-1234"
        } ], 'correct json returned';
};

subtest "POST update OK" => sub {
    my $res = $endpoint->run_test_request(
        POST => '/servicerequestupdates.json',
        #jurisdiction_id => 'brent',
        api_key => 'test',
        updated_datetime => '2019-03-01T12:00:00Z',
        service_code => 'Symology-AbanVeh',
        service_request_id => "Symology-1001",
        status => 'OPEN',
        first_name => 'Bob',
        last_name => 'Mould',
        description => "This is the update",
        service_request_id_ext => 5678,
        update_id => 456,
        media_url => 'http://example.org/photo/1.jpeg',
    );
    ok $res->is_success, 'valid request'
        or diag $res->content;

    is_deeply decode_json($res->content),
        [ {
            'update_id' => "Symology-456",
        } ], 'correct json returned';
};

subtest "GET updates OK" => sub {
#my $sftp = $endpoint->endpoint_config->{updates_sftp};
#    $sftp->{out} = path(__FILE__)->sibling('files')->child('brent');

    my $res = $endpoint->run_test_request(
        GET => '/servicerequestupdates.json?start_date=2018-11-27T00:00:00Z&end_date=2018-11-29T00:00:00Z',
    );
    ok $res->is_success, 'valid request'
        or diag $res->content;

    my $response = decode_json($res->content);
    is_deeply $response,
        [
            {
                description => "",
                media_url => '',
                service_request_id => 'Symology-323',
                status => 'investigating',
                update_id => 'Symology-00000323_6',
                updated_datetime => '2018-11-28T15:05:00+00:00',
                external_status_code => '19',
            },
            {
                description => "Text going here explaining reason for no further action",
                media_url => '',
                service_request_id => 'Symology-323',
                status => 'no_further_action',
                update_id => 'Symology-00000323_8',
                updated_datetime => '2018-11-28T15:05:00+00:00',
                external_status_code => '21_NFA',
            }
        ], 'correct json returned';
};

done_testing;
