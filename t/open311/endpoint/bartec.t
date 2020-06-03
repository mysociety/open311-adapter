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
        service_name => "Leaf Removal",
        description => "Leaf Removal",
        metadata => 'false',
        type => "realtime",
        keywords => "",
        groups => [ "Street Cleansing" ]
    },
    ],
    'correct services returned';
};

done_testing;
