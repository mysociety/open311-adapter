package Integrations::Confirm::Dummy;
use Path::Tiny;
use Moo;
extends 'Integrations::Confirm';
with 'Role::Config';
has config_filename => ( is => 'ro', default => 'dummy' );
sub _build_config_file { path(__FILE__)->sibling("confirm.yml")->stringify }

package Open311::Endpoint::Integration::UK::Dummy;
use Moo;
extends 'Open311::Endpoint::Integration::Confirm';
has integration_class => (is => 'ro', default => 'Integrations::Confirm::Dummy');


package main;

use strict;
use warnings;

use Test::More;
use Test::LongString;
use Test::MockModule;

use JSON::MaybeXS;
use Path::Tiny;

my ($IC, $SIC, $DC);

my $open311 = Test::MockModule->new('Integrations::Confirm');
$open311->mock(perform_request => sub {
    my ($self, $op) = @_; # Don't care about subsequent ops
    $op = $$op;
    if ($op->name && $op->name eq 'GetEnquiryLookups') {
        return {
            OperationResponse => { GetEnquiryLookupsResponse => { TypeOfService => [
                { ServiceCode => 'ABC', ServiceName => 'Graffiti', EnquirySubject => [ { SubjectCode => "DEF" } ] }
            ] } }
        };
    }
    $op = $op->value;
    if ($op->name eq 'NewEnquiry') {
        # Check more contents of req here
        foreach (${$op->value}->value) {
            is $_->value, 999999 if $_->name eq 'SiteCode';
        }
        return { OperationResponse => { NewEnquiryResponse => { Enquiry => { EnquiryNumber => 2001 } } } };
    } elsif ($op->name eq 'EnquiryUpdate') {
        # Check contents of req here
        my %req = map { $_->name => $_->value } ${$op->value}->value;
        if ($req{EnquiryNumber} eq '1002') {
            if ($req{LoggedTime}) {
                return { Fault => { Reason => 'Validate enquiry update.1002.Logged Date 04/06/2018 15:33:28 must be greater than the Effective Date of current status log' } };
            } else {
                return { OperationResponse => { EnquiryUpdateResponse => { Enquiry => { EnquiryNumber => 1002, EnquiryLogNumber => 111 } } } };
            }
        }
        return { OperationResponse => { EnquiryUpdateResponse => { Enquiry => { EnquiryNumber => 2001, EnquiryLogNumber => 2 } } } };
    } elsif ($op->name eq 'GetEnquiryStatusChanges') {
        return { OperationResponse => { GetEnquiryStatusChangesResponse => { UpdatedEnquiry => [
            { EnquiryNumber => 2001, EnquiryStatusLog => [ { EnquiryLogNumber => 3, LogEffectiveTime => '2018-03-01T12:00:00Z', EnquiryStatusCode => 'INP' } ] },
            { EnquiryNumber => 2002, EnquiryStatusLog => [ { EnquiryLogNumber => 1, LogEffectiveTime => '2018-03-01T13:00:00Z', EnquiryStatusCode => 'DUP' } ] },
        ] } } };
    }
    return {};
});

use Open311::Endpoint::Integration::UK::Dummy;

my $endpoint = Open311::Endpoint::Integration::UK::Dummy->new(
    jurisdiction_id => 'dummy',
    config_file => path(__FILE__)->sibling("confirm.yml")->stringify,
);

subtest "GET Service List" => sub {
    my $res = $endpoint->run_test_request( GET => '/services.xml' );
    ok $res->is_success, 'xml success';
    my $expected = <<XML;
<?xml version="1.0" encoding="utf-8"?>
<services>
  <service>
    <description>Flooding</description>
    <group>Flooding &amp; Drainage</group>
    <keywords></keywords>
    <metadata>true</metadata>
    <service_code>ABC_DEF</service_code>
    <service_name>Flooding</service_name>
    <type>realtime</type>
  </service>
</services>
XML
    is $res->content, $expected
        or diag $res->content;
};

subtest "GET Service List Description" => sub {
    my $res = $endpoint->run_test_request( GET => '/services/ABC_DEF.xml' );
    ok $res->is_success, 'xml success';
    my $expected = <<XML;
<?xml version="1.0" encoding="utf-8"?>
<service_definition>
  <attributes>
    <attribute>
      <automated>server_set</automated>
      <code>easting</code>
      <datatype>number</datatype>
      <datatype_description></datatype_description>
      <description>easting</description>
      <order>1</order>
      <required>true</required>
      <variable>false</variable>
    </attribute>
    <attribute>
      <automated>server_set</automated>
      <code>northing</code>
      <datatype>number</datatype>
      <datatype_description></datatype_description>
      <description>northing</description>
      <order>2</order>
      <required>true</required>
      <variable>false</variable>
    </attribute>
    <attribute>
      <automated>server_set</automated>
      <code>fixmystreet_id</code>
      <datatype>string</datatype>
      <datatype_description></datatype_description>
      <description>external system ID</description>
      <order>3</order>
      <required>true</required>
      <variable>false</variable>
    </attribute>
    <attribute>
      <automated>server_set</automated>
      <code>report_url</code>
      <datatype>string</datatype>
      <datatype_description></datatype_description>
      <description>Report URL</description>
      <order>4</order>
      <required>true</required>
      <variable>true</variable>
    </attribute>
    <attribute>
      <automated>server_set</automated>
      <code>title</code>
      <datatype>string</datatype>
      <datatype_description></datatype_description>
      <description>Title</description>
      <order>5</order>
      <required>true</required>
      <variable>true</variable>
    </attribute>
    <attribute>
      <automated>server_set</automated>
      <code>description</code>
      <datatype>text</datatype>
      <datatype_description></datatype_description>
      <description>Description</description>
      <order>6</order>
      <required>true</required>
      <variable>true</variable>
    </attribute>
    <attribute>
      <automated>hidden_field</automated>
      <code>asset_details</code>
      <datatype>text</datatype>
      <datatype_description></datatype_description>
      <description>Asset information</description>
      <order>7</order>
      <required>false</required>
      <variable>true</variable>
    </attribute>
    <attribute>
      <automated>hidden_field</automated>
      <code>site_code</code>
      <datatype>text</datatype>
      <datatype_description></datatype_description>
      <description>Site code</description>
      <order>8</order>
      <required>false</required>
      <variable>true</variable>
    </attribute>
    <attribute>
      <automated>hidden_field</automated>
      <code>central_asset_id</code>
      <datatype>string</datatype>
      <datatype_description></datatype_description>
      <description>Central Asset ID</description>
      <order>9</order>
      <required>false</required>
      <variable>true</variable>
    </attribute>
  </attributes>
  <service_code>ABC_DEF</service_code>
</service_definition>
XML
    is $res->content, $expected
        or diag $res->content;
};

subtest "POST OK" => sub {
    $IC = 'CS';
    $SIC = 'DP';
    $DC = 'OTS';
    my $res = $endpoint->run_test_request( 
        POST => '/requests.json', 
        api_key => 'test',
        service_code => 'ABC_DEF',
        address_string => '22 Acacia Avenue',
        first_name => 'Bob',
        last_name => 'Mould',
        description => "This is the details",
        'attribute[easting]' => 100,
        'attribute[northing]' => 100,
        'attribute[fixmystreet_id]' => 1001,
        'attribute[title]' => 'Title',
        'attribute[description]' => 'This is the details',
        'attribute[report_url]' => 'http://example.com/report/1001',
    );
    ok $res->is_success, 'valid request'
        or diag $res->content;

    is_deeply decode_json($res->content),
        [ {
            "service_request_id" => 2001
        } ], 'correct json returned';
};

subtest 'POST update' => sub {
    my $res = $endpoint->run_test_request(
        POST => '/servicerequestupdates.xml',
        api_key => 'test',
        service_request_id => 1001,
        update_id => 123,
        first_name => 'Bob',
        last_name => 'Mould',
        description => 'Update here',
        status => 'OPEN',
        updated_datetime => '2016-09-01T15:00:00Z',
        media_url => 'http://example.org/',
    );
    ok $res->is_success, 'valid request' or diag $res->content;

my $expected = <<XML;
<?xml version="1.0" encoding="utf-8"?>
<service_request_updates>
  <request_update>
    <update_id>2001_2</update_id>
  </request_update>
</service_request_updates>
XML

    is_string $res->content, $expected, 'xml string ok'
    or diag $res->content;
};

subtest 'POST update with invalid LoggedTime' => sub {
    my $res = $endpoint->run_test_request(
        POST => '/servicerequestupdates.xml',
        api_key => 'test',
        service_request_id => 1002,
        update_id => 123,
        first_name => 'Bob',
        last_name => 'Mould',
        description => 'Update here',
        status => 'OPEN',
        updated_datetime => '2016-09-01T15:00:00Z',
        media_url => 'http://example.org/',
    );
    ok $res->is_success, 'valid request' or diag $res->content;

my $expected = <<XML;
<?xml version="1.0" encoding="utf-8"?>
<service_request_updates>
  <request_update>
    <update_id>1002_111</update_id>
  </request_update>
</service_request_updates>
XML

    is_string $res->content, $expected, 'xml string ok'
    or diag $res->content;
};

subtest 'GET update' => sub {
    my $res = $endpoint->run_test_request(
        GET => '/servicerequestupdates.xml?start_date=2018-01-01T00:00:00Z&end_date=2018-02-01T00:00:00Z',
    );
    ok $res->is_success, 'valid request' or diag $res->content;

my $expected = <<XML;
<?xml version="1.0" encoding="utf-8"?>
<service_request_updates>
  <request_update>
    <description></description>
    <external_status_code>INP</external_status_code>
    <media_url></media_url>
    <service_request_id>2001</service_request_id>
    <status>in_progress</status>
    <update_id>2001_3</update_id>
    <updated_datetime>2018-03-01T12:00:00+00:00</updated_datetime>
  </request_update>
  <request_update>
    <description></description>
    <external_status_code>DUP</external_status_code>
    <media_url></media_url>
    <service_request_id>2002</service_request_id>
    <status>duplicate</status>
    <update_id>2002_1</update_id>
    <updated_datetime>2018-03-01T13:00:00+00:00</updated_datetime>
  </request_update>
</service_request_updates>
XML

    is_string $res->content, $expected, 'xml string ok'
    or diag $res->content;
};

done_testing;
