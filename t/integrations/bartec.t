package Integrations::Bartec::Dummy;
use Path::Tiny;
use Moo;
extends 'Integrations::Bartec';
sub _build_config_file { path(__FILE__)->sibling('bartec.yml')->stringify }

sub get_integration {
    my $self = shift;
    my $integ = Integrations::Bartec::Dummy->new;
    $integ->config_filename('dummy');
    return $integ;
}
my $integration = get_integration();

use strict; use warnings;

use Test::More;
use Test::LongString;
use Test::MockModule;
use Test::Output;

BEGIN { $ENV{TEST_MODE} = 1; }

sub gen_full_response {
    my $append = shift(@_);

    my $xml .= <<EOF;
<?xml version="1.0" encoding="utf-8"?>
<soap:Envelope xmlns:soap="http://schemas.xmlsoap.org/soap/envelope/"
               xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
               xmlns:xsd="http://www.w3.org/2001/XMLSchema">
<soap:Body>$append</soap:Body>
</soap:Envelope>
EOF

    return $xml;
} # end sub gen_full_response

subtest 'Authentication success' => sub {
    my $soap = Test::MockModule->new('SOAP::Lite');
    $soap->mock(
        call => sub {
            my $xml .= <<'EOF';
<AuthenticateResponse xmlns="http://bartec-systems.com/">
  <AuthenticateResult xmlns="http://www.bartec-systems.com">
    <Token><TokenString>ABC=</TokenString></Token>
    <Errors />
  </AuthenticateResult>
</AuthenticateResponse>
EOF
            my $full_xml = gen_full_response($xml);
            my $env      = SOAP::Deserializer->deserialize($full_xml);
            return $env;
        }
    );

    my $response = $integration->Authenticate;
    my $expected = {
      is_success => 1,
      token => 'ABC=',
    };

    is_deeply $response, $expected, 'returns an error';
};

subtest 'Authentication failure' => sub {
    my $soap = Test::MockModule->new('SOAP::Lite');
    $soap->mock(
        call => sub {
            my $xml .= <<'EOF';
<AuthenticateResponse xmlns="http://bartec-systems.com/">
  <AuthenticateResult xmlns="http://www.bartec-systems.com">
    <Errors>
      <Error>
        <Result>1</Result>
        <Message>Invalid login credentials supplied</Message>
      </Error>
    </Errors>
  </AuthenticateResult>
</AuthenticateResponse>
EOF
            my $full_xml = gen_full_response($xml);
            my $env      = SOAP::Deserializer->deserialize($full_xml);
            return $env;
        }
    );

    my $response = $integration->Authenticate;
    my $expected = {
      is_success => 0,
      error => 'Invalid login credentials supplied',
    };

    is_deeply $response, $expected, 'returns an error';
};

subtest 'Authentication token expired' => sub {
    my $soap = Test::MockModule->new('SOAP::Lite');
    $soap->mock(
        call => sub {
            my ($self, $method) = @_;
            my $xml;

            if ($method->name eq 'Authenticate') {
                $xml .= <<'EOF';
<AuthenticateResponse xmlns="http://bartec-systems.com/">
  <AuthenticateResult xmlns="http://www.bartec-systems.com">
    <Token><TokenString>ABC=</TokenString></Token>
    <Errors />
  </AuthenticateResult>
</AuthenticateResponse>
EOF

            } else {
                $xml .= <<'EOF';
<ServiceRequests_Types_GetResponse xmlns="http://bartec-systems.com/">
  <ServiceRequests_Types_GetResult RecordCount="0" xmlns="http://www.bartec-systems.com/ServiceRequests_Get.xsd">
    <Errors>
       <Result xmlns="http://www.bartec-systems.com">1</Result>
       <Message xmlns="http://www.bartec-systems.com">Invalid Token</Message>
    </Errors>
  </ServiceRequests_Types_GetResult>
</ServiceRequests_Types_GetResponse>
EOF
            }
            my $full_xml = gen_full_response($xml);
            my $env      = SOAP::Deserializer->deserialize($full_xml);
            return $env;
        }
    );

    my $response = $integration->ServiceRequests_Types_Get;
    my $expected = {
      Errors => {
          Message => 'Invalid Token',
          Result => 1
      }
    };

    is_deeply $response, $expected, 'returns an error';
};

done_testing;
