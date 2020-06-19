use strict; use warnings;

use Test::More;
use Test::LongString;
use Test::MockModule;
use Test::MockTime ':all';
use Test::Output;
use JSON::MaybeXS;
use Path::Tiny;
use SOAP::Lite;
use SOAP::Transport::HTTP;

BEGIN { $ENV{TEST_MODE} = 1; }

use Open311::Endpoint::Integration::Bartec;
my $endpoint = Open311::Endpoint::Integration::Bartec->new( jurisdiction_id => 'bartec' );

my $integration = Test::MockModule->new('Integrations::Bartec');
$integration->mock('_build_config_file', sub {
    path(__FILE__)->sibling('bartec.yml');
});

my %responses = (
    Authenticate => '<AuthenticateResponse xmlns="http://bartec-systems.com/">
  <AuthenticateResult xmlns="http://www.bartec-systems.com">
    <Token><TokenString>ABC=</TokenString></Token>
    <Errors />
  </AuthenticateResult>
</AuthenticateResponse>',
    ServiceRequests_Types_Get => path(__FILE__)->parent(1)->realpath->child('xml/bartec/servicerequests_types_get.xml')->slurp,
    ServiceRequests_Create => path(__FILE__)->parent(1)->realpath->child('xml/bartec/servicerequests_create.xml')->slurp,
    ServiceRequests_Statuses_Get => path(__FILE__)->parent(1)->realpath->child('xml/bartec/servicerequests_status_get.xml')->slurp,
    Premises_Get => path(__FILE__)->parent(1)->realpath->child('xml/bartec/get_premises.xml')->slurp,
);

sub gen_full_response {
    my ($append) = @_;

    my $xml .= <<EOF;
<?xml version="1.0" encoding="utf-8"?>
<soap:Envelope xmlns:soap="http://schemas.xmlsoap.org/soap/envelope/"
               xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
               xmlns:xsd="http://www.w3.org/2001/XMLSchema">
<soap:Body>$append</soap:Body>
</soap:Envelope>
EOF

    return $xml;
}

my %sent;

my $t = SOAP::Transport::HTTP::Client->new();
my $transport = Test::MockModule->new('SOAP::Transport::HTTP::Client', no_auto => 1);
$transport->mock(send_receive => sub {
        my $self = shift;
        my %args = @_;

        (my $action = $args{action}) =~ s#http://bartec-systems.com/##;
        $action =~ s/"//g;
        $sent{$action} = $args{envelope};
        return gen_full_response( $responses{$action} );
    }
);

subtest "check fetch service description" => sub {
    my $res = $endpoint->run_test_request(
      GET => '/services.json?jurisdiction_id=bartec',
    );

    ok $res->is_success, 'valid request'
        or diag $res->content;

    is_deeply decode_json($res->content),
    [
    {
        service_code => "1",
        service_name => "Leaf removal",
        description => "Leaf removal",
        metadata => 'true',
        type => "realtime",
        keywords => "",
        groups => [ "Street cleansing" ]
    },
    ],
    'correct services returned';
};

subtest "check fetch service" => sub {
    my $res = $endpoint->run_test_request(
      GET => '/services/1.json?jurisdiction_id=bartec',
    );

    ok $res->is_success, 'valid request'
        or diag $res->content;

    is_deeply decode_json($res->content),
    {
        service_code => "1",
        attributes => [
          {
            variable => 'false',
            code => "easting",
            datatype => "number",
            required => 'true',
            datatype_description => '',
            order => 1,
            description => "easting",
            automated => 'server_set',
          },
          {
            variable => 'false',
            code => "northing",
            datatype => "number",
            required => 'true',
            datatype_description => '',
            order => 2,
            description => "northing",
            automated => 'server_set',
          },
          {
            variable => 'false',
            code => "fixmystreet_id",
            datatype => "string",
            required => 'true',
            datatype_description => '',
            order => 3,
            description => "external system ID",
            automated => 'server_set',
          },
          {
            variable => 'true',
            code => "report_url",
            datatype => "string",
            required => 'true',
            datatype_description => '',
            order => 4,
            description => "Report URL",
            automated => 'server_set',
          },
          {
            variable => 'true',
            code => "title",
            datatype => "string",
            required => 'true',
            datatype_description => '',
            order => 5,
            description => "Title",
            automated => 'server_set',
          },
          {
            variable => 'true',
            code => "description",
            datatype => "text",
            required => 'true',
            datatype_description => '',
            order => 6,
            description => "Description",
            automated => 'server_set',
          },
          {
            variable => 'true',
            code => "asset_details",
            datatype => "text",
            required => 'false',
            datatype_description => '',
            order => 7,
            description => "Asset information",
            automated => 'hidden_field',
          },
          {
            variable => 'true',
            code => "site_code",
            datatype => "text",
            required => 'false',
            datatype_description => '',
            order => 8,
            description => "Site code",
            automated => 'hidden_field',
          },
          {
            variable => 'true',
            code => "central_asset_id",
            datatype => "string",
            required => 'false',
            datatype_description => '',
            order => 9,
            description => "Central Asset ID",
            automated => 'hidden_field',
          },
          {
            variable => 'true',
            code => "closest_address",
            datatype => "string",
            required => 'false',
            datatype_description => '',
            order => 10,
            description => "Closest address",
            automated => 'server_set',
          },
          {
            variable => 'true',
            code => "postcode",
            datatype => "string",
            required => 'false',
            datatype_description => '',
            order => 11,
            description => "postcode",
            automated => 'server_set',
          },
          {
            variable => 'true',
            code => "street",
            datatype => "string",
            required => 'false',
            datatype_description => '',
            order => 12,
            description => "Closest street",
            automated => 'server_set',
          },
          {
            variable => 'true',
            code => "house_no",
            datatype => "string",
            required => 'false',
            datatype_description => '',
            order => 13,
            description => "Closest house number",
            automated => 'server_set',
          },
        ]
    },
    'correct services returned';
};

subtest "check send basic report" => sub {
    set_fixed_time('2020-06-17T16:28:30Z');
    my $res = $endpoint->run_test_request(
        POST => '/requests.json',
        jurisdiction_id => 'bartec',
        api_key => 'test',
        service_code => '1',
        first_name => 'Bob',
        last_name => 'Mould',
        email => 'test@example.com',
        description => 'description',
        lat => '52.540930',
        long => '-0.289832',
        'attribute[fixmystreet_id]' => 1,
        'attribute[northing]' => 1,
        'attribute[easting]' => 1,
        'attribute[description]' => 1,
        'attribute[report_url]' => 1,
        'attribute[title]' => 1,
        'attribute[house_no]' => '14',
        'attribute[street]' => 'a street',
        'attribute[postcode]' => 'AB1 1BA',
    );

    my $sent = SOAP::Deserializer->deserialize( $sent{ServiceRequests_Create} );
    ok $res->is_success, 'valid request'
        or diag $res->content;

    is_deeply $sent->body->{ServiceRequests_Create}, {
        DateRequested => '2020-06-17T17:28:30+01:00',
        token => 'ABC=',
        UPRN => 987654321,
        ServiceTypeID => 1,
        ServiceStatusID => 2276,
        CrewID => 11,
        LandTypeID => 12,
        SLAID => 13,
        serviceLocationDescription => 'description',
        ServiceRequest_Location => {
            Metric => {
                Longitude => -0.289832,
                Latitude => 52.540930,
            }
        },
        #source => 'FixMyStreet',
        ExternalReference => 1,
        reporterContact => {
            Forename => 'Bob',
            Surname => 'Mould',
            Email => 'test@example.com',
        }
    }, 'correct request sent';

    is_deeply decode_json($res->content), [ { service_request_id => '0001' } ], 'correct return';
};

subtest 'get address from bounding box' => sub {
    my $uprn = $endpoint->get_nearest_uprn({
            long => -0.28938,
            lat => 52.540936,
            service_code => 1,
            attributes => {
                site_code => 123456789
            },
    });

    my $get_prem_obj = SOAP::Deserializer->deserialize( $sent{Premises_Get} );
    my $point1 = $get_prem_obj->dataof('//Point1/Metric');
    my $point2 = $get_prem_obj->dataof('//Point2/Metric');

    is $point1->attr->{Latitude}, 52.541374, "point 1 longitude correct";
    is $point1->attr->{Longitude}, -0.290116, "point 1 latitude correct";
    is $point2->attr->{Latitude}, 52.540498, "point 2 longitude correct";
    is $point2->attr->{Longitude}, -0.288644, "point 2 latitude correct";

    my $get_prem_req = $get_prem_obj->body->{Premises_Get};

    is_deeply $get_prem_req, {
        token => 'ABC=',
        UPRN => undef,
        Bounds => {
            Point1 => { Metric => '' },
            Point2 => { Metric => '' },
        }
    }, "sent bounding box";

    is $uprn, 100000101, "got correct uprn";
};

subtest 'get open space address from bounding box' => sub {
    my $uprn = $endpoint->get_nearest_uprn({
            long => -0.28938,
            lat => 52.540936,
            service_code => 100,
            attributes => {
                site_code => 123456789
            },
    });

    is $uprn, 987654323 , "got correct uprn";
};

subtest 'get uprn for usrn' => sub {
    my $uprn = $endpoint->get_nearest_uprn({
            long => -0.28938,
            lat => 52.540936,
            service_code => 200,
            attributes => {
                site_code => 123456789
            },
    });

    my $get_prem_obj = SOAP::Deserializer->deserialize( $sent{Premises_Get} );
    my $get_prem_req = $get_prem_obj->body->{Premises_Get};

    is_deeply $get_prem_req, {
        token => 'ABC=',
        UPRN => undef,
        USRN => 123456789,
    }, "only used USRN in request";

    is $uprn,987654321 , "got correct uprn";
};

done_testing;
