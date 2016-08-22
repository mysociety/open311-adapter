use strict;
use warnings;

use Test::More;
use Test::MockModule;

use JSON::MaybeXS;

my $open311 = Test::MockModule->new('Integrations::EastHerts::Highways');
$open311->mock(AddDefect => sub {
    my ($cls, $args) = @_;
    is $args->{ItemCode}, 'CS';
    is $args->{SubItemCode}, 'DP';
    is $args->{DefectCode}, 'OTS';
    return 1001;
});

use Open311::Endpoint::Integration::UK::EastHerts;

my $endpoint = Open311::Endpoint::Integration::UK::EastHerts->new;

subtest "GET Service List" => sub {
    my $res = $endpoint->run_test_request( GET => '/services.xml' );
    ok $res->is_success, 'xml success';
    my $expected = <<XML;
<?xml version="1.0" encoding="utf-8"?>
<services>
  <service>
    <description>Abandoned vehicles</description>
    <group></group>
    <keywords></keywords>
    <metadata>true</metadata>
    <service_code>SC_E_AVE</service_code>
    <service_name>Abandoned vehicles</service_name>
    <type>realtime</type>
  </service>
  <service>
    <description>Dog Bin overflow</description>
    <group></group>
    <keywords></keywords>
    <metadata>true</metadata>
    <service_code>P_C_DBE</service_code>
    <service_name>Dog Bin overflow</service_name>
    <type>realtime</type>
  </service>
  <service>
    <description>Dog fouling</description>
    <group></group>
    <keywords></keywords>
    <metadata>true</metadata>
    <service_code>SC_RS_DOG</service_code>
    <service_name>Dog fouling</service_name>
    <type>realtime</type>
  </service>
  <service>
    <description>Drugs Paraphernalia</description>
    <group></group>
    <keywords></keywords>
    <metadata>true</metadata>
    <service_code>ZZZDRUGS</service_code>
    <service_name>Drugs Paraphernalia</service_name>
    <type>realtime</type>
  </service>
  <service>
    <description>Litter</description>
    <group></group>
    <keywords></keywords>
    <metadata>true</metadata>
    <service_code>ZZZLITTER</service_code>
    <service_name>Litter</service_name>
    <type>realtime</type>
  </service>
  <service>
    <description>Litter Bin overflow</description>
    <group></group>
    <keywords></keywords>
    <metadata>true</metadata>
    <service_code>ZZZLITTERBIN</service_code>
    <service_name>Litter Bin overflow</service_name>
    <type>realtime</type>
  </service>
  <service>
    <description>Flyposting</description>
    <group></group>
    <keywords></keywords>
    <metadata>true</metadata>
    <service_code>SC_RS_FLP</service_code>
    <service_name>Flyposting</service_name>
    <type>realtime</type>
  </service>
  <service>
    <description>Flytipping</description>
    <group></group>
    <keywords></keywords>
    <metadata>true</metadata>
    <service_code>SC_RS_FLY</service_code>
    <service_name>Flytipping</service_name>
    <type>realtime</type>
  </service>
  <service>
    <description>Graffiti</description>
    <group></group>
    <keywords></keywords>
    <metadata>true</metadata>
    <service_code>ZZZGRAFFITI</service_code>
    <service_name>Graffiti</service_name>
    <type>realtime</type>
  </service>
  <service>
    <description>Grass Cutting</description>
    <group></group>
    <keywords></keywords>
    <metadata>true</metadata>
    <service_code>P_C_GNC</service_code>
    <service_name>Grass Cutting</service_name>
    <type>realtime</type>
  </service>
  <service>
    <description>Public toilets</description>
    <group></group>
    <keywords></keywords>
    <metadata>true</metadata>
    <service_code>SC_C_TOI</service_code>
    <service_name>Public toilets</service_name>
    <type>realtime</type>
  </service>
  <service>
    <description>Street cleaning</description>
    <group></group>
    <keywords></keywords>
    <metadata>true</metadata>
    <service_code>ZZZSTREETCLEANING</service_code>
    <service_name>Street cleaning</service_name>
    <type>realtime</type>
  </service>
</services>
XML
    is $res->content, $expected
        or diag $res->content;
};

subtest "POST OK" => sub {
    my $res = $endpoint->run_test_request( 
        POST => '/requests.json', 
        api_key => 'test',
        service_code => 'ZZZDRUGS',
        'attribute[code]' => 'CS_DP_OTS',
        address_string => '22 Acacia Avenue',
        first_name => 'Bob',
        last_name => 'Mould',
        description => "This is the details",
        'attribute[easting]' => 100,
        'attribute[northing]' => 100,
        'attribute[fixmystreet_id]' => 1001,
    );
    ok $res->is_success, 'valid request'
        or diag $res->content;

    is_deeply decode_json($res->content),
        [ {
            "service_request_id" => 1001
        } ], 'correct json returned';
};

done_testing;
