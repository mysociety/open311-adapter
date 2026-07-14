use strict;
use warnings;

BEGIN { $ENV{TEST_MODE} = 1; }

use Test::More;
use Test::MockModule;
use Path::Tiny;
use JSON::MaybeXS;

use constant {
    NSGREF => '123/4567',
};

use constant {
    NORTHING => 100,
    EASTING => 200,
};

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
    UPDATE_REPORT_ID_CLOSING => 234,
    FIELDS_FIELDLINE => 0,
    FIELDS_VALUETYPE => 1,
    FIELDS_VALUE => 2,
};

my $soap_lite = Test::MockModule->new('SOAP::Lite');
$soap_lite->mock(call => sub {
    # This is called when a test below makes a SOAP call, along with the data
    # to be passed via SOAP to the server. We check the values here, then pass
    # back a mocked result.
    my ($cls, @args) = @_;
    if ($args[0] eq 'SendRequestAdditionalGroup') {
        my @request = ${$args[2]->value}->value;
        my @fields = ${$args[4]->value}->value;
        is $request[REPORT_NSGREF]->value, NSGREF;
        is $request[REPORT_NEXTACTION]->value, undef;
        is $request[REPORT_NORTHING]->value, NORTHING;
        is $request[REPORT_EASTING]->value, EASTING;
        my @photo_descs = map { "\n\n[ This report contains a photo, see: http://example.org/photo/$_.jpeg ]" } 1..3;
        my $photo_descs = join '', @photo_descs;
        is $request[REPORT_DESC]->value, "This is the details$photo_descs";
        is $fields[0][FIELDS_FIELDLINE]->value, 10;
        is $fields[0][FIELDS_VALUETYPE]->value, 8;
        is $fields[0][FIELDS_VALUE]->value, "http://example.org/photo/1.jpeg";
        is $fields[1][FIELDS_FIELDLINE]->value, 11;
        is $fields[1][FIELDS_VALUETYPE]->value, 8;
        is $fields[1][FIELDS_VALUE]->value, "http://example.org/photo/2.jpeg";
        is $fields[2][FIELDS_FIELDLINE]->value, 12;
        is $fields[2][FIELDS_VALUETYPE]->value, 8;
        is $fields[2][FIELDS_VALUE]->value, "http://example.org/photo/3.jpeg";
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
    } elsif ($args[0] eq 'SendEventAction') {
        my @request = map { $_->value } ${$args[2]->value}->value;
        my $photo_desc = "\n\n[ This update contains a photo, see: http://example.org/photo/1.jpeg ]";
        my $report_id = $request[2];
        is_deeply \@request, [ 'ServiceCode', 1001, $report_id, "NOTE", '', 'FMS', "This is the update$photo_desc", undef ];
        return {
            StatusCode => 0,
            StatusMessage => 'Event Loaded',
            SendEventActionResults => {
                SendEventActionResultRow => {
                    RecordType => 2,
                }
            }
        };
    } elsif ($args[0] eq 'GetRequestAdditionalGroup') {
        my $service_code = $args[1]->value;
        is $service_code, 'SERV';
        my $id = $args[2]->value;
        like $id, qr/^[12]$/;
        return unless $id == 1;
        return {
            StatusCode => 0,
            Request => {
            OutCRNo => "789951",
                EventHistory => {
                    EventHistoryGet => [ {
                        "LineNo" => "1",
                        "HistoryDate" => "2020-11-01T00:00:00",
                        "HistoryTime" => "2020-11-25T08:04:00",
                        "HistoryEventType" => "",
                        "HistoryAction" => "",
                        "HistoryEvent" => "Inspection scheduled",
                        "HistoryDescription" => "",
                        "HistoryType" => "21",
                    } ],
                },
            },
        };
    } else {
        is $args[0], '';
    }
});

my $symology_integ = Test::MockModule->new('Integrations::Symology');
$symology_integ->mock(config => sub {
    {
        endpoint_url => 'http://www.example.org/',
    }
});

my $dudley = Test::MockModule->new('Open311::Endpoint::Integration::UK::Dudley');
$dudley->mock('_build_config_file', sub {
    path(__FILE__)->sibling('dudley_symology.yml');
});

use_ok 'Open311::Endpoint::Integration::UK::Dudley';

my $endpoint = Open311::Endpoint::Integration::UK::Dudley->new;

subtest "GET services" => sub {
    my $res = $endpoint->run_test_request(
        GET => '/services.json',
    );
    ok $res->is_success, 'valid request'
        or diag $res->content;

    is_deeply decode_json($res->content),
        [ {
          "service_code" => "Potholes",
          "service_name" => "Potholes",
          "description" => "Potholes",
          "metadata" => "true",
          "group" => "",
          "keywords" => "",
          "type" => "realtime"
       } ], 'correct json returned';
};

subtest "GET service" => sub {
    my $res = $endpoint->run_test_request(
        GET => '/services/Potholes.json',
    );
    ok $res->is_success, 'valid request'
        or diag $res->content;

    is_deeply decode_json($res->content),
        {
            "service_code" => "Potholes",
            "attributes" => [
                {
                    "code" => "easting",
                    "datatype" => "number",
                    "datatype_description" => "",
                    "description" => "easting",
                    "required" => "true",
                    "variable" => "false",
                    "automated" => "server_set",
                    "order" => 1,
                },
                {
                    "code" => "northing",
                    "datatype" => "number",
                    "datatype_description" => "",
                    "description" => "northing",
                    "required" => "true",
                    "variable" => "false",
                    "automated" => "server_set",
                    "order" => 2,
                },
                {
                    "code" => "fixmystreet_id",
                    "datatype" => "string",
                    "datatype_description" => "",
                    "description" => "external system ID",
                    "required" => "true",
                    "variable" => "false",
                    "automated" => "server_set",
                    "order" => 3,
                },
                {
                    "code" => "UnitID",
                    "datatype" => "string",
                    "datatype_description" => "",
                    "description" => "Unit ID",
                    "required" => "false",
                    "variable" => "true",
                    "automated" => "hidden_field",
                    "order" => 4,
                },
                {
                    "code" => "NSGRef",
                    "datatype" => "string",
                    "datatype_description" => "",
                    "description" => "NSG reference",
                    "required" => "false",
                    "variable" => "true",
                    "automated" => "hidden_field",
                    "order" => 5,
                },
                {
                    "code" => "contributed_by",
                    "datatype" => "string",
                    "datatype_description" => "",
                    "description" => "Contributed by",
                    "required" => "false",
                    "variable" => "true",
                    "automated" => "server_set",
                    "order" => 6,
                },
                {
                    "code" => "area_code",
                    "datatype" => "string",
                    "datatype_description" => "",
                    "description" => "Area code",
                    "required" => "false",
                    "variable" => "true",
                    "automated" => "server_set",
                    "order" => 7,
                },
                {
                    "code" => "report_url",
                    "datatype" => "string",
                    "datatype_description" => "",
                    "description" => "Report URL",
                    "required" => "false",
                    "variable" => "true",
                    "automated" => "server_set",
                    "order" => 8,
                },
            ],
        }, 'correct json returned';
};

subtest "POST Potholes in road OK" => sub {
    my $res = $endpoint->run_test_request(
        POST => '/requests.json',
        api_key => 'test',
        service_code => 'Potholes',
        first_name => 'Bob',
        last_name => 'Mould',
        description => "This is the details",
        lat => 51,
        long => -1,
        media_url => 'http://example.org/photo/1.jpeg',
        media_url => 'http://example.org/photo/2.jpeg',
        media_url => 'http://example.org/photo/3.jpeg',
        'attribute[NSGRef]' => NSGREF,
        'attribute[easting]' => EASTING,
        'attribute[northing]' => NORTHING,
        'attribute[fixmystreet_id]' => 123,
    );
    ok $res->is_success, 'valid request'
        or diag $res->content;

    is_deeply decode_json($res->content),
        [ {
            "service_request_id" => 1001
        } ], 'correct json returned';
};

subtest "POST update OK" => sub {
    my $res = $endpoint->run_test_request(
        POST => '/servicerequestupdates.json',
        api_key => 'test',
        updated_datetime => '2019-03-01T12:00:00Z',
        service_code => 'Potholes',
        service_request_id => 1001,
        status => 'OPEN',
        first_name => 'Bob',
        last_name => 'Mould',
        description => "This is the update",
        service_request_id_ext => UPDATE_REPORT_ID,
        update_id => 789,
        media_url => 'http://example.org/photo/1.jpeg',
    );
    ok $res->is_success, 'valid request'
        or diag $res->content;

    is_deeply decode_json($res->content),
        [ {
            'update_id' => 789,
        } ], 'correct json returned';
};

subtest "GET updates OK" => sub {
    my $res = $endpoint->run_test_request(
        GET => '/requests.json?service_request_id=1,2',
    );
    ok $res->is_success, 'valid request'
        or diag $res->content;

    is_deeply decode_json($res->content),
        [ {
            service_request_id => 789951,
            updated_datetime => '2020-11-01T08:04:00+00:00',
            requested_datetime => '2020-11-01T08:04:00+00:00',
            zipcode => '',
            lat => 0,
            long => 0,
            status => 'investigating',
            media_url => '',
            address_id => '',
            address => '',
            service_code => 'Potholes',
            service_name => 'Potholes',

        } ], 'correct json returned';
};

done_testing;
