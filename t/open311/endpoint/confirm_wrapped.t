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
    MISC_DEF: Misc DEF is not wrapped
  Not wrapped:
    MISC_ABC_1: Misc ABC 1
    MISC_ABC_2: Misc ABC 2
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
                { ServiceCode => 'MISC', ServiceName => 'Misc', EnquirySubject => [ { SubjectCode => "ABC" }, { SubjectCode => "DEF" } ] },
            ] } }
        };
    }
    return {};
});
$open311->mock(endpoint_url => sub { 'http://example.org/' });

my $endpoint = Open311::Endpoint::Integration::UK::Dummy->new;

subtest "GET Service List" => sub {
    my $res = $endpoint->run_test_request( GET => '/services.xml' );
    ok $res->is_success, 'xml success';
    my $expected = <<XML;
<?xml version="1.0" encoding="utf-8"?>
<services>
  <service>
    <description>Misc ABC 1</description>
    <groups>
      <group>Not wrapped</group>
    </groups>
    <keywords></keywords>
    <metadata>true</metadata>
    <service_code>MISC_ABC_1</service_code>
    <service_name>Misc ABC 1</service_name>
    <type>realtime</type>
  </service>
  <service>
    <description>Misc ABC 2</description>
    <groups>
      <group>Not wrapped</group>
    </groups>
    <keywords></keywords>
    <metadata>true</metadata>
    <service_code>MISC_ABC_2</service_code>
    <service_name>Misc ABC 2</service_name>
    <type>realtime</type>
  </service>
  <service>
    <description>Misc DEF is not wrapped</description>
    <groups>
      <group>Everything</group>
    </groups>
    <keywords></keywords>
    <metadata>true</metadata>
    <service_code>MISC_DEF</service_code>
    <service_name>Misc DEF is not wrapped</service_name>
    <type>realtime</type>
  </service>
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

done_testing;
