use strict;
use warnings;

package Open311::Endpoint::Integration::UK::Dummy;
use Moo;
extends 'Open311::Endpoint::Integration::Confirm';
around BUILDARGS => sub {
    my ($orig, $class, %args) = @_;
    $args{jurisdiction_id} = 'confirm_wrapped';
    $args{config_data} = '
service_whitelist:
   Everything:
     HM_PHS: Small pothole
     HM_PHL: Large pothole
     ST_STP4: Broken bridge
wrapped_services:
  POTHOLES:
    group: "Road defects"
    name: "Pothole"
    wraps:
      - HM_PHS
      - HM_PHL
  ST_STP4:
    passthrough: 1
    group: Bridges and safety barriers
';
    return $class->$orig(%args);
};

package main;

use Test::More;
use Test::LongString;
use Test::MockModule;

BEGIN { $ENV{TEST_MODE} = 1; }

my $open311 = Test::MockModule->new('Integrations::Confirm');
$open311->mock(perform_request => sub {
    my ($self, $op) = @_; # Don't care about subsequent ops
    $op = $$op;
    if ($op->name && $op->name eq 'GetEnquiryLookups') {
        return {
            OperationResponse => { GetEnquiryLookupsResponse => { TypeOfService => [
                { ServiceCode => 'HM', ServiceName => 'Highways', EnquirySubject => [ { SubjectCode => "PHS" } ] },
                { ServiceCode => 'HM', ServiceName => 'Highways', EnquirySubject => [ { SubjectCode => "PHL" } ] },
                { ServiceCode => 'ST', ServiceName => 'Streets', EnquirySubject => [ { SubjectCode => "STP4" } ] },
            ] } }
        };
    }
    return {};
});
$open311->mock(endpoint_url => sub { 'http://example.org/' });
$open311->mock(config => sub {
    {
        server_timezone => 'Europe/London',
        graphql_key => 'test-key',
        web_url => 'http://example.org/web',
        tenant_id => 'test',
    }
});
$open311->mock(perform_request_graphql => sub {
    my ($self, %args) = @_;

    if ($args{query} =~ /enquiryStatusLogs/) {
        return {
            data => {
                enquiryStatusLogs => [
                    {
                        enquiryNumber => '1001',
                        enquiryStatusCode => 'INP',
                        logNumber => '1',
                        loggedDate => '2018-03-01T12:00:00+00:00',
                        notes => 'Update for small pothole',
                        centralEnquiry => {
                            subjectCode => 'PHS',
                            serviceCode => 'HM'
                        }
                    },
                    {
                        enquiryNumber => '1002',
                        enquiryStatusCode => 'FIX',
                        logNumber => '2',
                        loggedDate => '2018-03-01T13:00:00+00:00',
                        notes => 'Fixed large pothole',
                        centralEnquiry => {
                            subjectCode => 'PHL',
                            serviceCode => 'HM'
                        }
                    },
                    {
                        enquiryNumber => '1003',
                        enquiryStatusCode => 'INP',
                        logNumber => '3',
                        loggedDate => '2018-03-01T14:00:00+00:00',
                        notes => 'Update for bridge',
                        centralEnquiry => {
                            subjectCode => 'STP4',
                            serviceCode => 'ST'
                        }
                    }
                ]
            }
        };
    }
    return {};
});

my $endpoint = Open311::Endpoint::Integration::UK::Dummy->new;

subtest "GET Service List" => sub {
    my $res = $endpoint->run_test_request( GET => '/services.xml' );
    ok $res->is_success, 'xml success';
    my $expected = <<XML;
<?xml version="1.0" encoding="utf-8"?>
<services>
  <service>
    <description>Pothole</description>
    <groups>
      <group>Road defects</group>
    </groups>
    <keywords></keywords>
    <metadata>true</metadata>
    <service_code>POTHOLES</service_code>
    <service_name>Pothole</service_name>
    <type>realtime</type>
  </service>
  <service>
    <description>Broken bridge</description>
    <groups>
      <group>Bridges and safety barriers</group>
    </groups>
    <keywords></keywords>
    <metadata>true</metadata>
    <service_code>ST_STP4</service_code>
    <service_name>Broken bridge</service_name>
    <type>realtime</type>
  </service>
</services>
XML
    is_string $res->content, $expected;
};

subtest "GET wrapped Service List Description" => sub {
    my $res = $endpoint->run_test_request( GET => '/services/POTHOLES.xml' );
    ok $res->is_success, 'xml success';
    my $expected = <<XML;
<?xml version="1.0" encoding="utf-8"?>
<service_definition>
  <attributes>
    <attribute>
      <code>_wrapped_service_code</code>
      <datatype>singlevaluelist</datatype>
      <datatype_description></datatype_description>
      <description>What is the issue?</description>
      <order>1</order>
      <required>true</required>
      <values>
        <value>
          <name>Large pothole</name>
          <key>HM_PHL</key>
        </value>
        <value>
          <name>Small pothole</name>
          <key>HM_PHS</key>
        </value>
      </values>
      <variable>true</variable>
    </attribute>
    <attribute>
      <automated>server_set</automated>
      <code>easting</code>
      <datatype>number</datatype>
      <datatype_description></datatype_description>
      <description>easting</description>
      <order>2</order>
      <required>true</required>
      <variable>false</variable>
    </attribute>
    <attribute>
      <automated>server_set</automated>
      <code>northing</code>
      <datatype>number</datatype>
      <datatype_description></datatype_description>
      <description>northing</description>
      <order>3</order>
      <required>true</required>
      <variable>false</variable>
    </attribute>
    <attribute>
      <automated>server_set</automated>
      <code>fixmystreet_id</code>
      <datatype>string</datatype>
      <datatype_description></datatype_description>
      <description>external system ID</description>
      <order>4</order>
      <required>true</required>
      <variable>false</variable>
    </attribute>
    <attribute>
      <automated>server_set</automated>
      <code>report_url</code>
      <datatype>string</datatype>
      <datatype_description></datatype_description>
      <description>Report URL</description>
      <order>5</order>
      <required>true</required>
      <variable>true</variable>
    </attribute>
    <attribute>
      <automated>server_set</automated>
      <code>title</code>
      <datatype>string</datatype>
      <datatype_description></datatype_description>
      <description>Title</description>
      <order>6</order>
      <required>true</required>
      <variable>true</variable>
    </attribute>
    <attribute>
      <automated>server_set</automated>
      <code>description</code>
      <datatype>text</datatype>
      <datatype_description></datatype_description>
      <description>Description</description>
      <order>7</order>
      <required>true</required>
      <variable>true</variable>
    </attribute>
    <attribute>
      <automated>hidden_field</automated>
      <code>asset_details</code>
      <datatype>text</datatype>
      <datatype_description></datatype_description>
      <description>Asset information</description>
      <order>8</order>
      <required>false</required>
      <variable>true</variable>
    </attribute>
    <attribute>
      <automated>hidden_field</automated>
      <code>site_code</code>
      <datatype>string</datatype>
      <datatype_description></datatype_description>
      <description>Site code</description>
      <order>9</order>
      <required>false</required>
      <variable>true</variable>
    </attribute>
    <attribute>
      <automated>hidden_field</automated>
      <code>central_asset_id</code>
      <datatype>string</datatype>
      <datatype_description></datatype_description>
      <description>Central Asset ID</description>
      <order>10</order>
      <required>false</required>
      <variable>true</variable>
    </attribute>
    <attribute>
      <automated>server_set</automated>
      <code>closest_address</code>
      <datatype>string</datatype>
      <datatype_description></datatype_description>
      <description>Closest address</description>
      <order>11</order>
      <required>false</required>
      <variable>true</variable>
    </attribute>
  </attributes>
  <service_code>POTHOLES</service_code>
</service_definition>
XML
    is_string $res->content, $expected;
};

subtest "GET Service Request Updates with category change for wrapped services" => sub {
    my $res = $endpoint->run_test_request(
        GET => '/servicerequestupdates.xml?start_date=2018-03-01T00:00:00Z&end_date=2018-03-02T00:00:00Z'
    );
    my $expected = <<XML;
<?xml version="1.0" encoding="utf-8"?>
<service_request_updates>
  <request_update>
    <description></description>
    <external_status_code>INP</external_status_code>
    <extras>
      <category>Pothole</category>
      <group>Road defects</group>
    </extras>
    <media_url></media_url>
    <service_request_id>1001</service_request_id>
    <status>open</status>
    <update_id>1001_1</update_id>
    <updated_datetime>2018-03-01T12:00:00+00:00</updated_datetime>
  </request_update>
  <request_update>
    <description></description>
    <external_status_code>FIX</external_status_code>
    <extras>
      <category>Pothole</category>
      <group>Road defects</group>
    </extras>
    <media_url></media_url>
    <service_request_id>1002</service_request_id>
    <status>open</status>
    <update_id>1002_2</update_id>
    <updated_datetime>2018-03-01T13:00:00+00:00</updated_datetime>
  </request_update>
  <request_update>
    <description></description>
    <external_status_code>INP</external_status_code>
    <extras>
      <category>Broken bridge</category>
      <group>Bridges and safety barriers</group>
    </extras>
    <media_url></media_url>
    <service_request_id>1003</service_request_id>
    <status>open</status>
    <update_id>1003_3</update_id>
    <updated_datetime>2018-03-01T14:00:00+00:00</updated_datetime>
  </request_update>
</service_request_updates>
XML
    is_string $res->content, $expected;
};

done_testing;
