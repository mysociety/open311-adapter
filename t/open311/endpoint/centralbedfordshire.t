use strict;
use warnings;

BEGIN { $ENV{TEST_MODE} = 1; }

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
    REPORT_NEXTINSPECTION => 15,
    REPORT_NEXTACTIONUSERNAME => 16,
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
    if ($args[0] eq 'SendRequestAdditionalGroup') {
        my @request = ${$args[2]->value}->value;
        is $request[REPORT_NSGREF]->value, NSGREF;
        is $request[REPORT_NEXTACTION]->value, undef;
        is $request[REPORT_NEXTACTIONUSERNAME]->value, $request[REPORT_REQUEST_TYPE]->value eq "Bridges" ? 'USER0001' : 'POT00001';
        is $request[REPORT_NORTHING]->value, NORTHING;
        my $photo_desc = "\n\n[ This report contains a photo, see: http://example.org/photo/1.jpeg ]";
        is $request[REPORT_DESC]->value, "This is the details$photo_desc";
        is $request[REPORT_PRIORITY]->value, ($request[REPORT_REQUEST_TYPE]->value eq "Bridges" ? 'Priority1' : 'Priority2');
        return {
            StatusCode => 0,
            StatusMessage => 'Success',
            SendRequestResults => {
                SendRequestResultRow => {
                    RecordType => 2,
                    ConvertCRNo => $request[REPORT_REQUEST_TYPE]->value eq "Bridges" ? 1001 : 1002,
                }
            }
        };
    } elsif ($args[0] eq 'SendEventAction') {
        my @request = map { $_->value } ${$args[2]->value}->value;
        my $photo_desc = "\n\n[ This update contains a photo, see: http://example.org/photo/1.jpeg ]";
        my $report_id = $request[2];
        my $code = 'GN11';
        is_deeply \@request, [ 'ServiceCode', 1001, $report_id, $code, '', 'FMS', "This is the update$photo_desc" ];
        return {
            StatusCode => 0,
            StatusMessage => 'Event Loaded',
            SendEventActionResults => {
                SendEventActionResultRow => {
                    RecordType => 2,
                }
            }
        };
    } else {
        is $args[0], '';
    }
});

my $centralbeds_integ = Test::MockModule->new('Integrations::Symology');
$centralbeds_integ->mock(config => sub {
    {
        endpoint_url => 'http://www.example.org/',
    }
});

my $centralbeds_end = Test::MockModule->new('Open311::Endpoint::Integration::UK::CentralBedfordshire');
$centralbeds_end->mock(endpoint_config => sub {
    {
        username => 'FMS',
        nsgref_to_action => {},
        customer_defaults => {
            CustomerType => "",
            ContactType => "",
        },
        category_mapping => {
            Bridges => {
                name => 'Bridges',
                parameters => {
                    ServiceCode => 'ServiceCode',
                    RequestType => 'Bridges',
                    Priority => 'Priority1',
                    NextActionUserName => 'USER0001',
                },
                questions => [],
                logic => [],
            },
            Potholes => {
                name => 'Potholes',
                parameters => {
                    ServiceCode => 'ServiceCode',
                    RequestType => 'Potholes',
                    Priority => 'Priority2',
                    NextActionUserName => 'POT00001',
                },
                questions => [],
                logic => [],
            },
        },
    }
});

use Open311::Endpoint::Integration::UK::CentralBedfordshire;

my $endpoint = Open311::Endpoint::Integration::UK::CentralBedfordshire->new;

subtest "GET services" => sub {
    my $res = $endpoint->run_test_request(
        GET => '/services.json',
    );
    ok $res->is_success, 'valid request'
        or diag $res->content;

    my $content = decode_json($res->content);
    my $services = [ sort { $a->{service_code} cmp $b->{service_code} } @$content ];
    is_deeply $services,
        [
            {
                "service_code" => "Bridges",
                "service_name" => "Bridges",
                "description" => "Bridges",
                "metadata" => "true",
                "group" => "",
                "keywords" => "",
                "type" => "realtime"
            },
            {
                "service_code" => "Potholes",
                "service_name" => "Potholes",
                "description" => "Potholes",
                "metadata" => "true",
                "group" => "",
                "keywords" => "",
                "type" => "realtime"
            },
        ], 'correct json returned';
};

subtest "GET service" => sub {
    my $res = $endpoint->run_test_request(
        GET => '/services/Bridges.json',
    );
    ok $res->is_success, 'valid request'
        or diag $res->content;

    is_deeply decode_json($res->content), {
        "service_code" => "Bridges",
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
                }
            ],
        }, 'correct json returned';
};

subtest "POST Bridges OK" => sub {
    my $res = $endpoint->run_test_request(
        POST => '/requests.json',
        api_key => 'test',
        service_code => 'Bridges',
        first_name => 'Bob',
        last_name => 'Mould',
        description => "This is the details",
        lat => 51,
        long => -1,
        media_url => 'http://example.org/photo/1.jpeg',
        'attribute[NSGRef]' => NSGREF,
        'attribute[easting]' => EASTING,
        'attribute[northing]' => NORTHING,
        'attribute[fixmystreet_id]' => UPDATE_REPORT_ID,
    );
    ok $res->is_success, 'valid request'
        or diag $res->content;

    is_deeply decode_json($res->content),
        [ {
            "service_request_id" => 1001
        } ], 'correct json returned';
};

subtest "POST Bridges OK" => sub {
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
        'attribute[NSGRef]' => NSGREF,
        'attribute[easting]' => EASTING,
        'attribute[northing]' => NORTHING,
        'attribute[fixmystreet_id]' => 456,
    );
    ok $res->is_success, 'valid request'
        or diag $res->content;

    is_deeply decode_json($res->content),
        [ {
            "service_request_id" => 1002
        } ], 'correct json returned';
};

subtest "POST update OK" => sub {
    my $res = $endpoint->run_test_request(
        POST => '/servicerequestupdates.json',
        api_key => 'test',
        updated_datetime => '2019-03-01T12:00:00Z',
        service_code => 'Bridges',
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

done_testing;