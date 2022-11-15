use strict;
use warnings;

BEGIN { $ENV{TEST_MODE} = 1; }

use JSON::MaybeXS;
use Path::Tiny;
use Test::More;
use Test::MockModule;
use Test::LongString;

# Set up

sub new_service {
    Open311::Endpoint::Service->new(description => $_[0], service_code => $_[0], service_name => $_[0]);
}

my $echo = Test::MockModule->new('Open311::Endpoint::Integration::UK::Brent::Echo');
$echo->mock(services => sub {
    return ( new_service('A_BC'), new_service('D_EF') );
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
        my $code = '';
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
          "service_code" => "Echo-A_BC",
          "service_name" => "A_BC",
          "description" => "A_BC",
          "metadata" => "false",
          "group" => "",
          "keywords" => "",
          "type" => "realtime"
        }, {
          "service_code" => "Echo-D_EF",
          "service_name" => "D_EF",
          "description" => "D_EF",
          "metadata" => "false",
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
    );
    ok $res->is_success, 'valid request'
        or diag $res->content;

    is_deeply decode_json($res->content),
        [ {
            "service_request_id" => "Symology-1001"
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

done_testing;
