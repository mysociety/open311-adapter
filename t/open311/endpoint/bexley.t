use strict;
use warnings;

use Test::More;
use Test::MockModule;

use JSON::MaybeXS;

use constant {
    REPORT_NSGREF => 0,
    REPORT_DATE => 1,
    REPORT_TIME => 2,
    REPORT_USER => 3,
    REPORT_REQUEST_TYPE => 4,
    REPORT_PRIORITY => 5,
    REPORT_AC1 => 6,
    REPORT_ACT2 => 7,
    REPORT_REF => 8,
    REPORT_DESC => 9,
    REPORT_EASTING => 10,
    REPORT_NORTHING => 11,
    REPORT_INWEB => 12,
    REPORT_SERVICECODE => 13,
    REPORT_NEXTACTION => 14,
};

use constant {
    NSGREF => '123/4567',
};

use constant {
    NORTHING => 100,
    EASTING_BAD => -100,
    EASTING_GOOD => 100,
    EASTING_GOOD_BURNT => 200,
};

my $soap_lite = Test::MockModule->new('SOAP::Lite');
$soap_lite->mock(call => sub {
    # This is called when a test below makes a SOAP call, along with the data
    # to be passed via SOAP to the server. We check the values here, then pass
    # back a mocked result.
    my ($cls, @args) = @_;
    if ($args[0] eq 'SendRequestAdditionalGroup') {
        my @request = ${$args[2]->value}->value;
        is $request[REPORT_NSGREF]->value, NSGREF;
        my $next_action = Open311::Endpoint::Integration::UK::Bexley->endpoint_config->{nsgref_to_action}{+NSGREF};
        is $request[REPORT_NEXTACTION]->value, $next_action; # Worked out automatically from 0
        is $request[REPORT_NORTHING]->value, NORTHING;
        my $photo_desc = "\n\n[ This report contains a photo, see: http://example.org/photo/1.jpeg ]";
        my $burnt = $request[REPORT_EASTING]->value == EASTING_GOOD_BURNT ? 'Yes' : 'No';
        is $request[REPORT_DESC]->value, "This is the details$photo_desc\n\nBurnt out?: $burnt\n\nCar details: M4 GIC, red Ford Focus";
        is $request[REPORT_PRIORITY]->value, $request[REPORT_EASTING]->value == EASTING_GOOD_BURNT ? 'P1' : "N";
        if ($request[REPORT_EASTING]->value == EASTING_BAD) {
            return {
                StatusCode => 1,
                StatusMessage => 'Failed',
                SendRequestResults => {
                    SendRequestResultRow => {
                        RecordType => 1,
                        MessageText => 'Unknown identifier',
                    }
                }
            };
        }
        return {
            StatusCode => 0,
            SendRequestResults => {
                SendRequestResultRow => {
                    ConvertCRNo => 1001,
                }
            }
        };
    } elsif ($args[0] eq 'SendEventAction') {
        my @request = map { $_->value } ${$args[2]->value}->value;
        my $photo_desc = "\n\n[ This update contains a photo, see: http://example.org/photo/1.jpeg ]";
        is_deeply \@request, [ 'ServiceCode', 1001, 123, 'CCA', '', 'FMS', "This is the update$photo_desc" ];
        return {
            StatusCode => 0,
            SendEventActionResults => {
                SendEventActionResultRow => {
                }
            }
        };
    } else {
        is $args[0], '';
    }
});

my $bexley_integ = Test::MockModule->new('Integrations::Symology::Bexley');
$bexley_integ->mock(config => sub {
    {
        endpoint_url => 'http://www.example.org/',
    }
});

my $bexley_end = Test::MockModule->new('Open311::Endpoint::Integration::UK::Bexley');
$bexley_end->mock(endpoint_config => sub {
    {
        username => 'FMS',
        nsgref_to_action => {
            NSGREF, 'N1',
            '234/5678' => 'S2',
        },
        category_mapping => {
            AbanVeh => {
                name => 'Abandoned vehicles',
                parameters => {
                    ServiceCode => 'ServiceCode',
                    RequestType => 'ReqType',
                    AnalysisCode1 => 'A1',
                    AnalysisCode2 => 'A2',
                },
                questions => [
                    { code => 'message', description => 'Please ignore yellow cars', variable => 0 },
                    { code => 'car_details', description => 'Car details', },
                    { code => 'burnt', description => 'Burnt out?', values => [ 'Yes', 'No' ], },
                ],
                logic => [
                    { rules => [ '$attr.burnt', 'Yes' ], output => { Priority => 'P1' } },
                ],
            },
        },
    }
});

use Open311::Endpoint::Integration::UK::Bexley;

my $endpoint = Open311::Endpoint::Integration::UK::Bexley->new;

subtest "GET services" => sub {
    my $res = $endpoint->run_test_request(
        GET => '/services.json',
    );
    ok $res->is_success, 'valid request'
        or diag $res->content;

    is_deeply decode_json($res->content),
        [ {
          "service_code" => "AbanVeh",
          "service_name" => "Abandoned vehicles",
          "description" => "Abandoned vehicles",
          "metadata" => "true",
          "group" => "",
          "keywords" => "",
          "type" => "realtime"
       } ], 'correct json returned';
};

subtest "GET service" => sub {
    my $res = $endpoint->run_test_request(
        GET => '/services/AbanVeh.json',
    );
    ok $res->is_success, 'valid request'
        or diag $res->content;

    is_deeply decode_json($res->content), {
        "service_code" => "AbanVeh",
       "attributes" => [
          {
             "datatype" => "number",
             "code" => "easting",
             "order" => 1,
             "required" => "true",
             "automated" => "server_set",
             "description" => "easting",
             "variable" => "false",
             "datatype_description" => ""
          },
          {
             "datatype" => "number",
             "code" => "northing",
             "order" => 2,
             "required" => "true",
             "automated" => "server_set",
             "description" => "northing",
             "datatype_description" => "",
             "variable" => "false"
          },
          {
             "datatype_description" => "",
             "variable" => "false",
             "description" => "external system ID",
             "automated" => "server_set",
             "required" => "true",
             "order" => 3,
             "code" => "fixmystreet_id",
             "datatype" => "string"
          },
          {
             "description" => "Unit ID",
             "variable" => "true",
             "datatype_description" => "",
             "automated" => "hidden_field",
             "order" => 4,
             "required" => "false",
             "datatype" => "string",
             "code" => "UnitID"
          },
          {
             "description" => "NSG reference",
             "variable" => "true",
             "datatype_description" => "",
             "automated" => "hidden_field",
             "order" => 5,
             "required" => "false",
             "datatype" => "string",
             "code" => "NSGRef"
          },
          {
             "required" => "false",
             "order" => 6,
             "datatype" => "string",
             "code" => "contributed_by",
             "description" => "Contributed by",
             "variable" => "true",
             "datatype_description" => "",
             "automated" => "server_set"
          },
          {
             "required" => "false",
             "order" => 7,
             "datatype" => "string",
             "code" => "message",
             "description" => "Please ignore yellow cars",
             "variable" => "false",
             "datatype_description" => "",
          },
          {
             "required" => "true",
             "order" => 8,
             "datatype" => "string",
             "code" => "car_details",
             "description" => "Car details",
             "variable" => "true",
             "datatype_description" => "",
          },
          {
             "required" => "true",
             "order" => 9,
             "datatype" => "singlevaluelist",
             "code" => "burnt",
             "description" => "Burnt out?",
             "variable" => "true",
             "values" => [ { key => 'No', name => 'No', }, { key => 'Yes', name => 'Yes', } ],
             "datatype_description" => "",
          }
       ],
    }, 'correct json returned';
};

subtest "POST Abandoned Vehicles Bad" => sub {
    # Tests of the generated SOAP call appear at the top in the mocked module
    my $res = $endpoint->run_test_request(
        POST => '/requests.json',
        api_key => 'test',
        service_code => 'AbanVeh',
        first_name => 'Bob',
        last_name => 'Mould',
        description => "This is the details",
        lat => 51,
        long => -1,
        media_url => 'http://example.org/photo/1.jpeg',
        'attribute[NSGRef]' => NSGREF,
        'attribute[easting]' => EASTING_BAD,
        'attribute[northing]' => NORTHING,
        'attribute[fixmystreet_id]' => 123,
        'attribute[car_details]' => "M4 GIC, red Ford Focus",
        'attribute[burnt]' => "No",
    );
    ok !$res->is_success, 'invalid request'
        or diag $res->content;

    is_deeply decode_json($res->content),
        [ {
            "description" => "Couldn't create Request in Symology: Failed - Unknown identifier\n",
            "code" => 500,
        } ], 'correct json returned';
};

subtest "POST Abandoned Vehicles OK" => sub {
    my $res = $endpoint->run_test_request(
        POST => '/requests.json',
        api_key => 'test',
        service_code => 'AbanVeh',
        first_name => 'Bob',
        last_name => 'Mould',
        description => "This is the details",
        lat => 51,
        long => -1,
        media_url => 'http://example.org/photo/1.jpeg',
        'attribute[NSGRef]' => NSGREF,
        'attribute[easting]' => EASTING_GOOD,
        'attribute[northing]' => NORTHING,
        'attribute[fixmystreet_id]' => 123,
        'attribute[car_details]' => "M4 GIC, red Ford Focus",
        'attribute[burnt]' => "No",
    );
    ok $res->is_success, 'valid request'
        or diag $res->content;

    is_deeply decode_json($res->content),
        [ {
            "service_request_id" => 1001
        } ], 'correct json returned';
};

subtest "POST Abandoned Vehicles burnt OK" => sub {
    my $res = $endpoint->run_test_request(
        POST => '/requests.json',
        api_key => 'test',
        service_code => 'AbanVeh',
        first_name => 'Bob',
        last_name => 'Mould',
        description => "This is the details",
        lat => 51,
        long => -1,
        media_url => 'http://example.org/photo/1.jpeg',
        'attribute[NSGRef]' => NSGREF,
        'attribute[easting]' => EASTING_GOOD_BURNT,
        'attribute[northing]' => NORTHING,
        'attribute[fixmystreet_id]' => 123,
        'attribute[car_details]' => "M4 GIC, red Ford Focus",
        'attribute[burnt]' => "Yes",
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
        service_code => 'AbanVeh',
        service_request_id => 1001,
        status => 'OPEN',
        first_name => 'Bob',
        last_name => 'Mould',
        description => "This is the update",
        service_request_id_ext => 123,
        update_id => 456,
        media_url => 'http://example.org/photo/1.jpeg',
    );
    ok $res->is_success, 'valid request'
        or diag $res->content;

    is_deeply decode_json($res->content),
        [ {
            'update_id' => 456,
        } ], 'correct json returned';
};

done_testing;
