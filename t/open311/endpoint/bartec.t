package Integrations::Bartec::Dummy;
use Path::Tiny;
use Moo;
extends 'Integrations::Bartec';
sub _build_config_file { path(__FILE__)->sibling('bartec.yml')->stringify }

sub get_integration {
    my $self = shift;
    my $integ = 'Integrations::Bartec::Dummy';
    $integ = $integ->on_fault(sub {
        my($soap, $res) = @_;
        die ref $res ? $res->faultstring : $soap->transport->status, "\n";
    });
    $integ->config_filename('dummy');
    return $integ;
}

package main;

use strict; use warnings;

use Test::More;
use Test::LongString;
use Test::MockModule;
use Test::Output;
use JSON::MaybeXS;
use Path::Tiny;

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

my $soap = Test::MockModule->new('SOAP::Lite');
$soap->mock(call => sub {
        my ($self, $call) = @_;

        my $xml = gen_full_response( $responses{$call} );
        return SOAP::Deserializer->deserialize($xml);
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

done_testing;
