use strict; use warnings;

use Test::More;
use Test::LongString;
use Test::MockTime ':all';

use JSON::MaybeXS;

use Module::Loaded;
BEGIN { mark_as_loaded('DBD::Oracle') }

use t::open311::endpoint::Endpoint_Warwick;

my $endpoint = t::open311::endpoint::Endpoint_Warwick->new;

subtest "GET Service List" => sub {
    my $res = $endpoint->run_test_request( GET => '/services.xml' );
    ok $res->is_success, 'xml success';
    my $expected = <<XML;
<?xml version="1.0" encoding="utf-8"?>
<services>
  <service>
    <description>Pothole</description>
    <group>highways</group>
    <keywords></keywords>
    <metadata>true</metadata>
    <service_code>PO</service_code>
    <service_name>Pothole</service_name>
    <type>realtime</type>
  </service>
</services>
XML
    is $res->content, $expected
        or diag $res->content;
};

subtest "POST OK" => sub {
    set_fixed_time('2014-01-01T12:00:00Z');
    my $res = $endpoint->run_test_request( 
        POST => '/requests.json', 
        api_key => 'test',
        service_code => 'PO',
        address_string => '22 Acacia Avenue',
        first_name => 'Bob',
        last_name => 'Mould',
        'attribute[easting]' => 100,
        'attribute[northing]' => 100,
        'attribute[external_id]' => 1001,
        'attribute[closest_address]' => '22 Acacia Avenue',
    );
    ok $res->is_success, 'valid request'
        or diag $res->content;

    is_deeply decode_json($res->content),
        [ {
            "service_notice" => "Warwickshire Open311 Endpoint",
            "service_request_id" => 1001
        } ], 'correct json returned';

    is_deeply \%t::open311::endpoint::Endpoint_Warwick::BINDINGS, 
        {
          ':ce_surname' => 'MOULD',
          ':ce_y' => '100',
          ':ce_x' => '100',
          ':ce_work_phone' => '',
          ':ce_contact_type' => 'PU',
          ':ce_source' => 'FMS',
          ':ce_doc_reference' => '1001',
          ':ce_enquiry_type' => 'PO',
          ':ce_email' => '',
          ':ce_description' => '',
          ':ce_location' => '22 Acacia Avenue',
          ':ce_incident_datetime' => '2014-01-01 12:00',
          ':ce_class' => 'N/A',
          ':ce_cpr_id' => 5,
          ':ce_compl_user_type' => 'USER',
          ':ce_status_code' => 'RE',
          ':ce_cat' => 'DEF',
          ':ce_forename' => 'BOB'
        }, 
        'bindings as expected';
};

subtest 'updates' => sub {
    my $res = $endpoint->run_test_request( GET => '/servicerequestupdates.xml', );
    ok $res->is_success, 'valid request' or diag $res->content;

my $expected = <<XML;
<?xml version="1.0" encoding="utf-8"?>
<service_request_updates>
  <request_update>
    <description>Closed the ticket</description>
    <media_url></media_url>
    <service_request_id>1001</service_request_id>
    <status>closed</status>
    <update_id>999</update_id>
    <updated_datetime>2014-07-23T11:07:00+01:00</updated_datetime>
  </request_update>
</service_request_updates>
XML

    is_string $res->content, $expected, 'xml string ok'
    or diag $res->content;

    chomp (my $expected_sql = <<SQL);
SELECT * FROM (
        SELECT
            row_id,
            service_request_id,
            to_char(updated_timedate, 'YYYY-MM-DD HH24:MI'),
            status,
            description
        FROM higatlas.fms_update
        WHERE updated_timedate >= to_date(2013-12-31 12:00, YYYY-MM-DD HH24:MI) AND (status='OPEN' OR status='CLOSED')
        ORDER BY updated_timedate DESC) WHERE ROWNUM <= 1000
SQL

    is_string $t::open311::endpoint::Endpoint_Warwick::UPDATES_SQL, $expected_sql, 'SQL as expected';
};

restore_time();
done_testing;
