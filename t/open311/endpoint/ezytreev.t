use strict;
use warnings;

use Test::More;
use Test::MockModule;
use Test::LongString;

BEGIN { $ENV{TEST_MODE} = 1; }

my $ezytreev_mock = Test::MockModule->new('Open311::Endpoint::Integration::Ezytreev');
$ezytreev_mock->mock(config => sub {
    {
        category_mapping => {
            FallenTree => {
                name => "Fallen/damaged tree or branch",
            },
        },
    }
});

use Open311::Endpoint::Integration::Ezytreev;

my $endpoint = Open311::Endpoint::Integration::Ezytreev->new;

subtest "GET services" => sub {
    my $res = $endpoint->run_test_request(
        GET => '/services.xml',
    );
    ok $res->is_success, 'valid request'
        or diag $res->content;

    is_string $res->content, <<XML, 'xml string ok';
<?xml version="1.0" encoding="utf-8"?>
<services>
  <service>
    <description>Fallen/damaged tree or branch</description>
    <group></group>
    <keywords></keywords>
    <metadata>true</metadata>
    <service_code>FallenTree</service_code>
    <service_name>Fallen/damaged tree or branch</service_name>
    <type>realtime</type>
  </service>
</services>
XML
};

done_testing;
